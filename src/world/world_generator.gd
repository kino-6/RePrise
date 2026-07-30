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
	_place_sites(map, rng)
	_place_seals(map, rng)
	_place_events(map, rng)
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

	var from_gate := map.distance_field(map.start_pos)
	var to_castle := map.distance_field(map.castle_pos)
	var span := maxi(from_gate[map.castle_pos.y * map.width + map.castle_pos.x], 1)

	# 街道 = 本筋の上で、門から少し離れたところ（1 歩目で出会わせない）。
	var on_route: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if not map.is_walkable(x, y) or map.sites.has(Vector2i(x, y)):
				continue
			var a := from_gate[y * map.width + x]
			var b := to_castle[y * map.width + x]
			if a < 0 or b < 0 or a + b - span > 0:
				continue
			if a < span / 5 or a > span * 4 / 5:
				continue
			on_route.append(Vector2i(x, y))

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

	# 6. 買い物ができること。町に 1 つも歩けないと、備えの手段が宝箱だけになる
	var towns := 0
	for pos in map.sites:
		if String(map.sites[pos].get("kind", "")) == "town" and reachable.call(pos):
			towns += 1
	if towns < 1:
		problems.append("歩いて行ける町が無い")

	return problems


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
const SEAL_HEAD := [
	"しずまりの", "とこしえの", "うつろな", "かたくなな", "まどろむ",
	"ふるびた", "こごえた", "いさぎよい", "ものいわぬ", "あかつきの",
]
const SEAL_TAIL := ["錠", "枷", "結び", "封", "戒め", "楔"]

## なぜそれが要るのかの一文。名前だけだと「集めろと言われたから集める」になる。
const SEAL_WHY := [
	"これが ある かぎり 城の あるじは 傷つかない。",
	"むかし ここに 沈められた ものが 城を まもっている。",
	"この地の ちからが 城の とびらを 閉ざしている。",
	"洞の そこで 息づいて、城へ ちからを おくっている。",
]


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


## 生物相を**面**で置く。
##
## これが「世界が適当に見える」問題の本体だった。1 マスずつ危険度から
## 地形を抽くと、草原と森と丘が均一に混ざった斑模様になり、どこも同じ顔になる。
## 実際の世界地図が世界に見えるのは、**同じ地形がまとまって続く**からで、
## 「ここは森林地帯」「ここから雪原」と読めることが地図の情報量になる。
##
## 種をいくつか撒いて、いちばん近い種の生物相に染める（ボロノイ）。
## 種ごとの生物相は**その場所の危険度に合うものから選ぶ**ので、
## 門のそばに火山は来ないし、城の手前が草原になることもない。
const BIOME_SEEDS := 9


static func _assign_biomes(map: WorldMap, rng: DetRng) -> void:
	var land := _land_cells(map)
	if land.is_empty():
		return

	# 種を撒く。近すぎる種は地帯が細切れになるので間隔をあける。
	var seeds: Array[Vector2i] = []
	var kinds: Array[int] = []
	for _i in BIOME_SEEDS * 8:
		if seeds.size() >= BIOME_SEEDS:
			break
		var at: Vector2i = land[rng.range_i(0, land.size() - 1)]
		var too_near := false
		for other in seeds:
			if absi(other.x - at.x) + absi(other.y - at.y) < 12:
				too_near = true
				break
		if too_near:
			continue
		seeds.append(at)
		kinds.append(0)
	if seeds.is_empty():
		seeds.append(land[0])
		kinds.append(0)

	# いちばん近い種に染める。距離は素直なマンハッタンでよい
	# （陸路で測ると地帯が道の形に伸びて、地図として読みにくくなる）。
	var owner := PackedByteArray()
	owner.resize(map.width * map.height)
	var danger_sum := []
	var cell_count := []
	danger_sum.resize(seeds.size())
	cell_count.resize(seeds.size())
	danger_sum.fill(0)
	cell_count.fill(0)

	for y in map.height:
		for x in map.width:
			var best := 0
			var best_d := -1
			for i in seeds.size():
				var d := absi(seeds[i].x - x) + absi(seeds[i].y - y)
				if best_d < 0 or d < best_d:
					best_d = d
					best = i
			owner[y * map.width + x] = best
			if map.is_walkable(x, y):
				danger_sum[best] = int(danger_sum[best]) + map.danger_at(x, y)
				cell_count[best] = int(cell_count[best]) + 1

	# **生物相は「種の危険度」ではなく「その地帯の平均の危険度」で決める。**
	# 種で決めると、危険度 4 で引いた湿地が門（危険度 1）まで広がってしまう。
	# 面を先に確定させてから中身を選べば、地帯と危険度が必ず噛み合う。
	for i in seeds.size():
		var mean := 1
		if int(cell_count[i]) > 0:
			mean = int(danger_sum[i]) / int(cell_count[i])
		kinds[i] = _biome_for_danger(mean, rng)

	for y in map.height:
		for x in map.width:
			map.set_biome(x, y, kinds[owner[y * map.width + x]])


## その危険度に置いてよい生物相から 1 つ選ぶ。
static func _biome_for_danger(danger: int, rng: DetRng) -> int:
	var candidates: Array[int] = []
	for i in WorldMap.BIOMES.size():
		var band: Array = WorldMap.BIOMES[i].get("danger", [1, 10])
		if danger >= int(band[0]) and danger <= int(band[1]):
			candidates.append(i)
	if candidates.is_empty():
		return 0
	return candidates[rng.range_i(0, candidates.size() - 1)]


## 生物相の候補から 1 マスずつ塗る。
##
## 帯の中の揺れは残す（同じタイルで埋めると地帯が単調な板になる）。
## 大事なのは「地帯の中では傾向が揃っていること」で、完全な均一ではない。
static func _paint_terrain(map: WorldMap, rng: DetRng) -> void:
	for y in map.height:
		for x in map.width:
			if map.get_tile(x, y) != WorldMap.T_PLAIN:
				continue  # 海と、既に置いた門・城には触らない
			var palette: Array = map.biome_at(x, y).get("tiles", [WorldMap.T_PLAIN])
			map.set_tile(x, y, int(palette[rng.range_i(0, palette.size() - 1)]))

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


static func _too_close(map: WorldMap, at: Vector2i) -> bool:
	for pos in map.sites:
		var other: Vector2i = pos
		if absi(other.x - at.x) + absi(other.y - at.y) < SITE_SPACING:
			return true
	return false
