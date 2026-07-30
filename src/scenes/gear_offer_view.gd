class_name GearOfferView
extends Node2D

## 拾った装備を、その場で着けるか聞く画面（C-9）。
##
## 宝箱・イベント・店のどれで手に入れても**ここ 1 つ**に集まる
## （`GameState.gear_gained` を通る）。経路ごとに聞いていたら、
## 経路が増えるたびに聞き忘れが出る。
##
## 守ること:
##
##   * **断っても失わない。** 入手そのものは既に済んでいて、ここは
##     「いま着けるか」を聞くだけ。閉じれば手持ちに残る。
##   * **効き目を数で見せる。** 「つよそう」ではなく、いまの値 → 着けた後の値。
##     外れる装備も出す（黙って外れるのがいちばん困る）。
##   * **割り込ませない。** 開いているあいだは歩けないので、遭遇も階段も起きない。
##   * 表示語は `Terms`（`docs` の語彙の外部化に合わせる）。

signal chosen(member_index: int)   ## -1 なら「もちものへ」

const WINDOW_TEX := preload("res://assets/ui/window.png")
const CURSOR_TEX := preload("res://assets/ui/cursor.png")

const RECT := Rect2(56, 54, 400, 212)
const ROW := 28.0

var gear_id := ""
var _members: Array = []
var _index := 0


func open(id: String, members: Array) -> void:
	gear_id = id
	_members = members
	_index = _bag_row()
	for i in _members.size():
		if _can_member(i):
			_index = i
			break
	visible = true
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process_unhandled_input(false)


## 「もちものへ」の行番号。仲間の下に置く。
func _bag_row() -> int:
	return _members.size()


func _can_member(index: int) -> bool:
	return (
		index >= 0
		and index < _members.size()
		and (_members[index] as PartyMember).can_equip(gear_id)
	)


func _is_selectable(index: int) -> bool:
	return index == _bag_row() or _can_member(index)


## 適性の無い仲間は表示には残すが、カーソルは止めない。
func _move_selection(direction: int) -> void:
	var rows := _members.size() + 1
	for _try in rows:
		_index = (_index + direction + rows) % rows
		if _is_selectable(_index):
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		Sound.play("cancel")
		chosen.emit(-1)
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		Sound.play("confirm")
		chosen.emit(-1 if _index == _bag_row() else _index)


## その者に着けたときの差。**いまの値 → 着けた後の値**を組み立てる。
##
## 装備が持つ能力だけを見る（持っていない能力を 0 と並べても読みづらい）。
func delta_text(member: PartyMember) -> String:
	if not member.can_equip(gear_id):
		return Terms.CANNOT_EQUIP
	var gear := Database.gear(gear_id)
	var slot := String(gear.get("slot", ""))
	var worn := String(member.equipment.get(slot, ""))
	var parts: Array[String] = []
	for stat in ["atk", "def", "agi", "hp", "mag"]:
		var now := int(Database.gear(worn).get(stat, 0)) if worn != "" else 0
		var next := int(gear.get(stat, 0))
		if now == next:
			continue
		parts.append("%s %+d→%+d" % [Terms.stat(stat), now, next])
	# 行動コストは負が軽い。**符号の向きが逆なので言い換える。**
	var cost_now := int(Database.gear(worn).get("cost_scale", 0)) if worn != "" else 0
	var cost_next := int(gear.get("cost_scale", 0))
	if cost_now != cost_next:
		parts.append("%s %d→%d" % [
			Terms.SPEED, Terms.speed(cost_now), Terms.speed(cost_next)])
	if parts.is_empty():
		return "かわらない"
	return "　".join(parts)


## 外れる装備の名（何も着けていなければ空）。
func removed_name(member: PartyMember) -> String:
	var slot := String(Database.gear(gear_id).get("slot", ""))
	var worn := String(member.equipment.get(slot, ""))
	return "" if worn == "" else String(Database.gear(worn).get("name", worn))


func _draw() -> void:
	if not visible:
		return
	PixelUI.ui_frame()
	var name := String(Database.gear(gear_id).get("name", gear_id))
	var panel := UiPanel.begin(self, RECT, WINDOW_TEX, Terms.GOT_GEAR % name)
	var desc := String(Database.gear(gear_id).get("desc", ""))
	if desc != "":
		# 装備の説明は data 側（漢字を含む）。**14px より下げない**（D-5）。
		panel.line(desc, PixelUI.C_TEXT_DIM)
	panel.skip(4.0)

	var top := panel.cursor_y()
	for i in _members.size():
		var member: PartyMember = _members[i]
		var at := Vector2(panel.inner().position.x + 14, top + float(i) * ROW)
		if _index == i:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		var can_wear := member.can_equip(gear_id)
		var tint := (
			PixelUI.C_TEXT if _index == i
			else PixelUI.C_TEXT_DIM if can_wear
			else PixelUI.C_SHADOW
		)
		var width := panel.inner().end.x - at.x
		# **名前と差分を同じ行に並べない。** 能力が 3 つ動く装備だと差分だけで
		# 幅を食い切って、名前が「ア…」に詰まった（関門が拾った）。
		# 1 行目は名前と外れるもの、2 行目に差分を下ろす。
		var off := removed_name(member) if can_wear else ""
		UiPanel.inside(self, Rect2(at, Vector2(width, PixelUI.LINE))).row(
			member.name,
			Terms.CANNOT_EQUIP if not can_wear
			else "" if off == ""
			else "（%s が %s）" % [off, Terms.TAKES_OFF],
			tint, PixelUI.C_TEXT_DIM
		)
		UiPanel.inside(self, Rect2(
			at + Vector2(12, 12), Vector2(width - 12.0, PixelUI.LINE)
		# 能力の呼び名は漢字を含む（速さ・体力）。**14px より下げない**（D-5）。
		)).line(delta_text(member), PixelUI.C_TEXT_DIM)

	var bag_at := Vector2(
		panel.inner().position.x + 14, top + float(_members.size()) * ROW)
	if _index == _bag_row():
		MenuList.draw_cursor(self, CURSOR_TEX, bag_at)
	UiPanel.inside(self, Rect2(
		bag_at, Vector2(panel.inner().end.x - bag_at.x, PixelUI.LINE)
	)).line(
		Terms.TO_BAG,
		PixelUI.C_ACTIVE if _index == _bag_row() else PixelUI.C_TEXT_DIM
	)
