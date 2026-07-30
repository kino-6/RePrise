extends Node

## ラン全体とメタ進行の管理（オートロード名: GameState）。
##
## 「何を失い、何を持ち帰るか」の境界をここ 1 か所に集約する。境界が散ると
## ローグライクは必ず壊れるので、失うものは end_run() で確実に捨てる。

const SAVE_PATH := "user://save.json"

## 直前のセーブの控え。書く前にここへ寄せる。
##
## 1 世代あれば事故の大半は防げる（書き込み中の異常終了、壊れた JSON、
## テストが実データを踏む、など）。世代を増やすより、まず 1 つ持つことが効く。
const SAVE_BACKUP_PATH := "user://save.bak.json"

## 書きかけの置き場。本体へは差し替えでしか触らない。
##
## FileAccess.open(WRITE) は**開いた瞬間に中身を捨てる**ので、本体を直接開くと
## そこから書き終わるまでのあいだセーブが存在しない状態になる。
## その隙に落ちると本体が消える（実際に消えた）。
const SAVE_TEMP_PATH := "user://save.tmp.json"

## 実際に読み書きする先。既定は上の 3 つ。
##
## テストから差し替えられるようにしてある。**ここを定数のまま扱うと、
## セーブを試すテストが実データを潰す。** 一度それで名簿を 1 人にした
## （テストは全部緑のまま、画面を見て初めて気付いた）。
var save_path := SAVE_PATH
var backup_path := SAVE_BACKUP_PATH
var temp_path := SAVE_TEMP_PATH


## テスト用。読み書き先を丸ごと別名へ寄せる。
func use_save_paths(prefix: String) -> void:
	save_path = "%s.json" % prefix
	backup_path = "%s.bak.json" % prefix
	temp_path = "%s.tmp.json" % prefix


const PARTY_SIZE := 4

## 最終階。ここには下り階段が無く、主の間の扉だけがある。
## ランに終わりを与えるための唯一の数字なので、ここ以外に散らさない。
const FINAL_FLOOR := 10

## 初期メンバー。拠点で控えを増やしていく想定だが、連れて行けるのは常に 4 人。
const DEFAULT_PARTY := [
	{ "name": "アレン", "job": "soldier" },
	{ "name": "セラ", "job": "priest" },
	{ "name": "ノア", "job": "mage" },
	{ "name": "キリ", "job": "thief" },
]

signal run_started(seed_value: int)
signal run_ended(victory: bool, summary: Dictionary)
signal floor_changed(floor_number: int)

# --- 恒久（拠点に残る） ---
var roster: Array[PartyMember] = []
var deepest_floor: int = 0
var runs_attempted: int = 0

## 恒久通貨「残響」。毎ランの道中スコアに応じて必ず支払われる。
##
## 最深階の更新やボス撃破のような一度きりの達成に紐付けると、達成したあとの
## ランで前進が止まり、周回する理由が消える。だから「今回どれだけやれたか」に
## 対して毎回払う。深く潜り、多く倒し、多く稼いだぶんだけ増える。
var echo: int = 0

## 買ったアップグレード（upgrade_id -> 段数）。
var upgrades: Dictionary = {}

## ランをまたぐ物語の進行（`docs/cross_world_story_design.md` の「永続状態」）。
##
## **生成済みの一型と進行だけ**を持つ。長文はカタログ側にあるので、ここには
## 結末の ID しか残さない（セーブに文章を複製しない）。
## 古いセーブでは空に落ちる ―― 空でも遊べることが条件。
##
##   active_id / skin      … 選出時に確定して即保存する
##   phase_index           … 表示または失敗継続が確定してから進める
##   setbacks              … 結末の文脈に使う。**打ち切る条件にはしない**
##   completed             … 結末 ID だけ
##   recent_ids            … 同じ型が続かないようにするため
var cross_world: Dictionary = {}


## またぐ物語の空の状態。形をここ 1 か所に置く。
static func empty_cross_world() -> Dictionary:
	return {
		"schema": 1,
		"active_id": "",
		"phase_index": 0,
		"skin": {},
		"started_run": 0,
		"next_due_run": 0,
		"setbacks": [],
		"history": [],
		"completed": {},
		"recent_ids": [],
	}

# --- ラン中のみ（全滅で消える） ---
var run_active: bool = false
var run_seed: int = 0

## その世界。ランごとに丸ごと作り直され、二度と同じものは出ない。
## 拠点だけが世界の外にあるので、これを捨ててもメタ進行は残る。
var world: WorldMap = null

## 世界のどこに立っているか。町や洞から出たときに、ここへ戻す。
var world_pos: Vector2i = Vector2i.ZERO

