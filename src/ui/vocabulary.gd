class_name Vocabulary
extends RefCounted

## 呼び名と造語の読み込み口（`data/vocabulary.json`）。
##
## **コードを触らずに語を差し替えられる状態にしておくのが目的。**
## 「奈落」「銀の砦」「資源」「危険度」「封」のような造語は見直しの対象なので、
## 定数として散らしておくと、変えるたびに全ファイルを grep することになる。
##
## `Terms` と `Lore` は残してある（呼び出し側は今まで通り `Terms.ECHO` を使う）。
## 変わったのは中身の出所だけ。
##
## ファイルが無い・壊れているときは、引数で渡した既定値に落ちる。
## **語彙が読めないだけでゲームが止まってはいけない。**

const PATH := "res://data/vocabulary.json"

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
		push_warning("%s が読めない。既定の語を使う。" % PATH)


static func _ensure() -> void:
	if not _loaded:
		reload()


## 1 語。`section` は "terms" / "biomes" など、`key` はその中の名前。
static func word(section: String, key: String, fallback: String) -> String:
	_ensure()
	var group: Dictionary = _data.get(section, {})
	var value: Variant = group.get(key, fallback)
	return String(value) if typeof(value) == TYPE_STRING else fallback


## 語の列（語彙表）。空なら既定へ落ちる。
static func words(section: String, key: String, fallback: Array) -> Array:
	_ensure()
	var group: Dictionary = _data.get(section, {})
	var value: Variant = group.get(key, null)
	if typeof(value) == TYPE_ARRAY and not (value as Array).is_empty():
		return value
	return fallback


## 入れ子の語彙表（`seal_names.head` など）。
## `group_key` が空なら section 直下を見る（`seal_names` のように 1 段だけの場合）。
static func nested(section: String, group_key: String, key: String, fallback: Array) -> Array:
	_ensure()
	var group: Dictionary = _data.get(section, {})
	var inner: Variant = group if group_key == "" else group.get(group_key, null)
	if typeof(inner) != TYPE_DICTIONARY:
		return fallback
	var value: Variant = (inner as Dictionary).get(key, null)
	if typeof(value) == TYPE_ARRAY and not (value as Array).is_empty():
		return value
	return fallback
