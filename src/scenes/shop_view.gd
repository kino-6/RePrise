class_name ShopView
extends Node2D

## 道中の出店。ゴールドの唯一の使い道。
##
## ゴールドをラン内限定の資源に決めたので、拠点ではなくここが買い物の場になる。
## 「今飲むか、あとに取っておくか」をラン中に判断させたいのであって、
## 拠点で計画を立てさせたいわけではない。だから店は道中にしか無い。
##
## 在庫はフロア（DungeonMap）が持つ。階を降りれば品は戻るが、
## 同じ階で買い占めることはできない。
##
## 画面配置（384x240）
##   y   6.. 30  店の名と所持金
##   y  34..156  左: 品書き / 右: 選択中の品とパーティの状態
##   y 160..234  説明と持ち物

signal closed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const HEADER_RECT := Rect2(6, 6, 372, 24)
const LIST_RECT := Rect2(6, 34, 170, 122)
const DETAIL_RECT := Rect2(180, 34, 198, 122)
const MENU_RECT := Rect2(6, 160, 372, 74)

const ROW_HEIGHT := 20
const NOTICE_TIME := 1.6
const INPUT_LOCK := 0.15

## 休息の値段は階層に比例させる。深いほど「もう一度整える」判断が重くなる。
const REST_BASE_PRICE := 20

var _map: DungeonMap = null
var _floor := 1
var _ids: Array = []
var _index := 0
var _notice := ""
var _notice_timer := 0.0
var _input_lock := 0.0


func open(map: DungeonMap, floor_number: int) -> void:
	_map = map
	_floor = floor_number
	_ids = Database.item_ids_for_floor(floor_number)
	# 在庫はこのフロアで一度だけ用意する。出入りしても戻らない。
	if _map.shop_stock.is_empty():
		# 「商いの伝手」を買っているぶんだけ品が多く並ぶ。
		var extra := GameState.upgrade_value("shop_stock")
		for id in _ids:
			_map.shop_stock[id] = int(Database.item(String(id)).get("stock", 1)) + extra
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


## 品書きの行数。品物 + 「やすむ」 + 「たちさる」。
func _rest_row() -> int:
	return _ids.size()


func _leave_row() -> int:
	return _ids.size() + 1


func rest_price() -> int:
	return REST_BASE_PRICE * _floor


func _stock_of(item_id: String) -> int:
	return int(_map.shop_stock.get(item_id, 0))


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	var rows := _leave_row() + 1
	if Input.is_action_just_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sound.play("cursor")
		queue_redraw()
	elif Input.is_action_just_pressed("cancel"):
		Sound.play("cancel")
		_leave()
	elif Input.is_action_just_pressed("confirm"):
		_decide()


func _decide() -> void:
	if _index == _leave_row():
		Sound.play("confirm")
		_leave()
	elif _index == _rest_row():
		_rest()
	else:
		_buy(String(_ids[_index]))


func _leave() -> void:
	close()
	closed.emit()


func _buy(item_id: String) -> void:
	var price := int(Database.item(item_id).get("price", 0))
	if _stock_of(item_id) <= 0:
		Sound.play("cancel")
		_notify("それは 売り切れだ")
		return
	if not GameState.spend_gold(price):
		Sound.play("cancel")
		_notify("ゴールドが たりない")
		return
	_map.shop_stock[item_id] = _stock_of(item_id) - 1
	GameState.add_item(item_id)
	Sound.play("chest")
	_notify("%s を 買った" % Database.item(item_id).get("name", item_id))


## 全回復。道具と違って手番を消費しないぶん高い。
func _rest() -> void:
	var price := rest_price()
	var party := GameState.active_party()
	var hurt := false
	for m in party:
		if m.hp < m.max_hp() or m.mp < m.max_mp():
			hurt = true
	if not hurt:
		Sound.play("cancel")
		_notify("休むほどでもない")
		return
	if not GameState.spend_gold(price):
		Sound.play("cancel")
		_notify("ゴールドが たりない")
		return
	for m in party:
		m.hp = m.max_hp()
		m.mp = m.max_mp()
	Sound.play("heal")
	_notify("すっかり 元気になった")


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x14, 0x0E, 0x10), true)
	_draw_header()
	_draw_list()
	_draw_detail()
	_draw_menu()
	_draw_notice()


func _draw_header() -> void:
	PixelUI.draw_window(self, HEADER_RECT, WINDOW_TEX)
	PixelUI.draw_text(self, HEADER_RECT.position + Vector2(12, 17), "みせ", PixelUI.C_ACTIVE, 13)
	var purse := "%d ゴールド" % GameState.gold
	var x := HEADER_RECT.end.x - 12 - PixelUI.text_width(purse, 11)
	PixelUI.draw_text(self, Vector2(x, HEADER_RECT.position.y + 17), purse, PixelUI.C_TEXT, 11)