## いま入っている拠点地（{} なら世界の上に立っている）。
## {"kind": "town"/"cave"/"castle", "danger": int, "index": int}
var site: Dictionary = {}

## 難度の軸。**「地下 N 階」が担っていたものをそのまま引き継ぐ。**
##
## 世界の上では「門からの陸路距離」で決まり、洞の中では「その洞の危険度＋階」。
## data/*.json の floor_min / floor_max もこの目盛りなので、名前だけ変えて
## 中身は据え置きにしてある（実測で合わせた難度曲線を捨てないため）。
var floor_number: int = 1
var gold: int = 0
var steps: int = 0
var rng: DetRng = null

## 撃破数と、そのランで「稼いだ」ゴールドの累計。
##
## スコアに使うのは所持金ではなく累計。所持金で測ると、出店で使うほど
## 恒久報酬が減ることになり、買わずに抱えるのが最適解になってしまう。
var kills: int = 0
var gold_earned: int = 0

## 手持ちの装備（equipment.json の ID の列）。装備中のものは PartyMember 側が持つ。
## ゴールドと同じくラン内資源で、全滅で失う。
var gear_stock: Array[String] = []

## イベントが残す一時的な効果。**すべてラン内資源**（全滅で消える）。
## 恒久資産には触らない、という決めごとを跨がないための置き場。
var event_encounter_bias := 0   ## -1 で遭遇が減り、+1 で増える
var event_bias_steps := 0       ## 効果が残る歩数
var event_shop_bonus := 0       ## 町の品数に足す
var event_boon := ""            ## temporary_* のうち 1 つ

## 済んだイベント（同じものを二度出さない）。
var event_done: Dictionary = {}

## これまでに選んだ手の傾向（tag -> 回数）。
##
## **世界がプレイヤーを覚えている**ようにするためのもの。後のイベントで
## 同じ傾向の tag が出たら、その文に一言添える。1 件ごとに独立していると、
## 何件並べても「無関係な出来事の列」で終わる。
var event_tags: Dictionary = {}


## その tag を前に選んだことがあるか。
func chose_tag_before(tag: String) -> bool:
	return int(event_tags.get(tag, 0)) > 0


## 一時効果を 1 歩ぶん進める。切れたら戻す。
func step_event_effects() -> void:
	if event_bias_steps <= 0:
		return
	event_bias_steps -= 1
	if event_bias_steps <= 0:
		event_encounter_bias = 0
		event_boon = ""


## 持ち物（item_id -> 個数）。ゴールドと同じくランの中でしか存在しない。
## 「買ったものを持ち帰れる」ようにすると、出店が拠点の延長になって
## 道中の判断が薄まるので、ここは必ず捨てる側に置く。
var inventory: Dictionary = {}


func _ready() -> void:
	if not load_game():
		roster = _build_default_roster()
		cross_world = empty_cross_world()


func _build_default_roster() -> Array[PartyMember]:
	var members: Array[PartyMember] = []
	for entry in DEFAULT_PARTY:
		members.append(PartyMember.create(String(entry["name"]), String(entry["job"])))
	return members


## 出撃する 4 人。今は名簿の先頭 4 人固定だが、拠点 UI で選ばせる余地を残す。
## 出撃する 4 人（名簿の添字）。
##
## 名簿が 4 人固定だと拠点の「出撃する」が選択にならない。控えを置いて、
## 誰を連れて行くかを決めさせる。熟練度は職業ごと・本人ごとに積むので、
## 「留守番させた者は育たない」が効いてくる。
var active_indices: Array[int] = []

## 迎えられる仲間の名前。使い切ったら番号を付ける。
const RECRUIT_NAMES := ["ミナ", "ルカ", "トア", "シオ", "ヤト", "リン", "クド", "エマ"]

## 仲間を迎える値段。1 人増えるごとに上がる（無限に増やせると編成が意味を失う）。
const RECRUIT_BASE_PRICE := 24
const RECRUIT_STEP := 18
const ROSTER_LIMIT := 8


func active_party() -> Array[PartyMember]:
	_ensure_active_indices()
	var party: Array[PartyMember] = []
	for i in active_indices:
		if i >= 0 and i < roster.size():
			party.append(roster[i])
	return party


## 選ばれていない者を含む名簿の全員。拠点の編成画面で使う。
func all_members() -> Array[PartyMember]:
	return roster


func is_active(index: int) -> bool:
	return index in active_indices


## 出撃するかどうかを切り替える。4 人を超えるときと 1 人未満になるときは断る。
func toggle_active(index: int) -> bool:
	_ensure_active_indices()
	if index < 0 or index >= roster.size():
		return false
	if index in active_indices:
		if active_indices.size() <= 1:
			return false
		active_indices.erase(index)
		return true
	if active_indices.size() >= PARTY_SIZE:
		return false
	active_indices.append(index)
	# 並び順は名簿順に揃える（選んだ順で前衛が変わると分かりにくい）
	active_indices.sort()
	return true


