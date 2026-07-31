extends SceneTree

## 世界のシミュレータ。
##
##   godot --headless --script res://tests/balance.gd
##   godot --headless --script res://tests/balance.gd -- --runs=500 --detail
##
## **測る側と遊ぶ側で同じコードを通す。** ここが今回いちばん大事な作り。
##
## 旧版は「バランス測定」という名前で、中身は `1 階につき 4 戦` という
## 書き写した模型だった。通るし数字も出るが、ゲームには存在しない構造を
## 測っていた。**壊れているより悪い（健全に見える）。**
##
## そこで今の版は、実際のランと同じ部品だけを呼ぶ。
##
##   * 世界 …… `WorldGenerator.generate()`（遊ぶときと同じ生成器）
##   * 経路 …… `FieldMap.route()`（自動移動と同じ幅優先）
##   * 地形の重み …… `WorldMap.encounter_weight()`
##   * 遭遇の判定 …… `Encounter.should_meet()`（`ExploreView` と共有）
##   * 敵編成 …… `Encounter.build()` / `build_boss()`
##   * 戦闘 …… `BattleSystem`（本物。ダメージ式も CTB もそのまま）
##   * 味方の判断 …… `AutoTactic`（画面のオートと同じ）
##
## 数値をここに書き写したら負け。**定数を持たないこと**を規約にする。
##
## 出すのは 1 つの数字ではなく分布。「主に挑めた 31%」だけでは、
## 遠くて届かないのか、道中で削られて死ぬのかが分からない。

## 何ラン回すか（`--runs=` で上書きできる）。
## 何ランぶん回すか。
##
## **勝率の判定と、1 戦の長さの測定では必要な数がまるで違う。**
## 勝率は 1 ランに 1 回しか結果が出ないので 200 要るが、戦闘の長さは
## 1 ランで数十戦あるため 40 ランでも数百〜千戦になる。
## 長さを見たいだけのときは `--runs=40` で足りる（200 は数分かかる）。
const DEFAULT_RUNS := 200

## 1 戦の打ち切り。無限ループ（互いに削れない編成）から抜けるための保険。
const MAX_TURNS := 400

const PARTY := [
	{ "name": "アレン", "job": "soldier" },
	{ "name": "セラ", "job": "priest" },
	{ "name": "ノア", "job": "mage" },
	{ "name": "キリ", "job": "thief" },
]

## 歩き方。**世界が広いので「どう進むか」で結果が変わる。**
## 直行と寄り道を並べて測らないと、洞に入る価値が数字にならない。
enum Policy { STRAIGHT, DETOUR, SEALS, TOUR }

const POLICY_NAMES := {
	Policy.STRAIGHT: "直行（城へ最短。封が残るので入れない）",
	Policy.DETOUR: "寄り道（手近な洞を 2 つ）",
	Policy.SEALS: "封（3 つの封の洞だけ回って城へ）",
	Policy.TOUR: "全周（洞を全部まわってから城）",
}

var _runs := DEFAULT_RUNS
var _detail := false


func _initialize() -> void:
	Database.reload()
	_read_args()

	if _boss_probe > 0:
		_run_boss_probe(_boss_probe)
		quit()
		return

	print("=== 世界シミュレータ ===")
	print("%d ラン × %d 方針" % [_runs, POLICY_NAMES.size()])

	var reports := {}
	for policy in [Policy.STRAIGHT, Policy.DETOUR, Policy.SEALS, Policy.TOUR]:
		reports[policy] = _run_policy(policy)

	for policy in reports:
		_print_report(String(POLICY_NAMES[policy]), reports[policy])

	print("---")
	_print_verdict(reports)
	if not _out_of_band.is_empty():
		print("---")
		print("帯の外: %s" % "、".join(_out_of_band))
		print("難度を直すか、帯そのものを直す。**黙って通さない。**")
		# **`quit()` は関数を抜けない。** ここで return しないと、下の
		# `quit()` が終了コードを 0 に上書きして、赤いはずの回が緑で通る。
		quit(1)
		return
	quit()


