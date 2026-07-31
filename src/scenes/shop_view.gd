class_name ShopView
extends Node2D

## 道中の出店。消耗品と装備を買う場所。
##
## ゴールドをラン内限定の資源に決めたので、拠点ではなくここが買い物の場になる。
## 「今飲むか、あとに取っておくか」をラン中に判断させたいのであって、
## 拠点で計画を立てさせたいわけではない。だから店は道中にしか無い。
## 全回復は町の宿だけが担う。出店で休めると、町へ戻る判断も宿の役割も消える。
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

## 品書きは横で分類を切り替える。装備を取得順の一列へ混ぜると、
## 武器・防具・装飾品のどれを見ているか分からない。
const CATEGORY_KEYS: Array[String] = ["item", "weapon", "armor", "accessory"]

## 在庫の入れ物。**地図ではなく辞書を受け取る。**
##
## 町（世界の上）と洞の中の出店で、同じ品書きを使いたい。地図を渡す形だと
## 町には地図が無いので、店の側が場所を知っていることになってしまう。
## 在庫を持っているのは呼び出し側（町なら世界、洞ならその階）。
var _stock: Dictionary = {}
var _catalog: Dictionary = {}
var _ids: Array = []
var _category_index := 0
var _index := 0
var _notice := Notice.new()
var _input_lock := 0.0


func open(stock: Dictionary, floor_number: int) -> void:
	_stock = stock
	_catalog = _catalog_for_floor(floor_number)
	# 在庫はこのフロアで一度だけ用意する。出入りしても戻らない。
	if _stock.is_empty():
		# 「商いの伝手」を買っているぶんだけ品が多く並ぶ。
		var extra := GameState.upgrade_value("shop_stock") + GameState.event_shop_bonus
		for category in CATEGORY_KEYS:
			for id in _catalog.get(category, []):
				var base := int(_entry(String(id)).get("stock", 1))
				# 装備は 1 点もの。伝手を買っても在庫は増やさない。
				_stock[id] = base if _is_gear(String(id)) else base + extra
	_category_index = 0
	_activate_category()
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


func _leave_row() -> int:
	return _ids.size()


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


## 店頭分類。テストからも使い、装備データの slot と表示がずれないようにする。
static func category_of(id: String) -> String:
	var gear := Database.gear(id)
	return "item" if gear.is_empty() else String(gear.get("slot", ""))


static func category_keys() -> Array[String]:
	return CATEGORY_KEYS.duplicate()


static func _catalog_for_floor(floor_number: int) -> Dictionary:
	var result := {
		"item": Database.item_ids_for_floor(floor_number),
		"weapon": [],
		"armor": [],
		"accessory": [],
	}
	for id in Database.gear_ids_for_shop(floor_number):
		var category := category_of(String(id))
		if result.has(category):
			result[category].append(id)
	return result


func _activate_category() -> void:
	var key := CATEGORY_KEYS[_category_index]
	_ids = Array(_catalog.get(key, [])).duplicate()
	_index = 0
	_notice.clear()


func _move_category(step: int) -> void:
	_category_index = posmod(_category_index + step, CATEGORY_KEYS.size())
	_activate_category()
	Sound.play("cursor")
	queue_redraw()


func _category_label() -> String:
	match CATEGORY_KEYS[_category_index]:
		"weapon":
			return Terms.SHOP_WEAPONS
		"armor":
			return Terms.SHOP_ARMOR
		"accessory":
			return Terms.SHOP_ACCESSORIES
		_:
			return Terms.SHOP_ITEMS


## 開発用の実プレイ計測。表示名ではなく安定した分類キーを返す。
func current_category() -> String:
	return CATEGORY_KEYS[_category_index]


## 撮影用。装備タブの長い品名・能力表示まで実画面で検査する。
func debug_set_category(category: String) -> void:
	var found := CATEGORY_KEYS.find(category)
	if found < 0:
		return
	_category_index = found
	_activate_category()
	queue_redraw()


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
	elif event.is_action_pressed("ui_left"):
		_move_category(-1)
	elif event.is_action_pressed("ui_right"):
		_move_category(1)
	elif event.is_action_pressed("cancel"):
		Sound.play("cancel")
		_leave()
	elif event.is_action_pressed("confirm"):
		_decide()


func _decide() -> void:
	if _index == _leave_row():
		Sound.play("confirm")
		_leave()
	else:
		_buy(String(_ids[_index]))


func _leave() -> void:
	close()
	closed.emit()


func _buy(item_id: String) -> void:
	var price := price_of(item_id)
	if _stock_of(item_id) <= 0:
		Sound.play("cancel")
		_notify(Terms.SOLD_OUT)
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
	_notify(Terms.BOUGHT % _entry(item_id).get("name", item_id))


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
	# 4 分類を常に並べ、いまいるタブだけ山括弧で示す。
	# 選択中の分類名だけでは、左右で切り替えられること自体が伝わらない。
	var tabs: Array[String] = []
	for i in CATEGORY_KEYS.size():
		var label := _label_for(CATEGORY_KEYS[i])
		tabs.append("＜%s＞" % label if i == _category_index else label)
	UiPanel.inside(self, PixelUI.content(HEADER_RECT)).row(
		"　".join(tabs),
		"%d %s" % [GameState.gold, Terms.GOLD],
		PixelUI.C_ACTIVE, PixelUI.C_TEXT, PixelUI.SIZE_HEAD
	)


