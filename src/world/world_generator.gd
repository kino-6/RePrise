class_name WorldGenerator
extends RefCounted

## 1 ラン ぶんの世界を作る。
##
## 乱数は渡された DetRng からしか引かない。時刻にもエンジンの乱数にも触らないので、
## 同じシードからは必ず同じ世界が出る（洞の生成と同じ約束）。
##
## 作る順番には理由がある。
##
##   1. 大陸骨格を作る … 対岸を結ぶ旅程を先に置く
##   2. 門と城を決める … 骨格の両端。これが難度の軸になる
##   3. 仮の危険度を配る … 生物相を旅程の帯へ割り当てるため
##   4. 地形を塊で塗る … 1 マスごとの斑点抽選にしない
##   5. 本街道を通す … プレイヤーにも本筋を見える形で渡す
##   6. 危険度を配り直す … 最終地形の実距離と表示を一致させる
##   7. 拠点地を置く … 町は本街道、洞は枝道の先
##
## 4 と 5 が逆だと、せっかく引いた街道を地形の塗りが上書きする。
const MAP_W := 96
const MAP_H := 64

## 大陸の旅程骨格。西岸と東岸の間を 6 地域で結び、その周囲だけ乱歩で膨らませる。
const REGION_ANCHORS := 6
const COAST_MARGIN := 6
const SPINE_BRUSH := 5
const LOBE_WALKERS := 2
const LOBE_STEPS := 150
const LOBE_BRUSH := 2
const LOBE_RADIUS := 18

## 門から城まで、最低でもこの歩数は旅をさせる。
const MIN_WORLD_SPAN := 80

## 拠点地の数。**洞は行かなくても終点に着ける**位置に置く。
## 寄るか急ぐかが判断になるのは、寄らない選択が成立するときだけ。
const TOWN_COUNT := 4
const CAVE_COUNT := 5
const CAVE_DETOUR_MIN := 8
const CAVE_DETOUR_MAX := 20

## 町と町、洞と洞が近すぎると寄り道の意味が薄れる。
const SITE_SPACING := 8


## 何度まで作り直すか。**検算に落ちた世界は出さない。**
const MAX_ATTEMPTS := 12


## 世界を 1 つ作る。
##
## **作ったものは必ずその場で検算する。** 詰む世界を 1 つ出すだけで、
## そのランが丸ごと無駄になる。落ちたら種を振り直して作り直し、
## それでも駄目なら最後の 1 つを返して理由を警告に残す
## （黙って壊れた世界を返すより、出す・気づける方がまだよい）。
static func generate(rng: DetRng) -> WorldMap:
	var map: WorldMap = null
	var problems: Array[String] = []
	for attempt in MAX_ATTEMPTS:
		# 種を振り直す。同じ種で作り直しても同じ世界しか出ない。
		map = _build(rng.fork("attempt:%d" % attempt))
		problems = verify(map)
		if problems.is_empty():
			return map
	push_warning("検算に通る世界を作れなかった: %s" % "　/　".join(problems))
	return map


static func _build(rng: DetRng) -> WorldMap:
	var map := WorldMap.new(MAP_W, MAP_H)
	map.biome = "world"
	_carve_land(map, rng)
	_place_gate_and_castle(map, rng)
	_spread_danger(map)
	_assign_biomes(map, rng)
	_paint_terrain(map, rng)
	_carve_main_road(map)
	# 山・溶岩を置いたあとの実距離で危険度を確定する。
	_spread_danger(map)
	_place_sites(map, rng)
	_connect_sites_to_road(map)
	_place_seals(map, rng)
	_place_events(map, rng)
	# 物語は最後。町と洞が置かれていないと拍を土地へ結べない。
	map.story = StoryArcGenerator.generate_for_world(map, rng.fork("story"))
	return map


