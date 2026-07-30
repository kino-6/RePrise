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
## 画面配置（512x320）
##   y   8.. 44  店の名と所持金
##   y  50..226  左: 品書き / 右: 選択中の品とパーティの状態
##   y 232..312  説明と持ち物

signal closed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const HEADER_RECT := Rect2(8, 8, 496, 36)
const LIST_RECT := Rect2(8, 50, 228, 176)
const DETAIL_RECT := Rect2(244, 50, 260, 176)
const MENU_RECT := Rect2(8, 232, 496, 80)

const ROW_HEIGHT := 24
const INPUT_LOCK := 0.15

## 休息の値段は階層に比例させる。深いほど「もう一度整える」判断が重くなる。
const REST_BASE_PRICE := 20

## 在庫の入れ物。**地図ではなく辞書を受け取る。**
##
## 町（世界の上）と洞の中の出店で、同じ品書きを使いたい。地図を渡す形だと
## 町には地図が無いので、店の側が場所を知っていることになってしまう。
## 在庫を持っているのは呼び出し側（町なら世界、洞ならその階）。
var _stock: Dictionary = {}
var _floor := 1
var _ids: Array = []
var _index := 0
var _notice := Notice.new()
var _input_lock := 0.0


func open(stock: Dictionary, floor_number: int) -> void:
	_stock = stock
	_floor = floor_number
	# 消耗品と装備を同じ品書きに並べる。店を 2 つに分けるほどの品数ではない。
	_ids = Database.item_ids_for_floor(floor_number)
	_ids.append_array(Database.gear_ids_for_floor(floor_number))
	# 在庫はこのフロアで一度だけ用意する。出入りしても戻らない。
	if _stock.is_empty():
		# 「商いの伝手」を買っているぶんだけ品が多く並ぶ。
		var extra := GameState.upgrade_value("shop_stock") + GameState.event_shop_bonus
		for id in _ids:
			var base := int(_entry(String(id)).get("stock", 1))
			# 装備は 1 点もの。伝手を買っても在庫は増やさない。
			_stock[id] = base if _is_gear(String(id)) else base + extra
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


## 品書きの行数。品物 + 「やすむ」 + 「たちさる」。
func _rest_row() -> int:
	return _ids.size()


func _leave_row() -> int:
	return _ids.size() + 1


func rest_price() -> int:
	return REST_BASE_PRICE * _floor


## 値段。「商いの目」を買っているぶん安くなる。
##
## **恒久強化は能力値に触れない**という前提を守りつつ、拠点の投資を
## 道中の買い物へ効かせる軸。強くはならないが、選べる品が増える。
func price_of(item_id: String) -> int:
	var base := int(_entry(item_id).get("price", 0))
	var cut := clampi(GameState.upgrade_value("price_cut"), 0, 60)
	return maxi(base * (100 - cut) / 100, 1)


func _stock_of(item_id: String) -> int:
	return int(_stock.get(item_id, 0))


## 装備か消耗品か。品書きは 1 本だが、買った先の置き場所が違う。
func _is_gear(id: String) -> bool:
	return not Database.gear(id).is_empty()


func _entry(id: String) -> Dictionary:
	return Database.gear(id) if _is_gear(id) else Database.item(id)


# --------------------------------------------------------------------------
# 入力
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	var rows := _leave_row() + 1
	if event.is_action_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sound.play("cursor")
		queue_redraw()
	elif event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_leave()
	elif event.is_action_pressed("confirm"):
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
	var price := price_of(item_id)
	if _stock_of(item_id) <= 0:
		Sound.play("cancel")
		_notify("それは 売り切れだ")
		return
	if not GameState.spend_gold(price):
		Sound.play("cancel")
		_notify("%sが たりない" % Terms.GOLD)
		return
	_stock[item_id] = _stock_of(item_id) - 1
	if _is_gear(item_id):
		GameState.add_gear(item_id)
	else:
		GameState.add_item(item_id)
	Sound.play("chest")
	_notify("%s を 買った" % _entry(item_id).get("name", item_id))


## 全回復。道具と違って手番を消費しないぶん高い。
func _rest() -> void:
	var price := rest_price()
	var party := GameState.active_party()
	var hurt := false
	for m in party:
		if m.hp < m.max_hp() or m.mp < m.max_mp() or m.poison_steps > 0:
			hurt = true
	if not hurt:
		Sound.play("cancel")
		_notify("休むほどでもない")
		return
	if not GameState.spend_gold(price):
		Sound.play("cancel")
		_notify("%sが たりない" % Terms.GOLD)
		return
	for m in party:
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		m.cure_poison()
	Sound.play("heal")
	_notify("すっかり 元気になった")


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------


func _draw() -> void:
	PixelUI.ui_frame()
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x14, 0x0E, 0x10), true)
	_draw_header()
	_draw_list()
	_draw_detail()
	_draw_menu()
	_draw_notice()


