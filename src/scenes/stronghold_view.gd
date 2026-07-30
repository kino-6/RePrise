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
## 画面配置（512x320）
##   y   8.. 44  砦の名と戦績
##   y  50..218  左: 名簿と「出撃する」 / 右: 選択中の詳細
##   y 224..312  覚えた技 / 職業えらび

signal departed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const HEADER_RECT := Rect2(8, 8, 496, 36)
const ROSTER_RECT := Rect2(8, 50, 176, 164)
const DETAIL_RECT := Rect2(192, 50, 312, 164)
const MENU_RECT := Rect2(8, 220, 496, 92)

const ROW_HEIGHT := 23


## 前の画面を閉じた決定キーが、そのままこの画面の決定として流れ込むのを防ぐ。
const INPUT_LOCK := 0.15

## 立ち絵は explore_view と同じ 24x32 のシートから正面 1 コマだけ抜く。
##
## 職業が 15 まで増えたので preload の列挙はやめ、開いたときに 1 度だけ読んで
## 覚えておく。_draw() の中で読むと、読み込み中の白い板が描かれてしまう。
const PORTRAIT_SIZE := Vector2(24, 32)

static var _portraits: Dictionary = {}


static func portrait_of(job_id: String) -> Texture2D:
	if _portraits.has(job_id):
		return _portraits[job_id]
	var path := "res://assets/sprites/hero_%s.png" % job_id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_portraits[job_id] = tex
	return tex

## 覚えた技の一覧は 4 列 x 3 段。職業 4 x ランク 3 = 12 個で必ず収まる。
const ABILITY_COLUMNS := 4

enum State { MEMBER, JOB, UPGRADE, PARTY }

var members: Array[PartyMember] = []

var _state: State = State.MEMBER
## 0..members.size()-1 が各メンバー、最後の 1 つが「出撃する」。
var _index := 0
var _job_ids: Array = []
var _job_index := 0
var _upgrade_ids: Array = []
var _party_index := 0
var _upgrade_index := 0
var _notice := Notice.new()
var _input_lock := 0.0


func open() -> void:
	members = GameState.active_party()
	_job_ids = Database.job_ids()
	_upgrade_ids = Database.upgrade_ids()
	_upgrade_index = 0
	_state = State.MEMBER
	_index = 0
	_notice.clear()
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
	if _notice.tick(delta):
		queue_redraw()


func _notify(text: String) -> void:
	_notice.set_text(text)
	queue_redraw()


## 名簿の下に並ぶ行。「出撃する」は名簿が伸びても常に末尾に置く。
func _party_row() -> int:
	return members.size()


func _upgrade_row() -> int:
	return members.size() + 1


func _depart_row() -> int:
	return members.size() + 2


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
			_input_member(event)
		State.JOB:
			_input_job(event)
		State.UPGRADE:
			_input_upgrade(event)
		State.PARTY:
			_input_party(event)


func _input_member(event: InputEvent) -> void:
	var rows := _depart_row() + 1
	if event.is_action_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		Sound.play("confirm")
		if _index == _depart_row():
			close()
			departed.emit()
		elif _index == _upgrade_row():
			_state = State.UPGRADE
			_upgrade_index = 0
			queue_redraw()
		elif _index == _party_row():
			_state = State.PARTY
			_party_index = 0
			queue_redraw()
		else:
			_open_job_menu()
	elif event.is_action_pressed("cancel"):
		# 一覧のどこにいても一手で出撃へ戻れるようにする
		if _index != _depart_row():
			_index = _depart_row()
			Sound.play("cancel")
			queue_redraw()


## 開発用。アップグレードの画面を撮るために使う。
func debug_open_upgrades() -> void:
	_index = _upgrade_row()
	_upgrade_index = 0
	_state = State.UPGRADE
	queue_redraw()


## 開発用。出撃（潜る理由と名簿）の画面を撮るために使う。
func debug_open_depart() -> void:
	_index = _depart_row()
	_state = State.MEMBER
	queue_redraw()


