class_name WorldGenerator
extends RefCounted

## 1 ラン ぶんの世界を作る。
##
## 乱数は渡された DetRng からしか引かない。時刻にもエンジンの乱数にも触らないので、
## 同じシードからは必ず同じ世界が出る（洞の生成と同じ約束）。
##
## 作る順番には理由がある。
##
##   1. 陸を作る … 通れる場所を先に決めないと、あとの全部が置けない
##   2. 門と城を決める … 陸路でいちばん離れた 2 点。これが難度の軸になる
##   3. 危険度を配る … 門からの陸路距離を 1..10 に伸ばす
##   4. 地形を塗る … 危険度の帯で草原→森→丘→山。**見た目が難度の予告になる**
##   5. 拠点地を置く … 町は本筋の上、洞は本筋から外して「寄り道」にする
##
## 4 と 5 が逆だと、町が山の中に建つ。

const MAP_W := 64
const MAP_H := 48

## 陸の作り方。中心から乱歩で削り出す（島の形になる）。
const LAND_WALKERS := 6
const LAND_STEPS := 420
const LAND_BRUSH := 2

## 拠点地の数。**洞は行かなくても終点に着ける**位置に置く。
## 寄るか急ぐかが判断になるのは、寄らない選択が成立するときだけ。
const TOWN_COUNT := 4
const CAVE_COUNT := 5

## 町と町、洞と洞が近すぎると寄り道の意味が薄れる。
const SITE_SPACING := 7


static func generate(rng: DetRng) -> WorldMap:
	var map := WorldMap.new(MAP_W, MAP_H)
	map.biome = "world"
	_carve_land(map, rng)
	_place_gate_and_castle(map, rng)
	_spread_danger(map)
	_paint_terrain(map, rng)
	_place_sites(map, rng)
	return map


# --------------------------------------------------------------------------
# 1. 陸
# --------------------------------------------------------------------------


## 乱歩で陸を削り出す。部屋と通路（洞のやり方）だと四角い大陸になってしまう。
static func _carve_land(map: WorldMap, rng: DetRng) -> void:
	var center := Vector2i(MAP_W / 2, MAP_H / 2)
	for w in LAND_WALKERS:
		var at := center
		# 歩き手ごとに違う方角へ散らす。全部同じ点から始めると団子になる。
		for _spread in w * 3:
			at += FieldMap.NEIGHBORS[rng.range_i(0, 3)]
		for _step in LAND_STEPS:
			_brush(map, at)
			at += FieldMap.NEIGHBORS[rng.range_i(0, 3)]
			# 縁からは折り返す。海に出た歩き手が戻ってこないと陸が痩せる。
			at.x = clampi(at.x, LAND_BRUSH + 2, MAP_W - LAND_BRUSH - 3)
			at.y = clampi(at.y, LAND_BRUSH + 2, MAP_H - LAND_BRUSH - 3)


static func _brush(map: WorldMap, at: Vector2i) -> void:
	for dy in range(-LAND_BRUSH, LAND_BRUSH + 1):
		for dx in range(-LAND_BRUSH, LAND_BRUSH + 1):
			# 角を落として丸くする。四角い筆だと海岸線が階段状になる。
			if absi(dx) + absi(dy) > LAND_BRUSH + 1:
				continue
			map.set_tile(at.x + dx, at.y + dy, WorldMap.T_PLAIN)


# --------------------------------------------------------------------------
# 2. 門と城
# --------------------------------------------------------------------------


## 陸路でいちばん離れた 2 点を門と城にする。
##
## 直線距離で選ぶと、海を挟んだ対岸が「遠い」ことになって、
## 実際には歩けない。**距離は必ず陸路で測る。**
static func _place_gate_and_castle(map: WorldMap, rng: DetRng) -> void:
	var land := _land_cells(map)
	if land.is_empty():
		# 万一の保険。陸が無いと詰むので中心を陸にする。
		map.set_tile(MAP_W / 2, MAP_H / 2, WorldMap.T_PLAIN)
		land = [Vector2i(MAP_W / 2, MAP_H / 2)]

	# 適当な陸から最遠点、そこからさらに最遠点（木の直径を採る手口）
	var seed_cell: Vector2i = land[rng.range_i(0, land.size() - 1)]
	var gate := _farthest_from(map, seed_cell)
	var castle := _farthest_from(map, gate)

	map.start_pos = gate
	map.castle_pos = castle
	map.set_tile(gate.x, gate.y, WorldMap.T_GATE)
	map.set_tile(castle.x, castle.y, WorldMap.T_CASTLE)
	map.sites[castle] = {"kind": "castle", "danger": WorldMap.MAX_DANGER, "index": 0}


