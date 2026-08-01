class_name DungeonGenerator
extends RefCounted

## 部屋と通路によるフロア生成。
##
## 乱数は渡された DetRng からしか引かない。時刻にもエンジンの乱数にも触らないので、
## 同じシードと同じ階層からは必ず同じフロアが出る。

## 階層ごとの地形。深いほど景色が変わる（進んでいる感じを絵で出す）。
## 素材が無い場所は既定に落ちるので、ここに書いても壊れない。
const BIOME_BY_FLOOR := {7: "snowfield", 8: "snowfield", 9: "snowfield", 10: "snowfield"}


static func biome_for(floor_number: int) -> String:
	return String(BIOME_BY_FLOOR.get(floor_number, "dungeon"))


const MAP_W := 40
const MAP_H := 32

const ROOM_ATTEMPTS := 60
const ROOM_MIN := Vector2i(5, 4)
const ROOM_MAX := Vector2i(10, 7)
const ROOM_LIMIT := 8


## final_floor を立てると、出口が下り階段ではなく主の間の扉になる。
## 地形そのものは同じ手順で作る（最終階だけ別生成にすると、そこだけ
## 到達性テストの外側に出てしまうため）。
static func generate(rng: DetRng, floor_number: int, final_floor: bool = false) -> DungeonMap:
	var map := DungeonMap.new(MAP_W, MAP_H)
	map.biome = biome_for(floor_number)
	map.is_final = final_floor
	_carve_rooms(map, rng)
	if map.rooms.is_empty():
		# 万一 1 部屋も置けなかった場合の保険。空マップを返すと詰むので必ず 1 部屋作る。
		var fallback := Rect2i(2, 2, 8, 6)
		map.rooms.append(fallback)
		_fill_room(map, fallback)
	_connect_rooms(map, rng)
	_wrap_with_walls(map)
	_place_features(map, rng, floor_number)
	return map


static func _carve_rooms(map: DungeonMap, rng: DetRng) -> void:
	for _attempt in ROOM_ATTEMPTS:
		if map.rooms.size() >= ROOM_LIMIT:
			break
		var w := rng.range_i(ROOM_MIN.x, ROOM_MAX.x)
		var h := rng.range_i(ROOM_MIN.y, ROOM_MAX.y)
		var x := rng.range_i(2, MAP_W - w - 3)
		var y := rng.range_i(2, MAP_H - h - 3)
		var room := Rect2i(x, y, w, h)
		# 隣室と 1 マス以上あけて壁を残す
		var padded := room.grow(2)
		var overlaps := false
		for other in map.rooms:
			if padded.intersects(other):
				overlaps = true
				break
		if overlaps:
			continue
		map.rooms.append(room)
		_fill_room(map, room)


