class_name SettingsView
extends Node2D

const ConfirmFlow := preload("res://src/game/confirm_flow.gd")

## 設定。音量・文字の速さ・キーの割り当て。
##
## タイトルと探索メニューの両方から開ける。中身は `src/game/settings.gd` にあり、
## この画面は触るだけ（保存も適用も向こうの仕事）。

signal closed
signal save_erase_requested
signal run_abandon_requested

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const PANEL_RECT := Rect2(56, 40, 400, 200)
const HINT_RECT := Rect2(56, 248, 400, 56)
## 6行を窓へ収める。26pxのまま1行足すと「とじる」が内枠を越える。
const ROW := 23

enum Row { VOLUME, SPEED, KEYS, ERASE_SAVE, ABANDON_RUN, CLOSE }

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
## ラン放棄は探索メニューから設定を開いた場合だけ許す。
var _allow_run_abandon := false
## 0=閉じている / 1=最初の確認 / 2=最終確認。
var _abandon_stage := 0
## 各確認とも「もどる」から始める。決定連打だけでは絶対に終わらない。
var _abandon_index := 0


func open(
	allow_save_erase: bool = false, has_save_data: bool = false,
	allow_run_abandon: bool = false
) -> void:
	Settings.ensure_loaded()
	_index = 0
	_keys_open = false
	_awaiting = false
	_allow_save_erase = allow_save_erase
	_has_save_data = has_save_data
	_erase_open = false
	_erase_index = 0
	_allow_run_abandon = allow_run_abandon
	_abandon_stage = 0
	_abandon_index = 0
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
	if _abandon_stage > 0:
		_input_abandon(event)
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
			Row.ABANDON_RUN:
				if not begin_run_abandon():
					_notice = Terms.RUN_ABANDON_IN_RUN
					Sound.play("cancel")
			Row.CLOSE:
				Sound.play("confirm")
				close()
				closed.emit()
				return
			_:
				_nudge(+1)
	queue_redraw()


## 放棄確認を開く。タイトルの設定からは開けない。
func begin_run_abandon() -> bool:
	if not _allow_run_abandon:
		return false
	_abandon_stage = 1
	_abandon_index = 0
	_notice = ""
	Sound.play("confirm")
	queue_redraw()
	return true


## 二段階確認の本体。入力処理とテストが同じ経路を使う。
##
## confirmed=false はその場で閉じる。true は1回目なら最終確認へ進み、
## 2回目で初めて signal を出す。
func confirm_run_abandon(confirmed: bool) -> bool:
	if _abandon_stage <= 0:
		return false
	var next := ConfirmFlow.next_run_abandon_stage(_abandon_stage, confirmed)
	if next == 0:
		_abandon_stage = 0
		_abandon_index = 0
		Sound.play("cancel")
		queue_redraw()
		return false
	if next == 2:
		_abandon_stage = next
		_abandon_index = 0
		Sound.play("confirm")
		queue_redraw()
		return false
	_abandon_stage = 0
	_abandon_index = 0
	Sound.play("confirm")
	close()
	run_abandon_requested.emit()
	return true


func run_abandon_stage() -> int:
	return _abandon_stage


