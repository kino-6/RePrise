class_name SettingsView
extends Node2D

## 設定。音量・文字の速さ・キーの割り当て。
##
## タイトルと探索メニューの両方から開ける。中身は `src/game/settings.gd` にあり、
## この画面は触るだけ（保存も適用も向こうの仕事）。

signal closed
signal save_erase_requested

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const PANEL_RECT := Rect2(56, 40, 400, 200)
const HINT_RECT := Rect2(56, 248, 400, 56)
const ROW := 26

enum Row { VOLUME, SPEED, KEYS, ERASE_SAVE, CLOSE }

var _index := 0
var _keys_open := false
var _key_index := 0
## キーの入力待ち。押された 1 つを割り当てる。
var _awaiting := false
## セーブ消去はタイトルから開いたときだけ許す。ラン中の再保存で復活させないため。
var _allow_save_erase := false
var _has_save_data := false
var _erase_open := false
## 確認窓は必ず「やめる」から始める。
var _erase_index := 0


func open(allow_save_erase: bool = false, has_save_data: bool = false) -> void:
	Settings.ensure_loaded()
	_index = 0
	_keys_open = false
	_awaiting = false
	_allow_save_erase = allow_save_erase
	_has_save_data = has_save_data
	_erase_open = false
	_erase_index = 0
	_notice = ""
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	# 割り当て中は、押されたキーをそのまま受け取る（アクションとして解釈しない）。
	#
	# ただし**逃げ道は必ず残す**。ここで全部のキーを飲み込むと、
	# 割り当てを始めた時点で取り消せなくなる。自動プレイがこれで settings に
	# 25 秒張り付いて動けなくなった（人も同じところで詰まる）。
	if _awaiting:
		# **アクションでも抜けられるようにする。** キーイベントだけを見ていると、
		# InputEventAction を流し込む自動プレイはここから永久に出られない
		# （実際に settings へ 25 秒張り付いた）。キャンセルは取り消しに使う、
		# という約束はどの画面でも同じなので、割り当ての対象からは外す。
		if event.is_action_pressed("cancel"):
			_awaiting = false
			Sound.play("cancel")
			queue_redraw()
			return
		if event is InputEventKey:
			var key: InputEventKey = event
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if code == KEY_ESCAPE:
				_awaiting = false
				Sound.play("cancel")
				queue_redraw()
				return
			# 他の操作に割り当て済みのキーは断る。重ねると、その操作が
			# 二度と出せなくなる（自分で自分を閉じ込める設定になる）。
			var taken := _action_using(code)
			if taken != "":
				Sound.play("cancel")
				_notice = "そのキーは %s に つかわれている" % taken
				_awaiting = false
				queue_redraw()
				return
			Settings.rebind(String(Settings.ACTIONS[_key_index]), code)
			_awaiting = false
			_notice = ""
			Sound.play("confirm")
			queue_redraw()
		return

	if _keys_open:
		_input_keys(event)
		return
	if _erase_open:
		_input_erase(event)
		return
	_input_root(event)


## そのキーを既に使っている操作の名前（無ければ空）。
func _action_using(code: int) -> String:
	for i in Settings.ACTIONS.size():
		if i == _key_index:
			continue
		var action := String(Settings.ACTIONS[i])
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				var k: InputEventKey = e
				var c := k.physical_keycode if k.physical_keycode != 0 else k.keycode
				if c == code:
					return Settings.action_label(action)
	return ""


## 断ったときの一言。割り当て画面に出す。
var _notice := ""


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
			Row.ERASE_SAVE:
				if not _allow_save_erase:
					_notice = Terms.SAVE_ERASE_TITLE_ONLY
					Sound.play("cancel")
				elif not _has_save_data:
					_notice = Terms.SAVE_ERASE_NONE
					Sound.play("cancel")
				else:
					_erase_open = true
					_erase_index = 0
					_notice = ""
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


