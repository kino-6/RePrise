class_name DungeonMap
extends FieldMap

## 洞（ダンジョン）の 1 階ぶん。
##
## 格子・通行判定・経路探索は FieldMap 側にある。ここが持つのは
## 「洞にしか無いもの」だけ ―― 部屋、階段、宝箱、出店、最終階かどうか。

# tiles/dungeon.png の並び順と一致させること。
enum {
	T_FLOOR = 0,
	T_FLOOR_CRACKED = 1,
	T_WALL = 2,
	T_WALL_TOP = 3,
	T_STAIRS = 4,
	T_DOOR = 5,
	T_CHEST = 6,
	T_VOID = 7,
	T_SHOP = 8,
}

var rooms: Array[Rect2i] = []
## この階の出口。最終階では下り階段ではなく主の間の扉になる。
var stairs_pos: Vector2i = Vector2i.ZERO
var chests: Array[Vector2i] = []
## 出店の位置（無い階もある）。
var shop_pos: Vector2i = Vector2i(-1, -1)
## 出店の残り在庫（item_id -> 個数）。フロアごとに持つので、
## 階を降りれば品が戻り、同じ階で買い占めることはできない。
var shop_stock: Dictionary = {}

## 最終階かどうか。出口の意味が「次の階」から「ボス戦」に変わる。
var is_final: bool = false


func _init(w: int = 0, h: int = 0, _fill: int = 0) -> void:
	super(w, h, T_VOID)


## 出店は通れる。通れない置き方にすると、通路に建った瞬間にその階が詰む。
func is_walkable(x: int, y: int) -> bool:
	var t := get_tile(x, y)
	return t == T_FLOOR or t == T_FLOOR_CRACKED or t == T_STAIRS or t == T_DOOR or t == T_SHOP


func is_void(x: int, y: int) -> bool:
	return get_tile(x, y) == T_VOID


## 描画に使うタイル番号。
##
## 壁は「下が床なら手前の面、そうでなければ天面」に描き分ける。この 1 行だけで
## 見下ろし画面に厚みが出る。SFC 期のダンジョンが立体的に見えたのはこの処理。
func render_tile(x: int, y: int) -> int:
	var t := get_tile(x, y)
	if t != T_WALL:
		return t
	var below := get_tile(x, y + 1)
	var below_open := (
		below == T_FLOOR or below == T_FLOOR_CRACKED or below == T_STAIRS or below == T_SHOP
	)
	return T_WALL if below_open else T_WALL_TOP


func glyphs() -> Dictionary:
	return { T_FLOOR: ".", T_FLOOR_CRACKED: ",", T_WALL: "#", T_WALL_TOP: "#",
		T_STAIRS: ">", T_DOOR: "+", T_CHEST: "$", T_VOID: " ", T_SHOP: "S" }
