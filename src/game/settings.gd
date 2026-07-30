class_name Settings
extends RefCounted

## 遊ぶ人が変えられるもの。音量・文字の速さ・キーの割り当て。
##
## セーブ（`user://save.json`）とは別のファイルに置く。ゲームの進み具合と
## 環境の設定は寿命が違うので、片方が壊れてももう片方を巻き込まない。
##
## 決定性には関与しない。ここが変えるのは音と入力と表示の速さだけで、
## 乱数にもロジックにも触らない。

const PATH := "user://config.json"

## 変えられるキー。ここに無いもの（ui_accept など）は既定のまま。
const ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "confirm", "cancel", "auto"]

const ACTION_LABELS := {
	"ui_up": "うえ", "ui_down": "した", "ui_left": "ひだり", "ui_right": "みぎ", "auto": "オート",
	"confirm": "けってい", "cancel": "キャンセル",
}

## 文字の速さ。行が出るまでの秒数で持つ（小さいほど速い）。
const TEXT_SPEEDS := [0.85, 0.55, 0.28]
const SPEED_LABELS := ["ゆっくり", "ふつう", "はやい"]

static var volume := 8  ## 0..10
static var text_speed := 1  ## TEXT_SPEEDS の添字
## action -> 物理キーコード。空なら project.godot の既定を使う。
static var bindings: Dictionary = {}

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_config()
	apply()


static func line_delay() -> float:
	return float(TEXT_SPEEDS[clampi(text_speed, 0, TEXT_SPEEDS.size() - 1)])


static func speed_label() -> String:
	return String(SPEED_LABELS[clampi(text_speed, 0, SPEED_LABELS.size() - 1)])


## 操作の呼び名。設定画面で「そのキーは けってい に使われている」と出すのに使う。
static func action_label(action: String) -> String:
	return String(ACTION_LABELS.get(action, action))


## いま割り当たっているキーの名前。割り当てが無ければ既定を読む。
static func key_label(action: String) -> String:
	if bindings.has(action):
		return OS.get_keycode_string(int(bindings[action]))
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: InputEventKey = event
			return OS.get_keycode_string(
				key.physical_keycode if key.physical_keycode != 0 else key.keycode
			)
	return "—"


## 割り当てを変える。既定を消して 1 つだけ入れる。
static func rebind(action: String, keycode: int) -> void:
	bindings[action] = keycode
	_apply_binding(action, keycode)
	save_config()


static func _apply_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## 設定を実際に効かせる。読み込み直後と、変えたときに呼ぶ。
static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, volume <= 0)
		# 0..10 を dB へ。線形の音量つまみは小さい側が効かないので対数で置く。
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(volume / 10.0, 0.0, 1.0)))
	for action in bindings.keys():
		_apply_binding(String(action), int(bindings[action]))


static func load_config() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	volume = clampi(int(data.get("volume", volume)), 0, 10)
	text_speed = clampi(int(data.get("text_speed", text_speed)), 0, TEXT_SPEEDS.size() - 1)
	bindings.clear()
	for action in data.get("bindings", {}).keys():
		if String(action) in ACTIONS:
			bindings[String(action)] = int(data["bindings"][action])


static func save_config() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("設定を保存できない: %s" % PATH)
		return
	file.store_string(JSON.stringify({
		"volume": volume,
		"text_speed": text_speed,
		"bindings": bindings,
	}, "  "))
