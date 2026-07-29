class_name GameVersion
extends RefCounted

## ゲームのバージョン。
##
## 数字の原本は project.godot の `application/config/version` ただ 1 か所。
## ここに定数で持つとエクスポート時のファイル情報（.exe のプロパティ）と
## 表示が食い違うので、必ず ProjectSettings から読む。
##
## 静的クラスにしてあるのは、オートロードが `--headless --script` で
## 登録されないため（AGENTS.md の落とし穴を参照）。


## "0.1.0" のような素の数字。
static func number() -> String:
	var value := String(ProjectSettings.get_setting("application/config/version", ""))
	return value if value != "" else "0.0.0"


## 表示用。エクスポートしていないビルド（エディタ / ソースからの起動）は
## 見分けが付くように -dev を付ける。不具合報告がどちらのビルドか分かる。
static func label() -> String:
	var text := "v" + number()
	if not OS.has_feature("template"):
		text += "-dev"
	return text


## OS のタイトルバーに出す 1 行。
static func window_title() -> String:
	var name := String(ProjectSettings.get_setting("application/config/name", "Game"))
	return "%s  %s" % [name, label()]