static func _fill_room(map: DungeonMap, room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			map.set_tile(x, y, DungeonMap.T_FLOOR)


## 生成順に L 字通路でつなぐ。全部屋が確実に到達可能になる。
static func _connect_rooms(map: DungeonMap, rng: DetRng) -> void:
	for i in range(1, map.rooms.size()):
		var a := _center(map.rooms[i - 1])
		var b := _center(map.rooms[i])
		# 横→縦か縦→横かをシードで決める（曲がり方に変化を出す）
		if rng.chance(50):
			_carve_h(map, a.x, b.x, a.y)
			_carve_v(map, a.y, b.y, b.x)
		else:
			_carve_v(map, a.y, b.y, a.x)
			_carve_h(map, a.x, b.x, b.y)


static func _center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


static func _carve_h(map: DungeonMap, x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		if map.get_tile(x, y) == DungeonMap.T_VOID:
			map.set_tile(x, y, DungeonMap.T_FLOOR)


static func _carve_v(map: DungeonMap, y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		if map.get_tile(x, y) == DungeonMap.T_VOID:
			map.set_tile(x, y, DungeonMap.T_FLOOR)


## 床に接する虚空を壁に変える。描画時に手前面と天面へ描き分けられる。
static func _wrap_with_walls(map: DungeonMap) -> void:
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) != DungeonMap.T_VOID:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if map.get_tile(x + dx, y + dy) == DungeonMap.T_FLOOR:
						map.set_tile(x, y, DungeonMap.T_WALL)
						break


static func _place_features(map: DungeonMap, rng: DetRng, floor_number: int) -> void:
	# 開始位置は従来のまま保ち、その隣に上り階段を置く。開始位置を動かすと全洞の
	# 経路・宝箱・遭遇列が変わり、戻る機能だけで既存バランスまで動いてしまう。
	map.start_pos = _center(map.rooms[0])
	map.upstairs_pos = _visible_feature_near(map, map.start_pos)
	map.set_tile(map.upstairs_pos.x, map.upstairs_pos.y, DungeonMap.T_UP_STAIRS)

	# 階段は開始地点から最も遠い部屋に置く。フロアを横断させるため。
	var farthest := map.rooms[0]
	var best_distance := -1
	for room in map.rooms:
		var d: int = absi(_center(room).x - map.upstairs_pos.x) + absi(_center(room).y - map.upstairs_pos.y)
		if d > best_distance:
			best_distance = d
			farthest = room
	map.stairs_pos = _center(farthest)
	# 生成失敗時の1部屋構成でも、上りと下りを同じマスに重ねない。
	if map.stairs_pos == map.start_pos or map.stairs_pos == map.upstairs_pos:
		map.stairs_pos = map.rooms[0].end - Vector2i(2, 2)
	map.set_tile(
		map.stairs_pos.x, map.stairs_pos.y,
		DungeonMap.T_DOOR if map.is_final else DungeonMap.T_STAIRS
	)
	map.down_arrival_pos = _arrival_near(map, map.stairs_pos)

	# ひび割れ床（見た目の変化のみ）
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) == DungeonMap.T_FLOOR and rng.chance(6):
				map.set_tile(x, y, DungeonMap.T_FLOOR_CRACKED)

	# 宝箱。深いほど増える。
	var chest_count := clampi(1 + floor_number / 2, 1, 4)
	var candidates := map.rooms.duplicate()
	rng.shuffle(candidates)
	for room in candidates:
		if map.chests.size() >= chest_count:
			break
		var spot := Vector2i(
			rng.range_i(room.position.x, room.end.x - 1),
			rng.range_i(room.position.y, room.end.y - 1)
		)
		if spot in [map.start_pos, map.upstairs_pos, map.stairs_pos, map.down_arrival_pos]:
			continue
		if not map.is_walkable(spot.x, spot.y):
			continue
		map.chests.append(spot)
		map.set_tile(spot.x, spot.y, DungeonMap.T_CHEST)

	_place_shop(map, rng)


## 階段を踏んだ直後に同じ階段が再発火しないよう、隣の床へ着地させる。
## 走査順は固定し、同じ地形なら同じ位置を返す。
static func _arrival_near(map: DungeonMap, feature: Vector2i) -> Vector2i:
	# キャラは足元から上へ16pxはみ出す。階段の上側へ立たせれば、下にある階段を
	# 全部見せたまま正面（初期向きの下）へ一歩で踏める。
	for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT]:
		var at: Vector2i = feature + step
		var tile := map.get_tile(at.x, at.y)
		if tile == DungeonMap.T_FLOOR or tile == DungeonMap.T_FLOOR_CRACKED:
			return at
	return feature


## 開始位置から見える場所へ戻り階段を置く。キャラは足元から上へ伸びるため、
## 下側を最優先にすると立ち絵に隠れず、初期向きのまま一歩で戻れる。
static func _visible_feature_near(map: DungeonMap, start: Vector2i) -> Vector2i:
	for step in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		var at: Vector2i = start + step
		var tile := map.get_tile(at.x, at.y)
		if tile == DungeonMap.T_FLOOR or tile == DungeonMap.T_FLOOR_CRACKED:
			return at
	return start


## 出店。毎階あると補給が作業になり、無さすぎるとゴールドが死ぬので、
## 半分くらいの階に出す。最終階だけは必ず出す（主に挑む前の最後の支度）。
static func _place_shop(map: DungeonMap, rng: DetRng) -> void:
	if not map.is_final and not rng.chance(55):
		return
	# 開始部屋と階段の部屋は避ける。出会い頭と直前では支度の意味が薄い。
	var candidates: Array[Rect2i] = []
	for room in map.rooms:
		if room.has_point(map.start_pos) or room.has_point(map.stairs_pos):
			continue
		candidates.append(room)
	if candidates.is_empty():
		candidates = map.rooms.duplicate()

	rng.shuffle(candidates)
	for room in candidates:
		var spot := _center(room)
		if spot == map.start_pos or spot == map.stairs_pos:
			continue
		if not map.is_walkable(spot.x, spot.y):
			continue
		map.shop_pos = spot
		map.set_tile(spot.x, spot.y, DungeonMap.T_SHOP)
		return
