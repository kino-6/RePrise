class_name WorldMap
extends FieldMap

## 1 ラン ぶんの世界。全滅しても踏破しても、この世界には二度と来ない。
##
## 洞（DungeonMap）との違いは 2 つだけ。
##
##   1. **危険度の場を持つ。** 出発からの陸路距離で 1..10 が決まる。
##      今まで「地下 N 階」が担っていた難度の軸がこれに置き換わる。
##   2. **拠点地を持つ。** 町・洞・城。踏むと中へ入る。
##
## タイル番号は assets/tiles/world.png の並び順に合わせる。
## 素材がまだ無いあいだは既存の地形タイルへ落ちる（ExploreView.tileset_for）。

enum {
	T_SEA = 0,
	T_PLAIN = 1,
	T_FOREST = 2,
	T_HILL = 3,
	T_MOUNTAIN = 4,
	T_GATE = 5,     ## 砦から着く場所。ここが危険度 1 の起点
	T_TOWN = 6,
	T_CAVE = 7,
	T_CASTLE = 8,   ## 終点。踏むと主戦
}

## 危険度の上限。今の 10 階ぶんの難度曲線をそのまま使うための数字。
## data/*.json の floor_min / floor_max もこの目盛りで書かれている。
const MAX_DANGER := 10

## 終点の位置。
var castle_pos: Vector2i = Vector2i(-1, -1)

## 拠点地（位置 -> {"kind": "town"/"cave"/"castle", "danger": int, "index": int}）。
var sites: Dictionary = {}

## マスごとの危険度 1..MAX_DANGER。海と届かない土地は 0。
var danger: PackedByteArray = PackedByteArray()

## 訪れた拠点地。町の在庫や洞の踏破を覚えておくのに使う。
var visited: Dictionary = {}


func _init(w: int = 0, h: int = 0, _fill: int = 0) -> void:
	super(w, h, T_SEA)
	danger = PackedByteArray()
	danger.resize(w * h)
	danger.fill(0)


## 海は渡れない。山も越えられない（世界に形を与えるのは通れない場所のほう）。
func is_walkable(x: int, y: int) -> bool:
	var t := get_tile(x, y)
	return t != T_SEA and t != T_MOUNTAIN


func is_void(x: int, y: int) -> bool:
	return false if in_bounds(x, y) else true


func danger_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 1
	return maxi(int(danger[y * width + x]), 1)


func set_danger(x: int, y: int, value: int) -> void:
	if in_bounds(x, y):
		danger[y * width + x] = clampi(value, 0, MAX_DANGER)


func site_at(pos: Vector2i) -> Dictionary:
	return sites.get(pos, {})


## 地形ごとの遭遇しやすさ（歩数に足す重み）。
##
## 草原は歩きやすく、森と丘は出やすい。全部同じにすると、地形が
## ただの模様になってしまう。**通れる/通れない以外の意味を持たせる。**
func encounter_weight(x: int, y: int) -> int:
	match get_tile(x, y):
		T_PLAIN:
			return 1
		T_FOREST:
			return 3
		T_HILL:
			return 2
		_:
			return 0  # 拠点地の上は安全


func glyphs() -> Dictionary:
	return { T_SEA: "~", T_PLAIN: ".", T_FOREST: "f", T_HILL: "n", T_MOUNTAIN: "^",
		T_GATE: "G", T_TOWN: "T", T_CAVE: "o", T_CASTLE: "C" }