## 主戦だけを取り出して測る（D-8）。
##
## 世界を 1 周させてからでは、主の強さだけを動かした効き目が読めない
## （道中の乱れに埋もれる）。城に着いた頃の party を作って、主とだけ戦わせる。
##
##     godot --headless --script tests/balance.gd -- --boss=200
func _run_boss_probe(count: int) -> void:
	print("=== 主戦だけ（Lv %d の party × %d 回）===" % [BOSS_PROBE_LEVEL, count])
	var tally := {}
	for i in count:
		var rng := DetRng.new(i * 7919 + 13).fork("boss")
		var members := _fresh_party()
		for m in members:
			m.level = BOSS_PROBE_LEVEL
			m.hp = m.max_hp()
			m.mp = m.max_mp()
		var boss := Encounter.build_boss(rng, WorldMap.MAX_DANGER)
		if boss.is_empty():
			continue
		var name := boss[0].name
		var state := {
			"steps": 0, "battles": 0, "gold": 0, "danger": 10, "dead": false,
			"turns_by_foes": {}, "turns_by_danger": {}, "rests": 0,
			"gear_stock": [] as Array[String],
		}
		var won := _fight(members, boss, rng, WorldMap.MAX_DANGER, state)
		var row: Array = tally.get(name, [0, 0, 0])
		var turns := 0
		for key in state["turns_by_foes"]:
			turns += int(state["turns_by_foes"][key][1])
		tally[name] = [int(row[0]) + 1, int(row[1]) + (1 if won else 0), int(row[2]) + turns]
	var names: Array = tally.keys()
	names.sort()
	var total := 0
	var wins := 0
	for name in names:
		var row: Array = tally[name]
		total += int(row[0])
		wins += int(row[1])
		print("  %-16s %3d 戦  勝率 %3d%%  平均 %4.1f 手番" % [
			name, int(row[0]), int(row[1]) * 100 / maxi(int(row[0]), 1),
			int(row[2]) / float(maxi(int(row[0]), 1)),
		])
	print("  ---")
	print("  合計 %d 戦 / party の勝率 %d%%" % [total, wins * 100 / maxi(total, 1)])


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			_runs = maxi(int(arg.trim_prefix("--runs=")), 1)
		elif arg.begins_with("--boss="):
			_boss_probe = maxi(int(arg.trim_prefix("--boss=")), 1)
		elif arg == "--detail":
			_detail = true


# --------------------------------------------------------------------------
# 集計
# --------------------------------------------------------------------------


func _run_policy(policy: Policy) -> Dictionary:
	var report := {
		"reached": 0, "won": 0, "died": 0,
		"died_at": {}, "steps": 0, "battles": 0,
		"level_sum": 0, "level_runs": 0,
		"death_level_sum": 0, "death_danger_sum": 0,
		"gold_sum": 0, "gold_runs": 0,
		"world_span": 0,
		"turns_by_foes": {},
		"turns_by_danger": {},
	}
	for i in _runs:
		# 種はランごとに散らす。連番にすると隣のランと似た世界が並ぶ。
		var result := _simulate(i * 7919 + 13, policy)
		report["steps"] = int(report["steps"]) + int(result["steps"])
		report["battles"] = int(report["battles"]) + int(result["battles"])
		report["world_span"] = int(report["world_span"]) + int(result["span"])
		var into: Dictionary = report["turns_by_foes"]
		for key in result["turns_by_foes"]:
			var add: Array = result["turns_by_foes"][key]
			var row: Array = into.get(key, [0, 0, 0, 0, 0, 0, 0])
			into[key] = [
				int(row[0]) + int(add[0]),
				int(row[1]) + int(add[1]),
				maxi(int(row[2]), int(add[2])),
				int(row[3]) + int(add[3]),
				maxi(int(row[4]), int(add[4])),
				int(row[5]) + int(add[5]),
				maxi(int(row[6]), int(add[6])),
			]
		report["turns_by_foes"] = into
		var dinto: Dictionary = report["turns_by_danger"]
		for key in result["turns_by_danger"]:
			var add2: Array = result["turns_by_danger"][key]
			var row2: Array = dinto.get(key, [0, 0, 0])
			dinto[key] = [
				int(row2[0]) + int(add2[0]),
				int(row2[1]) + int(add2[1]),
				int(row2[2]) + int(add2[2]),
			]
		report["turns_by_danger"] = dinto
		if bool(result["reached"]):
			report["reached"] = int(report["reached"]) + 1
			report["level_sum"] = int(report["level_sum"]) + int(result["level"])
			report["level_runs"] = int(report["level_runs"]) + 1
			report["gold_sum"] = int(report["gold_sum"]) + int(result["gold"])
			report["gold_runs"] = int(report["gold_runs"]) + 1
		if bool(result["won"]):
			report["won"] = int(report["won"]) + 1
		if bool(result["died"]):
			report["died"] = int(report["died"]) + 1
			report["death_level_sum"] = int(report["death_level_sum"]) + int(result["level"])
			report["death_danger_sum"] = int(report["death_danger_sum"]) + int(result["danger"])
			var band := int(result["danger"])
			report["died_at"][band] = int(report["died_at"].get(band, 0)) + 1
	return report