func _label_for(category: String) -> String:
	match category:
		"weapon":
			return Terms.SHOP_WEAPONS
		"armor":
			return Terms.SHOP_ARMOR
		"accessory":
			return Terms.SHOP_ACCESSORIES
		_:
			return Terms.SHOP_ITEMS


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

		if row == _leave_row():
			_draw_row(base, inner, row, Terms.SHOP_LEAVE, "", false)
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
	if row == _leave_row():
		tint = PixelUI.C_ACTIVE if _index == row else PixelUI.C_TEXT_DIM
	if sold_out:
		tint = PixelUI.C_SHADOW.lerp(PixelUI.C_TEXT_DIM, 0.5)
	# 品名と値段を 1 行に。**値段は消えては困る**ので、詰まるのは品名のほう。
	UiPanel.inside(self, Rect2(
		base, Vector2(inner.end.x - 2.0 - base.x, PixelUI.LINE)
	)).row(label, right, tint, PixelUI.C_TEXT_DIM)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(DETAIL_RECT).position
	if _ids.is_empty():
		UiPanel.inside(self, Rect2(
			origin + Vector2(6, 0),
			Vector2(PixelUI.content(DETAIL_RECT).size.x - 12.0, PixelUI.LINE)
		)).line(Terms.SHOP_CATEGORY_EMPTY, PixelUI.C_TEXT_DIM)
		return
	if _index < _ids.size() and _is_gear(String(_ids[_index])):
		_draw_gear_fit(origin, String(_ids[_index]))
		return

	# パーティの体力。何を買うべきかは、この数字を見て決まる。
	UiPanel.inside(self, Rect2(
		origin + Vector2(6, 0),
		Vector2(PixelUI.content(DETAIL_RECT).size.x - 12.0, PixelUI.LINE)
	)).line("みんなの ようす", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var party := GameState.active_party()
	for i in party.size():
		var m := party[i]
		var row := origin + Vector2(6, 22 + i * 34)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		# 名前・HP・MP を 3 列に。列ごとに幅を持つので、名前が長くても数に食い込まない。
		var line := UiPanel.inside(self, Rect2(
			row, Vector2(PixelUI.content(DETAIL_RECT).end.x - 6.0 - row.x, PixelUI.LINE)))
		var cols := line.columns(3, 4.0)
		cols[0].line(m.name, name_color)
		cols[1].line("%d/%d" % [m.hp, m.max_hp()], PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		if m.max_mp() > 0:
			cols[2].line("M%d/%d" % [m.mp, m.max_mp()], PixelUI.C_MP, PixelUI.SIZE_SUB)
		PixelUI.draw_gauge(self, Rect2(row.x, row.y + 19, 224, 5), ratio, PixelUI.hp_color(ratio))


## 装備を買う前に、いまのパーティで誰が着けられるかを見せる。
## 買った後の GearOfferView で初めて不適合と分かるのでは遅い。
func _draw_gear_fit(origin: Vector2, gear_id: String) -> void:
	UiPanel.inside(self, Rect2(
		origin + Vector2(6, 0),
		Vector2(PixelUI.content(DETAIL_RECT).size.x - 12.0, PixelUI.LINE)
	)).line(Terms.GEAR_FIT, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
	var party := GameState.active_party()
	for i in party.size():
		var member: PartyMember = party[i]
		var can_wear := member.can_equip(gear_id)
		var row := origin + Vector2(6, 24 + i * 34)
		UiPanel.inside(self, Rect2(
			row, Vector2(PixelUI.content(DETAIL_RECT).end.x - 6.0 - row.x, PixelUI.LINE)
		)).row(
			member.name,
			Terms.CAN_EQUIP if can_wear else Terms.CANNOT_EQUIP,
			PixelUI.C_TEXT if can_wear else PixelUI.C_SHADOW,
			PixelUI.C_ACTIVE if can_wear else PixelUI.C_TEXT_DIM,
			PixelUI.SIZE_SUB
		)


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
	else:
		desc = Terms.SHOP_LEAVE_DESC
	# 説明は 1 行で収める。装備は「説明＋能力値」で長くなる。
	# **幅は窓の内側から取る**（464 と手で書くと、窓を変えた瞬間に古くなる）。
	_menu_line(origin, 0).line(desc, PixelUI.C_TEXT)

	_menu_line(origin, 26).row(
		Terms.SHOP_OWNED,
		Terms.SHOP_CATEGORY_HINT,
		PixelUI.C_TEXT_DIM,
		PixelUI.C_ACTIVE,
		PixelUI.SIZE_SUB
	)
	var owned := GameState.inventory_ids()
	var total_items := 0
	for item_id in owned:
		total_items += GameState.item_count(String(item_id))
	var gear_counts := {"weapon": 0, "armor": 0, "accessory": 0}
	for gear_id in GameState.gear_stock:
		var category := category_of(String(gear_id))
		if gear_counts.has(category):
			gear_counts[category] += 1
	var stock_summary := Terms.SHOP_STOCK_SUMMARY % [
		total_items,
		int(gear_counts["weapon"]),
		int(gear_counts["armor"]),
		int(gear_counts["accessory"]),
	]
	var selected_count := ""
	if _index < _ids.size():
		var selected_id := String(_ids[_index])
		selected_count = Terms.SHOP_OWNED_COUNT % (
			GameState.gear_stock.count(selected_id)
			if _is_gear(selected_id)
			else GameState.item_count(selected_id)
		)
	_menu_line(origin, 46).row(
		stock_summary, selected_count,
		PixelUI.C_TEXT, PixelUI.C_ACTIVE, PixelUI.SIZE_SUB
	)


## 下の窓の 1 行。**幅は窓の内側から取る。**
func _menu_line(origin: Vector2, dy: float) -> UiPanel:
	var inner := PixelUI.content(MENU_RECT)
	return UiPanel.inside(self, Rect2(
		origin + Vector2(8, dy), Vector2(inner.end.x - origin.x - 16.0, PixelUI.LINE)))


func _draw_notice() -> void:
	_notice.draw(self, WINDOW_TEX, 130.0)
