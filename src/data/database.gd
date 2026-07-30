class_name Database
extends RefCounted

## data/*.json を読むだけの層。
##
## 状態を持たない読み取り専用データなので Node にはせず、静的クラスにしてある。
## オートロードだと `--headless --script` 実行時にグローバル登録されず、
## テストから触れなくなるため。初回アクセス時に自動で読み込む。
##
## ゲーム内容は JSON 側に置き、コードには持ち込まない。バランス調整でスクリプトを
## 触らずに済むし、後段でローカル AI に文章を作らせる際も「生成物を JSON へ焼く」
## だけで取り込めるようにしておく。

static var jobs: Dictionary = {}
static var abilities: Dictionary = {}
static var monsters: Dictionary = {}
static var items: Dictionary = {}
static var equipment: Dictionary = {}
static var upgrades: Dictionary = {}

static var _loaded := false


static func _ensure() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	jobs = _load_json("res://data/jobs.json")
	abilities = _load_json("res://data/abilities.json")
	monsters = _load_json("res://data/monsters.json")
	items = _load_json("res://data/items.json")
	equipment = _load_json("res://data/equipment.json")
	upgrades = _load_json("res://data/upgrades.json")
	_loaded = true


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("データが開けない: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON が辞書ではない: %s" % path)
		return {}
	var result: Dictionary = parsed
	result.erase("_comment")
	return result


static func all_jobs() -> Dictionary:
	_ensure()
	return jobs


static func all_abilities() -> Dictionary:
	_ensure()
	return abilities


static func all_monsters() -> Dictionary:
	_ensure()
	return monsters


static func job(id: String) -> Dictionary:
	_ensure()
	return jobs.get(id, {})


static func ability(id: String) -> Dictionary:
	_ensure()
	return abilities.get(id, {})


static func monster(id: String) -> Dictionary:
	_ensure()
	return monsters.get(id, {})


static func all_items() -> Dictionary:
	_ensure()
	return items


static func item(id: String) -> Dictionary:
	_ensure()
	return items.get(id, {})


static func all_equipment() -> Dictionary:
	_ensure()
	return equipment


static func gear(id: String) -> Dictionary:
	_ensure()
	return equipment.get(id, {})


## その階の出店に並ぶ装備。品揃えが揺れないよう並び順を確定させる。
static func gear_ids_for_floor(floor_number: int) -> Array:
	_ensure()
	var result: Array = []
	for id in equipment.keys():
		if floor_number >= int(equipment[id].get("floor_min", 1)):
			result.append(id)
	result.sort()
	return result


## 装備の一覧（スロット順 → ID 順）。つよさ画面と装備画面で同じ並びにする。
static func gear_ids_in_slot(slot: String) -> Array:
	_ensure()
	var result: Array = []
	for id in equipment.keys():
		if String(equipment[id].get("slot", "")) == slot:
			result.append(id)
	result.sort()
	return result


static func all_upgrades() -> Dictionary:
	_ensure()
	return upgrades


static func upgrade(id: String) -> Dictionary:
	_ensure()
	return upgrades.get(id, {})


## 並び順を確定させてから返す（拠点の一覧が起動ごとに入れ替わらないように）。
static func upgrade_ids() -> Array:
	_ensure()
	var ids := upgrades.keys()
	ids.sort()
	return ids


## その階の出店に並ぶ品。深いほど品揃えが増える。
## 並び順を確定させてから返す（キーの列挙順に依存すると品揃えが揺れる）。
static func item_ids_for_floor(floor_number: int) -> Array:
	_ensure()
	var result: Array = []
	for id in items.keys():
		if floor_number >= int(items[id].get("floor_min", 1)):
			result.append(id)
	result.sort()
	return result


static func job_ids() -> Array:
	_ensure()
	var ids := jobs.keys()
	ids.sort()
	return ids


## その階層に出現しうるモンスター ID。並び順を確定させてから返す
## （キーの列挙順に依存すると、同じシードでも別の敵が出かねない）。
##
## ボスは通常の遭遇には混ぜない。主の間でしか出会わないから主なので。
static func monster_ids_for_floor(floor_number: int, biome: String = "") -> Array:
	var ids := []
	var monsters := all_monsters()
	for id in monsters:
		var m: Dictionary = monsters[id]
		if bool(m.get("boss", false)):
			continue
		if floor_number < int(m.get("floor_min", 1)) or floor_number > int(m.get("floor_max", 99)):
			continue
		# 生物相の指定がある敵はその土地にしか出ない。
		# **指定の無い敵はどこにでも出る**ので、絞ってもプールは空にならない
		# （空にすると、その土地で一度も戦えないまま通り抜けられてしまう）。
		if biome != "":
			var homes: Array = m.get("biomes", [])
			if not homes.is_empty() and biome not in homes:
				continue
		ids.append(id)
	return ids


static func boss_ids_for_floor(floor_number: int) -> Array:
	_ensure()
	var result: Array = []
	for id in monsters.keys():
		var m: Dictionary = monsters[id]
		if not bool(m.get("boss", false)):
			continue
		if floor_number >= int(m.get("floor_min", 1)) and floor_number <= int(m.get("floor_max", 99)):
			result.append(id)
	result.sort()
	return result