## オート中の待ち。`battle_view.gd` の `AUTO_WINDOW_DELAY` / `WINDOW_LINES` と揃える。
##
## **点滅と閃光は待ちと並行に流れるので秒を足さない**（`_process` を見ると
## `_timer` と同じ枠で減る）。1 戦の長さを決めているのは**行数**だけだった。
## 手番数から 0.40 秒/手番で見積もっていたが、根拠が無かった。
## **数字を変えたらここも変える**（合わなくなると測っている意味が無い）。
const AUTO_WINDOW_DELAY := 0.16
const WINDOW_LINES := 3

## 直す前の式（1 行ずつ 0.10 秒送り）。**比較のためだけに残す。**
const OLD_LINE_DELAY := 0.10

## これを超えたら「長い戦」とみなす手番数。0.40 秒 x 30 = 12 秒。
const LONG_TURNS := 30

## 宝箱 1 つぶんの基準ゴールド（`main.gd` の `_on_chest` と同じ扱い）。
const CHEST_GOLD := 40

## 全周で目指す帯。**外れたら終了コード 1。**
##
## 前の帯（到達 28〜38 / 勝利 10〜18）は**壊れた Sim の数字から引かれていた**。
## 宿にも寄らず宝箱も開けない party を描写した 35% が、そのまま目標になっていた。
## 事故でできた辛さを設計として固定することになるので、引き直した。
##
## いまの方針は「**到達は起きてよい、勝利は稀であるべき**」。
## 旅がゲーム本体なので着けないと何も始まらない。主が山場で、その差
## （着いたのに勝てなかった）が物語になる。
##
## 到達の上限が高いのは、判定が**全周**（洞を全部まわる最も手厚い遊び方）で
## 行われるため。下限 45 は「旅が緩すぎない」ことの確認に残す。
const REACH_MIN := 45
const REACH_MAX := 85
const WIN_MIN := 12
const WIN_MAX := 25

## 帯を外れた項目。空でなければ落ちる。
var _out_of_band: Array[String] = []

## 主戦だけを測るときの party のレベル。
## **城に着いた頃の実測**（全周で Lv 15.0 / 封だけで Lv 13.0）の低いほう寄り。
const BOSS_PROBE_LEVEL := 14

var _boss_probe := 0

const ChestReward := preload("res://src/dungeon/chest_reward.gd")


