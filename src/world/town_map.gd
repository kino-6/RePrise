class_name TownMap
extends FieldMap

## 町の中。世界の上の「町」を踏むとここへ入る。
##
## 町を品書きだけにしていたときは、町が場所として存在していなかった。
## 中を歩けるようにすると、宿・店・人が別々の場所になり、
## 「誰に話すか」「何を先にするか」がそのまま行動になる。
##
## 地図の型は FieldMap なので、`ExploreView` がそのまま歩ける。
## タイル番号は洞（DungeonMap）と同じ並びを使う ―― 町のために新しい絵を
## 起こさずに済むし、`assets/tiles/<生物相>.png` がそのまま効く。

enum {
	T_GROUND = 0,
	T_GROUND_ALT = 1,
	T_WALL = 2,
	T_WALL_TOP = 3,
	T_EXIT = 4,     ## 出口（洞の階段と同じ絵）。踏むと世界へ戻る
	T_DOOR = 5,     ## 宿の扉
	T_SIGN = 6,     ## 宝箱の絵を看板として使う
	T_VOID = 7,
	T_SHOP = 8,
}

# 町専用シートの末尾。地図データの種類は増やさず、計画街路と広場の
# 位置情報から描画番号だけを選ぶ。4変種は座標だけで決まり、決定性を崩さない。
const ART_ROAD_FIRST := 9
const ART_PLAZA_FIRST := 13
const ART_VARIANTS := 4

## 町の人（位置 -> {"kind": ..., "line": String}）。
## 話しかける = 隣から押し当てる（洞の宝箱と同じ作法）。
var folk: Dictionary = {}

## 宿の位置。踏むと休める。
var inn_pos: Vector2i = Vector2i(-1, -1)
var shop_pos: Vector2i = Vector2i(-1, -1)
var exit_pos: Vector2i = Vector2i(-1, -1)

## 品書きの在庫。町ごとに世界が覚えるので、ここは受け皿だけ。
var shop_stock: Dictionary = {}

## 町の名。生成時に決める。
var town_name: String = ""

## 間取りより先に決めた町の設定と、その設定を読める形にした構造。
var profile: TownProfile = null
var plaza_pos: Vector2i = Vector2i(-1, -1)
var landmark_pos: Vector2i = Vector2i(-1, -1)
var main_street: Array[Vector2i] = []
var facility_paths: Array[Vector2i] = []
var plaza_tiles: Array[Vector2i] = []


func _init(w: int = 0, h: int = 0, _fill: int = 0) -> void:
	super(w, h, T_VOID)


## 人の居るマスは通れない（押し当てて話すため）。
func is_walkable(x: int, y: int) -> bool:
	if folk.has(Vector2i(x, y)):
		return false
	var t := get_tile(x, y)
	return t == T_GROUND or t == T_GROUND_ALT or t == T_EXIT or t == T_DOOR or t == T_SHOP


func is_void(x: int, y: int) -> bool:
	return get_tile(x, y) == T_VOID


## 洞と同じ描き分け。壁の下が地面なら手前の面、そうでなければ天面。
func render_tile(x: int, y: int) -> int:
	var t := get_tile(x, y)
	if t == T_GROUND_ALT:
		var at := Vector2i(x, y)
		if at in plaza_tiles:
			return ART_PLAZA_FIRST + posmod(x * 3 + y * 5, ART_VARIANTS)
		if at in main_street or at in facility_paths:
			return ART_ROAD_FIRST + posmod(x * 5 + y * 3, ART_VARIANTS)
	if t != T_WALL:
		return t
	var below := get_tile(x, y + 1)
	var open := below == T_GROUND or below == T_GROUND_ALT or below == T_EXIT \
		or below == T_DOOR or below == T_SHOP
	return T_WALL if open else T_WALL_TOP


func glyphs() -> Dictionary:
	return { T_GROUND: ".", T_GROUND_ALT: ",", T_WALL: "#", T_WALL_TOP: "#",
		T_EXIT: ">", T_DOOR: "+", T_SIGN: "$", T_VOID: " ", T_SHOP: "S" }