func recruit_price() -> int:
	return RECRUIT_BASE_PRICE + RECRUIT_STEP * maxi(roster.size() - PARTY_SIZE, 0)


func can_recruit() -> bool:
	return roster.size() < ROSTER_LIMIT


## 仲間を迎える。恒久通貨で払う（ランをまたいで残る買い物なので）。
## 職業は基本職から選ぶ。上級職は本人が熟練を積んで解放するもの。
func recruit() -> PartyMember:
	if not can_recruit() or echo < recruit_price():
		return null
	echo -= recruit_price()
	var index := roster.size()
	var member_name := String(RECRUIT_NAMES[index % RECRUIT_NAMES.size()])
	if index >= RECRUIT_NAMES.size():
		member_name += str(index / RECRUIT_NAMES.size() + 1)
	# 職業は名簿の人数で決める（乱数を使わない＝同じ手順から同じ結果）
	const STARTING_JOBS := ["soldier", "priest", "mage", "thief"]
	var job := String(STARTING_JOBS[index % STARTING_JOBS.size()])
	var member := PartyMember.create(member_name, job)
	roster.append(member)
	# 保存は呼び出し側の責任にする。ここで書くと、テストが実セーブを
	# 書き換えてしまう（実際に名簿を 1 人に減らした）。
	return member


## 出撃メンバーが未設定・壊れているときに整える。
## 古いセーブには active_indices が無いので、先頭 4 人に落ちる。
func _ensure_active_indices() -> void:
	var valid: Array[int] = []
	for i in active_indices:
		if i >= 0 and i < roster.size() and i not in valid:
			valid.append(i)
	active_indices = valid
	# 足りないぶんを埋めるのは**空のときだけ**。
	# 減ったら毎回埋め直すと、外した者がすぐ戻ってきて編成ができない
	# （実際にテストがそれを捕まえた）。
	if active_indices.is_empty():
		var at := 0
		while active_indices.size() < mini(PARTY_SIZE, roster.size()) and at < roster.size():
			active_indices.append(at)
			at += 1
	active_indices.sort()


# --------------------------------------------------------------------------
# ラン
# --------------------------------------------------------------------------


func start_new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else _fresh_seed()
	rng = DetRng.new(run_seed)
	# 世界を先に作る。危険度は「門からの陸路距離」で決まるので、
	# 地形が決まらないと難度も決まらない。
	world = WorldGenerator.generate(DetRng.new(run_seed).fork("world"))
	world_pos = world.start_pos
	site = {}
	floor_number = 1
	gold = 0
	steps = 0
	kills = 0
	gold_earned = 0
	inventory = {}
	event_encounter_bias = 0
	event_bias_steps = 0
	event_shop_bonus = 0
	event_boon = ""
	event_done = {}
	event_tags = {}
	run_active = true
	runs_attempted += 1
	for m in active_party():
		m.reset_for_run()
	_apply_upgrades_to_run()
	run_started.emit(run_seed)
	floor_changed.emit(floor_number)


## 買ったアップグレードをランの初期状態に反映する。
##
## 能力値には触らない。ランごとにレベルが 1 に戻るのが仕組みの土台なので、
## そこを恒久強化で埋めると土台が消える。手に入るのは「立ち上がりの楽さ」だけ。
## 職業ごとの初期装備を支給する。
##
## 裸で潜らせない、というだけのもの。毎ラン同じものが出るので積み上がらず、
## 「恒久強化は能力値に触れない」という不変条件とも噛み合う。
func _grant_starting_gear() -> void:
	for m in active_party():
		for gear_id in Database.job(m.job_id).get("starting_gear", []):
			var id := String(gear_id)
			if Database.gear(id).is_empty():
				continue
			add_gear(id)
			equip_gear(m, id)
		m.hp = m.max_hp()
		m.mp = m.max_mp()


## 1 ランに 1 度だけ全滅をまぬがれる残り回数（「命の綱」）。
## **ラン内資源。** 恒久側には何も積まない。
var lifeline_left := 0


## 出撃前から在り処が分かっている封（「封の言い伝え」）。
func reveal_known_seals() -> Array[String]:
	var told: Array[String] = []
	if world == null:
		return told
	var count := upgrade_value("known_seals")
	for i in mini(count, world.seals.size()):
		world.seals[i]["known"] = true
		var at: Vector2i = world.seals[i].get("pos", Vector2i.ZERO)
		told.append("%s は %s の 洞。" % [
			String(world.seals[i].get("name", "封")), world.biome_name_at(at.x, at.y)
		])
	return told