## 任意イベントを世界へ置く。街道 1 / 町 1 / 洞 1。
##
## 骨格は Codex のカタログ（`data/world_events.json`）から抽き、表層だけを
## `DetRng` が選ぶ。**選択肢もコストも見返りもここでは触らない。**
## 街道は本筋の上（通れば必ず出会う）、町と洞はその拠点地のマスに重ねる。
static func _place_events(map: WorldMap, rng: DetRng) -> void:
	map.events = {}
	var catalog := WorldEventCatalog.load_catalog()
	if catalog.is_empty():
		return

	# 街道 = 本筋の上で、門から少し離れたところ（1 歩目で出会わせない）。
	var on_route: Array[Vector2i] = []
	@warning_ignore("integer_division")
	var route_lo := map.main_road.size() / 5
	@warning_ignore("integer_division")
	var route_hi := map.main_road.size() * 4 / 5
	for i in range(route_lo, route_hi + 1):
		var at: Vector2i = map.main_road[i]
		if not map.sites.has(at):
			on_route.append(at)

	var slots := []
	if not on_route.is_empty():
		slots.append({"pos": on_route[rng.range_i(0, on_route.size() - 1)], "kind": "world"})
	for kind in ["town", "cave"]:
		var pool: Array[Vector2i] = []
		for pos in map.sites:
			if String(map.sites[pos].get("kind", "")) == kind:
				pool.append(pos)
		if not pool.is_empty():
			slots.append({"pos": pool[rng.range_i(0, pool.size() - 1)], "kind": kind})

	for slot in slots:
		var at: Vector2i = slot["pos"]
		var context := {
			"site_kind": String(slot["kind"]),
			"danger": map.danger_at(at.x, at.y),
			"biome": map.biome_id_at(at.x, at.y),
		}
		var picked := WorldEventCatalog.select_for_world(rng, context, 1, catalog)
		if picked.is_empty():
			continue
		map.events[at] = WorldEventCatalog.instantiate(picked[0], rng, context)


# --------------------------------------------------------------------------
# 検算
#
# 生成器が自分の出力を疑う。ここを通ったものだけが世界になる。
# --------------------------------------------------------------------------


