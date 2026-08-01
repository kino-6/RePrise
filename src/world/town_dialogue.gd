extends RefCounted

## 町の台詞を `data/town_dialogue.json` から読む。
##
## 役や町の構造は Script が決め、文章だけをデータで差し替えられるようにする。
## ファイルが無い・壊れている場合も町生成は止めず、短い既定文へ落とす。

const PATH := "res://data/town_dialogue.json"

static var _data: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
	else:
		push_warning("%s が読めない。町の台詞は既定文を使う。" % PATH)


static func role_lines(role: String) -> Array:
	_ensure()
	var roles: Dictionary = _data.get("roles", {})
	return _strings(
		roles.get(role, []),
		["旅の準備はできていますか？"]
	)


## 会話窓へ出す役名。画像IDとは分け、呼び名だけ差し替えられるようにする。
static func role_name(role: String) -> String:
	_ensure()
	var names: Dictionary = _data.get("role_names", {})
	return String(names.get(role, "町の人"))


## 生業に対応する仕事場の表示文。仕組みは TownInteraction、文章はここに置く。
static func facility(industry_id: String) -> Dictionary:
	_ensure()
	var facilities: Dictionary = _data.get("facilities", {})
	var entry: Variant = facilities.get(industry_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {
			"name": "町の仕事場",
			"hint": "町の仕事場で、旅の準備を整えられる。",
			"repeat": "この仕事場は利用済みだ。",
		}
	return (entry as Dictionary).duplicate()


static func profile_lines(group: String, profile_id: String) -> Array:
	_ensure()
	var profiles: Dictionary = _data.get("profiles", {})
	var entries: Dictionary = profiles.get(group, {})
	var fallback := ["町の様子について話してくれた。"]
	match group:
		"industries":
			fallback = ["この町では、みんなで仕事を分けている。"]
		"rulers":
			fallback = ["町の決まりは、入口の掲示板で確認できる。"]
		"problems":
			fallback = ["今は町全体が困っている。"]
	return _strings(entries.get(profile_id, []), fallback)


static func _ensure() -> void:
	if not _loaded:
		reload()


static func _strings(value: Variant, fallback: Array) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return fallback
	var result: Array[String] = []
	for raw in value:
		var text := String(raw).strip_edges()
		if text != "":
			result.append(text)
	return fallback if result.is_empty() else result