## 全滅を 1 度だけ肩代わりする。使えたら true。
func spend_lifeline() -> bool:
	if lifeline_left <= 0:
		return false
	lifeline_left -= 1
	for m in active_party():
		m.hp = maxi(m.max_hp() / 4, 1)
		m.cure_poison()
	return true


func _apply_upgrades_to_run() -> void:
	_grant_starting_gear()
	lifeline_left = upgrade_value("lifeline")
	gold = upgrade_value("start_gold")
	var herbs := upgrade_value("start_herb")
	if herbs > 0:
		add_item("herb", herbs)


## シードだけは実時間から取る。ここから先は一切の乱数がこの種から決まる。
func _fresh_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000) & 0x7FFFFFFF


## 系統ごとに独立した RNG。地形生成で乱数を余分に引いても
## 敵の出現や宝の中身がずれないようにする。
## 系統ごとに独立した RNG。
##
## 場所も混ぜる。危険度だけでフォークすると、**同じ危険度の別の洞で
## まったく同じ地形と同じ敵が出る**（世界が広くなったぶん、これは目に見える）。
func rng_for(label: String) -> DetRng:
	var place := "world" if site.is_empty() else "%s%d" % [site.get("kind", "site"), int(site.get("index", 0))]
	return DetRng.new(run_seed).fork("%s:%s:%d" % [label, place, floor_number])


## 洞の中で 1 階降りる。危険度はその洞のぶんに階を足す（上限 10）。
func descend() -> void:
	site["floor"] = int(site.get("floor", 1)) + 1
	floor_number = mini(
		int(site.get("danger", 1)) + int(site.get("floor", 1)) - 1, WorldMap.MAX_DANGER
	)
	deepest_floor = maxi(deepest_floor, floor_number)
	floor_changed.emit(floor_number)


## 拠点地から出たあと、その 1 マス外へ降ろす。
##
## 中に居た場所（拠点地のマス）へそのまま戻すと、**一歩動いてまた入る**。
## 人が操作していれば「出たのにまた入った」で済むが、自動プレイは
## 町の出入りを延々と繰り返して先へ進まなくなった（100 秒で戦闘 1 回）。
## DQ でも町を出れば町の外に立つ。そこに合わせる。
func step_outside_site(from: Vector2i) -> Vector2i:
	if world == null:
		return from
	for step in FieldMap.NEIGHBORS:
		var at: Vector2i = from + step
		if world.is_walkable(at.x, at.y) and not world.sites.has(at):
			return at
	return from


## 世界の上を 1 歩。危険度は立っている場所で決まる。
func stand_on_world(at: Vector2i) -> void:
	world_pos = at
	site = {}
	if world != null:
		floor_number = world.danger_at(at.x, at.y)
	deepest_floor = maxi(deepest_floor, floor_number)
	floor_changed.emit(floor_number)


## 拠点地に入る。洞は 1 階から、町と城はその場の危険度のまま。
func enter_site(at: Vector2i) -> Dictionary:
	if world == null:
		return {}
	var found: Dictionary = world.site_at(at).duplicate()
	if found.is_empty():
		return {}
	found["pos"] = at
	found["floor"] = 1
	site = found
	floor_number = int(found.get("danger", 1))
	deepest_floor = maxi(deepest_floor, floor_number)
	floor_changed.emit(floor_number)
	return site


## その場所で次の拍が起きるか（起きなければ空）。
##
## 拍は順番どおりにしか進まない。3 拍目の土地へ先に着いても何も起きない。
## **順序を崩すと話が読めなくなる**ので、進みは 1 本道に保つ。
func story_beat_at(pos: Vector2i) -> Dictionary:
	if world == null:
		return {}
	var beat := world.next_beat()
	if beat.is_empty():
		return {}
	if String(beat.get("site_id", "")) != world.site_id_at(pos):
		return {}
	return beat


## 拍を 1 つ進める。
func advance_story() -> void:
	if world != null:
		world.story_beat += 1


## 物語がどこまで来たか（画面に出す）。
func story_progress() -> String:
	if world == null or world.story.get("beats", []).is_empty():
		return ""
	return "%d/%d" % [world.story_beat, world.story.get("beats", []).size()]


## 洞から任意で出られるか。
##
## **用が済んでいるときだけ。** 封がまだ在る洞で使えると、番人を避けて
## 出入りを繰り返す近道になる。
func can_escape_site() -> bool:
	if String(site.get("kind", "")) != "cave":
		return false
	var s := seal_here()
	return s.is_empty() or bool(s.get("broken", false))


