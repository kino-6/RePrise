class_name FieldMenu
extends Node2D

## 探索中のメニュー。決定キーで開き、キャンセルで閉じる。
##
## どうぐ / つよさ / そうび の 3 つだけ。ここに無いと、道具は戦闘中にしか使えず、
## 装備は買った瞬間にしか触れず、能力値はどこにも出ないままになる。
##
## 画面配置（512x320）
##   左  : 第 1 階層（どうぐ / つよさ / そうび / とじる）
##   右  : 選んだものの中身
##   下  : 説明と操作の案内

signal closed
signal settings_requested
signal map_requested
## ラン途中で保存して閉じる。**世界 1 周が 1 ランなので、途中で閉じられないと無理がある。**
signal suspend_requested
## 用が済んだ洞から出る。最深部まで歩かせないための逃げ道。
signal escape_requested

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const ROOT_RECT := Rect2(8, 8, 150, 152)
const BODY_RECT := Rect2(166, 8, 338, 240)
const HINT_RECT := Rect2(8, 256, 496, 56)
const PARTY_RECT := Rect2(8, 168, 150, 80)

## 第 1 階層の行送り。
##
## 1 行の高さ。項目は送って表示し、下に現在位置を残す。
const ROW := 17
const ROOT_VISIBLE := 7

## そうびの 3 スロット。順番は固定する。
const SLOTS: Array[String] = ["weapon", "armor", "accessory"]
## 部位の呼び名。**`static var` にする** ―― `Terms` は語彙ファイルから
## 読むので定数式にならない（`const` だと「定数式ではない」で落ちる）。
static var SLOT_LABELS := {
	"weapon": Terms.SLOT_WEAPON,
	"armor": Terms.SLOT_ARMOR,
	"accessory": Terms.SLOT_ACCESSORY,
}

enum State { ROOT, MEMBER, ITEM, ITEM_TARGET, STATUS, SLOT, GEAR, JOB }

static var ROOT_ITEMS: Array[String] = [
	Terms.MENU_ITEMS, Terms.MENU_STATUS, Terms.MENU_EQUIP, Terms.MENU_JOB, Terms.MAP_MENU,
	Terms.MENU_SETTINGS, Terms.MENU_SUSPEND, Terms.MENU_ESCAPE, Terms.MENU_CLOSE,
]

## てんしょくの一覧は 2 列。15 職あるので 1 列だと枠から出る。
const JOB_COLS := 2
## BODY_RECT に説明を残したまま収まる一覧数。超えたらカーソルに追従して送る。
const ITEM_ROWS := 10
const GEAR_ROWS := 4

var _state: State = State.ROOT
var _root_index := 0
var _member_index := 0
var _item_index := 0
var _target_index := 0
var _slot_index := 0
var _gear_index := 0
var _notice := Notice.new()
var _input_lock := 0.0

## そうび / つよさ のどちらから人を選んでいるか。
var _after_member: State = State.STATUS

const INPUT_LOCK := 0.15


func open() -> void:
	_state = State.ROOT
	_root_index = 0
	_member_index = 0
	_notice.clear()
	_input_lock = INPUT_LOCK
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


func is_root() -> bool:
	return _state == State.ROOT


func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock -= delta
	if _notice.tick(delta):
		queue_redraw()


func _notify(text: String) -> void:
	_notice.set_text(text)
	queue_redraw()


## 開発用。そうびの画面を撮るのに使う。
func debug_open_equip() -> void:
	_root_index = 2
	_after_member = State.SLOT
	_member_index = 0
	_slot_index = 0
	_gear_index = 1
	_state = State.GEAR
	queue_redraw()


func _party() -> Array[PartyMember]:
	return GameState.active_party()


func _items() -> Array:
	return GameState.inventory_ids()