static func _land_cells(map: WorldMap) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) == WorldMap.T_PLAIN:
				cells.append(Vector2i(x, y))
	return cells


static func _farthest_from(map: WorldMap, from: Vector2i) -> Vector2i:
	var dist := map.distance_field(from)
	var best := from
	var best_d := -1
	for y in map.height:
		for x in map.width:
			var d := dist[y * map.width + x]
			if d > best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


# --------------------------------------------------------------------------
# 3. 危険度
# --------------------------------------------------------------------------


## 門からの陸路距離を 1..10 に伸ばす。門が 1、城が 10。
##
## 「遠くへ行くほど危ない」を距離そのもので表す。DQ の作法であり、
## 今まで `floor_number` が担っていた難度の軸をここが引き継ぐ。
static func _spread_danger(map: WorldMap) -> void:
	var dist := map.distance_field(map.start_pos)
	var span := maxi(dist[map.castle_pos.y * map.width + map.castle_pos.x], 1)
	for y in map.height:
		for x in map.width:
			var d := dist[y * map.width + x]
			if d < 0:
				continue  # 届かない土地。ここには何も置かない
			var tier := 1 + (d * (WorldMap.MAX_DANGER - 1)) / span
			map.set_danger(x, y, mini(tier, WorldMap.MAX_DANGER))


# --------------------------------------------------------------------------
# 4. 地形
# --------------------------------------------------------------------------


## 危険度の帯で地形を塗る。**見た目が難度の予告になる**のが狙い。
##
## 森と丘が「歩ける」まま出やすさだけ変えるのに対して、山は通れない。
## 通れない地形を深いところに置くと、道が細くなって終盤が険しく見える。
const TERRAIN_BY_DANGER := {
	1: [WorldMap.T_PLAIN, WorldMap.T_PLAIN, WorldMap.T_PLAIN, WorldMap.T_FOREST],
	2: [WorldMap.T_PLAIN, WorldMap.T_PLAIN, WorldMap.T_FOREST, WorldMap.T_FOREST],
	3: [WorldMap.T_PLAIN, WorldMap.T_FOREST, WorldMap.T_FOREST, WorldMap.T_HILL],
	4: [WorldMap.T_PLAIN, WorldMap.T_FOREST, WorldMap.T_HILL, WorldMap.T_HILL],
	5: [WorldMap.T_FOREST, WorldMap.T_HILL, WorldMap.T_HILL, WorldMap.T_MOUNTAIN],
	6: [WorldMap.T_FOREST, WorldMap.T_HILL, WorldMap.T_HILL, WorldMap.T_MOUNTAIN],
	7: [WorldMap.T_HILL, WorldMap.T_HILL, WorldMap.T_MOUNTAIN, WorldMap.T_PLAIN],
	8: [WorldMap.T_HILL, WorldMap.T_MOUNTAIN, WorldMap.T_MOUNTAIN, WorldMap.T_PLAIN],
	9: [WorldMap.T_HILL, WorldMap.T_MOUNTAIN, WorldMap.T_MOUNTAIN, WorldMap.T_PLAIN],
	10: [WorldMap.T_HILL, WorldMap.T_MOUNTAIN, WorldMap.T_MOUNTAIN, WorldMap.T_PLAIN],
}


static func _paint_terrain(map: WorldMap, rng: DetRng) -> void:
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) != WorldMap.T_PLAIN:
				continue  # 海と、既に置いた門・城には触らない
			var tier := map.danger_at(x, y)
			var palette: Array = TERRAIN_BY_DANGER.get(tier, [WorldMap.T_PLAIN])
			map.set_tile(x, y, int(palette[rng.range_i(0, palette.size() - 1)]))

	# 山で門と城が孤立していないか確かめ、閉じていたら道を通す。
	# **生成物は必ず到達可能でなければならない**（詰む世界を出さない）。
	_ensure_reachable(map)