## いま入っている洞に封があるか（無ければ空）。
func seal_here() -> Dictionary:
	if world == null or String(site.get("kind", "")) != "cave":
		return {}
	return world.seal_at(Vector2i(site.get("pos", Vector2i(-1, -1))))


## 封を解く。解けたら true。
func break_seal() -> bool:
	var s := seal_here()
	if s.is_empty() or bool(s.get("broken", false)):
		return false
	s["broken"] = true
	return true


func seals_remaining() -> int:
	return world.seals_remaining() if world != null else 0


## いま立っている土地の生物相。敵の抽選と絵の両方に使う。
## 洞の中ではその洞が建っている土地の生物相を引き継ぐ。
func biome_here() -> String:
	if not site.is_empty():
		return String(site.get("biome", ""))
	if world == null:
		return ""
	return world.biome_id_at(world_pos.x, world_pos.y)


## いまの土地の名（「雪原」など）。HUD に出す。
func place_name() -> String:
	if not site.is_empty():
		return String(site.get("place", ""))
	if world == null:
		return ""
	return world.biome_name_at(world_pos.x, world_pos.y)


## 洞の何階まで降りられるか。深い土地の洞ほど階が多い（危険度が上限で頭打ちになる）。
func cave_depth() -> int:
	return clampi(1 + int(site.get("danger", 1)) / 3, 1, 3)


## ランの終了。ここで失うものを捨て、持ち帰るものだけを残して保存する。
## 物語の結末の 1 行。まだ選んでいなければ、そこまでの状態を短く述べる。
func _story_ending() -> String:
	if world == null or not bool(world.story.get("valid", false)):
		return ""
	var who := String(world.story.get("skin", {}).get("anchor_name", ""))
	if world.story_choice == "":
		if world.story_beat <= 0:
			return ""
		return "%s の話は、まだ途中で途切れた。" % who
	var resolved := StoryArcGenerator.resolve_ending(world.story, world.story_choice, [])
	var line := String(resolved.get("line", ""))
	return line if line != "" else "%s との約束は果たされた。" % who


func end_run(victory: bool) -> Dictionary:
	# 道中スコアは失う側の値（階・撃破・稼ぎ）から作り、残響だけを残す側へ移す。
	# 全滅でも必ず何かが増えるので、失敗したランも次のランの足しになる。
	var score := run_score(victory)
	var earned_echo := echo_for_score(score)
	echo += earned_echo

	var summary := {
		"victory": victory,
		"seed": run_seed,
		# 物語の結末。選ばなかった（途中で終わった）ときは、たどり着いた拍までで
		# 締める。**六拍を回収しないと、物語を出した意味が無い。**
		"story_ending": _story_ending(),
		"floor": floor_number,
		"gold": gold,
		"gold_earned": gold_earned,
		"kills": kills,
		"steps": steps,
		"score": score,
		"echo": earned_echo,
		"echo_total": echo,
		"members": [],
	}
	for m in active_party():
		summary["members"].append({
			"name": m.name,
			"job": m.job_id,
			"job_name": Database.job(m.job_id).get("name", m.job_id),
			"level": m.level,
			"mastery_rank": m.mastery_rank(),
			"learned": m.learned.duplicate(),
		})
		# level / hp / mp / 毒 はここで捨てる。job_exp と learned は触らない＝持ち帰る。
		m.reset_for_run()

	run_active = false
	gold = 0
	gold_earned = 0
	kills = 0
	steps = 0
	floor_number = 1
	inventory = {}
	gear_stock.clear()
	save_game()
	run_ended.emit(victory, summary)
	return summary


# --------------------------------------------------------------------------
# ゴールドと持ち物（ランの中でしか存在しない資源）
# --------------------------------------------------------------------------


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	return true


## ゴールドを得る。稼いだ累計も同時に伸ばす（スコアはこちらで測る）。
func earn_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_earned += amount


func add_item(item_id: String, count: int = 1) -> void:
	if count <= 0 or not Database.all_items().has(item_id):
		return
	inventory[item_id] = item_count(item_id) + count


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


## 1 個消費する。持っていなければ false。
func consume_item(item_id: String) -> bool:
	var have := item_count(item_id)
	if have <= 0:
		return false
	if have == 1:
		inventory.erase(item_id)
	else:
		inventory[item_id] = have - 1
	return true


## 所持品の一覧。並び順を確定させる（辞書の列挙順に依存させない）。
func inventory_ids() -> Array:
	var ids := inventory.keys()
	ids.sort()
	return ids


# --------------------------------------------------------------------------
# 装備（これもラン内資源）
# --------------------------------------------------------------------------


func add_gear(gear_id: String) -> void:
	if Database.gear(gear_id).is_empty():
		return
	gear_stock.append(gear_id)


