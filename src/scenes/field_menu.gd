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

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const ROOT_RECT := Rect2(8, 8, 150, 152)
const BODY_RECT := Rect2(166, 8, 338, 240)
const HINT_RECT := Rect2(8, 256, 496, 56)
const PARTY_RECT := Rect2(8, 168, 150, 80)

const ROW := 24

## そうびの 3 スロット。順番は固定する。
const SLOTS: Array[String] = ["weapon", "armor", "accessory"]
const SLOT_LABELS := {"weapon": "ぶき", "armor": "よろい", "accessory": "かざり"}

enum State { ROOT, MEMBER, ITEM, ITEM_TARGET, STATUS, SLOT, GEAR }

const ROOT_ITEMS: Array[String] = ["どうぐ", "つよさ", "そうび", "とじる"]

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


func _selected() -> PartyMember:
	var party := _party()
	return party[clampi(_member_index, 0, party.size() - 1)] if not party.is_empty() else null


func _items() -> Array:
	return GameState.inventory_ids()


func _gear_list() -> Array[String]:
	return GameState.gear_stock_for_slot(SLOTS[_slot_index])


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
					_notify("どうぐを もっていない")
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
		_state = _after_member
	queue_redraw()


func _input_item(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_state = State.ROOT
		queue_redraw()
		return
	_item_index = _move(_item_index, _items().size(), event)
	if event.is_action_pressed("confirm"):
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
				_notify("たおれている ものには つかえない")
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
		"revive":
			if who.hp > 0:
				Sound.play("cancel")
				_notify("%sは たおれていない" % who.name)
				return
			who.hp = maxi(who.max_hp() * power / 100, 1)
			_notify("%sは いきを ふきかえした！" % who.name)
		_:
			Sound.play("cancel")
			_notify("ここでは つかえない")
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
	_slot_index = _move(_slot_index, SLOTS.size(), event)
	if event.is_action_pressed("confirm"):
		Sound.play("confirm")
		_gear_index = 0
		_state = State.GEAR
	queue_redraw()


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
			_notify("なにも つけていない")
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
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x08, 0x0A, 0x14), true)
	_draw_root()
	_draw_party_box()
	_draw_body()
	_draw_hint()


