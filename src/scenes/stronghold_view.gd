class_name StrongholdView
extends Node2D

## 拠点「銀の砦」。ランとランのあいだに立つ唯一の画面。
##
## ローグライクのメタ進行は「何を失い、何が残ったか」を数える場が無いと
## 手応えにならない。レベルが 1 に戻ったことと、熟練度が積み上がったことを
## 同じ画面に並べて見せるのがここの役目。
##
## 転職はダーマ神殿と同じ扱い。熟練度は職業ごとに別勘定で残り、覚えた技は
## 職業に紐付かないので、転職しても失われるのはレベルだけになる。
##
## 画面配置（384x240）
##   y   6.. 30  砦の名と戦績
##   y  34..156  左: 名簿と「出撃する」 / 右: 選択中の詳細
##   y 160..234  覚えた技 / 職業えらび

signal departed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const HEADER_RECT := Rect2(6, 6, 372, 24)
const ROSTER_RECT := Rect2(6, 34, 130, 122)
const DETAIL_RECT := Rect2(140, 34, 238, 122)
const MENU_RECT := Rect2(6, 160, 372, 74)

const ROW_HEIGHT := 20
const NOTICE_TIME := 2.0

## 前の画面を閉じた決定キーが、そのままこの画面の決定として流れ込むのを防ぐ。
const INPUT_LOCK := 0.15

## 立ち絵は explore_view と同じ 24x32 のシートから正面 1 コマだけ抜く。
## _draw() の中で load() すると読み込み中の白い板が描かれるので、必ず preload する。
const PORTRAIT_SIZE := Vector2(24, 32)
const PORTRAITS := {
	"soldier": preload("res://assets/sprites/hero_soldier.png"),
	"priest": preload("res://assets/sprites/hero_priest.png"),
	"mage": preload("res://assets/sprites/hero_mage.png"),
	"thief": preload("res://assets/sprites/hero_thief.png"),
}

## 覚えた技の一覧は 4 列 x 3 段。職業 4 x ランク 3 = 12 個で必ず収まる。
const ABILITY_COLUMNS := 4

enum State { MEMBER, JOB }

var members: Array[PartyMember] = []

var _state: State = State.MEMBER
## 0..members.size()-1 が各メンバー、最後の 1 つが「出撃する」。
var _index := 0
var _job_ids: Array = []
var _job_index := 0
var _notice := ""
var _notice_timer := 0.0
var _input_lock := 0.0


func open() -> void:
	members = GameState.active_party()
	_job_ids = Database.job_ids()
	_state = State.MEMBER
	_index = 0
	_notice = ""
	_notice_timer = 0.0
	_input_lock = INPUT_LOCK
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock -= delta
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice = ""
			queue_redraw()


func _notify(text: String) -> void:
	_notice = text
	_notice_timer = NOTICE_TIME
	queue_redraw()


## 「出撃する」の行番号。名簿が伸びても常に末尾に置く。
func _depart_row() -> int:
	return members.size()


func _selected() -> PartyMember:
	return members[_index] if _index < members.size() else null


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	match _state:
		State.MEMBER:
			_input_member()
		State.JOB:
			_input_job()


func _input_member() -> void:
	var rows := _depart_row() + 1
	if Input.is_action_just_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("confirm"):
		Sound.play("confirm")
		if _index == _depart_row():
			close()
			departed.emit()
		else:
			_open_job_menu()
	elif Input.is_action_just_pressed("cancel"):
		# 一覧のどこにいても一手で出撃へ戻れるようにする
		if _index != _depart_row():
			_index = _depart_row()
			Sound.play("cancel")
			queue_redraw()


## 開発用。職業えらびの画面を撮るために、名簿の 1 人を選んでそこまで進める。
##   godot --path . -- --shot=job
func debug_open_job_menu(member_index: int) -> void:
	if members.is_empty():
		return
	_index = clampi(member_index, 0, members.size() - 1)
	_open_job_menu()


func _open_job_menu() -> void:
	var member := _selected()
	_job_index = maxi(_job_ids.find(member.job_id), 0)
	_state = State.JOB
	queue_redraw()