func remove_gear(gear_id: String) -> bool:
	var at := gear_stock.find(gear_id)
	if at < 0:
		return false
	gear_stock.remove_at(at)
	return true


## その者がそのスロットに装備できる手持ち（並び順を確定させる）。
func gear_stock_for_slot(slot: String) -> Array[String]:
	var result: Array[String] = []
	for id in gear_stock:
		if String(Database.gear(id).get("slot", "")) == slot:
			result.append(id)
	result.sort()
	return result


## 装備を付け替える。外れたものは手持ちへ戻る。
func equip_gear(member: PartyMember, gear_id: String) -> bool:
	if not remove_gear(gear_id):
		return false
	var removed := member.equip(gear_id)
	if removed != "":
		gear_stock.append(removed)
	return true


func unequip_gear(member: PartyMember, slot: String) -> bool:
	var removed := member.unequip(slot)
	if removed == "":
		return false
	gear_stock.append(removed)
	return true


# --------------------------------------------------------------------------
# 残響（恒久通貨）とアップグレード
# --------------------------------------------------------------------------

## スコアの重み。すべて整数演算で閉じる（同じランからは必ず同じ点が出る）。
const SCORE_PER_FLOOR := 100
const SCORE_PER_KILL := 12
const SCORE_GOLD_DIVISOR := 4
const SCORE_VICTORY_BONUS := 600
## このスコアごとに残響 1 枚。
##
## 全アップグレードを極めるのに 163 必要なので、10 階を制覇したランで 39、
## 浅い階で全滅したランで 5〜10 ほど入る計算にしてある。1 回の生還で
## 全部揃ってしまうと、拠点で選ぶ楽しみがその時点で終わる。
const SCORE_PER_ECHO := 50


## そのランの道中スコア。深く潜り、多く倒し、多く稼いだぶんだけ伸びる。
func run_score(victory: bool) -> int:
	var score := floor_number * SCORE_PER_FLOOR
	score += kills * SCORE_PER_KILL
	@warning_ignore("integer_division")
	score += gold_earned / SCORE_GOLD_DIVISOR
	if victory:
		score += SCORE_VICTORY_BONUS
	return score


@warning_ignore("integer_division")
func echo_for_score(score: int) -> int:
	return score / SCORE_PER_ECHO


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_maxed(id: String) -> bool:
	return upgrade_level(id) >= int(Database.upgrade(id).get("levels", 0))


## 次の 1 段の値段。段が上がるほど高くなる。
func upgrade_price(id: String) -> int:
	var u := Database.upgrade(id)
	if u.is_empty():
		return 0
	return int(u.get("cost", 0)) + int(u.get("cost_step", 0)) * upgrade_level(id)


## 買えるかどうかの判定だけを切り出す。保存を伴わないので、
## ここだけならテストから安全に叩ける（buy_upgrade はセーブを書き換える）。
func can_buy_upgrade(id: String) -> bool:
	if run_active or Database.upgrade(id).is_empty() or upgrade_maxed(id):
		return false
	return echo >= upgrade_price(id)


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	echo -= upgrade_price(id)
	upgrades[id] = upgrade_level(id) + 1
	save_game()
	return true


## その効果の現在値（段数 x 1 段ぶんの増分の合計）。
## 効果を持つアップグレードが増えても、参照側はこの 1 本だけを見ればよい。
func upgrade_value(effect: String) -> int:
	var total := 0
	for id in Database.upgrade_ids():
		var u := Database.upgrade(String(id))
		if String(u.get("effect", "")) == effect:
			total += int(u.get("value", 0)) * upgrade_level(String(id))
	return total


# --------------------------------------------------------------------------
# 拠点
# --------------------------------------------------------------------------


## 転職。**どこでも自由にできる。取り上げるものは何も無い。**
##
## もとはラン中を禁じ、そのあと「レベルを 1 に戻す」で釣り合わせようとしたが、
## どちらもこのゲームの決めごとに反していた。
##
##   * 熟練・覚えた技・資源・名簿は**永久資産**で、ここに手を付けてはいけない
##   * **利便性を損なう代償は、ラン中であっても入れない**
##
## レベルは人に付いているので、ラン中に職を変えると同じ強さで別の技一式が
## 手に入る。それは承知のうえで許す。乗り換えの自由を取る、という判断。
func change_job(member: PartyMember, job_id: String) -> bool:
	if not member.change_job(job_id):
		return false
	save_game()
	return true


# --------------------------------------------------------------------------
# セーブ（恒久データのみ）
# --------------------------------------------------------------------------


