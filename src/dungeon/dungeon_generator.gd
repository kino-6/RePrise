class_name DungeonGenerator
extends RefCounted

## 部屋と通路によるフロア生成。
##
## 乱数は渡された DetRng からしか引かない。時刻にもエンジンの乱数にも触らないので、
## 同じシードと同じ階層からは必ず同じフロアが出る。

const MAP_W := 40
const MAP_H := 32

const ROOM_ATTEMPTS := 60
const ROOM_MIN := Vector2i(5, 4)
const ROOM_MAX := Vector2i(10, 7)
const ROOM_LIMIT := 8


static func generate(rng: DetRng, floor_number: int) -> DungeonMap:
	var map := DungeonMap.new(MAP_W, MAP_H)
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
	map.start_pos = _center(map.rooms[0])

	# 階段は開始地点から最も遠い部屋に置く。フロアを横断させるため。
	var farthest := map.rooms[0]
	var best_distance := -1
	for room in map.rooms:
		var d: int = absi(_center(room).x - map.start_pos.x) + absi(_center(room).y - map.start_pos.y)
		if d > best_distance:
			best_distance = d
			farthest = room
	map.stairs_pos = _center(farthest)
	map.set_tile(map.stairs_pos.x, map.stairs_pos.y, DungeonMap.T_STAIRS)

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
		if spot == map.start_pos or spot == map.stairs_pos:
			continue
		if not map.is_walkable(spot.x, spot.y):
			continue
		map.chests.append(spot)
		map.set_tile(spot.x, spot.y, DungeonMap.T_CHEST)
