extends Node

## ラン全体とメタ進行の管理（オートロード名: GameState）。
##
## 「何を失い、何を持ち帰るか」の境界をここ 1 か所に集約する。境界が散ると
## ローグライクは必ず壊れるので、失うものは end_run() で確実に捨てる。

const SAVE_PATH := "user://save.json"
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

# --- ラン中のみ（全滅で消える） ---
var run_active: bool = false
var run_seed: int = 0
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

## 持ち物（item_id -> 個数）。ゴールドと同じくランの中でしか存在しない。
## 「買ったものを持ち帰れる」ようにすると、出店が拠点の延長になって
## 道中の判断が薄まるので、ここは必ず捨てる側に置く。
var inventory: Dictionary = {}


func _ready() -> void:
	if not load_game():
		roster = _build_default_roster()


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
	save_game()
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
	floor_number = 1
	gold = 0
	steps = 0
	kills = 0
	gold_earned = 0
	inventory = {}
	run_active = true
	runs_attempted += 1
	for m in active_party():
		m.reset_for_run()
	_apply_upgrades_to_run()
	run_started.emit(run_seed)
	floor_changed.emit(floor_number)


## 買ったアップグレードをランの初期状態に反映する。
##
## 能力値には触らない。レベルを失うことがランの代償なので、そこを恒久強化で
## 埋めると代償そのものが消える。手に入るのは「立ち上がりの楽さ」だけにする。
func _apply_upgrades_to_run() -> void:
	gold = upgrade_value("start_gold")
	var herbs := upgrade_value("start_herb")
	if herbs > 0:
		add_item("herb", herbs)


## シードだけは実時間から取る。ここから先は一切の乱数がこの種から決まる。
func _fresh_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000) & 0x7FFFFFFF


## 系統ごとに独立した RNG。地形生成で乱数を余分に引いても
## 敵の出現や宝の中身がずれないようにする。
func rng_for(label: String) -> DetRng:
	return DetRng.new(run_seed).fork("%s:%d" % [label, floor_number])


func descend() -> void:
	floor_number += 1
	deepest_floor = maxi(deepest_floor, floor_number)
	floor_changed.emit(floor_number)


## ランの終了。ここで失うものを捨て、持ち帰るものだけを残して保存する。
func end_run(victory: bool) -> Dictionary:
	# 道中スコアは失う側の値（階・撃破・稼ぎ）から作り、残響だけを残す側へ移す。
	# 全滅でも必ず何かが増えるので、失敗したランも次のランの足しになる。
	var score := run_score(victory)
	var earned_echo := echo_for_score(score)
	echo += earned_echo

	var summary := {
		"victory": victory,
		"seed": run_seed,
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
		# level / hp / mp はここで捨てる。job_exp と learned は触らない＝持ち帰る。
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


## 拠点での転職。恒久データが動くので、その場で保存する。
##
## ラン中は禁じる。潜行中に職業を変えられると「レベルを失う」というランの
## 代償が抜け道になり、熟練度の持ち帰りが手応えでなくなる。
func change_job(member: PartyMember, job_id: String) -> bool:
	if run_active:
		return false
	if not member.change_job(job_id):
		return false
	save_game()
	return true


# --------------------------------------------------------------------------
# セーブ（恒久データのみ）
# --------------------------------------------------------------------------


## セーブの形式。上げたら load_from_dict() に旧版の読み方を残すこと。
const SAVE_VERSION := 2


## 恒久データを辞書にする。ファイル入出力と分けてあるので、
## 「書いて読み直しても壊れない」をテストから確かめられる。
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deepest_floor": deepest_floor,
		"runs_attempted": runs_attempted,
		"echo": echo,
		"upgrades": upgrades,
		"roster": roster.map(func(m: PartyMember) -> Dictionary: return m.to_dict()),
		"active": active_indices,
	}


## 辞書から恒久データを復元する。**古い版を必ず読めること。**
## 無い項目は既定値に落ちるので、version が上がっても遊んでいる人のデータは消えない。
func load_from_dict(data: Dictionary) -> bool:
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


func save_game() -> void:
	var data := to_dict()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("セーブに失敗: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "  "))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("セーブが壊れている。初期状態で開始する。")
		return false
	return load_from_dict(parsed)