func _print_report(title: String, r: Dictionary) -> void:
	print("---")
	print("【%s】" % title)
	var runs := float(_runs)
	print("  城に着けた : %d / %d (%d%%)" % [
		int(r["reached"]), _runs, int(r["reached"]) * 100 / _runs])
	print("  主を倒した : %d / %d (%d%%)" % [
		int(r["won"]), _runs, int(r["won"]) * 100 / _runs])
	print("  1 ランの歩数 : 平均 %.0f 歩（門から城まで %.0f 歩）" % [
		int(r["steps"]) / runs, int(r["world_span"]) / runs])
	print("  1 ランの戦闘 : 平均 %.1f 回" % [int(r["battles"]) / runs])
	if int(r["level_runs"]) > 0:
		print("  城に着いた時 : 平均 Lv %.1f / ゴールド %d" % [
			int(r["level_sum"]) / float(r["level_runs"]),
			int(r["gold_sum"]) / int(r["gold_runs"]),
		])
	if int(r["died"]) > 0:
		# レベルと危険度の差が、そのまま「間に合っていない量」になる。
		print("  倒れた時     : 平均 Lv %.1f / 危険度 %.1f" % [
			int(r["death_level_sum"]) / float(r["died"]),
			int(r["death_danger_sum"]) / float(r["died"]),
		])
	# 敵の数ごとの手番。**1 戦の長さはここでほぼ決まる。**
	# 秒はこの手番数に「1 手番あたりの遅延」を掛けたものなので、
	# 遅延を削る前にこの表を見る（削る方向は既に限界まで来ている）。
	# **新旧を同じ回で並べる。** 自動プレイは回ごとに世界も敵も変わるので
	# 前後比較には粗すぎた（速くしたのに「遅くなった」数字が出た）。
	# ここは同じシードの同じ戦闘を両方の式で見るので、差だけが出る。
	print("  1 戦の長さ   : 敵の数ごと（旧 = 1 行 %.2f 秒 / 新 = %d 行 %.2f 秒）" % [
		OLD_LINE_DELAY, WINDOW_LINES, AUTO_WINDOW_DELAY])
	var counts: Array = r["turns_by_foes"].keys()
	counts.sort()
	for n in counts:
		var row: Array = r["turns_by_foes"][n]
		var fights := float(maxi(int(row[0]), 1))
		print(
			"    敵 %d 体 %5d 戦 %5.1f 手番  平均 %4.1f→%4.1f 秒  最長 %4.1f→%4.1f 秒" % [
				n, int(row[0]), int(row[1]) / fights,
				int(row[3]) / fights * OLD_LINE_DELAY,
				int(row[5]) / fights * AUTO_WINDOW_DELAY,
				int(row[4]) * OLD_LINE_DELAY,
				int(row[6]) * AUTO_WINDOW_DELAY,
			]
		)

	print("  長い戦の在処 : 危険度ごと（%d 手番以上を長いとする）" % LONG_TURNS)
	var dbands: Array = r["turns_by_danger"].keys()
	dbands.sort()
	for band in dbands:
		var row2: Array = r["turns_by_danger"][band]
		var total := maxi(int(row2[1]), 1)
		print("    危険度 %2d  %5d 戦  平均 %5.1f 手番  長い %4d 戦 (%2d%%)" % [
			band, int(row2[1]), int(row2[2]) / float(total),
			int(row2[0]), int(row2[0]) * 100 / total,
		])

	# どこで死ぬかの分布。**ここが一番効く情報。**
	# 「届かない」のと「届いても勝てない」のは、直し方がまるで違う。
	print("  倒れた危険度 :")
	var bands: Array = r["died_at"].keys()
	bands.sort()
	for band in bands:
		var count := int(r["died_at"][band])
		print("    危険度 %2d  %4d  %s" % [band, count, "#".repeat(maxi(count * 40 / _runs, 1))])