## セーブの形式。上げたら load_from_dict() に旧版の読み方を残すこと。
## セーブの形式。またぐ物語の永続状態を足したので 3 へ。
## **古い版を必ず読めること**（無い項目は空へ落ちる）。
const SAVE_VERSION := 3


## 恒久データを辞書にする。ファイル入出力と分けてあるので、
## 「書いて読み直しても壊れない」をテストから確かめられる。
## 中断の置き場。本体セーブとは分ける（拠点の恒久データを汚さない）。
const SUSPEND_PATH := "user://suspend.json"

## 中断の形式。
const SUSPEND_VERSION := 1


## 中断できるか（ラン中で、まだ終わっていない）。
func can_suspend() -> bool:
	return run_active and world != null


## ラン途中の状態を書き出す。
##
## **世界そのものは書かない。** 決定性があるので `run_seed` から作り直せる
## （64x48 の地形と拠点地と物語を丸ごと書くより、種 1 つのほうが安く確実）。
## 書くのは「種から復元できないもの」だけ ―― どこに居て、何を解いて、
## 何を持っているか。
func to_suspend() -> Dictionary:
	var broken: Array = []
	for s in world.seals:
		broken.append(bool(s.get("broken", false)))
	var done: Array = []
	for pos in event_done:
		done.append([int(pos.x), int(pos.y)])
	var run_members: Array = []
	for m in active_party():
		run_members.append(m.to_run_dict())
	return {
		"version": SUSPEND_VERSION,
		"seed": run_seed,
		"pos": [world_pos.x, world_pos.y],
		"site": site.duplicate(),
		"danger": floor_number,
		"gold": gold, "steps": steps, "kills": kills, "gold_earned": gold_earned,
		"inventory": inventory.duplicate(),
		"gear_stock": gear_stock.duplicate(),
		"runs_attempted": runs_attempted,
		"seals_broken": broken,
		"events_done": done,
		"event_tags": event_tags.duplicate(),
		"story_beat": world.story_beat,
		"story_choice": world.story_choice,
		"lifeline": lifeline_left,
		"members": run_members,
	}


func save_suspend() -> bool:
	if not can_suspend():
		return false
	var file := FileAccess.open(SUSPEND_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_suspend(), "  "))
	return true


func has_suspend() -> bool:
	return FileAccess.file_exists(SUSPEND_PATH)


func clear_suspend() -> void:
	if not has_suspend():
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(SUSPEND_PATH)


## 中断から再開する。**世界は種から作り直す。**
func resume() -> bool:
	if not has_suspend():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUSPEND_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		clear_suspend()
		return false
	var d: Dictionary = parsed

	run_seed = int(d.get("seed", 0))
	rng = DetRng.new(run_seed)
	world = WorldGenerator.generate(DetRng.new(run_seed).fork("world"))
	if world == null or world.seals.is_empty():
		clear_suspend()
		return false

	var raw_pos: Array = d.get("pos", [0, 0])
	world_pos = Vector2i(int(raw_pos[0]), int(raw_pos[1]))
	site = d.get("site", {}).duplicate()
	floor_number = int(d.get("danger", 1))
	gold = int(d.get("gold", 0))
	steps = int(d.get("steps", 0))
	kills = int(d.get("kills", 0))
	gold_earned = int(d.get("gold_earned", 0))
	inventory = d.get("inventory", {}).duplicate()
	gear_stock.assign(d.get("gear_stock", []))
	runs_attempted = int(d.get("runs_attempted", runs_attempted))
	lifeline_left = int(d.get("lifeline", 0))
	event_tags = d.get("event_tags", {}).duplicate()

	var broken: Array = d.get("seals_broken", [])
	for i in mini(broken.size(), world.seals.size()):
		world.seals[i]["broken"] = bool(broken[i])
	event_done = {}
	for raw in d.get("events_done", []):
		var pair: Array = raw
		if pair.size() == 2:
			event_done[Vector2i(int(pair[0]), int(pair[1]))] = true
	world.story_beat = int(d.get("story_beat", 0))
	world.story_choice = String(d.get("story_choice", ""))

	var run_members: Array = d.get("members", [])
	var party := active_party()
	for i in mini(run_members.size(), party.size()):
		party[i].load_run_dict(run_members[i])

	run_active = true
	clear_suspend()   # 読んだら消す（同じ中断を二度使えないようにする）
	run_started.emit(run_seed)
	floor_changed.emit(floor_number)
	return true


## 開発用の名前付き保存。**中断と同じ書き出しを使い回す。**
##
## 「この世界のこの場面」を読み直せると、不具合の再現とバランス確認が一気に楽になる。
## 別の書式を作ると中断と二重管理になるので、置き場だけ分ける。
const DEV_DIR := "user://dev/"