## 城まで歩けることを保証する。届かないなら、届く場所から山を削って繋ぐ。
static func _ensure_reachable(map: WorldMap) -> void:
	for _attempt in 40:
		var dist := map.distance_field(map.start_pos)
		if dist[map.castle_pos.y * map.width + map.castle_pos.x] >= 0:
			return
		# 城のまわりで、いちばん門に近い到達済みマスへ向けて 1 マス削る
		var opened := false
		for radius in range(1, maxi(map.width, map.height)):
			var best := Vector2i(-1, -1)
			var best_d := -1
			for y in range(map.castle_pos.y - radius, map.castle_pos.y + radius + 1):
				for x in range(map.castle_pos.x - radius, map.castle_pos.x + radius + 1):
					if not map.in_bounds(x, y):
						continue
					var d := dist[y * map.width + x]
					if d < 0:
						continue
					if best_d < 0 or d < best_d:
						best_d = d
						best = Vector2i(x, y)
			if best.x < 0:
				continue
			# best から城へ向かって、通れない地形をならしていく
			var at := best
			while at != map.castle_pos:
				at += Vector2i(signi(map.castle_pos.x - at.x), 0) if at.x != map.castle_pos.x \
					else Vector2i(0, signi(map.castle_pos.y - at.y))
				if map.get_tile(at.x, at.y) in [WorldMap.T_SEA, WorldMap.T_MOUNTAIN]:
					map.set_tile(at.x, at.y, WorldMap.T_HILL)
			opened = true
			break
		if not opened:
			return


# --------------------------------------------------------------------------
# 5. 拠点地
# --------------------------------------------------------------------------


## 町と洞を置く。
##
## **町は本筋の上、洞は本筋から外す。** 洞が道の途中にあると
## 「寄らない」が選べなくなり、寄り道が寄り道でなくなる。
static func _place_sites(map: WorldMap, rng: DetRng) -> void:
	var to_castle := map.distance_field(map.castle_pos)
	var from_gate := map.distance_field(map.start_pos)
	var span := maxi(from_gate[map.castle_pos.y * map.width + map.castle_pos.x], 1)

	# 本筋 = 門から城への最短経路の近く。そこに沿って町を置く。
	var on_route: Array[Vector2i] = []
	var off_route: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if not map.is_walkable(x, y) or Vector2i(x, y) == map.start_pos:
				continue
			var a := from_gate[y * map.width + x]
			var b := to_castle[y * map.width + x]
			if a < 0 or b < 0:
				continue
			# 遠回り度。0 なら最短経路の上にいる。
			var detour := a + b - span
			if detour <= 2:
				on_route.append(Vector2i(x, y))
			elif detour >= 6:
				off_route.append(Vector2i(x, y))

	_scatter(map, rng, on_route, "town", TOWN_COUNT, from_gate, span)
	_scatter(map, rng, off_route, "cave", CAVE_COUNT, from_gate, span)


static func _scatter(
	map: WorldMap, rng: DetRng, pool: Array[Vector2i], kind: String, count: int,
	from_gate: PackedInt32Array, span: int
) -> void:
	if pool.is_empty():
		return
	var tile := WorldMap.T_TOWN if kind == "town" else WorldMap.T_CAVE
	var placed := 0
	# 門に近い順に並べ、等間隔に拾う。乱数だけで選ぶと片側に寄る。
	pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from_gate[a.y * map.width + a.x] < from_gate[b.y * map.width + b.x])

	for slot in count:
		# 帯の中から 1 つ選ぶ。帯を切っておけば、門の近くから城の手前まで散る。
		var lo := (pool.size() * slot) / count
		var hi := maxi((pool.size() * (slot + 1)) / count - 1, lo)
		for _try in 12:
			var at: Vector2i = pool[rng.range_i(lo, hi)]
			if at == map.castle_pos or map.sites.has(at):
				continue
			if _too_close(map, at):
				continue
			var d := from_gate[at.y * map.width + at.x]
			var tier := clampi(1 + (d * (WorldMap.MAX_DANGER - 1)) / maxi(span, 1), 1, WorldMap.MAX_DANGER)
			map.set_tile(at.x, at.y, tile)
			map.sites[at] = {"kind": kind, "danger": tier, "index": placed}
			placed += 1
			break


static func _too_close(map: WorldMap, at: Vector2i) -> bool:
	for pos in map.sites:
		var other: Vector2i = pos
		if absi(other.x - at.x) + absi(other.y - at.y) < SITE_SPACING:
			return true
	return false