func _draw_list() -> void:
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	for i in _ids.size():
		var item_id := String(_ids[i])
		var it := Database.item(item_id)
		var base := LIST_RECT.position + Vector2(20, 20 + i * ROW_HEIGHT)
		var sold_out := _stock_of(item_id) <= 0
		if _index == i:
			draw_texture(CURSOR_TEX, (base + Vector2(-13, -8)).floor())
		var tint := PixelUI.C_TEXT if _index == i else PixelUI.C_TEXT_DIM
		if sold_out:
			tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.5)
		PixelUI.draw_text(self, base, String(it.get("name", item_id)), tint, 11)
		var right := "売切" if sold_out else "%dG x%d" % [
			int(it.get("price", 0)), _stock_of(item_id)
		]
		PixelUI.draw_text(
			self, base + Vector2(LIST_RECT.size.x - 34 - PixelUI.text_width(right, 9), 0),
			right, PixelUI.C_TEXT_DIM, 9
		)

	_draw_list_row(_rest_row(), "やすむ", "%dG" % rest_price())
	_draw_list_row(_leave_row(), "たちさる", "")


func _draw_list_row(row: int, label: String, right: String) -> void:
	var base := LIST_RECT.position + Vector2(20, 20 + row * ROW_HEIGHT)
	if _index == row:
		draw_texture(CURSOR_TEX, (base + Vector2(-13, -8)).floor())
	var tint := PixelUI.C_ACTIVE if _index == row else PixelUI.C_TEXT_DIM
	PixelUI.draw_text(self, base, label, tint, 11)
	if right != "":
		PixelUI.draw_text(
			self, base + Vector2(LIST_RECT.size.x - 34 - PixelUI.text_width(right, 9), 0),
			right, PixelUI.C_TEXT_DIM, 9
		)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	var origin := DETAIL_RECT.position

	# パーティの体力。何を買うべきかは、この数字を見て決まる。
	PixelUI.draw_text(self, origin + Vector2(14, 20), "みんなの ようす", PixelUI.C_TEXT_DIM, 9)
	var party := GameState.active_party()
	for i in party.size():
		var m := party[i]
		var row := origin + Vector2(14, 36 + i * 20)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		PixelUI.draw_text(self, row, m.name, name_color, 11)
		PixelUI.draw_text(
			self, row + Vector2(48, 0), "%d/%d" % [m.hp, m.max_hp()], PixelUI.C_TEXT_DIM, 9
		)
		if m.max_mp() > 0:
			PixelUI.draw_text(
				self, row + Vector2(110, 0), "M%d/%d" % [m.mp, m.max_mp()], PixelUI.C_MP, 9
			)
		PixelUI.draw_gauge(self, Rect2(row.x, row.y + 4, 160, 4), ratio, PixelUI.hp_color(ratio))


func _draw_menu() -> void:
	PixelUI.draw_window(self, MENU_RECT, WINDOW_TEX)
	var origin := MENU_RECT.position

	var desc := ""
	if _index < _ids.size():
		desc = String(Database.item(String(_ids[_index])).get("desc", ""))
	elif _index == _rest_row():
		desc = "%d ゴールドで 傷も魔力も すっかり戻す。" % rest_price()
	else:
		desc = "ダンジョンへ もどる。"
	PixelUI.draw_text(self, origin + Vector2(16, 20), desc, PixelUI.C_TEXT, 11)

	PixelUI.draw_text(self, origin + Vector2(16, 40), "もちもの", PixelUI.C_TEXT_DIM, 9)
	var owned := GameState.inventory_ids()
	if owned.is_empty():
		PixelUI.draw_text(self, origin + Vector2(16, 58), "なし", PixelUI.C_TEXT_DIM, 10)
		return
	for i in owned.size():
		var item_id := String(owned[i])
		var at := origin + Vector2(16 + i * 88, 58)
		PixelUI.draw_text(
			self, at,
			"%s%d" % [Database.item(item_id).get("name", item_id), GameState.item_count(item_id)],
			PixelUI.C_TEXT, 10
		)


func _draw_notice() -> void:
	if _notice == "":
		return
	var width := PixelUI.text_width(_notice, 12) + 28.0
	var box := Rect2((PixelUI.SCREEN.x - width) * 0.5, 96, width, 28)
	PixelUI.draw_window(self, box, WINDOW_TEX)
	PixelUI.draw_text(self, box.position + Vector2(14, 18), _notice, PixelUI.C_TEXT, 12)