func _print_verdict(reports: Dictionary) -> void:
	var straight: Dictionary = reports[Policy.STRAIGHT]
	var detour: Dictionary = reports[Policy.DETOUR]
	var s_win := int(straight["won"]) * 100 / _runs
	var d_win := int(detour["won"]) * 100 / _runs
	var s_reach := int(straight["reached"]) * 100 / _runs

	# **判定はいちばん強い方針（全周）で行う。**
	# 直行が勝てないのは設計どおり（急げば着くが勝てない）なので、
	# そこを基準に「主が硬い」と言うと、毎回誤診する。
	# **判定はいちばん強い方針（全周）で行う。**
	# 人は道すがら洞を拾っていくので、実際の遊び方は全周に近い。
	# 封だけを狙って深い土地へ急ぐ線は「急ぎすぎ」の参考値として並べる。
	var tour: Dictionary = reports[Policy.TOUR]
	var seals: Dictionary = reports[Policy.SEALS]
	var t_win := int(tour["won"]) * 100 / _runs
	var seal_win := int(seals["won"]) * 100 / _runs

	if s_reach < 5:
		print("所見: 城が遠すぎる。直行でも %d%% しか着かない。" % s_reach)
		print("      遭遇率（Encounter.MIN_SAFE_STEPS）か世界の広さ（WorldGenerator.MAP_W）を疑う。")
	elif t_win > 45:
		print("所見: 易しい。全周で %d%% 勝てるなら人が操作すると素通りになる。" % t_win)
		print("      Encounter.EXP_GAIN を下げる。")
	elif t_win < 8:
		print("所見: 辛い。全周しても %d%% しか勝てないので、勝ち筋が無い。" % t_win)
		print("      Encounter.EXP_GAIN を上げる。")
	else:
		print("所見: 妥当な帯（全周 %d%% / 封だけ狙い %d%%）。" % [t_win, seal_win])
		print("      自動操縦は道具も買い物も使わないので、")
		print("      これは人が操作したときの下限。")
	if s_win > 15:
		print("警告: 直行で %d%% 勝てている。急ぐ判断と寄る判断が同値になっていて、" % s_win)
		print("      「寄るか急ぐか」が判断として成立していない。")

	# 封が効いているか。**直行で勝ててはいけない**（扉が開かないので 0% が正しい）。
	if s_win > 0:
		print("警告: 直行で %d%% 勝てている。封の門が効いていない。" % s_win)
	elif seal_win <= 0:
		print("警告: 封を回っても勝てない。集めた先に勝ち筋が無い。")
	else:
		print("封: 効いている（直行 0%% → 封 %d%% → 全周 %d%%）。" % [seal_win, t_win])
		print("      急げば城には着くが扉が開かない、が数字として在る。")

	# **帯を外れたら終了コード 1（D-2）。**
	#
	# それまでは所見を print するだけで、赤くならなかった。数字が動いても
	# 誰も止めないので、判定が「妥当」と言い続けているあいだに実際の難度が
	# ずれていく。ここで落ちるようにして、**帯の外は不合格**にする。
	#
	# 帯の根拠は tasks.md の D-2（到達 28〜38% / 勝利 10〜18%）。
	# **この値は「人が操作したとき」の目標**で、Sim は道具も買い物も使わない
	# ぶん下振れする。外れたら難度を直すか、帯そのものを直す。
	var t_reach := int(tour["reached"]) * 100 / _runs
	var out_of_band: Array[String] = []
	if t_reach < REACH_MIN or t_reach > REACH_MAX:
		out_of_band.append("到達 %d%%（帯 %d〜%d%%）" % [t_reach, REACH_MIN, REACH_MAX])
	if t_win < WIN_MIN or t_win > WIN_MAX:
		out_of_band.append("勝利 %d%%（帯 %d〜%d%%）" % [t_win, WIN_MIN, WIN_MAX])
	_out_of_band = out_of_band

	# 手近な洞を 2 つ拾うだけでは足りないこと（封の洞を選ぶ意味）
	if d_win > 0:
		print("注意: 封と関係ない洞を 2 つ回るだけで %d%% 勝てている。" % d_win)
		print("      封を置いた意味が薄い。配置の帯を見直す。")


# --------------------------------------------------------------------------
# 1 ラン
# --------------------------------------------------------------------------