## 消去確認。決定を連打しても既定の「やめる」で閉じる。
## 実際に消すには、明示的に下へ動かしてからもう一度決定する必要がある。
func _input_erase(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		_erase_open = false
		Sound.play("cancel")
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		_erase_index = 1 - _erase_index
		Sound.play("cursor")
	elif event.is_action_pressed("confirm"):
		if _erase_index == 0:
			_erase_open = false
			Sound.play("cancel")
		else:
			Sound.play("confirm")
			save_erase_requested.emit()
	queue_redraw()


## Main がファイル消去を終えた結果を画面へ返す。
func finish_save_erase(success: bool) -> void:
	_erase_open = false
	if success:
		_has_save_data = false
		_notice = Terms.SAVE_ERASE_DONE
	else:
		_notice = Terms.SAVE_ERASE_FAILED
	queue_redraw()


## 撮影用。実ファイルへ触れず、確認窓だけを開く。
func debug_open_save_erase() -> void:
	_allow_save_erase = true
	_has_save_data = true
	_erase_open = true
	_erase_index = 0
	queue_redraw()


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
	PixelUI.ui_frame()
	# 下の画面を残したまま暗くする（設定は場面ではなく、上に開く窓）。
	draw_rect(Rect2(Vector2.ZERO, PixelUI.SCREEN), Color(0.02, 0.03, 0.06, 0.72), true)
	PixelUI.draw_window(self, PANEL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(PANEL_RECT).position + Vector2(16, 4)

	PixelUI.draw_text(self, origin, "せってい", PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	if _keys_open:
		_draw_keys(origin)
	elif _erase_open:
		_draw_erase(origin)
	else:
		_draw_root(origin)

	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var hint := PixelUI.content(HINT_RECT).position + Vector2(8, 0)
	if _awaiting:
		PixelUI.draw_text(self, hint, "割り当てたい キーを 押す", PixelUI.C_ACTIVE)
	elif _keys_open:
		PixelUI.draw_text(self, hint, "Ｚ で 割り当て　Ｘ で もどる", PixelUI.C_TEXT_DIM)
	elif _erase_open:
		PixelUI.draw_text(self, hint, Terms.SAVE_ERASE_HINT, PixelUI.C_TEXT_DIM)
	elif _notice != "":
		PixelUI.draw_text(self, hint, _notice, PixelUI.C_ACTIVE)
	else:
		PixelUI.draw_text(self, hint, "←→ で かえる　Ｘ で とじる", PixelUI.C_TEXT_DIM)


func _draw_root(origin: Vector2) -> void:
	var rows := [
		["おと", "%d" % Settings.volume if Settings.volume > 0 else "なし"],
		["もじの はやさ", Settings.speed_label()],
		["キーの わりあて", "▶"],
		[
			Terms.SAVE_ERASE,
			"" if (_allow_save_erase and _has_save_data)
				else Terms.SAVE_ERASE_NONE if _allow_save_erase
				else Terms.SAVE_ERASE_TITLE_ONLY,
		],
		["とじる", ""],
	]
	for i in rows.size():
		var at := origin + Vector2(0, 34 + i * ROW)
		if i == _index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var enabled := i != Row.ERASE_SAVE or (_allow_save_erase and _has_save_data)
		var tint := PixelUI.C_TEXT if i == _index and enabled else PixelUI.C_TEXT_DIM
		PixelUI.draw_text(self, at, String(rows[i][0]), tint)
		PixelUI.draw_text_right(
			self, Vector2(origin.x + 340, at.y), String(rows[i][1]), PixelUI.C_TEXT_DIM
		)


func _draw_erase(origin: Vector2) -> void:
	PixelUI.draw_text(
		self, origin + Vector2(0, 36), Terms.SAVE_ERASE_QUESTION,
		PixelUI.C_TEXT, PixelUI.SIZE_HEAD
	)
	PixelUI.draw_text(
		self, origin + Vector2(0, 66), Terms.SAVE_ERASE_WARNING, PixelUI.C_ACTIVE
	)
	for i in 2:
		var at := origin + Vector2(0, 100 + i * ROW)
		if i == _erase_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var label := Terms.SAVE_ERASE_CANCEL if i == 0 else Terms.SAVE_ERASE_EXECUTE
		PixelUI.draw_text(
			self, at, label, PixelUI.C_TEXT if i == _erase_index else PixelUI.C_TEXT_DIM
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