## 職業は 2 列 x 2 段に並べる。上下で列内を、左右で列をまたぐ。
func _input_job() -> void:
	if _job_ids.is_empty():
		return
	var rows := _job_rows()
	if Input.is_action_just_pressed("ui_down"):
		_job_index = (_job_index + 1) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("ui_up"):
		_job_index = (_job_index - 1 + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("ui_right"):
		_job_index = (_job_index + rows) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("ui_left"):
		_job_index = (_job_index - rows + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
	elif Input.is_action_just_pressed("confirm"):
		_apply_job()


func _job_rows() -> int:
	return int(ceil(_job_ids.size() / 2.0))


func _apply_job() -> void:
	var member := _selected()
	var job_id := String(_job_ids[_job_index])
	if GameState.change_job(member, job_id):
		Sound.play("confirm")
		_notify("%sは %s に なった！" % [member.name, _job_name(job_id)])
	else:
		# 同じ職業を選び直しただけ。咎めずに閉じる。
		Sound.play("cancel")
	_state = State.MEMBER
	queue_redraw()


# --------------------------------------------------------------------------
# 表示用の小道具
# --------------------------------------------------------------------------


func _job_name(job_id: String) -> String:
	return String(Database.job(job_id).get("name", job_id))


func _max_rank(job_id: String) -> int:
	return Database.job(job_id).get("mastery", []).size()


## ★ で埋めた熟練度。数字だけより「あと 1 段」が直感で分かる。
func _stars(rank: int, max_rank: int) -> String:
	return "★".repeat(rank) + "☆".repeat(maxi(max_rank - rank, 0))


## 「72/160」の形。最大まで行っていたら到達点だけを出す。
func _mastery_text(member: PartyMember, job_id: String) -> String:
	var points := member.mastery_points(job_id)
	var remain := member.mastery_to_next(job_id)
	if remain <= 0:
		return "%d きわめた" % points
	return "%d/%d" % [points, points + remain]


func _portrait_of(job_id: String) -> Texture2D:
	return PORTRAITS.get(job_id, null)


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x10, 0x0E, 0x1C), true)
	_draw_header()
	_draw_roster()
	_draw_detail()
	_draw_menu()
	_draw_notice()


func _draw_header() -> void:
	PixelUI.draw_window(self, HEADER_RECT, WINDOW_TEX)
	PixelUI.draw_text(self, HEADER_RECT.position + Vector2(12, 17), "銀の砦", PixelUI.C_ACTIVE, 13)
	var record := "最深 地下%d階　%d回目の潜行" % [
		maxi(GameState.deepest_floor, 1), GameState.runs_attempted + 1
	]
	var x := HEADER_RECT.end.x - 12 - PixelUI.text_width(record, 10)
	PixelUI.draw_text(self, Vector2(x, HEADER_RECT.position.y + 17), record, PixelUI.C_TEXT_DIM, 10)


func _draw_roster() -> void:
	PixelUI.draw_window(self, ROSTER_RECT, WINDOW_TEX)
	for i in members.size():
		var m := members[i]
		var base := ROSTER_RECT.position + Vector2(20, 20 + i * ROW_HEIGHT)
		var on := _index == i and _state == State.MEMBER
		if _index == i:
			draw_texture(CURSOR_TEX, (base + Vector2(-13, -8)).floor())
		PixelUI.draw_text(self, base, m.name, PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM, 12)
		PixelUI.draw_text(self, base + Vector2(44, 0), _job_name(m.job_id), PixelUI.C_TEXT_DIM, 9)

	var depart := ROSTER_RECT.position + Vector2(20, 20 + _depart_row() * ROW_HEIGHT)
	if _index == _depart_row():
		draw_texture(CURSOR_TEX, (depart + Vector2(-13, -8)).floor())
	var color := PixelUI.C_ACTIVE if _index == _depart_row() else PixelUI.C_TEXT_DIM
	PixelUI.draw_text(self, depart, "出撃する", color, 12)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	if _index == _depart_row():
		_draw_departure_note()
		return

	var member := _selected()
	# 転職を選んでいるあいだは行き先の職業で見せる。姿と能力の変化を確定前に確認できる。
	var shown_job := String(_job_ids[_job_index]) if _state == State.JOB else member.job_id
	var origin := DETAIL_RECT.position

	var portrait := _portrait_of(shown_job)
	if portrait != null:
		draw_texture_rect_region(
			portrait,
			Rect2(origin + Vector2(196, 12), PORTRAIT_SIZE),
			Rect2(Vector2.ZERO, PORTRAIT_SIZE)
		)

	PixelUI.draw_text(self, origin + Vector2(14, 24), member.name, PixelUI.C_TEXT, 13)
	# ラン開始時の姿を出す。拠点ではレベルは常に 1 で、そこが「失ったもの」の証拠になる。
	var head := "%s　Lv1　待×%d" % [
		_job_name(shown_job), int(Database.job(shown_job).get("cost_scale", 100))
	]
	PixelUI.draw_text(self, origin + Vector2(14, 40), head, PixelUI.C_TEXT_DIM, 10)

	PixelUI.draw_text(self, origin + Vector2(14, 58), "じゅくれんど", PixelUI.C_TEXT_DIM, 9)
	for i in _job_ids.size():
		var job_id := String(_job_ids[i])
		var row := origin + Vector2(14, 74 + i * 14)
		var current := job_id == shown_job
		var tint := PixelUI.C_ACTIVE if current else PixelUI.C_TEXT_DIM
		PixelUI.draw_text(self, row, _job_name(job_id), tint, 10)
		PixelUI.draw_text(
			self, row + Vector2(66, 0),
			_stars(member.mastery_rank(job_id), _max_rank(job_id)), tint, 10
		)
		PixelUI.draw_text(
			self, row + Vector2(118, 0), _mastery_text(member, job_id), PixelUI.C_TEXT_DIM, 9
		)