func _simulate(seed_value: int, policy: Policy) -> Dictionary:
	var members := _fresh_party()
	# 遊ぶときとまったく同じ手順で世界を作る。
	var world := WorldGenerator.generate(DetRng.new(seed_value).fork("world"))
	var rng := DetRng.new(seed_value).fork("sim")

	var span := world.route(world.start_pos, world.castle_pos).size()
	var state := {
		"steps": 0, "battles": 0, "gold": 0, "danger": 1, "dead": false,
		# 敵の数ごとの手番数。**「6 体だけが長い」と決めずに測る**ための記録
		# （数 → [戦闘数, 手番の合計, 最長]）。
		"turns_by_foes": {},
		# 長い戦がどこに固まっているか（危険度 → [長い戦, 全戦闘, 手番合計]）。
		# **敵の数で説明がつかなかった**ので、危険度の側から見る。
		"turns_by_danger": {},
		# 宿で休んだ回数と、拾って着けていない装備。
		"rests": 0,
		"gear_stock": [] as Array[String],
	}

	# 行き先の列。
	#
	# **城は封が 3 つ解けるまで開かない**ので、直行は「着くが入れない」になる。
	# それを含めて測る（遊ぶ側と同じ構造を通すのがこのシミュレータの前提）。
	var waypoints: Array[Vector2i] = []
	if policy == Policy.DETOUR:
		waypoints.append_array(_pick_caves(world, 2))
	elif policy == Policy.SEALS:
		# 封のある洞だけを回ってから城へ。これが想定している遊び方。
		for s in world.seals:
			waypoints.append(s["pos"])
	elif policy == Policy.TOUR:
		waypoints.append_array(_pick_caves(world, 99))
	waypoints.append(world.castle_pos)

	var at := world.start_pos
	for goal in waypoints:
		at = _walk(world, members, rng, state, at, goal)
		if bool(state["dead"]):
			return _result(members, state, false, false, span)
		# 洞に着いたら中を 1 往復ぶん歩く（宝箱と戦闘のぶん）。
		if goal != world.castle_pos:
			_delve(world, members, rng, state, goal)
			if bool(state["dead"]):
				return _result(members, state, false, false, span)
			# 洞の底には**封の番人**が居る（遊ぶ側と同じ扱い）。
			# ここを飛ばすと、封を集める線が実際より楽に測れてしまう。
			var seal := world.seal_at(goal)
			if not seal.is_empty():
				var keeper := Encounter.build_guardian(
					rng, int(state["danger"]), world.biome_id_at(goal.x, goal.y)
				)
				if not keeper.is_empty():
					if not _fight(members, keeper, rng, int(state["danger"]), state):
						state["dead"] = true
						return _result(members, state, false, false, span)
				seal["broken"] = true

	# 城に着いた。**封が残っていれば扉は開かない。**
	if world.seals_remaining() > 0:
		return _result(members, state, true, false, span)
	var boss := Encounter.build_boss(rng, WorldMap.MAX_DANGER)
	if boss.is_empty():
		return _result(members, state, true, false, span)
	var won := _fight(members, boss, rng, WorldMap.MAX_DANGER, state)
	return _result(members, state, true, won, span)


func _fresh_party() -> Array[PartyMember]:
	var members: Array[PartyMember] = []
	for entry in PARTY:
		var m := PartyMember.create(String(entry["name"]), String(entry["job"]))
		# 実際のランと同じく初期装備を着せる。着せずに測ると、
		# ここで出る数字が遊んでいる状態と食い違う。
		for gear_id in Database.job(m.job_id).get("starting_gear", []):
			m.equip(String(gear_id))
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		members.append(m)
	return members


## 目的地まで歩く。1 歩ごとに地形の重みを足し、遭遇したら戦う。
## **歩き方も遭遇の式も遊ぶときと同じ関数を通す。**
func _walk(
	world: WorldMap, members: Array[PartyMember], rng: DetRng, state: Dictionary,
	from: Vector2i, to: Vector2i
) -> Vector2i:
	var path := world.route(from, to)
	var weighted := 0
	var walked := 0
	var at := from
	for step in path:
		at = step
		state["steps"] = int(state["steps"]) + 1
		state["danger"] = world.danger_at(at.x, at.y)
		if world.sites.has(at):
			weighted = 0  # 拠点地の上は安全（ExploreView と同じ扱い）
			walked = 0
			# **町を通ったら休む（D-2）。** 宿は無料で全回復・毒治療なので、
			# 実プレイでは町の前を素通りしない。ここを飛ばしていたせいで、
			# Sim は「町のある世界でも一度も回復しない」測り方になっていた。
			if String(world.site_at(at).get("kind", "")) == "town":
				_rest(members, state)
			continue
		weighted += world.encounter_weight(at.x, at.y)
		walked += 1
		if not Encounter.should_meet(rng, walked, weighted):
			continue
		weighted = 0
		walked = 0
		var foes := Encounter.build(rng, int(state["danger"]), 100, world.biome_id_at(at.x, at.y))
		if foes.is_empty():
			continue
		if not _fight(members, foes, rng, int(state["danger"]), state):
			state["dead"] = true
			return at
	return at