func _gear_list() -> Array[String]:
	var member := _selected()
	if member == null:
		return []
	return GameState.gear_stock_for_member_slot(member, SLOTS[_slot_index])


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	match _state:
		State.ROOT:
			_input_root(event)
		State.MEMBER:
			_input_member(event)
		State.ITEM:
			_input_item(event)
		State.ITEM_TARGET:
			_input_item_target(event)
		State.STATUS:
			if event.is_action_pressed("cancel") or event.is_action_pressed("confirm"):
				Sound.play("cancel")
				_state = State.MEMBER
				queue_redraw()
		State.SLOT:
			_input_slot(event)
		State.JOB:
			_input_job(event)
		State.GEAR:
			_input_gear(event)


func _move(index: int, size: int, event: InputEvent) -> int:
	if size <= 0:
		return 0
	if event.is_action_pressed("ui_down"):
		Sound.play("cursor")
		return (index + 1) % size
	if event.is_action_pressed("ui_up"):
		Sound.play("cursor")
		return (index - 1 + size) % size
	return index


func _input_root(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_leave()
		return
	_root_index = _move(_root_index, ROOT_ITEMS.size(), event)
	if event.is_action_pressed("confirm"):
		Sound.play("confirm")
		match _root_index:
			0:
				if _items().is_empty():
					_notify(Terms.NO_ITEMS)
				else:
					_item_index = 0
					_state = State.ITEM
			1:
				_after_member = State.STATUS
				_state = State.MEMBER
			2:
				_after_member = State.SLOT
				_state = State.MEMBER
			3:
				_after_member = State.JOB
				_state = State.MEMBER
			4:
				close()
				map_requested.emit()
				return
			5:
				close()
				settings_requested.emit()
				return
			6:
				close()
				suspend_requested.emit()
				return
			7:
				close()
				escape_requested.emit()
				return
			8:
				_leave()
				return
	queue_redraw()


func _input_member(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.ROOT
		queue_redraw()
		return
	_member_index = _move(_member_index, _party().size(), event)
	if event.is_action_pressed("confirm"):
		Sound.play("confirm")
		_slot_index = 0
		if _after_member == State.JOB:
			_job_ids = Database.job_ids()
			_job_index = maxi(_job_ids.find(_selected().job_id), 0)
		_state = _after_member
	queue_redraw()


var _job_ids: Array = []
var _job_index := 0


func _selected() -> PartyMember:
	var party := _party()
	return party[clampi(_member_index, 0, party.size() - 1)] if not party.is_empty() else null


## てんしょく。どこでも自由にできる（取り上げるものは無い）。
## 開発用。てんしょくの一覧を撮るために使う。
func debug_open_jobs() -> void:
	_root_index = 3
	_member_index = 0
	_after_member = State.JOB
	_job_ids = Database.job_ids()
	_job_index = maxi(_job_ids.find(_selected().job_id), 0)
	_state = State.JOB
	queue_redraw()


## 開発用。つよさ の画面を撮るために使う。
func debug_open_status() -> void:
	_root_index = 1
	_member_index = 0
	_after_member = State.STATUS
	_state = State.STATUS
	queue_redraw()


func _input_job(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
		return
	if _job_ids.is_empty():
		return
	var rows := int(ceil(_job_ids.size() / float(JOB_COLS)))
	if event.is_action_pressed("ui_down"):
		_job_index = (_job_index + 1) % _job_ids.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_up"):
		_job_index = (_job_index - 1 + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_right"):
		_job_index = (_job_index + rows) % _job_ids.size()
		Sound.play("cursor")
	elif event.is_action_pressed("ui_left"):
		_job_index = (_job_index - rows + _job_ids.size()) % _job_ids.size()
		Sound.play("cursor")
	elif event.is_action_pressed("confirm"):
		_apply_job()
	queue_redraw()


func _apply_job() -> void:
	var member := _selected()
	if member == null:
		return
	var job_id := String(_job_ids[_job_index])
	if job_id == member.job_id:
		Sound.play("cancel")
		_notify("すでに %s だ" % _job_name(job_id))
		return
	if not member.can_take_job(job_id):
		Sound.play("cancel")
		_notify("つくには %s が いる" % "　".join(member.unmet_requirements(job_id)))
		return
	if not GameState.change_job(member, job_id):
		Sound.play("cancel")
		return
	Sound.play("learn")
	_notify("%sは %s になった" % [member.name, _job_name(job_id)])
	_state = State.MEMBER


func _job_name(job_id: String) -> String:
	return String(Database.job(job_id).get("name", job_id))


func _input_item(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.ROOT
		queue_redraw()
		return
	_item_index = _move(_item_index, _items().size(), event)
	if event.is_action_pressed("confirm"):
		if _items().is_empty():
			return
		var item := Database.item(String(_items()[_item_index]))
		if (
			String(item.get("target", "")) == "one_enemy"
			or String(item.get("effect", "")) == "haste"
		):
			Sound.play("cancel")
			_notify(Terms.BATTLE_ONLY)
			queue_redraw()
			return
		Sound.play("confirm")
		_target_index = 0
		_state = State.ITEM_TARGET
	queue_redraw()


func _input_item_target(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.ITEM
		queue_redraw()
		return
	_target_index = _move(_target_index, _party().size(), event)
	if event.is_action_pressed("confirm"):
		_use_item()
	queue_redraw()


## 道具を歩きながら使う。戦闘中と違って手番は消費しない（時間軸の外なので）。
func _use_item() -> void:
	var items := _items()
	if items.is_empty():
		return
	var item_id := String(items[clampi(_item_index, 0, items.size() - 1)])
	var it := Database.item(item_id)
	var who := _party()[clampi(_target_index, 0, _party().size() - 1)]
	var effect := String(it.get("effect", ""))
	var power := int(it.get("power", 0))
	var label := String(it.get("name", item_id))

	match effect:
		"heal_hp":
			if who.hp <= 0:
				Sound.play("cancel")
				_notify(Terms.CANNOT_USE_ON_FALLEN)
				return
			if who.hp >= who.max_hp():
				Sound.play("cancel")
				_notify("%sは 元気だ" % who.name)
				return
			var before := who.hp
			who.hp = mini(who.hp + power, who.max_hp())
			_notify("%sの きずが %d かいふくした" % [who.name, who.hp - before])
		"heal_mp":
			if who.mp >= who.max_mp():
				Sound.play("cancel")
				_notify("%sの まりょくは みちている" % who.name)
				return
			var mp_before := who.mp
			who.mp = mini(who.mp + power, who.max_mp())
			_notify("%sの まりょくが %d もどった" % [who.name, who.mp - mp_before])
		"cleanse":
			if not who.cure_poison():
				Sound.play("cancel")
				_notify("%sは なんともない" % who.name)
				return
			_notify("%sの どくが 消えた" % who.name)
		"heal_cleanse":
			if who.hp <= 0:
				Sound.play("cancel")
				_notify(Terms.CANNOT_USE_ON_FALLEN)
				return
			var hp_before := who.hp
			var cured := who.cure_poison()
			who.hp = mini(who.hp + power, who.max_hp())
			var healed := who.hp - hp_before
			if healed <= 0 and not cured:
				Sound.play("cancel")
				_notify("%sは なんともない" % who.name)
				return
			if cured and healed > 0:
				_notify("%sの 傷とどくが 癒えた" % who.name)
			elif cured:
				_notify("%sの どくが 消えた" % who.name)
			else:
				_notify("%sの きずが %d かいふくした" % [who.name, healed])
		"revive":
			if who.hp > 0:
				Sound.play("cancel")
				_notify("%sは たおれていない" % who.name)
				return
			who.hp = maxi(who.max_hp() * power / 100, 1)
			_notify("%sは いきを ふきかえした！" % who.name)
		_:
			Sound.play("cancel")
			_notify(Terms.CANNOT_USE_HERE)
			return

	GameState.consume_item(item_id)
	Sound.play("heal")
	if _items().is_empty():
		_state = State.ROOT
	else:
		_item_index = mini(_item_index, _items().size() - 1)
		_state = State.ITEM
	queue_redraw()
	# 使ったことを呼び出し側の HUD にも伝える
	_notify("%s（%s）" % [_notice.text, label])


func _input_slot(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.MEMBER
		queue_redraw()
		return
	# 最後の 1 行は「さいきょう」。**全員ぶんをまとめて配る。**
	_slot_index = _move(_slot_index, SLOTS.size() + 1, event)
	if event.is_action_pressed("confirm"):
		if _slot_index == SLOTS.size():
			_apply_best_gear()
			queue_redraw()
			return
		Sound.play("confirm")
		_gear_index = 0
		_state = State.GEAR
	queue_redraw()


## さいきょう装備（C-10）。**判断は `BestGear` 一本**にしてある ――
## ここと自動プレイで別々に書くと、測っている強さと遊べる強さがずれる。
func _apply_best_gear() -> void:
	var changed := BestGear.apply(GameState, GameState.active_party())
	if changed > 0:
		Sound.play("confirm")
		_notify("%s装備を %d 個 つけかえた" % [Terms.BEST_GEAR, changed])
	else:
		Sound.play("cancel")
		_notify(Terms.NO_BETTER_GEAR)


func _input_gear(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.SLOT
		queue_redraw()
		return
	# 先頭は「はずす」なので +1 個ぶん多く回す
	_gear_index = _move(_gear_index, _gear_list().size() + 1, event)
	if event.is_action_pressed("confirm"):
		_apply_gear()
	queue_redraw()


func _apply_gear() -> void:
	var member := _selected()
	if member == null:
		return
	var slot: String = SLOTS[_slot_index]
	if _gear_index == 0:
		if GameState.unequip_gear(member, slot):
			Sound.play("confirm")
			_notify("%sを はずした" % SLOT_LABELS[slot])
		else:
			Sound.play("cancel")
			_notify(Terms.NOTHING_EQUIPPED)
		queue_redraw()
		return

	var list := _gear_list()
	var gear_id := list[clampi(_gear_index - 1, 0, list.size() - 1)]
	if GameState.equip_gear(member, gear_id):
		Sound.play("confirm")
		_notify("%sは %s を そうびした" % [member.name, Database.gear(gear_id).get("name", gear_id)])
	else:
		Sound.play("cancel")
	_gear_index = 0
	_state = State.SLOT
	queue_redraw()


func _leave() -> void:
	close()
	closed.emit()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _draw() -> void:
	PixelUI.ui_frame()
	# 塗りつぶさずに暗くするだけ。下のダンジョンが透けていれば
	# 「歩みを止めて鞄を開けている」ように見える（塗ると場面が切り替わって見える）。
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color(0.03, 0.04, 0.08, 0.55), true)
	_draw_root()
	_draw_party_box()
	_draw_body()
	_draw_hint()


func _draw_root() -> void:
	PixelUI.draw_window(self, ROOT_RECT, WINDOW_TEX)
	var origin := PixelUI.content(ROOT_RECT).position + Vector2(16, 2)
	var shown := MenuList.range_of(_root_index, ROOT_ITEMS.size(), ROOT_VISIBLE)
	for i in range(shown[0], shown[1]):
		var at := origin + Vector2(0, (i - shown[0]) * ROW)
		if i == _root_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var on := i == _root_index and _state == State.ROOT
		UiPanel.inside(self, Rect2(
			at, Vector2(PixelUI.content(ROOT_RECT).end.x - 6.0 - at.x, PixelUI.LINE)
		)).line(ROOT_ITEMS[i], PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM)
	MenuList.draw_position(
		self, PixelUI.content(ROOT_RECT),
		_root_index, ROOT_ITEMS.size(), ROOT_VISIBLE
	)


## 左下は常にパーティの並び。誰を選んでいるかがどの階層でも見える。
func _draw_party_box() -> void:
	PixelUI.draw_window(self, PARTY_RECT, WINDOW_TEX)
	var origin := PixelUI.content(PARTY_RECT).position + Vector2(16, 2)
	var party := _party()
	var picking := _state in [State.MEMBER, State.ITEM_TARGET]
	var index := _target_index if _state == State.ITEM_TARGET else _member_index
	for i in party.size():
		var at := origin + Vector2(0, i * 17)
		var m := party[i]
		var color := PixelUI.C_TEXT_DIM
		if m.hp <= 0:
			color = PixelUI.C_HP_LOW
		if picking and i == index:
			draw_texture(CURSOR_TEX, (at + Vector2(-14, 2)).floor())
			color = PixelUI.C_ACTIVE
		# 名前と HP を 1 行に。**HP は消えては困る**ので、詰まるのは名前のほう。
		UiPanel.inside(self, Rect2(
			at, Vector2(118.0 + origin.x - at.x, PixelUI.LINE)
		)).row(
			m.name, "%d/%d" % [m.hp, m.max_hp()],
			color, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)


func _draw_body() -> void:
	PixelUI.draw_window(self, BODY_RECT, WINDOW_TEX)
	match _state:
		State.ITEM, State.ITEM_TARGET:
			_draw_items()
		State.STATUS:
			_draw_status()
		State.SLOT, State.GEAR:
			_draw_equip()
		State.JOB:
			_draw_jobs()
		_:
			if _root_index == 0:
				_draw_items()
			elif _root_index == 1 or _root_index == 2:
				_draw_status()
			elif _root_index == 3:
				_draw_job_notice()
			elif _root_index == 4:
				_draw_map_notice()
			elif _root_index == 6:
				_draw_suspend_notice()
			elif _root_index == 7:
				_draw_escape_notice()


## 職業一覧の 1 列の幅。★ の位置（+132）まで含めた列の取り分。
const JOB_COL_W := 132.0


## 案内 3 種の見出し行。**幅は窓の内側から取る**（文言を変えても溢れない）。
func _note_head(origin: Vector2) -> UiPanel:
	var body := PixelUI.content(BODY_RECT)
	return UiPanel.inside(self, Rect2(
		origin, Vector2(body.end.x - origin.x - 8.0, PixelUI.LINE)))


## 案内 3 種の本文 i 行目。
func _note_line(origin: Vector2, i: int) -> UiPanel:
	return _note_head(origin + Vector2(0, 32 + i * 22))


## てんしょくを選ぶ前の案内。押す前に読める位置に置く。
func _draw_job_notice() -> void:
	var origin := PixelUI.content(BODY_RECT).position + Vector2(12, 4)
	_note_head(origin).line(Terms.MENU_JOB, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	var lines := [
		"いつでも どこでも 職を かえられる。",
		"レベルも じゅくれんも そのまま のこる。",
	]
	for i in lines.size():
		_note_line(origin, i).line(lines[i], PixelUI.C_TEXT_DIM)


func _draw_map_notice() -> void:
	var origin := PixelUI.content(BODY_RECT).position + Vector2(12, 4)
	_note_head(origin).line(Terms.WORLD_MAP, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	for i in Terms.MAP_MENU_LINES.size():
		_note_line(origin, i).line(Terms.MAP_MENU_LINES[i], PixelUI.C_TEXT_DIM)


## 職業の一覧。2 列。選べない職業は理由を下に出す。
func _draw_jobs() -> void:
	var member := _selected()
	if member == null or _job_ids.is_empty():
		return
	var origin := PixelUI.content(BODY_RECT).position + Vector2(12, 2)
	_note_head(origin).line(
		"%s を てんしょく" % member.name, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	_note_head(origin + Vector2(0, 24)).line(
		"Lv%d のまま。おぼえた わざも のこる" % member.level,
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)

	var rows := int(ceil(_job_ids.size() / float(JOB_COLS)))
	for i in _job_ids.size():
		var job_id := String(_job_ids[i])
		@warning_ignore("integer_division")
		var col := i / rows
		var row := i % rows
		var at := origin + Vector2(16 + col * 156, 46 + row * 17)
		var on := i == _job_index
		var locked := not member.can_take_job(job_id)
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		if job_id == member.job_id:
			tint = PixelUI.C_ACTIVE
		elif locked:
			tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.55)
		var label := _job_name(job_id) if not locked else _job_name(job_id) + "×"
		# 列に幅を渡す。2 列に 15 職を詰めているので、長い職名は隣の列へ届く
		# （枠の中なので、はみ出し検出では捕まらなかった）。
		UiPanel.inside(self, Rect2(at, Vector2(JOB_COL_W, PixelUI.LINE))).line(label, tint)
		# **★ を並べない。** 2 列に 15 職を詰めているので、4 つ並べると
		# 隣の列の職業名に届く（枠の中なので、はみ出し検出では捕まらなかった）。
		# 数で出せば桁が増えても幅が変わらない。
		var rank := member.mastery_rank(job_id)
		if rank > 0:
			PixelUI.draw_text_right(
				self, Vector2(at.x + 132.0, at.y + 2), "★%d" % rank, tint, PixelUI.SIZE_SUB
			)


## 中断の案内。**何が起きるかを押す前に書く。**
func _draw_suspend_notice() -> void:
	var origin := PixelUI.content(BODY_RECT).position + Vector2(12, 4)
	_note_head(origin).line(Terms.MENU_SUSPEND, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	var lines := [
		"いまの ところで 保存して とじる。",
		"つぎに ひらくと ここから つづく。",
		"世界も もちものも そのまま。",
	]
	for i in lines.size():
		_note_line(origin, i).line(lines[i], PixelUI.C_TEXT_DIM)


## 洞から出る案内。使えないときは理由を出す。
func _draw_escape_notice() -> void:
	var origin := PixelUI.content(BODY_RECT).position + Vector2(12, 4)
	_note_head(origin).line(Terms.MENU_ESCAPE, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	var lines: Array[String] = []
	if GameState.can_escape_site():
		lines = ["ここでの 用は 済んでいる。", "入口へ もどって 世界へ 出る。"]
	else:
		lines = ["まだ ここには 用が ある。", "封を やぶるまでは ぬけだせない。"]
	for i in lines.size():
		_note_line(origin, i).line(lines[i], PixelUI.C_TEXT_DIM)


func _draw_items() -> void:
	var body := PixelUI.content(BODY_RECT)
	var area := Rect2(
		body.position + Vector2(16, 4),
		Vector2(body.size.x - 26.0, body.size.y - 8.0)
	)
	var panel := UiPanel.inside(self, area)
	panel.line(Terms.BAG, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var items := _items()
	if items.is_empty():
		panel.skip(6.0)
		panel.line(Terms.BAG_EMPTY, PixelUI.C_TEXT_DIM)
		return
	panel.skip(6.0)
	var item_range := MenuList.range_of(_item_index, items.size(), ITEM_ROWS)
	for i in range(item_range[0], item_range[1]):
		var it := Database.item(String(items[i]))
		var on := i == _item_index and _state in [State.ITEM, State.ITEM_TARGET]
		if on:
			MenuList.draw_cursor(
				self, CURSOR_TEX, Vector2(area.position.x, panel.cursor_y()))
		# 個数は右端で守る。品名が長くても数は消えない。
		panel.row(
			String(it.get("name", items[i])),
			"%d こ" % GameState.item_count(String(items[i])),
			PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM
		)
	MenuList.draw_position(self, area, _item_index, items.size(), ITEM_ROWS)


func _draw_status() -> void:
	var m := _selected()
	if m == null:
		return
	var body := PixelUI.content(BODY_RECT)
	var area := Rect2(
		body.position + Vector2(16, 4),
		Vector2(body.size.x - 26.0, body.size.y - 8.0)
	)
	var panel := UiPanel.inside(self, area)
	panel.line(m.name, PixelUI.C_TEXT, PixelUI.SIZE_HEAD)
	# 「Lv」だけだと、この人のレベルなのか職業の熟練なのか読めない。
	# 人のレベル（ランで失う）と職業の熟練（持ち帰る）は別物なので、必ず並べて書く。
	panel.row(
		String(Database.job(m.job_id).get("name", m.job_id)),
		"%s %d" % [Terms.SPEED, Terms.speed(m.cost_scale())],
		PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM
	)
	if m.poison_steps > 0:
		UiPanel.inside(self, Rect2(
			area.position + Vector2(232, 30), Vector2(48.0, PixelUI.LINE)
		)).line(Terms.POISON, PixelUI.C_HP_LOW, PixelUI.SIZE_SUB)

	var mastery := "★".repeat(m.mastery_rank()) + "☆".repeat(
		maxi(Database.job(m.job_id).get("mastery", []).size() - m.mastery_rank(), 0)
	)
	# **値は行の右端で揃える。** ラベルから固定の位置に置くと、長いラベル
	# （「しょくぎょうの 熟練」）が必ず値と重なった（実際に重なっていた）。
	# `row()` は右を守って左を詰めるので、ラベルが伸びても衝突しない。
	#
	# 長い 2 行は 2 列の格子に入れず、幅いっぱいの独立した行にする。
	# 人のレベル（ランで失う）と職業の熟練（持ち帰る）は別物なので、
	# 短く縮めて並べるより、行を分けて書き切るほうがよい。
	panel.skip(6.0)
	panel.row(Terms.OWN_LEVEL, "%d" % m.level, PixelUI.C_TEXT_DIM,
		PixelUI.C_TEXT, PixelUI.SIZE_SUB)
	panel.row(Terms.JOB_MASTERY, mastery, PixelUI.C_TEXT_DIM, PixelUI.C_TEXT)

	# 能力は 2 列 x 3 行。列ごとに幅を持つので、値が隣の列へ食い込まない。
	panel.skip(6.0)
	var cols := panel.columns(2, 16.0)
	var rows := [
		["HP", "%d/%d" % [m.hp, m.max_hp()]],
		["MP", "%d/%d" % [m.mp, m.max_mp()]],
		[Terms.STAT_ATK_LABEL, "%d" % m.attack_power()],
		[Terms.STAT_MAG_LABEL, "%d" % m.magic_power()],
		[Terms.STAT_DEF_LABEL, "%d" % m.defense_power()],
		[Terms.STAT_AGI_LABEL, "%d" % m.agility()],
	]
	for i in rows.size():
		@warning_ignore("integer_division")
		cols[i / 3].row(
			String(rows[i][0]), String(rows[i][1]),
			PixelUI.C_TEXT_DIM, PixelUI.C_TEXT, PixelUI.SIZE_SUB
		)

	panel.move_to(cols[0].cursor_y() + 8.0)
	panel.line(Terms.MENU_EQUIP, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	for i in SLOTS.size():
		var gear_id := String(m.equipment.get(SLOTS[i], ""))
		var label := String(Database.gear(gear_id).get("name", "—")) if gear_id != "" else "—"
		# 品名は data 側で漢字を含む。**14px より下げない**（D-5）。
		panel.row(
			String(SLOT_LABELS[SLOTS[i]]), label, PixelUI.C_TEXT_DIM, PixelUI.C_TEXT)


func _draw_equip() -> void:
	var m := _selected()
	if m == null:
		return
	var origin := PixelUI.content(BODY_RECT).position + Vector2(16, 4)
	var body := PixelUI.content(BODY_RECT)
	var width := body.end.x - origin.x - 8.0
	UiPanel.inside(self, Rect2(origin, Vector2(width, PixelUI.LINE))).line(
		"%s の そうび" % m.name, PixelUI.C_TEXT)

	for i in SLOTS.size():
		var at := origin + Vector2(0, 28 + i * ROW)
		var on := i == _slot_index
		if on and _state == State.SLOT:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var gear_id := String(m.equipment.get(SLOTS[i], ""))
		var label := String(Database.gear(gear_id).get("name", "")) if gear_id != "" else "—"
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		# 部位名と品名の 2 列。品名は外部化の対象なので長さを前提にしない。
		UiPanel.inside(self, Rect2(at, Vector2(76.0, PixelUI.LINE))).line(
			String(SLOT_LABELS[SLOTS[i]]), tint, PixelUI.SIZE_SUB)
		UiPanel.inside(self, Rect2(
			at + Vector2(76, -2), Vector2(width - 76.0, PixelUI.LINE)
		)).line(label, tint)

	# 「さいきょう」の行。3 つのスロットの下に置く。
	var best_at := origin + Vector2(0, 28 + SLOTS.size() * ROW)
	var best_on := _slot_index == SLOTS.size()
	if best_on and _state == State.SLOT:
		MenuList.draw_cursor(self, CURSOR_TEX, best_at)
	UiPanel.inside(self, Rect2(
		best_at + Vector2(76, -2),
		Vector2(PixelUI.content(BODY_RECT).end.x - best_at.x - 84.0, PixelUI.LINE)
	)).line(Terms.BEST_GEAR, PixelUI.C_ACTIVE if best_on else PixelUI.C_TEXT_DIM)

	if _state != State.GEAR:
		return

	# 付け替え候補。先頭は必ず「はずす」。
	var list := _gear_list()
	var list_body := PixelUI.content(BODY_RECT)
	var panel := UiPanel.inside(self, Rect2(
		Vector2(origin.x, origin.y + 110.0),
		Vector2(
			list_body.end.x - origin.x - 10.0,
			list_body.end.y - origin.y - 112.0
		)
	))
	panel.line(Terms.SWAP, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	panel.skip(4.0)
	var entries: Array[String] = [Terms.TAKE_OFF]
	for id in list:
		entries.append(String(Database.gear(id).get("name", id)))
	var gear_range := MenuList.range_of(_gear_index, entries.size(), GEAR_ROWS)
	for i in range(gear_range[0], gear_range[1]):
		# **入らない行は `row()` が黙って捨てる**ので、自分で打ち切らなくてよい。
		var on := i == _gear_index
		if on:
			draw_texture(CURSOR_TEX, Vector2(origin.x - 14.0, panel.cursor_y() + 2.0).floor())
		# 効き目は右端で守る。品名が長くても数値は消えない。
		panel.row(
			entries[i],
			"" if i == 0 else GearText.summary(Database.gear(list[i - 1])),
			PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM
		)
	MenuList.draw_position(
		self, panel.inner(), _gear_index, entries.size(), GEAR_ROWS
	)


func _draw_hint() -> void:
	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var hint := PixelUI.content(HINT_RECT)
	var origin := hint.position + Vector2(8, 0)
	var panel := UiPanel.inside(self, Rect2(
		origin, Vector2(hint.end.x - origin.x, hint.end.y - origin.y)))
	if _notice.text != "":
		panel.line(_notice.text, PixelUI.C_ACTIVE)
	else:
		var desc := ""
		match _state:
			State.ITEM, State.ITEM_TARGET:
				var items := _items()
				if not items.is_empty():
					desc = String(Database.item(String(items[_item_index])).get("desc", ""))
			State.GEAR:
				var list := _gear_list()
				if _gear_index > 0 and _gear_index - 1 < list.size():
					desc = String(Database.gear(list[_gear_index - 1]).get("desc", ""))
			_:
				desc = ""
		panel.line(desc, PixelUI.C_TEXT_DIM)
	# 操作の案内は必ず 2 行目に置く（説明の長さで動かさない）。
	panel.move_to(origin.y + 24.0)
	panel.line(Terms.HINT_LIST, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
