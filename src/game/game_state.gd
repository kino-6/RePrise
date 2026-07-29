extends Node

## ラン全体とメタ進行の管理（オートロード名: GameState）。
##
## 「何を失い、何を持ち帰るか」の境界をここ 1 か所に集約する。境界が散ると
## ローグライクは必ず壊れるので、失うものは end_run() で確実に捨てる。

const SAVE_PATH := "user://save.json"
const PARTY_SIZE := 4

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

# --- ラン中のみ（全滅で消える） ---
var run_active: bool = false
var run_seed: int = 0
var floor_number: int = 1
var gold: int = 0
var steps: int = 0
var rng: DetRng = null


func _ready() -> void:
	if not load_game():
		roster = _build_default_roster()


func _build_default_roster() -> Array[PartyMember]:
	var members: Array[PartyMember] = []
	for entry in DEFAULT_PARTY:
		members.append(PartyMember.create(String(entry["name"]), String(entry["job"])))
	return members


## 出撃する 4 人。今は名簿の先頭 4 人固定だが、拠点 UI で選ばせる余地を残す。
func active_party() -> Array[PartyMember]:
	return roster.slice(0, PARTY_SIZE)


# --------------------------------------------------------------------------
# ラン
# --------------------------------------------------------------------------


func start_new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else _fresh_seed()
	rng = DetRng.new(run_seed)
	floor_number = 1
	gold = 0
	steps = 0
	run_active = true
	runs_attempted += 1
	for m in active_party():
		m.reset_for_run()
	run_started.emit(run_seed)
	floor_changed.emit(floor_number)


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
	var summary := {
		"victory": victory,
		"seed": run_seed,
		"floor": floor_number,
		"gold": gold,
		"steps": steps,
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
	steps = 0
	floor_number = 1
	save_game()
	run_ended.emit(victory, summary)
	return summary


# --------------------------------------------------------------------------
# セーブ（恒久データのみ）
# --------------------------------------------------------------------------


func save_game() -> void:
	var data := {
		"version": 1,
		"deepest_floor": deepest_floor,
		"runs_attempted": runs_attempted,
		"roster": roster.map(func(m: PartyMember) -> Dictionary: return m.to_dict()),
	}
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
	var data: Dictionary = parsed
	deepest_floor = int(data.get("deepest_floor", 0))
	runs_attempted = int(data.get("runs_attempted", 0))
	roster.clear()
	for entry in data.get("roster", []):
		roster.append(PartyMember.from_dict(entry))
	return not roster.is_empty()