## 世界が最後まで遊べるかを確かめる。問題の一覧を返す（空なら健全）。
##
## **見た目ではなく到達性と構造を見る。** 綺麗な世界でも、封に届かなければ
## そのランは最初から負けが決まっている。目で見て気づけない類の壊れ方なので、
## 機械に測らせる。テスト（`_test_world_generation`）もここを呼ぶ。
static func verify(map: WorldMap) -> Array[String]:
	var problems: Array[String] = []
	if map == null:
		return ["世界が無い"]

	var dist := map.distance_field(map.start_pos)
	var reachable := func(at: Vector2i) -> bool:
		return map.in_bounds(at.x, at.y) and dist[at.y * map.width + at.x] >= 0

	# 1. 城まで歩けること。これが崩れたら他を見るまでもない。
	if not reachable.call(map.castle_pos):
		problems.append("城まで歩けない")
	if map.width != MAP_W or map.height != MAP_H:
		problems.append("世界の寸法が %dx%d（%dx%d であるべき）" % [
			map.width, map.height, MAP_W, MAP_H
		])
	var span := -1
	if map.in_bounds(map.castle_pos.x, map.castle_pos.y):
		span = dist[map.castle_pos.y * map.width + map.castle_pos.x]
	if span < MIN_WORLD_SPAN:
		problems.append("門から城が %d 歩（最低 %d 歩）" % [span, MIN_WORLD_SPAN])

	# 本街道は生成器の内部だけでなく、地図で見える旅程でなければならない。
	if map.main_road.is_empty():
		problems.append("本街道が無い")
	else:
		if map.main_road[0] != map.start_pos or map.main_road[-1] != map.castle_pos:
			problems.append("本街道の両端が門と城ではない")
		for i in range(1, map.main_road.size()):
			if _grid_distance(map.main_road[i - 1], map.main_road[i]) != 1:
				problems.append("本街道が途中で切れている")
				break
		for at in map.main_road:
			var tile := map.get_tile(at.x, at.y)
			if tile not in [
				WorldMap.T_ROAD, WorldMap.T_GATE, WorldMap.T_TOWN, WorldMap.T_CASTLE
			]:
				problems.append("本街道が地図に描かれていない: %s" % str(at))
				break

		var biome_runs := 0
		var last_biome := -1
		for at in map.main_road:
			var biome := map.biome_index_at(at.x, at.y)
			if biome != last_biome:
				biome_runs += 1
				last_biome = biome
		if biome_runs < 4:
			problems.append("本街道の地域が %d 種類しかない" % biome_runs)

	# 2. 封が 3 つあること
	if map.seals.size() != SEAL_COUNT:
		problems.append("封が %d 個（%d 個であるべき）" % [map.seals.size(), SEAL_COUNT])

	# 3. 封のある洞にすべて歩けること。1 つでも届かなければ城の扉が永久に開かない
	var seen_bands := {}
	var seen_caves := {}
	for s in map.seals:
		var at: Vector2i = s.get("pos", Vector2i(-1, -1))
		if not reachable.call(at):
			problems.append("封（%s）のある洞に歩けない" % String(s.get("name", "?")))
		if seen_caves.has(at):
			problems.append("同じ洞に封が 2 つ置かれている")
		seen_caves[at] = true
		seen_bands[String(s.get("band", ""))] = true
		if String(s.get("name", "")) == "":
			problems.append("封に名前が無い")

	# 4. 帯が 3 つに分かれていること。全部が浅い土地にあると、
	#    「順番は自由だが必ず 3 つ回る」という形が崩れて、難度曲線も潰れる。
	if map.seals.size() == SEAL_COUNT and seen_bands.size() != SEAL_COUNT:
		problems.append("封の危険度が帯ごとに分かれていない")

	# 5. 置いたイベントに歩いて行けること。
	#    届かないイベントは、置いた手間がそのまま無駄になる。
	for pos in map.events:
		var at: Vector2i = pos
		if not reachable.call(at):
			problems.append("イベント（%s）に歩けない" % String(map.events[pos].get("event_id", "?")))
		if String(map.events[pos].get("event_id", "")) == "":
			problems.append("イベントに id が無い")
		if not map.sites.has(at) and map.get_tile(at.x, at.y) != WorldMap.T_ROAD:
			problems.append("街道イベントが街道の外にある")

	# 6. 物語が成立していること。**筋が通らない世界は出さない。**
	#    六拍のどれかが土地に結べていないと、そのランは途中で話が切れる。
	if not bool(map.story.get("valid", false)):
		problems.append("物語が成立しない: %s" % str(map.story.get("errors", [])))
	else:
		var beats: Array = map.story.get("beats", [])
		if beats.size() != 6:
			problems.append("物語の拍が %d（6 であるべき）" % beats.size())
		# 拍は座標ではなく id（"cave:2" など）で土地に結ばれている。
		# 座標で見ていたときは常に -1 で、この検算は**空振りしていた**。
		for beat in beats:
			var site_id := String(beat.get("site_id", ""))
			if site_id == "":
				problems.append("物語の拍（%s）が土地に結ばれていない" % String(beat.get("id", "?")))
				continue
			var at := map.pos_of_site_id(site_id)
			if at.x < 0:
				problems.append("物語の拍（%s）の土地 %s が世界に無い" % [
					String(beat.get("id", "?")), site_id
				])
			elif not reachable.call(at):
				problems.append("物語の拍（%s）の土地に歩けない" % String(beat.get("id", "?")))

	# 7. 拠点数と街道網。世界を広げても、目的地が乱数で孤立してはいけない。
	var towns := 0
	var caves := 0
	var road_reached := _road_network(map)
	for pos in map.sites:
		var kind := String(map.sites[pos].get("kind", ""))
		if kind == "town" and reachable.call(pos):
			towns += 1
		elif kind == "cave" and reachable.call(pos):
			caves += 1
		if kind in ["town", "cave"] and not road_reached.has(pos):
			problems.append("%sが街道網につながっていない: %s" % [kind, str(pos)])
	if towns != TOWN_COUNT:
		problems.append("町が %d 個（%d 個であるべき）" % [towns, TOWN_COUNT])
	if caves != CAVE_COUNT:
		problems.append("洞が %d 個（%d 個であるべき）" % [caves, CAVE_COUNT])

	# 生物相の境界は少数の面であること。1マス交互の斑模様を検算で落とす。
	var same_neighbors := 0
	var neighbor_pairs := 0
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) == WorldMap.T_SEA:
				continue
			for step in [Vector2i.RIGHT, Vector2i.DOWN]:
				var other: Vector2i = Vector2i(x, y) + step
				if not map.in_bounds(other.x, other.y):
					continue
				if map.get_tile(other.x, other.y) == WorldMap.T_SEA:
					continue
				neighbor_pairs += 1
				if map.biome_index_at(x, y) == map.biome_index_at(other.x, other.y):
					same_neighbors += 1
	if neighbor_pairs > 0 and same_neighbors * 100 / neighbor_pairs < 85:
		problems.append("生物相が細切れ（同一隣接 %d%%）" % [
			same_neighbors * 100 / neighbor_pairs
		])

	return problems


