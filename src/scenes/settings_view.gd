class_name SettingsView
extends Node2D

## 設定。音量・文字の速さ・キーの割り当て。
##
## タイトルと探索メニューの両方から開ける。中身は `src/game/settings.gd` にあり、
## この画面は触るだけ（保存も適用も向こうの仕事）。

signal closed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const PANEL_RECT := Rect2(56, 40, 400, 200)
const HINT_RECT := Rect2(56, 248, 400, 56)
const ROW := 26

enum Row { VOLUME, SPEED, KEYS, CLOSE }

var _index := 0
var _keys_open := false
var _key_index := 0
## キーの入力待ち。押された 1 つを割り当てる。
var _awaiting := false


func open() -> void:
	Settings.ensure_loaded()
	_index = 0
	_keys_open = false
	_awaiting = false
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	# 割り当て中は、押されたキーをそのまま受け取る（アクションとして解釈しない）。
	if _awaiting:
		if event is InputEventKey:
			var key: InputEventKey = event
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			Settings.rebind(String(Settings.ACTIONS[_key_index]), code)
			_awaiting = false
			Sound.play("confirm")
			queue_redraw()
		return

	if _keys_open:
		_input_keys(event)
		return
	_input_root(event)


func _input_root(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		close()
		closed.emit()
		return
	if event.is_action_pressed("ui_down"):
		_index = (_index + 1) % Row.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_up"):
		_index = (_index - 1 + Row.size()) % Row.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_left"):
		_nudge(-1)
	elif event.is_action_pressed("ui_right"):
		_nudge(+1)
	elif event.is_action_pressed("confirm"):
		match _index:
			Row.KEYS:
				_keys_open = true
				_key_index = 0
				Sound.play("confirm")
			Row.CLOSE:
				Sound.play("confirm")
				close()
				closed.emit()
				return
			_:
				_nudge(+1)
	queue_redraw()


## 左右で値を動かす。決定でも 1 つ進む（どちらでも触れるほうが迷わない）。
func _nudge(delta: int) -> void:
	match _index:
		Row.VOLUME:
			Settings.volume = clampi(Settings.volume + delta, 0, 10)
		Row.SPEED:
			Settings.text_speed = posmod(
				Settings.text_speed + delta, Settings.TEXT_SPEEDS.size()
			)
		_:
			return
	Settings.apply()
	Settings.save_config()
	Sound.play("cursor")


func _input_keys(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_keys_open = false
		queue_redraw()
		return
	if event.is_action_pressed("ui_down"):
		_key_index = (_key_index + 1) % Settings.ACTIONS.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_up"):
		_key_index = (_key_index - 1 + Settings.ACTIONS.size()) % Settings.ACTIONS.size()
		Sound.play("cursor")
	elif event.is_action_pressed("confirm"):
		_awaiting = true
	queue_redraw()


# --------------------------------------------------------------------------


func _draw() -> void:
	# 下の画面を残したまま暗くする（設定は場面ではなく、上に開く窓）。
	draw_rect(Rect2(Vector2.ZERO, PixelUI.SCREEN), Color(0.02, 0.03, 0.06, 0.72), true)
	PixelUI.draw_window(self, PANEL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(PANEL_RECT).position + Vector2(16, 4)

	PixelUI.draw_text(self, origin, "せってい", PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	if _keys_open:
		_draw_keys(origin)
	else:
		_draw_root(origin)

	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var hint := PixelUI.content(HINT_RECT).position + Vector2(8, 0)
	if _awaiting:
		PixelUI.draw_text(self, hint, "割り当てたい キーを 押す", PixelUI.C_ACTIVE)
	elif _keys_open:
		PixelUI.draw_text(self, hint, "Ｚ で 割り当て　Ｘ で もどる", PixelUI.C_TEXT_DIM)
	else:
		PixelUI.draw_text(self, hint, "←→ で かえる　Ｘ で とじる", PixelUI.C_TEXT_DIM)


func _draw_root(origin: Vector2) -> void:
	var rows := [
		["おと", "%d" % Settings.volume if Settings.volume > 0 else "なし"],
		["もじの はやさ", Settings.speed_label()],
		["キーの わりあて", "▶"],
		["とじる", ""],
	]
	for i in rows.size():
		var at := origin + Vector2(0, 34 + i * ROW)
		if i == _index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var tint := PixelUI.C_TEXT if i == _index else PixelUI.C_TEXT_DIM
		PixelUI.draw_text(self, at, String(rows[i][0]), tint)
		PixelUI.draw_text_right(
			self, Vector2(origin.x + 340, at.y), String(rows[i][1]), PixelUI.C_TEXT_DIM
		)


func _draw_keys(origin: Vector2) -> void:
	for i in Settings.ACTIONS.size():
		var action := String(Settings.ACTIONS[i])
		var at := origin + Vector2(0, 34 + i * 22)
		if i == _key_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var tint := PixelUI.C_TEXT if i == _key_index else PixelUI.C_TEXT_DIM
		PixelUI.draw_text(self, at, String(Settings.ACTION_LABELS[action]), tint, PixelUI.SIZE_SUB)
		var label := "…" if (_awaiting and i == _key_index) else Settings.key_label(action)
		PixelUI.draw_text_right(
			self, Vector2(origin.x + 340, at.y), label, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
