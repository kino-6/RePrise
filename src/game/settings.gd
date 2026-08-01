class_name Settings
extends RefCounted

## 遊ぶ人が変えられるもの。音量・文字の速さ・オートの道具・キーの割り当て。
##
## セーブ（`user://save.json`）とは別のファイルに置く。ゲームの進み具合と
## 環境の設定は寿命が違うので、片方が壊れてももう片方を巻き込まない。
##
## 乱数には関与しない。オートの道具許可は行動候補を変えるが、同じ許可・同じ在庫・
## 同じ戦況なら同じ品を選び、判断側で乱数を消費しない。

const PATH := "user://config.json"

## 変えられるキー。ここに無いもの（ui_accept など）は既定のまま。
const ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "confirm", "cancel", "auto"]

const ACTION_LABELS := {
	"ui_up": "うえ", "ui_down": "した", "ui_left": "ひだり", "ui_right": "みぎ", "auto": "オート",
	"confirm": "けってい", "cancel": "キャンセル",
}

## テンキーは設定で変える主キーとは別の、常設の補助入力として扱う。
## 4方向のゲームなので斜めキーは割り当てない。5/Enter は決定、0/小数点は取消。
## 再割り当てで InputMap を作り直したあとにも足し直し、設定変更で消えないようにする。
const KEYPAD_ALIASES := {
	"ui_up": [KEY_KP_8],
	"ui_down": [KEY_KP_2],
	"ui_left": [KEY_KP_4],
	"ui_right": [KEY_KP_6],
	"confirm": [KEY_KP_5, KEY_KP_ENTER],
	"cancel": [KEY_KP_0, KEY_KP_PERIOD],
}

## 文字の速さ。行が出るまでの秒数で持つ（小さいほど速い）。
const TEXT_SPEEDS := [0.85, 0.55, 0.28]
const SPEED_LABELS := ["ゆっくり", "ふつう", "はやい"]

static var volume := 8  ## 0..10
static var text_speed := 1  ## TEXT_SPEEDS の添字
## オート中に救命用の消耗品を使ってよいか。既定は、意図しない消費を避けて false。
static var auto_items := false
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
	_add_keypad_aliases(action)
	save_config()


static func _apply_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## 開発用の実入力試走にも使う、各操作の代表テンキー。
static func primary_keypad_key(action: String) -> int:
	var keys: Array[int] = keypad_keys(action)
	return keys[0] if not keys.is_empty() else 0


static func keypad_keys(action: String) -> Array[int]:
	var result: Array[int] = []
	for raw_key in KEYPAD_ALIASES.get(action, []):
		result.append(int(raw_key))
	return result


static func input_has_physical_key(action: String, keycode: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for raw_event in InputMap.action_get_events(action):
		if raw_event is InputEventKey:
			var event: InputEventKey = raw_event
			var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if code == keycode:
				return true
	return false


static func _add_keypad_aliases(action: String) -> void:
	if not InputMap.has_action(action):
		return
	for keycode in keypad_keys(action):
		if input_has_physical_key(action, keycode):
			continue
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


static func _add_all_keypad_aliases() -> void:
	for raw_action in KEYPAD_ALIASES.keys():
		_add_keypad_aliases(String(raw_action))


## 設定を実際に効かせる。読み込み直後と、変えたときに呼ぶ。
static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, volume <= 0)
		# 0..10 を dB へ。線形の音量つまみは小さい側が効かないので対数で置く。
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(volume / 10.0, 0.0, 1.0)))
	for action in bindings.keys():
		_apply_binding(String(action), int(bindings[action]))
	_add_all_keypad_aliases()


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
	auto_items = bool(data.get("auto_items", false))
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
		"auto_items": auto_items,
		"bindings": bindings,
	}, "  "))