static func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 街道、門、町、洞、城だけを辿って届くマス。
static func _road_network(map: WorldMap) -> Dictionary:
	var reached := {}
	if not map.in_bounds(map.start_pos.x, map.start_pos.y):
		return reached
	var queue: Array[Vector2i] = [map.start_pos]
	reached[map.start_pos] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		for step in FieldMap.NEIGHBORS:
			var next: Vector2i = at + step
			if reached.has(next) or not map.in_bounds(next.x, next.y):
				continue
			if map.get_tile(next.x, next.y) not in [
				WorldMap.T_ROAD, WorldMap.T_GATE, WorldMap.T_TOWN,
				WorldMap.T_CAVE, WorldMap.T_CASTLE,
			]:
				continue
			reached[next] = true
			queue.append(next)
	return reached


# --------------------------------------------------------------------------
# 封
# --------------------------------------------------------------------------

## 封の数と、置く危険度の帯。**ここが固定だから 1 ラン の長さが読める。**
const SEAL_COUNT := 3
const SEAL_BANDS := [
	{"id": "low", "name": "浅", "range": [1, 4]},
	{"id": "mid", "name": "中", "range": [4, 7]},
	{"id": "high", "name": "深", "range": [7, 10]},
]

## 封の名。語 × 語で作る（テンプレート語彙表 × DetRng）。
## AI を繋ぐ前の土台で、これだけでも毎回違う名前が出る。
## AI が来たらここを差し替えるのではなく、**落ちたときの受け皿**として残す。
static var SEAL_HEAD: Array = Vocabulary.nested("seal_names", "", "head", ["しずまりの", "とこしえの", "うつろな", "かたくなな", "まどろむ"])
static var SEAL_TAIL: Array = Vocabulary.nested("seal_names", "", "tail", ["錠", "枷", "結び", "封"])

## なぜそれが要るのかの一文。名前だけだと「集めろと言われたから集める」になる。
static var SEAL_WHY: Array = Vocabulary.nested("seal_names", "", "why", ["これが ある かぎり 城の あるじは 傷つかない。"])


## 封を洞に置く。帯ごとに 1 つずつ。
##
## 洞にしか置かない（町に置くと寄り道が本筋になってしまう）。
## 帯に合う洞が無い帯は、いちばん近い危険度の未使用の洞で代える。
## それでも足りなければ検算が落として作り直しになる。
static func _place_seals(map: WorldMap, rng: DetRng) -> void:
	map.seals = []
	var caves: Array[Vector2i] = []
	for pos in map.sites:
		if String(map.sites[pos].get("kind", "")) == "cave":
			caves.append(pos)
	caves.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(map.sites[a].get("danger", 0)) < int(map.sites[b].get("danger", 0)))

	var used := {}
	for band in SEAL_BANDS:
		var lo := int(band["range"][0])
		var hi := int(band["range"][1])
		var pick := Vector2i(-1, -1)
		# まず帯に収まる洞から
		for at in caves:
			if used.has(at):
				continue
			var d := int(map.sites[at].get("danger", 0))
			if d >= lo and d <= hi:
				pick = at
				break
		# 無ければ帯に近い順で代える
		if pick.x < 0:
			var best := -1
			for at in caves:
				if used.has(at):
					continue
				var d := int(map.sites[at].get("danger", 0))
				var gap: int = mini(absi(d - lo), absi(d - hi))
				if best < 0 or gap < best:
					best = gap
					pick = at
		if pick.x < 0:
			continue  # 洞が足りない。検算が落とす
		used[pick] = true
		map.seals.append({
			"pos": pick,
			"band": String(band["id"]),
			"band_name": String(band["name"]),
			"danger": int(map.sites[pick].get("danger", 1)),
			"name": "%s%s" % [
				SEAL_HEAD[rng.range_i(0, SEAL_HEAD.size() - 1)],
				SEAL_TAIL[rng.range_i(0, SEAL_TAIL.size() - 1)],
			],
			"why": SEAL_WHY[rng.range_i(0, SEAL_WHY.size() - 1)],
			"broken": false,
		})
		# 洞の側にも印を付ける。HUD と町の聞き込みで使う。
		map.sites[pick]["seal"] = map.seals.size() - 1