## 開発用。編成の画面を撮るために使う。
func debug_open_party() -> void:
	_index = _party_row()
	_party_index = 0
	_state = State.PARTY
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
func _input_job(event: InputEvent) -> void:
	if _job_ids.is_empty():
		return
	var rows := _job_rows()
	if event.is_action_pressed("ui_down"):
		_job_index = (_job_index + 1) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_up"):
		_job_index = (_job_index - 1 + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_right"):
		_job_index = (_job_index + rows) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_left"):
		_job_index = (_job_index - rows + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		_apply_job()


## 熟練一覧に入る行数。枠の高さから決まる。
const MASTERY_ROWS := 7


## 表示する熟練の行（職業の添字）。選んでいる職業が必ず入るように窓をずらす。
func _mastery_window(shown_job: String) -> Array[int]:
	var current := maxi(_job_ids.find(shown_job), 0)
	var top := MenuList.top_of(current, _job_ids.size(), MASTERY_ROWS)
	var rows: Array[int] = []
	for i in range(top, mini(top + MASTERY_ROWS, _job_ids.size())):
		rows.append(i)
	return rows


## 職業えらびの列数。15 職を 4 列 x 4 行で並べる。
## 3 列 x 5 行だと 5 行目が枠から出た（窓の内側は 78px しかない）。
const JOB_COLS := 4


func _job_rows() -> int:
	return int(ceil(_job_ids.size() / float(JOB_COLS)))


func _input_upgrade(event: InputEvent) -> void:
	if _upgrade_ids.is_empty():
		_state = State.MEMBER
		queue_redraw()
		return
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
	elif event.is_action_pressed("ui_down"):
		_upgrade_index = (_upgrade_index + 1) % _upgrade_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_up"):
		_upgrade_index = (_upgrade_index - 1 + _upgrade_ids.size()) % _upgrade_ids.size()
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		_buy_upgrade()


## 編成。誰を連れて行くかを決め、ここで仲間も迎える。
##
## 名簿が 4 人固定だと「出撃する」が選択にならない。留守番させた者は育たないので、
## 誰を連れるかがそのまま次のランの手応えになる。
func _input_party(event: InputEvent) -> void:
	var rows := GameState.all_members().size() + 1  # 末尾は「なかまを迎える」
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
		return
	if event.is_action_pressed("ui_down"):
		_party_index = (_party_index + 1) % rows
		Sound.play("cursor")
	elif event.is_action_pressed("ui_up"):
		_party_index = (_party_index - 1 + rows) % rows
		Sound.play("cursor")
	elif event.is_action_pressed("confirm"):
		if _party_index >= GameState.all_members().size():
			_recruit()
		elif GameState.toggle_active(_party_index):
			Sound.play("confirm")
			members = GameState.active_party()
		else:
			Sound.play("cancel")
			_notify("%d 人までしか 連れて行けない" % GameState.PARTY_SIZE)
	queue_redraw()


func _recruit() -> void:
	if not GameState.can_recruit():
		Sound.play("cancel")
		_notify("これいじょう 仲間は 増えない")
		return
	var price := GameState.recruit_price()
	var member := GameState.recruit()
	if member == null:
		Sound.play("cancel")
		_notify("%s が %d 必要" % [Terms.ECHO, price])
		return
	GameState.save_game()
	Sound.play("learn")
	_notify("%s が 仲間に なった！" % member.name)


func _buy_upgrade() -> void:
	var id := String(_upgrade_ids[_upgrade_index])
	var label := String(Database.upgrade(id).get("name", id))
	if GameState.upgrade_maxed(id):
		Sound.play("cancel")
		_notify("%s は これいじょう のばせない" % label)
		return
	if not GameState.buy_upgrade(id):
		Sound.play("cancel")
		_notify("%sが たりない" % Terms.ECHO)
		return
	Sound.play("confirm")
	_notify("%s が %d 段に なった" % [label, GameState.upgrade_level(id)])


func _apply_job() -> void:
	var member := _selected()
	var job_id := String(_job_ids[_job_index])
	if not member.can_take_job(job_id):
		# 条件を満たしていない。閉じずにその場で理由を出す。
		Sound.play("cancel")
		_notify("まだ %s には なれない" % _job_name(job_id))
		return
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
	return portrait_of(job_id)


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
	var inner := PixelUI.content(HEADER_RECT)
	PixelUI.draw_text(self, inner.position + Vector2(6, 0), Terms.STRONGHOLD, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	var record := "%s %d　%s %s　%s" % [
		Terms.ECHO, GameState.echo,
		Terms.DEEPEST, "%d" % maxi(GameState.deepest_floor, 1),
		Terms.RUNS % (GameState.runs_attempted + 1),
	]
	PixelUI.draw_text_right(
		self, Vector2(inner.end.x - 4, inner.position.y + 3), record,
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_TEXT
	)


func _draw_roster() -> void:
	PixelUI.draw_window(self, ROSTER_RECT, WINDOW_TEX)
	var inner := PixelUI.content(ROSTER_RECT)
	for i in members.size():
		var m := members[i]
		var base := inner.position + Vector2(16, 6 + i * ROW_HEIGHT)
		var on := _index == i and _state == State.MEMBER
		if _index == i:
			MenuList.draw_cursor(self, CURSOR_TEX, base)
		PixelUI.draw_text(self, base, m.name, PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM)
		PixelUI.draw_text(
			self, base + Vector2(58, 2), _job_name(m.job_id), PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)

	_draw_roster_row(_party_row(), Terms.PARTY)
	_draw_roster_row(_upgrade_row(), Terms.UPGRADE)
	_draw_roster_row(_depart_row(), Terms.DEPART)


func _draw_roster_row(row: int, label: String) -> void:
	var inner := PixelUI.content(ROSTER_RECT)
	var at := inner.position + Vector2(16, 6 + row * ROW_HEIGHT)
	if _index == row:
		MenuList.draw_cursor(self, CURSOR_TEX, at)
	var color := PixelUI.C_ACTIVE if _index == row else PixelUI.C_TEXT_DIM
	PixelUI.draw_text(self, at, label, color)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	if _index == _depart_row():
		_draw_departure_note()
		return
	if _index == _upgrade_row():
		_draw_upgrade_note()
		return
	if _index == _party_row():
		_draw_party_note()
		return

	var member := _selected()
	# 転職を選んでいるあいだは行き先の職業で見せる。姿と能力の変化を確定前に確認できる。
	var shown_job := String(_job_ids[_job_index]) if _state == State.JOB else member.job_id
	var origin := PixelUI.content(DETAIL_RECT).position

	# 立ち絵は 2 倍に引き伸ばす。等倍だと 24x32 が余白に埋もれて誰の話か分からない。
	# 整数倍なのでドットは崩れない。
	var portrait := _portrait_of(shown_job)
	if portrait != null:
		draw_texture_rect_region(
			portrait,
			Rect2(origin + Vector2(232, 4), PORTRAIT_SIZE * 2.0),
			Rect2(Vector2.ZERO, PORTRAIT_SIZE)
		)

	PixelUI.draw_text(self, origin + Vector2(6, 2), member.name, PixelUI.C_TEXT, PixelUI.SIZE_HEAD)
	# ラン開始時の姿を出す。拠点ではレベルは常に 1 で、そこが「失ったもの」の証拠になる。
	# 拠点ではレベルは常に 1（失ったことの証拠）。「じぶんの」と明記して、
	# 右の熟練（職業ごとに積む・持ち帰る）と取り違えないようにする。
	var head := "%s　じぶん Lv1　%s %d" % [
		_job_name(shown_job), Terms.SPEED,
		Terms.speed(int(Database.job(shown_job).get("cost_scale", 100))),
	]
	PixelUI.draw_text(self, origin + Vector2(6, 24), head, PixelUI.C_TEXT_DIM)
	# 見出しは名前の右へ逃がす。1 行ぶん空けると職業が枠に収まらない。
	# 見出しと数を**右端で揃える**。左から固定の位置に置くと、
	# 「じゅくれんど」の幅が数字にかぶって枠まで押し出す（実際にはみ出していた）。
	# 右端は**立ち絵の左**まで。窓の右端まで寄せると絵の下に潜る。
	PixelUI.draw_text_right(
		self, origin + Vector2(226.0, 6),
		"%s %d/%d" % [Terms.MASTERY, _job_ids.find(shown_job) + 1, _job_ids.size()],
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)

	# 職業が 15 まで増えたので、全部並べると枠から溢れる。
	# 選んでいる職業を中心に、入る行数だけ切り出して見せる。
	var window := _mastery_window(shown_job)
	for slot in window.size():
		var i: int = window[slot]
		var job_id := String(_job_ids[i])
		var row := origin + Vector2(6, 46 + slot * 16)
		var current := job_id == shown_job
		var tint := PixelUI.C_ACTIVE if current else PixelUI.C_TEXT_DIM
		if not member.can_take_job(job_id):
			tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.55)
		PixelUI.draw_text(self, row, _job_name(job_id), tint)
		PixelUI.draw_text(
			self, row + Vector2(96, 2),
			_stars(member.mastery_rank(job_id), _max_rank(job_id)), tint, PixelUI.SIZE_SUB
		)
		PixelUI.draw_text(
			self, row + Vector2(148, 2), _mastery_text(member, job_id),
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)


func _draw_departure_note() -> void:
	var origin := PixelUI.content(DETAIL_RECT).position
	PixelUI.draw_text(self, origin + Vector2(6, 2), "地下へ もぐる", PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	# 1 行目が「なぜもぐるか」、残りが「何を失い、何が残るか」。
	# 文言は Lore 側（根拠は docs/premise.md）。3 行を超えると名簿と重なる。
	for i in Lore.DEPART_LINES.size():
		PixelUI.draw_text(
			self, origin + Vector2(6, 26 + i * 19), Lore.DEPART_LINES[i], PixelUI.C_TEXT_DIM
		)

	for i in members.size():
		var m := members[i]
		# 前提の 3 行を入れたぶん、名簿を下げて行間を詰める。
		# 窓の内側は 150px しかないので、4 人目（84+48+文字高）でちょうど収まる。
		var row := origin + Vector2(6, 84 + i * 16)
		PixelUI.draw_text(self, row, m.name, PixelUI.C_TEXT)
		PixelUI.draw_text(self, row + Vector2(58, 0), _job_name(m.job_id), PixelUI.C_TEXT_DIM)
		PixelUI.draw_text(
			self, row + Vector2(170, 2),
			_stars(m.mastery_rank(), _max_rank(m.job_id)), PixelUI.C_ACTIVE, PixelUI.SIZE_SUB
		)


## 編成。名簿の全員を並べ、連れて行く者に印を付ける。
func _draw_party_note() -> void:
	var origin := PixelUI.content(DETAIL_RECT).position
	PixelUI.draw_text(self, origin + Vector2(6, 2), Terms.PARTY, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	PixelUI.draw_text(
		self, origin + Vector2(6, 26),
		"%d 人まで 連れて行ける。" % GameState.PARTY_SIZE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)

	var all_members := GameState.all_members()
	var rows := all_members.size() + 1
	var span := MenuList.range_of(_party_index, rows, 6)
	for row in range(span[0], span[1]):
		var at := origin + Vector2(6, 46 + (row - span[0]) * 18)
		var on := _state == State.PARTY and row == _party_index
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		if row >= all_members.size():
			var price := GameState.recruit_price()
			var label := "なかまを 迎える（%s %d）" % [Terms.ECHO, price]
			if not GameState.can_recruit():
				label = "これで 全員"
			PixelUI.draw_text(
				self, at, label, PixelUI.C_ACTIVE if on else PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
			)
			continue
		var m := all_members[row]
		var mark := "●" if GameState.is_active(row) else "○"
		PixelUI.draw_text(
			self, at, "%s %s" % [mark, m.name],
			PixelUI.C_TEXT if GameState.is_active(row) else PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		PixelUI.draw_text(
			self, at + Vector2(110, 0), _job_name(m.job_id),
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
	MenuList.draw_position(self, PixelUI.content(DETAIL_RECT), _party_index, rows, 6)


## 資源の使い道の一覧。何段まで伸ばしたかと、次の 1 段の値段を並べる。
func _draw_upgrade_note() -> void:
	var origin := PixelUI.content(DETAIL_RECT).position
	PixelUI.draw_text(
		self, origin + Vector2(6, 2), "%s %d" % [Terms.ECHO, GameState.echo],
		PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD
	)
	PixelUI.draw_text(
		self, origin + Vector2(6, 26), Lore.ECHO_LINE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)
	PixelUI.draw_text(self, origin + Vector2(150, 50), Terms.RANK, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	PixelUI.draw_text(self, origin + Vector2(200, 50), Terms.PRICE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)

	for i in _upgrade_ids.size():
		var id := String(_upgrade_ids[i])
		var u := Database.upgrade(id)
		var row := origin + Vector2(6, 68 + i * 20)
		var level := GameState.upgrade_level(id)
		var maxed := GameState.upgrade_maxed(id)
		var on := _state == State.UPGRADE and i == _upgrade_index
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, row)
		PixelUI.draw_text(self, row, String(u.get("name", id)), tint)
		PixelUI.draw_text(
			self, row + Vector2(144, 0),
			"%d/%d" % [level, int(u.get("levels", 0))],
			PixelUI.C_ACTIVE if level > 0 else PixelUI.C_TEXT_DIM
		)
		var price := Terms.MAXED if maxed else "%d" % GameState.upgrade_price(id)
		PixelUI.draw_text(self, row + Vector2(200, 0), price, PixelUI.C_TEXT_DIM)


func _draw_menu() -> void:
	PixelUI.draw_window(self, MENU_RECT, WINDOW_TEX)
	if _state == State.JOB:
		_draw_job_menu()
	elif _state == State.UPGRADE or _index == _upgrade_row():
		_draw_upgrade_desc()
	elif _state == State.PARTY or _index == _party_row():
		_draw_party_hint()
	elif _index == _depart_row():
		_draw_hint()
	else:
		_draw_learned()


## 編成のときの案内。名簿の行と操作を分けて書く。
func _draw_party_hint() -> void:
	var origin := PixelUI.content(MENU_RECT).position
	PixelUI.draw_text(self, origin + Vector2(8, 2), "連れて行く なかまを えらぶ", PixelUI.C_TEXT)
	PixelUI.draw_text(
		self, origin + Vector2(8, 28), "● が 出撃する なかま。Ｚ で 入れ替える。", PixelUI.C_TEXT_DIM
	)
	PixelUI.draw_text(
		self, origin + Vector2(8, 52),
		"留守番した なかまは 熟練が 積まれない。", PixelUI.C_TEXT_DIM
	)


func _draw_upgrade_desc() -> void:
	var origin := PixelUI.content(MENU_RECT).position
	if _upgrade_ids.is_empty():
		return
	var id := String(_upgrade_ids[_upgrade_index])
	var u := Database.upgrade(id)
	PixelUI.draw_text(self, origin + Vector2(8, 2), String(u.get("name", id)), PixelUI.C_ACTIVE)
	PixelUI.draw_text(self, origin + Vector2(8, 26), String(u.get("desc", "")), PixelUI.C_TEXT)
	var tail := "Ｚで のばす　Ｘで もどる"
	if _state != State.UPGRADE:
		tail = "Ｚで えらぶ"
	PixelUI.draw_text(self, origin + Vector2(8, 52), tail, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)


func _draw_learned() -> void:
	var member := _selected()
	if member == null:
		return
	var origin := PixelUI.content(MENU_RECT).position
	PixelUI.draw_text(self, origin + Vector2(8, 0), "おぼえた わざ", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)

	if member.learned.is_empty():
		PixelUI.draw_text(
			self, origin + Vector2(8, 22), "まだ なにも おぼえていない。", PixelUI.C_TEXT_DIM
		)
		PixelUI.draw_text(
			self, origin + Vector2(8, 46), "たたかって じゅくれんを あげると おぼえる。",
			PixelUI.C_TEXT_DIM
		)
		return

	for i in member.learned.size():
		var ability_id := String(member.learned[i])
		var col := i % ABILITY_COLUMNS
		var row := i / ABILITY_COLUMNS
		var at := origin + Vector2(8 + col * 118, 22 + row * 20)
		PixelUI.draw_text(
			self, at, String(Database.ability(ability_id).get("name", ability_id)), PixelUI.C_TEXT
		)


func _draw_hint() -> void:
	var origin := PixelUI.content(MENU_RECT).position
	PixelUI.draw_text(self, origin + Vector2(8, 2), "↑↓ えらぶ　Ｚ けってい　Ｘ もどる", PixelUI.C_TEXT_DIM)
	PixelUI.draw_text(
		self, origin + Vector2(8, 28), "なかまを えらぶと てんしょくできる。", PixelUI.C_TEXT_DIM
	)
	PixelUI.draw_text(
		self, origin + Vector2(8, 52), "じゅくれんは しょくぎょうごとに のこる。", PixelUI.C_TEXT_DIM
	)


func _draw_job_menu() -> void:
	var member := _selected()
	var origin := PixelUI.content(MENU_RECT).position
	var highlighted := String(_job_ids[_job_index])

	# まだ就けない職業は、説明の代わりに「あと何が要るか」を出す。
	# 選べない理由が見えないと、上級職はただ灰色の行になってしまう。
	if member.can_take_job(highlighted):
		PixelUI.draw_text(
			self, origin + Vector2(8, 0),
			String(Database.job(highlighted).get("desc", "")), PixelUI.C_TEXT
		)
	else:
		PixelUI.draw_text(
			self, origin + Vector2(8, 0),
			"つくには %s が いる" % "　".join(member.unmet_requirements(highlighted)),
			PixelUI.C_HP_LOW
		)

	var rows := _job_rows()
	for i in _job_ids.size():
		var job_id := String(_job_ids[i])
		@warning_ignore("integer_division")
		var col := i / rows
		var row := i % rows
		var at := origin + Vector2(18 + col * 118, 20 + row * 14)
		var on := i == _job_index
		var locked := not member.can_take_job(job_id)
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if job_id == member.job_id:
			tint = PixelUI.C_ACTIVE
		elif locked:
			tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.55)
		# 4 列に詰めたので、ここは名前だけ。★ と速さと説明は上の詳細窓に出ている。
		# 名前の隣に ★ を置くと「まじゅうつかい」のような長い名前とぶつかった。
		var label := _job_name(job_id) if not locked else _job_name(job_id) + "×"
		PixelUI.draw_text(self, at, label, tint, PixelUI.SIZE_SUB)


func _draw_notice() -> void:
	_notice.draw(self, WINDOW_TEX, 130.0)