## 洞の中。階数は世界と同じ規則で決め、各階を歩いた想定で戦う。
##
## 地形は生成するが歩数までは追わない（洞の中の経路は世界の判断に影響しない）。
## 代わりに階段までの距離を測って、その歩数ぶんの遭遇を回す。
func _delve(
	world: WorldMap, members: Array[PartyMember], rng: DetRng, state: Dictionary, at: Vector2i
) -> void:
	var site: Dictionary = world.site_at(at)
	var danger := int(site.get("danger", 1))
	var depth: int = clampi(1 + danger / 3, 1, 3)
	for floor_number in range(1, depth + 1):
		var here: int = mini(danger + floor_number - 1, WorldMap.MAX_DANGER)
		state["danger"] = here
		var map := DungeonGenerator.generate(rng.fork("cave:%d" % floor_number), here, false)
		# **経路の近くの宝箱だけ開ける。**
		#
		# 全部開けると寛容すぎる ―― 階段までの道すがら、部屋の隅の箱までは
		# 寄らない。逆に 0 個にすると、初期装備のまま 10 階を戦うことになる
		# （それが直す前の状態で、「深いほど勝てない」が実際より強く出ていた）。
		_open_chests(members, rng, state, _chests_on_route(map), here)
		var biome := String(site.get("biome", ""))
		var steps := map.route(map.start_pos, map.stairs_pos).size()
		var weighted := 0
		var walked := 0
		for _s in steps:
			state["steps"] = int(state["steps"]) + 1
			weighted += 1  # 洞の中は 1 歩 1（ExploreView の _try_move_dungeon と同じ）
			walked += 1
			if not Encounter.should_meet(rng, walked, weighted):
				continue
			weighted = 0
			walked = 0
			var foes := Encounter.build(rng, here, 100, biome)
			if foes.is_empty():
				continue
			if not _fight(members, foes, rng, here, state):
				state["dead"] = true
				return


## 階段までの道から `CHEST_REACH` 歩以内にある宝箱の数。
##
## 遊ぶ側は階段へ向かいながら、目に入った箱に寄る。全部でも 0 でもない。
const CHEST_REACH := 4


func _chests_on_route(map: DungeonMap) -> int:
	if map.chests.is_empty():
		return 0
	var path := map.route(map.start_pos, map.stairs_pos)
	var near := 0
	for chest in map.chests:
		for step in path:
			var at: Vector2i = step
			if absi(at.x - chest.x) + absi(at.y - chest.y) <= CHEST_REACH:
				near += 1
				break
	return near


## 宿で休む。**無料で全回復と毒の治療**（`main.gd` の `_on_inn` と同じ）。
func _rest(members: Array[PartyMember], state: Dictionary) -> void:
	state["rests"] = int(state.get("rests", 0)) + 1
	for m in members:
		if m.hp <= 0:
			continue   # 倒れた者は宿では起きない（実プレイと同じ）
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		m.cure_poison()


## 宝箱を開ける。**手に入れた装備はその場で着せる**（C-9 と C-10 の経路）。
##
## 飛ばしていたせいで、Sim は初期装備のまま 10 階ぶんを戦っていた。
## 実プレイでは危険度が上がるほど良い装備が出るので、ここが抜けると
## 「深いほど勝てない」が実際より強く出る。
func _open_chests(
	members: Array[PartyMember], rng: DetRng, state: Dictionary,
	count: int, danger: int
) -> void:
	var stock: Array[String] = state.get("gear_stock", [] as Array[String])
	for _i in count:
		var reward: Dictionary = ChestReward.roll(rng, danger, CHEST_GOLD)
		state["gold"] = int(state["gold"]) + int(reward.get("gold", 0))
		var gear_id := String(reward.get("gear", ""))
		if gear_id != "":
			stock.append(gear_id)
	state["gear_stock"] = stock
	if stock.is_empty():
		return
	# **人と同じ処理で着せる。** ここに別の判断を書くと、測っている強さと
	# 遊べる強さが別物になる（毒で手番が消えていたのと同じ事故）。
	for move in BestGear.plan(members, stock):
		var member: PartyMember = members[int(move["member"])]
		var removed := member.equip(String(move["gear"]))
		stock.erase(String(move["gear"]))
		if removed != "":
			stock.append(removed)
	state["gear_stock"] = stock


func _result(
	members: Array[PartyMember], state: Dictionary, reached: bool, won: bool, span: int
) -> Dictionary:
	var level := 0
	for m in members:
		level = maxi(level, m.level)
	return {
		"reached": reached,
		"won": won,
		"died": bool(state["dead"]),
		"danger": int(state["danger"]),
		"steps": int(state["steps"]),
		"battles": int(state["battles"]),
		"gold": int(state["gold"]),
		"level": level,
		"span": span,
		"turns_by_foes": state["turns_by_foes"],
		"turns_by_danger": state["turns_by_danger"],
	}