func _draw_header() -> void:
	PixelUI.draw_window(self, HEADER_RECT, WINDOW_TEX)
	var inner := PixelUI.content(HEADER_RECT)
	PixelUI.draw_text(self, inner.position + Vector2(6, 0), Terms.SHOP, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	PixelUI.draw_text_right(
		self, Vector2(inner.end.x - 4, inner.position.y + 3),
		"%d %s" % [GameState.gold, Terms.GOLD], PixelUI.C_TEXT
	)


## 品書きに入る行数。装備を並べたぶん品数が増えたので、ここを超えたら送る。
const VISIBLE_ROWS := 6


## カーソルを中央付近に保ったまま送る窓の先頭行。
func _list_top() -> int:
	return MenuList.top_of(_index, _leave_row() + 1, VISIBLE_ROWS)


func _draw_list() -> void:
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	var inner := PixelUI.content(LIST_RECT)
	var top := _list_top()
	var total := _leave_row() + 1

	for row in range(top, mini(top + VISIBLE_ROWS, total)):
		var base := inner.position + Vector2(16, 6 + (row - top) * ROW_HEIGHT)
		if _index == row:
			MenuList.draw_cursor(self, CURSOR_TEX, base)

		if row == _rest_row():
			_draw_row(base, inner, row, "やすむ", "%dG" % rest_price(), false)
			continue
		if row == _leave_row():
			_draw_row(base, inner, row, "たちさる", "", false)
			continue

		var item_id := String(_ids[row])
		var it := _entry(item_id)
		var sold_out := _stock_of(item_id) <= 0
		var right := "うりきれ" if sold_out else "%dG x%d" % [
			# **並ぶ数字も割引後にする。** 買うときだけ安いと、表示が嘘になる。
			price_of(item_id), _stock_of(item_id)
		]
		_draw_row(base, inner, row, String(it.get("name", item_id)), right, sold_out)

	MenuList.draw_position(self, inner, _index, total, VISIBLE_ROWS)


func _draw_row(base: Vector2, inner: Rect2, row: int, label: String, right: String, sold_out: bool) -> void:
	var tint := PixelUI.C_TEXT if _index == row else PixelUI.C_TEXT_DIM
	if row >= _rest_row():
		tint = PixelUI.C_ACTIVE if _index == row else PixelUI.C_TEXT_DIM
	if sold_out:
		tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.5)
	PixelUI.draw_text(self, base, label, tint)
	if right != "":
		PixelUI.draw_text_right(
			self, Vector2(inner.end.x - 2, base.y + 2), right, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(DETAIL_RECT).position

	# パーティの体力。何を買うべきかは、この数字を見て決まる。
	PixelUI.draw_text(self, origin + Vector2(6, 0), "みんなの ようす", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var party := GameState.active_party()
	for i in party.size():
		var m := party[i]
		var row := origin + Vector2(6, 22 + i * 34)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		PixelUI.draw_text(self, row, m.name, name_color)
		PixelUI.draw_text(
			self, row + Vector2(66, 2), "%d/%d" % [m.hp, m.max_hp()],
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		if m.max_mp() > 0:
			PixelUI.draw_text(
				self, row + Vector2(140, 2), "M%d/%d" % [m.mp, m.max_mp()],
				PixelUI.C_MP, PixelUI.SIZE_SUB
			)
		PixelUI.draw_gauge(self, Rect2(row.x, row.y + 19, 224, 5), ratio, PixelUI.hp_color(ratio))


func _draw_menu() -> void:
	PixelUI.draw_window(self, MENU_RECT, WINDOW_TEX)
	var origin := PixelUI.content(MENU_RECT).position

	var desc := ""
	if _index < _ids.size():
		var id := String(_ids[_index])
		desc = String(_entry(id).get("desc", ""))
		if _is_gear(id):
			# 装備は説明が無いものも多いので、効き目の数字を出す
			var stats := GearText.summary(Database.gear(id))
			desc = stats if desc == "" else "%s　%s" % [desc, stats]
	elif _index == _rest_row():
		desc = "%d %sで 傷も魔力も すっかり戻す。" % [rest_price(), Terms.GOLD]
	else:
		desc = "ダンジョンへ もどる。"
	# 説明は 1 行で収める。装備は「説明＋能力値」で長くなるので切る
	# （切らずに置いたら窓から 3px 出た）。
	PixelUI.draw_text(
		self, origin + Vector2(8, 0),
		PixelUI.clip(desc, 464.0, PixelUI.SIZE_TEXT), PixelUI.C_TEXT
	)

	PixelUI.draw_text(self, origin + Vector2(8, 26), "もちもの", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var owned := GameState.inventory_ids()
	if owned.is_empty():
		PixelUI.draw_text(self, origin + Vector2(8, 46), "なし", PixelUI.C_TEXT_DIM)
		return
	for i in owned.size():
		var item_id := String(owned[i])
		var at := origin + Vector2(8 + i * 118, 46)
		PixelUI.draw_text(
			self, at,
			"%s%d" % [Database.item(item_id).get("name", item_id), GameState.item_count(item_id)],
			PixelUI.C_TEXT
		)


func _draw_notice() -> void:
	_notice.draw(self, WINDOW_TEX, 130.0)