func _input_abandon(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		confirm_run_abandon(false)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		_abandon_index = 1 - _abandon_index
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		confirm_run_abandon(_abandon_index == 1)


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


## 撮影用。実際にランを終わらせず、二つ目の確認を開く。
func debug_open_run_abandon() -> void:
	_allow_run_abandon = true
	begin_run_abandon()
	confirm_run_abandon(true)
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

	_wide(origin).line("せってい", PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	if _keys_open:
		_draw_keys(origin)
	elif _erase_open:
		_draw_erase(origin)
	elif _abandon_stage > 0:
		_draw_abandon(origin)
	else:
		_draw_root(origin)

	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var hint := PixelUI.content(HINT_RECT).position + Vector2(8, 0)
	if _awaiting:
		_wide(hint).line("割り当てたい キーを 押す", PixelUI.C_ACTIVE)
	elif _keys_open:
		_wide(hint).line("Ｚ で 割り当て　Ｘ で もどる", PixelUI.C_TEXT_DIM)
	elif _erase_open:
		_wide(hint).line(Terms.SAVE_ERASE_HINT, PixelUI.C_TEXT_DIM)
	elif _abandon_stage > 0:
		PixelUI.draw_text(self, hint, Terms.RUN_ABANDON_HINT, PixelUI.C_TEXT_DIM)
	elif _notice != "":
		_wide(hint).line(_notice, PixelUI.C_ACTIVE)
	else:
		_wide(hint).line("←→ で かえる　Ｘ で とじる", PixelUI.C_TEXT_DIM)


## 幅いっぱいの 1 行。**文言を差し替えても溢れない**ようにするための包み。
func _wide(at: Vector2) -> UiPanel:
	return UiPanel.inside(self, Rect2(
		at, Vector2(PixelUI.SCREEN.x - at.x - 24.0, PixelUI.LINE)))


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
		[
			Terms.RUN_ABANDON,
			"" if _allow_run_abandon else Terms.RUN_ABANDON_IN_RUN,
		],
		["とじる", ""],
	]
	for i in rows.size():
		var at := origin + Vector2(0, 34 + i * ROW)
		if i == _index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var enabled := (
			(i != Row.ERASE_SAVE or (_allow_save_erase and _has_save_data))
			and (i != Row.ABANDON_RUN or _allow_run_abandon)
		)
		var tint := PixelUI.C_TEXT if i == _index and enabled else PixelUI.C_TEXT_DIM
		# 項目と値を 1 行に。**値は消えては困る**ので、詰まるのは項目名のほう。
		UiPanel.inside(self, Rect2(at, Vector2(340.0, PixelUI.LINE))).row(
			String(rows[i][0]), String(rows[i][1]), tint, PixelUI.C_TEXT_DIM)


func _draw_erase(origin: Vector2) -> void:
	# 消去の確認は**外部化した文**（`Terms`）なので、長さを前提にしない。
	_wide(origin + Vector2(0, 36)).line(
		Terms.SAVE_ERASE_QUESTION, PixelUI.C_TEXT, PixelUI.SIZE_HEAD)
	_wide(origin + Vector2(0, 66)).line(Terms.SAVE_ERASE_WARNING, PixelUI.C_ACTIVE)
	for i in 2:
		var at := origin + Vector2(0, 100 + i * ROW)
		if i == _erase_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var label := Terms.SAVE_ERASE_CANCEL if i == 0 else Terms.SAVE_ERASE_EXECUTE
		_wide(at).line(
			label, PixelUI.C_TEXT if i == _erase_index else PixelUI.C_TEXT_DIM
		)


func _draw_abandon(origin: Vector2) -> void:
	var final := _abandon_stage == 2
	PixelUI.draw_text(
		self, origin + Vector2(0, 36),
		Terms.RUN_ABANDON_FINAL_QUESTION if final else Terms.RUN_ABANDON_FIRST_QUESTION,
		PixelUI.C_TEXT, PixelUI.SIZE_HEAD
	)
	PixelUI.draw_text(
		self, origin + Vector2(0, 66),
		Terms.RUN_ABANDON_FINAL_WARNING if final else Terms.RUN_ABANDON_FIRST_WARNING,
		PixelUI.C_ACTIVE
	)
	for i in 2:
		var at := origin + Vector2(0, 100 + i * ROW)
		if i == _abandon_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var label := Terms.RUN_ABANDON_CANCEL
		if i == 1:
			label = Terms.RUN_ABANDON_EXECUTE if final else Terms.RUN_ABANDON_NEXT
		PixelUI.draw_text(
			self, at, label, PixelUI.C_TEXT if i == _abandon_index else PixelUI.C_TEXT_DIM
		)


func _draw_keys(origin: Vector2) -> void:
	for i in Settings.ACTIONS.size():
		var action := String(Settings.ACTIONS[i])
		var at := origin + Vector2(0, 34 + i * 22)
		if i == _key_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var tint := PixelUI.C_TEXT if i == _key_index else PixelUI.C_TEXT_DIM
		var label := "…" if (_awaiting and i == _key_index) else Settings.key_label(action)
		# 操作名と割り当てを 1 行に。**割り当ては消えては困る**（何を押すか分からなくなる）。
		UiPanel.inside(self, Rect2(at, Vector2(340.0, PixelUI.LINE))).row(
			String(Settings.ACTION_LABELS[action]), label,
			tint, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
