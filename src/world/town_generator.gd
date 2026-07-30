class_name TownGenerator
extends RefCounted

## 町の中を作る。
##
## 洞と違って**迷わせない**のが目的。町は目的地であって迷路ではないので、
## 中央に広場を置き、宿・店・出口を広場から必ず見える位置に並べる。
## 迷う町は、用があって寄った人間にとってただの足止めになる。
##
## 乱数は渡された DetRng だけ。同じ世界の同じ町は毎回同じ形になる。

const MAP_W := 26
const MAP_H := 18

## 町の名の作り方。地形の語 + 場所の語。
## AI に書かせる前の土台で、これだけでも毎回違う名前が出る
## （docs/quest_design.md の「テンプレート語彙表 × DetRng」がこれ）。
const NAME_HEAD := [
	"かぜ", "いずみ", "しらかば", "あかつき", "みなも", "とうげ", "こだま",
	"すずかけ", "ゆきわ", "ほむら", "しおさい", "つきしろ",
]
const NAME_TAIL := ["の里", "の宿場", "の町", "のむら", "の辻"]

## 町人の一言。役どころごとに分ける。
##
## **同じ人物像を並べない。** 全員が世間話をすると町が背景になる。
## 宿の主・店番・物知り・子ども、と役を散らすと、町が人の居る場所になる。
const LINES := {
	"keeper": [
		"よく来た。やどは いつでも あいている。",
		"ゆっくり やすんでいくと いい。",
		"となりの みせで そなえを ととのえな。",
	],
	"trader": [
		"ここらの しなは そろえてある。",
		"おくへ 行くなら やくそうは 多めにな。",
		"かねは 使ってこそ 意味が ある。",
	],
	"elder": [
		"おくの 地は 生きものの たちが ちがう。",
		"ゆきの 地では こおりに つよい ものが 出る。",
		"ほのおの 地の ものに 火は きかんよ。",
		"いそぐ者ほど はやく たおれる。",
	],
	"child": [
		"ほら穴の おくに なにか あるって。",
		"おおきくなったら たびに 出るんだ。",
		"しろの ほうは 見ちゃ だめって いわれてる。",
	],
}

const FOLK_ROLES := ["keeper", "trader", "elder", "child"]


static func generate(rng: DetRng, danger: int, tileset: String) -> TownMap:
	var map := TownMap.new(MAP_W, MAP_H)
	map.biome = tileset
	map.town_name = "%s%s" % [
		NAME_HEAD[rng.range_i(0, NAME_HEAD.size() - 1)],
		NAME_TAIL[rng.range_i(0, NAME_TAIL.size() - 1)],
	]

	# 外周を壁で囲い、中を地面にする。町は 1 枚の広場。
	for y in MAP_H:
		for x in MAP_W:
			var edge := x == 0 or y == 0 or x == MAP_W - 1 or y == MAP_H - 1
			map.set_tile(x, y, TownMap.T_WALL if edge else TownMap.T_GROUND)

	# 石畳を少し混ぜる。一色だと広場が板に見えるが、
	# 撒きすぎると瓦礫だらけの廃墟になる（40 個は多すぎた）。
	for _i in 12:
		map.set_tile(
			rng.range_i(2, MAP_W - 3), rng.range_i(2, MAP_H - 3), TownMap.T_GROUND_ALT
		)

	# 建物を 2 つ置く（宿と店）。中は入れないので、壁の塊 + 入口 1 マス。
	map.inn_pos = _place_building(map, Vector2i(4, 3), TownMap.T_DOOR)
	map.shop_pos = _place_building(map, Vector2i(MAP_W - 10, 3), TownMap.T_SHOP)

	# 出口は下辺の中央。入ってきた向きと合うので迷わない。
	map.exit_pos = Vector2i(MAP_W / 2, MAP_H - 2)
	map.set_tile(map.exit_pos.x, map.exit_pos.y, TownMap.T_EXIT)
	map.start_pos = map.exit_pos + Vector2i.UP

	_place_folk(map, rng, danger)
	return map


## 建物 1 つ。5x4 の塊を置き、下辺の中央を入口にする。
static func _place_building(map: TownMap, at: Vector2i, entrance: int) -> Vector2i:
	for y in range(at.y, at.y + 4):
		for x in range(at.x, at.x + 6):
			map.set_tile(x, y, TownMap.T_WALL)
	var door := Vector2i(at.x + 2, at.y + 3)
	map.set_tile(door.x, door.y, entrance)
	# 看板を入口の隣に。何の建物かが近づく前に分かる。
	map.set_tile(door.x + 2, door.y, TownMap.T_SIGN)
	return door


## 町人を置く。役を散らし、**必ず歩ける場所の隣**に立たせる。
static func _place_folk(map: TownMap, rng: DetRng, danger: int) -> void:
	var spots: Array[Vector2i] = []
	for _i in 60:
		if spots.size() >= FOLK_ROLES.size():
			break
		var at := Vector2i(rng.range_i(2, MAP_W - 3), rng.range_i(8, MAP_H - 3))
		if map.get_tile(at.x, at.y) not in [TownMap.T_GROUND, TownMap.T_GROUND_ALT]:
			continue
		if at == map.start_pos or at == map.exit_pos:
			continue
		var near := false
		for other in spots:
			if absi(other.x - at.x) + absi(other.y - at.y) < 4:
				near = true
				break
		if near:
			continue
		spots.append(at)

	for i in spots.size():
		var role := String(FOLK_ROLES[i % FOLK_ROLES.size()])
		var pool: Array = LINES[role]
		map.folk[spots[i]] = {
			"kind": role,
			"line": String(pool[rng.range_i(0, pool.size() - 1)]),
			"danger": danger,
		}