func dev_save(name: String) -> bool:
	if not can_suspend():
		return false
	DirAccess.make_dir_recursive_absolute(DEV_DIR)
	var file := FileAccess.open("%s%s.json" % [DEV_DIR, name], FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_suspend(), "  "))
	return true


## 名前付き保存を読む。中断の経路をそのまま通すため、いったん中断へ写す。
func dev_load(name: String) -> bool:
	var path := "%s%s.json" % [DEV_DIR, name]
	if not FileAccess.file_exists(path):
		push_warning("開発用の保存が無い: %s" % path)
		return false
	var body := FileAccess.get_file_as_string(path)
	var out := FileAccess.open(SUSPEND_PATH, FileAccess.WRITE)
	if out == null:
		return false
	out.store_string(body)
	out.close()
	return resume()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deepest_floor": deepest_floor,
		"runs_attempted": runs_attempted,
		"echo": echo,
		"upgrades": upgrades,
		"roster": roster.map(func(m: PartyMember) -> Dictionary: return m.to_dict()),
		"active": active_indices,
		"cross_world": cross_world,
	}


## 辞書から恒久データを復元する。**古い版を必ず読めること。**
## 無い項目は既定値に落ちるので、version が上がっても遊んでいる人のデータは消えない。
func load_from_dict(data: Dictionary) -> bool:
	# またぐ物語。**古いセーブには無いので空へ落とす。**
	# 版が上がっても遊んでいる人のデータを壊さない、という約束を守る。
	var raw_cross: Variant = data.get("cross_world", null)
	cross_world = raw_cross if typeof(raw_cross) == TYPE_DICTIONARY else empty_cross_world()
	for key in empty_cross_world():
		if not cross_world.has(key):
			cross_world[key] = empty_cross_world()[key]

	deepest_floor = int(data.get("deepest_floor", 0))
	runs_attempted = int(data.get("runs_attempted", 0))
	# version 1 のセーブには残響もアップグレードも無い。既定値で素直に読める。
	echo = int(data.get("echo", 0))
	upgrades = data.get("upgrades", {})
	roster.clear()
	for entry in data.get("roster", []):
		roster.append(PartyMember.from_dict(entry))
	# 古いセーブには出撃メンバーの指定が無い。先頭 4 人に落ちる。
	active_indices.clear()
	for i in data.get("active", []):
		active_indices.append(int(i))
	_ensure_active_indices()
	return not roster.is_empty()


## セーブする。本体は「書き終わったものと差し替える」形でしか触らない。
##
## 直接開いて書くと、開いた瞬間から書き終わるまで本体が空になる。
## そこで落ちるとセーブが消えるので、控えに寄せる → 別名で書く → 差し替える、
## の順にする。どの時点で落ちても、本体か控えのどちらかは必ず生きている。
func save_game() -> void:
	var text := JSON.stringify(to_dict(), "  ")
	_backup_save()

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("セーブに失敗: %s" % temp_path)
		return
	file.store_string(text)
	file.close()  # 差し替える前に確実に閉じる（Windows では開いたままだと動かせない）

	# 書けたものを読み直して確かめる。壊れた JSON で本体を潰すのが最悪なので、
	# 差し替える前にここで止める。
	if typeof(JSON.parse_string(FileAccess.get_file_as_string(temp_path))) != TYPE_DICTIONARY:
		push_error("書いたセーブが読み返せない。差し替えを見送った。")
		return

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("user:// を開けない。セーブを差し替えられない。")
		return
	if dir.file_exists(save_path) and dir.remove(save_path) != OK:
		push_error("古いセーブを消せない。差し替えを見送った。")
		return
	if dir.rename(temp_path, save_path) != OK:
		push_error("セーブを差し替えられない。控えは %s に残っている。" % backup_path)


## 書く前に 1 つ前を控えへ寄せる。壊れた JSON を書いてしまっても、
## 前回の状態までは戻せる。
func _backup_save() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var current := FileAccess.get_file_as_string(save_path)
	if current.strip_edges() == "":
		return  # 空を控えにしても意味が無い
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string(current)


func load_game() -> bool:
	if _load_file(save_path):
		return true
	# 本体が読めないときだけ控えを試す。黙って戻すと「進んでいない」と誤解されるので、
	# 戻したことは警告に残す。
	if FileAccess.file_exists(backup_path) and _load_file(backup_path):
		push_warning("セーブが読めなかったので、1 つ前の控えから復帰した。")
		# 戻したらその場で本体を作り直す。書き戻さないと次の起動でも同じ警告が出て、
		# 鳴りっぱなしの警告は本物の異常を隠す。
		save_game()
		return true
	return false


func _load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("セーブが壊れている: %s" % path)
		return false
	return load_from_dict(parsed)