# --------------------------------------------------------------------------
# 1. 陸
# --------------------------------------------------------------------------


## 対岸を結ぶ骨格を先に置き、その周囲を乱歩で膨らませる。
##
## 中央から自由な乱歩だけで作ると、地図の広さを増しても中央に小さな島ができる。
## 両端を結ぶ旅程を固定し、乱数は地域の曲がり方と海岸線へ使う。
static func _carve_land(map: WorldMap, rng: DetRng) -> void:
	var west_y := rng.range_i(COAST_MARGIN + 8, MAP_H - COAST_MARGIN - 9)
	var east_y := rng.range_i(COAST_MARGIN + 8, MAP_H - COAST_MARGIN - 9)
	var anchors: Array[Vector2i] = []
	for i in REGION_ANCHORS:
		@warning_ignore("integer_division")
		var x := COAST_MARGIN + i * (MAP_W - COAST_MARGIN * 2 - 1) / (REGION_ANCHORS - 1)
		@warning_ignore("integer_division")
		var y := west_y + (east_y - west_y) * i / (REGION_ANCHORS - 1)
		if i > 0 and i < REGION_ANCHORS - 1:
			y += rng.range_i(-10, 10)
		y = clampi(y, COAST_MARGIN + 6, MAP_H - COAST_MARGIN - 7)
		anchors.append(Vector2i(x, y))

	# 骨格を幅のある陸で結ぶ。
	for i in range(anchors.size() - 1):
		_carve_corridor(map, anchors[i], anchors[i + 1], rng)

	# 各地域を短い乱歩で膨らませる。地域アンカーから離れすぎたら戻すため、
	# 世界全体を無方向に埋める歩行者にはならない。
	for center in anchors:
		for _walker in LOBE_WALKERS:
			var at := center
			for _step in LOBE_STEPS:
				_brush(map, at, LOBE_BRUSH)
				var next := at + FieldMap.NEIGHBORS[rng.range_i(0, 3)]
				if _grid_distance(next, center) > LOBE_RADIUS:
					var dx := signi(center.x - at.x)
					var dy := signi(center.y - at.y)
					next = at + (Vector2i(dx, 0) if rng.chance(50) else Vector2i(0, dy))
				next.x = clampi(next.x, COAST_MARGIN, MAP_W - COAST_MARGIN - 1)
				next.y = clampi(next.y, COAST_MARGIN, MAP_H - COAST_MARGIN - 1)
				at = next

	# 大陸の向きは同じにして読みやすくし、進行方向だけ半数で反転する。
	if rng.chance(50):
		anchors.reverse()
	map.start_pos = anchors[0]
	map.castle_pos = anchors[-1]


static func _carve_corridor(
	map: WorldMap, from: Vector2i, to: Vector2i, rng: DetRng
) -> void:
	var at := from
	while true:
		_brush(map, at, SPINE_BRUSH)
		if at == to:
			return
		var dx := absi(to.x - at.x)
		var dy := absi(to.y - at.y)
		if dx > 0 and dy > 0:
			# 残り距離の比率で軸を選び、目的地へ単調に近づく。
			if rng.range_i(1, dx + dy) <= dx:
				at.x += signi(to.x - at.x)
			else:
				at.y += signi(to.y - at.y)
		elif dx > 0:
			at.x += signi(to.x - at.x)
		else:
			at.y += signi(to.y - at.y)