## 洞をいくつか拾う。門に近い順（実際に寄れる順）で選ぶ。
func _pick_caves(world: WorldMap, count: int) -> Array[Vector2i]:
	var from_gate := world.distance_field(world.start_pos)
	var caves: Array[Vector2i] = []
	for pos in world.sites:
		if String(world.sites[pos].get("kind", "")) == "cave":
			caves.append(pos)
	caves.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from_gate[a.y * world.width + a.x] < from_gate[b.y * world.width + b.x])
	return caves.slice(0, count)


# --------------------------------------------------------------------------
# 戦闘（本物の BattleSystem をそのまま回す）
# --------------------------------------------------------------------------


func _fight(
	members: Array[PartyMember], foes: Array[Battler], rng: DetRng, danger: int,
	state: Dictionary
) -> bool:
	state["battles"] = int(state["battles"]) + 1
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))

	var system := BattleSystem.new()
	system.start(party, foes, rng, danger)

	var turns := 0
	# **実際に待たされる長さは手番数ではなく行数で決まる。**
	# オート中は 1 行につき `AUTO_LINE_DELAY` 待つので、
	# 秒を見積もるならこちらを数えないと外れる（手番だけ見て 0.40 秒/手番と
	# 見積もっていたが、根拠が無かった）。
	var lines := 0
	# 待ちの回数。オート中は窓 1 枚ぶん（3 行）ごとに 1 回待つので、
	# **秒はこちらに比例する**（行数ではなく）。
	var waits := 0
	while not system.is_over and turns < MAX_TURNS:
		turns += 1
		var actor := system.begin_turn()
		if actor == null:
			break
		# 毒と眠りの解決。眠っていればこの手番は飛ぶ。
		var head: Dictionary = system.begin_turn_effects(actor)
		if bool(head["skipped"]):
			continue
		if actor.is_ally:
			# **画面のオートと同じ判断を使う。** ここに素朴な AI を書くと、
			# 測っている強さと遊べる強さが別物になる。
			var plan := AutoTactic.decide(system, actor, AutoTactic.Mode.AGGRESSIVE)
			var said := system.perform(actor, String(plan["ability"]), plan["target"]).size()
			lines += said
			waits += ceili(said / float(WINDOW_LINES))
		else:
			var said_e := system.perform_enemy(actor).size()
			lines += said_e
			waits += ceili(said_e / float(WINDOW_LINES))

	# **敵の数ごとに手番を数える。** 1 戦の長さは手番数でほぼ決まるので、
	# 秒を測る前にここを見る（遅延はあとから掛け算するだけ）。
	var by_danger: Dictionary = state["turns_by_danger"]
	var drow: Array = by_danger.get(danger, [0, 0, 0])
	by_danger[danger] = [
		int(drow[0]) + (1 if turns >= LONG_TURNS else 0),
		int(drow[1]) + 1,
		int(drow[2]) + turns,
	]
	state["turns_by_danger"] = by_danger

	var tally: Dictionary = state["turns_by_foes"]
	var key := foes.size()
	var row: Array = tally.get(key, [0, 0, 0, 0, 0, 0, 0])
	tally[key] = [
		int(row[0]) + 1, int(row[1]) + turns, maxi(int(row[2]), turns),
		int(row[3] if row.size() > 3 else 0) + lines,
		maxi(int(row[4] if row.size() > 4 else 0), lines),
		int(row[5] if row.size() > 5 else 0) + waits,
		maxi(int(row[6] if row.size() > 6 else 0), waits),
	]
	state["turns_by_foes"] = tally

	for i in members.size():
		if i < party.size():
			members[i].sync_from_battler(party[i])

	if not system.victory():
		return false

	var reward := system.rewards()
	state["gold"] = int(state["gold"]) + int(reward["gold"])
	for m in members:
		if m.hp <= 0:
			continue
		m.gain_exp(int(reward["exp"]))
		m.gain_mastery(int(reward["mastery"]))
	return true
