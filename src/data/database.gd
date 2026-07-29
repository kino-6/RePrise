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

static var _loaded := false


static func _ensure() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	jobs = _load_json("res://data/jobs.json")
	abilities = _load_json("res://data/abilities.json")
	monsters = _load_json("res://data/monsters.json")
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


static func job_ids() -> Array:
	_ensure()
	var ids := jobs.keys()
	ids.sort()
	return ids


## その階層に出現しうるモンスター ID。並び順を確定させてから返す
## （キーの列挙順に依存すると、同じシードでも別の敵が出かねない）。
static func monster_ids_for_floor(floor_number: int) -> Array:
	_ensure()
	var result: Array = []
	for id in monsters.keys():
		var m: Dictionary = monsters[id]
		if floor_number >= int(m.get("floor_min", 1)) and floor_number <= int(m.get("floor_max", 99)):
			result.append(id)
	result.sort()
	return result