static func _brush(map: WorldMap, at: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			# 角を落として丸くする。四角い筆だと海岸線が階段状になる。
			if absi(dx) + absi(dy) > radius + 1:
				continue
			map.set_tile(at.x + dx, at.y + dy, WorldMap.T_PLAIN)


# --------------------------------------------------------------------------
# 2. 門と城
# --------------------------------------------------------------------------


## 大陸骨格の両端を門と城にする。
static func _place_gate_and_castle(map: WorldMap, _rng: DetRng) -> void:
	var land := _land_cells(map)
	if land.is_empty():
		# 万一の保険。陸が無いと詰むので中心を陸にする。
		map.set_tile(MAP_W / 2, MAP_H / 2, WorldMap.T_PLAIN)
		land = [Vector2i(MAP_W / 2, MAP_H / 2)]
	if not map.in_bounds(map.start_pos.x, map.start_pos.y):
		map.start_pos = land[0]
	if not map.in_bounds(map.castle_pos.x, map.castle_pos.y):
		map.castle_pos = land[-1]

	map.set_tile(map.start_pos.x, map.start_pos.y, WorldMap.T_GATE)
	map.set_tile(map.castle_pos.x, map.castle_pos.y, WorldMap.T_CASTLE)
	map.sites[map.castle_pos] = {
		"kind": "castle", "danger": WorldMap.MAX_DANGER, "index": 0
	}


static func _land_cells(map: WorldMap) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) == WorldMap.T_PLAIN:
				cells.append(Vector2i(x, y))
	return cells


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


## 生物相を旅程に沿った 5 つの地域として置く。
##
## ランダムな種をボロノイで広げると面にはなるが、地域の順序に意味が無い。
## 危険度 1〜2 / 3〜4 / ... / 9〜10 を一つの地域とし、門から城へ進むほど
## 景色が段階的に変わるようにする。
const BIOME_REGIONS := 5


static func _assign_biomes(map: WorldMap, rng: DetRng) -> void:
	var kinds: Array[int] = [0]  # 出発地域は草原。
	var used := {0: true}
	for region in range(1, BIOME_REGIONS):
		var danger := region * 2 + 1
		var candidates := _biomes_for_danger(danger)
		var fresh: Array[int] = []
		for candidate in candidates:
			if candidate != kinds[-1] and not used.has(candidate):
				fresh.append(candidate)
		if fresh.is_empty():
			for candidate in candidates:
				if candidate != kinds[-1]:
					fresh.append(candidate)
		if fresh.is_empty():
			fresh = candidates
		var picked: int = fresh[rng.range_i(0, fresh.size() - 1)] if not fresh.is_empty() else 0
		kinds.append(picked)
		used[picked] = true

	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) == WorldMap.T_SEA:
				continue
			@warning_ignore("integer_division")
			var region := clampi((map.danger_at(x, y) - 1) / 2, 0, BIOME_REGIONS - 1)
			map.set_biome(x, y, kinds[region])


static func _biomes_for_danger(danger: int) -> Array[int]:
	var candidates: Array[int] = []
	for i in WorldMap.BIOMES.size():
		var band: Array = WorldMap.BIOMES[i].get("danger", [1, 10])
		if danger >= int(band[0]) and danger <= int(band[1]):
			candidates.append(i)
	return candidates

## 地域を代表地形で塗り、別地形を半径 2〜5 のパッチで重ねる。
##
## 1 マスごとに候補を引くと、同じ生物相でも斑点模様になる。
## 乱数は「森がどこに固まるか」「溶岩湖がどこにあるか」へ使う。
static func _paint_terrain(map: WorldMap, rng: DetRng) -> void:
	var land: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) != WorldMap.T_PLAIN:
				continue  # 海と、既に置いた門・城には触らない
			var palette: Array = map.biome_at(x, y).get("tiles", [WorldMap.T_PLAIN])
			map.set_tile(x, y, _walkable_base_tile(palette))
			land.append(Vector2i(x, y))

	# 地域ごとに十分な数のパッチを置く。面積に比例させるため、
	# 世界を広げても粒の大きさだけが変わることはない。
	@warning_ignore("integer_division")
	var patches := maxi(land.size() / 28, 1)
	for _i in patches:
		var center: Vector2i = land[rng.range_i(0, land.size() - 1)]
		var biome_index := map.biome_index_at(center.x, center.y)
		var palette: Array = map.biome_at(center.x, center.y).get("tiles", [WorldMap.T_PLAIN])
		if palette.size() < 2:
			continue
		var tile := int(palette[rng.range_i(1, palette.size() - 1)])
		_paint_patch(map, center, biome_index, tile, rng.range_i(2, 5), rng)

	# 門と城のまわりは必ず歩けるようにしておく。生物相の抽選で溶岩や山に
	# 囲まれると、そこだけで詰む。
	for center in [map.start_pos, map.castle_pos]:
		for step in FieldMap.NEIGHBORS:
			var at: Vector2i = center + step
			if map.in_bounds(at.x, at.y) and not map.is_walkable(at.x, at.y):
				if map.get_tile(at.x, at.y) != WorldMap.T_SEA:
					map.set_tile(at.x, at.y, WorldMap.T_HILL)

	# 山と溶岩で城が孤立していないか確かめ、閉じていたら道を通す。
	# **生成物は必ず到達可能でなければならない**（詰む世界を出さない）。
	_ensure_reachable(map)


