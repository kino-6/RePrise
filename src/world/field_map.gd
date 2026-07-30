class_name FieldMap
extends RefCounted

## 歩ける格子の共通部分。ワールドも洞の中も、これを継承した 1 枚として扱う。
##
## 切り出した理由は `ExploreView` を分けないため。あそこは歩き・カメラ・
## 描画・エンカウントを持っているが、**地図の中身には依存していない。**
## 型だけ揃えれば、ワールドでも洞でも同じ 1 本で歩ける。
## 2 本に分けると、片方だけ直したバグが必ず出る。
##
## タイル番号の意味は子が決める（`assets/tiles/*.png` の並び順と一致させること）。

var width: int = 0
var height: int = 0
var tiles: PackedByteArray = PackedByteArray()

## 一行が現れる場所。
var start_pos: Vector2i = Vector2i.ZERO

## この地図の地形（`assets/tiles/<biome>.png`）。
var biome: String = "dungeon"


func _init(w: int = 0, h: int = 0, fill: int = 0) -> void:
	width = w
	height = h
	tiles = PackedByteArray()
	tiles.resize(w * h)
	tiles.fill(fill)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_tile(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return tiles[y * width + x]


func set_tile(x: int, y: int, t: int) -> void:
	if in_bounds(x, y):
		tiles[y * width + x] = t


## 通れるか。子が必ず上書きする。
func is_walkable(_x: int, _y: int) -> bool:
	return false


## 描画に使うタイル番号。既定はそのまま。
func render_tile(x: int, y: int) -> int:
	return get_tile(x, y)


## 描かないタイル（背景のまま抜く）。
func is_void(_x: int, _y: int) -> bool:
	return false


## 隣接の走査順。**固定する**こと。順番が揺れると同じ地形から違う経路が出て、
## 決定性が壊れる（オート移動のリプレイが再現しなくなる）。
const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## from から to までの最短経路（幅優先）。届かなければ空を返す。
##
## 自動プレイの「目的地へ向かう」の土台。ワールドでも洞でも同じものを使う。
## 目的地そのものは通行可否を問わない（扉・階段・町の入口を目標にできるように）。
func route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to or not in_bounds(to.x, to.y):
		return empty

	var came := {}
	var queue: Array[Vector2i] = [from]
	came[from] = from
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if at == to:
			break
		for step in NEIGHBORS:
			var next: Vector2i = at + step
			if came.has(next):
				continue
			if next != to and not is_walkable(next.x, next.y):
				continue
			came[next] = at
			queue.append(next)

	if not came.has(to):
		return empty
	var path: Array[Vector2i] = []
	var cursor := to
	while cursor != from:
		path.push_front(cursor)
		cursor = came[cursor]
	return path


## 起点から陸路で何歩かかるかを全マスぶん測る。届かないマスは -1。
##
## ワールドの危険度（出発からの距離で決まる）を作るのに要る。
## route() を各マスに対して呼ぶと 3000 回の幅優先になるので、1 回で済ませる。
func distance_field(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	if not in_bounds(from.x, from.y):
		return dist
	dist[from.y * width + from.x] = 0
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		var here := dist[at.y * width + at.x]
		for step in NEIGHBORS:
			var next: Vector2i = at + step
			if not in_bounds(next.x, next.y):
				continue
			var index := next.y * width + next.x
			if dist[index] >= 0 or not is_walkable(next.x, next.y):
				continue
			dist[index] = here + 1
			queue.append(next)
	return dist


## デバッグ用のアスキー出力。決定性テストの比較にも使う。
## 記号の対応は子が持つ（地図ごとに意味が違うため）。
func glyphs() -> Dictionary:
	return {}


func to_ascii() -> String:
	var table := glyphs()
	var lines: PackedStringArray = []
	for y in height:
		var row := ""
		for x in width:
			if Vector2i(x, y) == start_pos:
				row += "@"
			else:
				row += String(table.get(get_tile(x, y), "?"))
		lines.append(row)
	return "\n".join(lines)