func _draw_departure_note() -> void:
	var origin := DETAIL_RECT.position
	PixelUI.draw_text(self, origin + Vector2(14, 24), "地下へ もぐる", PixelUI.C_ACTIVE, 13)
	var lines := [
		"レベルは もちかえれない。",
		"じゅくれんと わざだけが のこる。",
	]
	for i in lines.size():
		PixelUI.draw_text(self, origin + Vector2(14, 44 + i * 14), lines[i], PixelUI.C_TEXT_DIM, 10)

	for i in members.size():
		var m := members[i]
		var row := origin + Vector2(14, 80 + i * 14)
		PixelUI.draw_text(self, row, m.name, PixelUI.C_TEXT, 10)
		PixelUI.draw_text(self, row + Vector2(44, 0), _job_name(m.job_id), PixelUI.C_TEXT_DIM, 10)
		PixelUI.draw_text(
			self, row + Vector2(126, 0),
			_stars(m.mastery_rank(), _max_rank(m.job_id)), PixelUI.C_ACTIVE, 10
		)


func _draw_menu() -> void:
	PixelUI.draw_window(self, MENU_RECT, WINDOW_TEX)
	if _state == State.JOB:
		_draw_job_menu()
	elif _index == _depart_row():
		_draw_hint()
	else:
		_draw_learned()


func _draw_learned() -> void:
	var member := _selected()
	var origin := MENU_RECT.position
	PixelUI.draw_text(self, origin + Vector2(16, 16), "おぼえた わざ", PixelUI.C_TEXT_DIM, 9)

	if member.learned.is_empty():
		PixelUI.draw_text(
			self, origin + Vector2(16, 36), "まだ なにも おぼえていない。", PixelUI.C_TEXT_DIM, 10
		)
		PixelUI.draw_text(
			self, origin + Vector2(16, 52), "たたかって じゅくれんを あげると おぼえる。",
			PixelUI.C_TEXT_DIM, 10
		)
		return

	for i in member.learned.size():
		var ability_id := String(member.learned[i])
		var col := i % ABILITY_COLUMNS
		var row := i / ABILITY_COLUMNS
		var at := origin + Vector2(16 + col * 88, 32 + row * 14)
		PixelUI.draw_text(
			self, at, String(Database.ability(ability_id).get("name", ability_id)),
			PixelUI.C_TEXT, 10
		)


func _draw_hint() -> void:
	var origin := MENU_RECT.position
	PixelUI.draw_text(self, origin + Vector2(16, 20), "↑↓ えらぶ　Ｚ けってい　Ｘ もどる", PixelUI.C_TEXT_DIM, 10)
	PixelUI.draw_text(
		self, origin + Vector2(16, 40), "なかまを えらぶと てんしょくできる。", PixelUI.C_TEXT_DIM, 10
	)
	PixelUI.draw_text(
		self, origin + Vector2(16, 56), "じゅくれんは しょくぎょうごとに のこる。",
		PixelUI.C_TEXT_DIM, 10
	)


func _draw_job_menu() -> void:
	var member := _selected()
	var origin := MENU_RECT.position
	PixelUI.draw_text(
		self, origin + Vector2(16, 16), "%s の しょくぎょう" % member.name, PixelUI.C_TEXT_DIM, 9
	)

	var rows := _job_rows()
	for i in _job_ids.size():
		var job_id := String(_job_ids[i])
		var col := i / rows
		var row := i % rows
		var at := origin + Vector2(24 + col * 178, 34 + row * 15)
		var on := i == _job_index
		if on:
			draw_texture(CURSOR_TEX, (at + Vector2(-9, -8)).floor())
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if job_id == member.job_id:
			tint = PixelUI.C_ACTIVE
		PixelUI.draw_text(self, at, _job_name(job_id), tint, 11)
		PixelUI.draw_text(
			self, at + Vector2(70, 0),
			_stars(member.mastery_rank(job_id), _max_rank(job_id)), PixelUI.C_TEXT_DIM, 9
		)
		PixelUI.draw_text(
			self, at + Vector2(120, 0),
			"待×%d" % int(Database.job(job_id).get("cost_scale", 100)), PixelUI.C_TEXT_DIM, 9
		)

	var desc := String(Database.job(String(_job_ids[_job_index])).get("desc", ""))
	PixelUI.draw_text(self, origin + Vector2(16, 66), desc, PixelUI.C_TEXT, 10)


func _draw_notice() -> void:
	if _notice == "":
		return
	var width := PixelUI.text_width(_notice, 12) + 28.0
	var box := Rect2((PixelUI.SCREEN.x - width) * 0.5, 96, width, 28)
	PixelUI.draw_window(self, box, WINDOW_TEX)
	PixelUI.draw_text(self, box.position + Vector2(14, 18), _notice, PixelUI.C_TEXT, 12)