static func _walkable_base_tile(palette: Array) -> int:
	for value in palette:
		var tile := int(value)
		if tile not in [WorldMap.T_SEA, WorldMap.T_MOUNTAIN, WorldMap.T_LAVA]:
			return tile
	return WorldMap.T_HILL


static func _paint_patch(
	map: WorldMap, center: Vector2i, biome_index: int, tile: int, radius: int, rng: DetRng
) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var distance := absi(dx) + absi(dy)
			if distance > radius + 1:
				continue
			# 外周を少し欠かし、四角や完全な菱形に見えないようにする。
			if distance >= radius and rng.chance(35):
				continue
			var at := center + Vector2i(dx, dy)
			if not map.in_bounds(at.x, at.y):
				continue
			if at in [map.start_pos, map.castle_pos]:
				continue
			if map.get_tile(at.x, at.y) == WorldMap.T_SEA:
				continue
			if map.biome_index_at(at.x, at.y) != biome_index:
				continue
			map.set_tile(at.x, at.y, tile)


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
				if not map.is_walkable(at.x, at.y) and map.get_tile(at.x, at.y) != WorldMap.T_SEA:
					map.set_tile(at.x, at.y, WorldMap.T_HILL)
			opened = true
			break
		if not opened:
			return


## 最終地形の最短路を、画面で読める本街道へ変える。
static func _carve_main_road(map: WorldMap) -> void:
	var path := map.route(map.start_pos, map.castle_pos)
	map.main_road = [map.start_pos]
	map.main_road.append_array(path)
	for at in map.main_road:
		if at in [map.start_pos, map.castle_pos]:
			continue
		map.set_tile(at.x, at.y, WorldMap.T_ROAD)


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

	# 町は、画面にも描かれている本街道へ置く。
	var on_route: Array[Vector2i] = []
	for at in map.main_road:
		if at not in [map.start_pos, map.castle_pos]:
			on_route.append(at)

	# 洞は本街道から外し、危険度の各帯へ散らす。
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
			# 洞は街道の外へ置くが、世界を広げたぶんだけ枝道まで際限なく
			# 長くしない。遠回り度は概ね街道からの往復距離になる。
			if detour >= CAVE_DETOUR_MIN and detour <= CAVE_DETOUR_MAX:
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
			# 洞の中の絵はその土地の生物相から決まる（雪原の洞は雪原の絵）。
			var biome := map.biome_at(at.x, at.y)
			map.set_tile(at.x, at.y, tile)
			map.sites[at] = {
				"kind": kind, "danger": tier, "index": placed,
				"biome": String(biome.get("id", "grassland")),
				"tileset": String(biome.get("tileset", "dungeon")),
				"place": String(biome.get("name", "")),
			}
			placed += 1
			break


## 洞から本街道へ枝道を伸ばす。目的地は任意だが、見つける根拠は地図へ残す。
static func _connect_sites_to_road(map: WorldMap) -> void:
	if map.main_road.is_empty():
		return
	for pos in map.sites:
		var kind := String(map.sites[pos].get("kind", ""))
		if kind != "cave":
			continue
		var site_at: Vector2i = pos
		var nearest := map.main_road[0]
		var nearest_distance := _grid_distance(site_at, nearest)
		for road_at in map.main_road:
			var distance := _grid_distance(site_at, road_at)
			if distance < nearest_distance:
				nearest = road_at
				nearest_distance = distance
		var spur := map.route(site_at, nearest)
		for at in spur:
			if at == nearest or map.sites.has(at):
				continue
			map.set_tile(at.x, at.y, WorldMap.T_ROAD)


static func _too_close(map: WorldMap, at: Vector2i) -> bool:
	for pos in map.sites:
		var other: Vector2i = pos
		if absi(other.x - at.x) + absi(other.y - at.y) < SITE_SPACING:
			return true
	return false
