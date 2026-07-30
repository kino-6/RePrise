class_name GameVersion
extends RefCounted

## ゲームのバージョン。
##
## **手で上げる番号を当てにしない。**
## `application/config/version` は 0.1.0 のまま数十コミット進んだ。人が覚えて
## 上げる仕組みは必ず抜けるので、**放っておいても変わるもの**（git の commit）を
## identity にする。
##
## 刻印は `tools/stamp_version.py` が `data/build.json` へ書き出す。
## 実行時に git を叩かないのは、書き出した配布物に `.git` が無いから
## （エディタでだけ効く仕組みは、不具合報告のときに役に立たない）。
##
## 刻印が無くても動く。無いときは番号だけを出す。
##
## 静的クラスにしてあるのは、オートロードが `--headless --script` で
## 登録されないため（AGENTS.md の落とし穴を参照）。

const STAMP_PATH := "res://data/build.json"

static var _stamp: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(STAMP_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAMP_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_stamp = parsed


## "0.1.0" のような素の数字。**節目にだけ人が上げるもの。**
## 日々の識別はハッシュに任せる。
static func number() -> String:
	var value := String(ProjectSettings.get_setting("application/config/version", ""))
	return value if value != "" else "0.0.0"


## 短縮ハッシュ（刻印が無ければ空）。
static func commit() -> String:
	_ensure()
	return String(_stamp.get("hash", ""))


## コミット日（刻印が無ければ空）。
static func commit_date() -> String:
	_ensure()
	return String(_stamp.get("date", ""))


## コミットしていない変更を含むビルドか。
##
## **ここが true のビルドは他の誰も再現できない。** 不具合報告のとき、
## この 1 文字（*）が「手元だけの状態」を切り分ける。
static func dirty() -> bool:
	_ensure()
	return bool(_stamp.get("dirty", false))


## 表示用。「v0.1.0+efcc6dc*-dev」の形。
##
##   +efcc6dc … どのコミットか
##   *        … コミットしていない変更を含む
##   -dev     … 書き出していないビルド（エディタ / ソースからの起動）
static func label() -> String:
	var text := "v" + number()
	var hash_text := commit()
	if hash_text != "":
		text += "+" + hash_text
		if dirty():
			text += "*"
	if not OS.has_feature("template"):
		text += "-dev"
	return text


## OS のタイトルバーに出す 1 行。
static func window_title() -> String:
	var game_name := String(ProjectSettings.get_setting("application/config/name", "Game"))
	return "%s  %s" % [game_name, label()]


## 不具合報告に貼れる 1 行。日付まで含める。
static func full() -> String:
	var text := label()
	var date := commit_date()
	return text if date == "" else "%s (%s)" % [text, date]