func _draw_root() -> void:
	PixelUI.draw_window(self, ROOT_RECT, WINDOW_TEX)
	var origin := PixelUI.content(ROOT_RECT).position + Vector2(16, 4)
	for i in ROOT_ITEMS.size():
		var at := origin + Vector2(0, i * ROW)
		if i == _root_index:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var on := i == _root_index and _state == State.ROOT
		PixelUI.draw_text(self, at, ROOT_ITEMS[i], PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM)


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
		PixelUI.draw_text(self, at, m.name, color, PixelUI.SIZE_SUB)
		PixelUI.draw_text_right(
			self, Vector2(origin.x + 118, at.y), "%d/%d" % [m.hp, m.max_hp()],
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
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
		_:
			if _root_index == 0:
				_draw_items()
			elif _root_index == 1 or _root_index == 2:
				_draw_status()


func _draw_items() -> void:
	var origin := PixelUI.content(BODY_RECT).position + Vector2(16, 4)
	PixelUI.draw_text(self, origin, "もちもの", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var items := _items()
	if items.is_empty():
		PixelUI.draw_text(self, origin + Vector2(0, 24), "なにも もっていない。", PixelUI.C_TEXT_DIM)
		return
	for i in items.size():
		var at := origin + Vector2(0, 24 + i * ROW)
		var it := Database.item(String(items[i]))
		var on := i == _item_index and _state in [State.ITEM, State.ITEM_TARGET]
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		PixelUI.draw_text(self, at, String(it.get("name", items[i])), PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM)
		PixelUI.draw_text_right(
			self, Vector2(origin.x + 280, at.y + 2), "%d こ" % GameState.item_count(String(items[i])),
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)


func _draw_status() -> void:
	var m := _selected()
	if m == null:
		return
	var origin := PixelUI.content(BODY_RECT).position + Vector2(16, 4)
	PixelUI.draw_text(self, origin, m.name, PixelUI.C_TEXT, PixelUI.SIZE_HEAD)
	PixelUI.draw_text(
		self, origin + Vector2(0, 26),
		"%s　Lv%d　%s %d" % [
			Database.job(m.job_id).get("name", m.job_id), m.level,
			Terms.SPEED, Terms.speed(m.cost_scale())
		],
		PixelUI.C_TEXT_DIM
	)

	var rows := [
		["HP", "%d/%d" % [m.hp, m.max_hp()]],
		["MP", "%d/%d" % [m.mp, m.max_mp()]],
		["こうげき", "%d" % m.attack_power()],
		["まりょく", "%d" % m.magic_power()],
		["しゅび", "%d" % m.defense_power()],
		["すばやさ", "%d" % m.agility()],
	]
	for i in rows.size():
		@warning_ignore("integer_division")
		var col := i / 3
		var row := i % 3
		var at := origin + Vector2(col * 150, 54 + row * 20)
		PixelUI.draw_text(self, at, String(rows[i][0]), PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		PixelUI.draw_text(self, at + Vector2(76, -2), String(rows[i][1]), PixelUI.C_TEXT)

	PixelUI.draw_text(self, origin + Vector2(0, 122), "そうび", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	for i in SLOTS.size():
		var at := origin + Vector2(0, 142 + i * 20)
		var gear_id := String(m.equipment.get(SLOTS[i], ""))
		var label := String(Database.gear(gear_id).get("name", "—")) if gear_id != "" else "—"
		PixelUI.draw_text(self, at, String(SLOT_LABELS[SLOTS[i]]), PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		PixelUI.draw_text(self, at + Vector2(76, -2), label, PixelUI.C_TEXT)


func _draw_equip() -> void:
	var m := _selected()
	if m == null:
		return
	var origin := PixelUI.content(BODY_RECT).position + Vector2(16, 4)
	PixelUI.draw_text(self, origin, "%s の そうび" % m.name, PixelUI.C_TEXT)

	for i in SLOTS.size():
		var at := origin + Vector2(0, 28 + i * ROW)
		var on := i == _slot_index
		if on and _state == State.SLOT:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var gear_id := String(m.equipment.get(SLOTS[i], ""))
		var label := String(Database.gear(gear_id).get("name", "")) if gear_id != "" else "—"
		var tint := PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		PixelUI.draw_text(self, at, String(SLOT_LABELS[SLOTS[i]]), tint, PixelUI.SIZE_SUB)
		PixelUI.draw_text(self, at + Vector2(76, -2), label, tint)

	if _state != State.GEAR:
		return

	# 付け替え候補。先頭は必ず「はずす」。
	var list := _gear_list()
	PixelUI.draw_text(self, origin + Vector2(0, 110), "つけかえる", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var entries: Array[String] = ["はずす"]
	for id in list:
		entries.append(String(Database.gear(id).get("name", id)))
	for i in entries.size():
		var at := origin + Vector2(0, 130 + i * 20)
		if at.y > PixelUI.content(BODY_RECT).end.y - 20:
			break
		var on := i == _gear_index
		if on:
			draw_texture(CURSOR_TEX, (at + Vector2(-14, 2)).floor())
		PixelUI.draw_text(
			self, at, entries[i], PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		)
		if i > 0:
			var gear := Database.gear(list[i - 1])
			PixelUI.draw_text_right(
				self, Vector2(origin.x + 280, at.y + 2), GearText.summary(gear),
				PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
			)


func _draw_hint() -> void:
	PixelUI.draw_window(self, HINT_RECT, WINDOW_TEX)
	var origin := PixelUI.content(HINT_RECT).position + Vector2(8, 0)
	if _notice.text != "":
		PixelUI.draw_text(self, origin, _notice.text, PixelUI.C_ACTIVE)
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
		PixelUI.draw_text(self, origin, desc, PixelUI.C_TEXT_DIM)
	PixelUI.draw_text(
		self, origin + Vector2(0, 24), "↑↓ えらぶ　Ｚ けってい　Ｘ もどる",
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)
