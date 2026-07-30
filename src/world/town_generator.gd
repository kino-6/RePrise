class_name TownGenerator
extends RefCounted

## 町の中を作る。
##
## 洞と違って**迷わせない**のが目的。町は目的地であって迷路ではないので、
## 中央に広場を置き、宿・店・出口を広場から必ず見える位置に並べる。
## 迷う町は、用があって寄った人間にとってただの足止めになる。
##
## 乱数は渡された DetRng だけ。同じ世界の同じ町は毎回同じ形になる。

## 町の名の作り方。地形の語 + 場所の語。
## AI に書かせる前の土台で、これだけでも毎回違う名前が出る
## （docs/quest_design.md の「テンプレート語彙表 × DetRng」がこれ）。
static var NAME_HEAD: Array = Vocabulary.nested(
	"town_names", "", "head",
	["かぜ", "いずみ", "しらかば", "あかつき", "みなも", "とうげ"]
)
static var NAME_TAIL: Array = Vocabulary.nested(
	"town_names", "", "tail", ["の里", "の宿場", "の町"]
)

## 町人の一言。役どころごとに分ける。
##
## **同じ人物像を並べない。** 全員が世間話をすると町が背景になる。
## 宿の主・店番・物知り・子ども、と役を散らすと、町が人の居る場所になる。
## 町の人の一言。**役ごとに言うことを変える。**
##
## 全員が世間話をすると町が背景になる。役が 17 になったので、
## 「その役だから言えること」を書き分けた ―― 鍛冶は道具の話、船頭は水路の話、
## 難民は外の世界の話。**同じ人物像を並べない**のがここの狙い。
##
## 物知り（elder）だけは決まり文句ではなく、そのときの手掛かりを話す
## （封の在り処。`ExploreView.rumor` から差し込む）。
const LINES := {
	"innkeeper": [
		"よく来た。やどは いつでも あいている。",
		"ゆっくり やすんでいくと いい。",
		"となりの みせで そなえを ととのえな。",
	],
	"merchant": [
		"ここらの しなは そろえてある。",
		"おくへ 行くなら やくそうは 多めにな。",
		"かねは 使ってこそ 意味が ある。",
	],
	"elder": [
		"おくの 地は 生きものの たちが ちがう。",
		"ゆきの 地では こおりに つよい ものが 出る。",
		"いそぐ者ほど はやく たおれる。",
	],
	"scout": [
		"ほら穴の おくに なにか あるって。",
		"きたの道は 山で ふさがっている。",
		"人の 通らぬ 道ほど はやい。",
	],
	"guard": [
		"門の そとは わしらの 手に あまる。",
		"夜に 出るなら 灯りを 持て。",
		"この町で もめごとは 起こすな。",
	],
	"blacksmith": [
		"重い得物は つよいが 手番が おそくなる。",
		"刃は 使うほど 手に なじむ。",
		"鉄は うそを つかん。",
	],
	"healer": [
		"どくは 歩くたびに 身を けずる。",
		"たおれる前に 手を 打て。",
		"やくそうを 惜しんで 死ぬ者を 何人も 見た。",
	],
	"farmer": [
		"ことしは 実りが すくない。",
		"畑の むこうに 光る ものを 見た。",
		"雨が 降らんのは 地が 変わったからだ。",
	],
	"miner": [
		"洞の 底には 古い ものが ねむっている。",
		"岩の 音を 聞け。ちがう音が したら もどれ。",
		"掘るほど 空気が わるくなる。",
	],
	"ferryman": [
		"水は わたれん。まわり道を さがしな。",
		"沼は 見た目より 深い。",
		"むかしは この先に 橋が あった。",
	],
	"mechanic": [
		"からくりは 直せば また 動く。",
		"あの 音は 帝国の ものだ。",
		"歯車が 合わねば 力は 出ん。",
	],
	"scribe": [
		"記録に のこらぬ ものは 無かったことに なる。",
		"この町の 名も、いずれ わすれられる。",
		"あんたの 旅も 書きとめておこう。",
	],
	"pilgrim": [
		"封は 世界の ふたを おさえている。",
		"どこへ 行っても 空は おなじだ。",
		"歩くことが いのりに なる。",
	],
	"refugee": [
		"むこうの 町は もう ない。",
		"にげてきた。それだけだ。",
		"帰る場所が ないのは、道が ないより つらい。",
	],
	"performer": [
		"うたは 世界を こえて のこるらしい。",
		"銭を くれたら もう一節。",
		"かなしい話ほど よく はやる。",
	],
	"beastkeeper": [
		"けものにも 帰る場所が ある。",
		"こいつは 人より よく 道を おぼえる。",
		"むやみに 手を 出すな。かむぞ。",
	],
	"imperial_officer": [
		"通行の 記録を 取らせてもらう。",
		"帝国の 道は 帝国の ものだ。",
		"詮索は せぬ。おまえも するな。",
	],
}

## 町に立つ役。**その町の生物相と危険度で顔ぶれが変わる。**
## 全部の町に同じ 4 人が立っていると、町が変わった気がしない。
const FOLK_ROLES := [
	"innkeeper", "merchant", "elder", "scout", "guard", "blacksmith",
	"healer", "farmer", "miner", "ferryman", "mechanic", "scribe",
	"pilgrim", "refugee", "performer", "beastkeeper", "imperial_officer",
]

## どの町にも必ず居る役（宿・店・物知り）。用が足せることを保証する。
const CORE_ROLES := ["innkeeper", "merchant", "elder"]

## 生物相に合う役。土地の顔を出すためのもの。
const BIOME_ROLES := {
	"wetland": ["ferryman", "healer"],
	"snowfield": ["pilgrim", "refugee"],
	"volcano": ["blacksmith", "mechanic"],
	"badland": ["miner", "refugee"],
	"desert": ["ferryman", "pilgrim"],
	"grassland": ["farmer", "performer"],
	"forest": ["beastkeeper", "scout"],
}

## 何人立たせるか。町の広さで変える。
const FOLK_MIN := 4
const FOLK_MAX := 7


## 町の広さ。生物相と危険度で少し振る（辺境の町は小さい）。
const SIZE_MIN := Vector2i(20, 14)
const SIZE_MAX := Vector2i(30, 20)


static func generate(rng: DetRng, danger: int, tileset: String) -> TownMap:
	# **寸法から振る。** 全部同じ大きさだと、間取りを変えても同じ町に見える。
	var w := rng.range_i(SIZE_MIN.x, SIZE_MAX.x)
	var h := rng.range_i(SIZE_MIN.y, SIZE_MAX.y)
	var map := TownMap.new(w, h)
	map.biome = tileset
	map.town_name = "%s%s" % [
		NAME_HEAD[rng.range_i(0, NAME_HEAD.size() - 1)],
		NAME_TAIL[rng.range_i(0, NAME_TAIL.size() - 1)],
	]

	for y in h:
		for x in w:
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			map.set_tile(x, y, TownMap.T_WALL if edge else TownMap.T_GROUND)

	# 石畳。撒きすぎると瓦礫の廃墟になる。
	for _i in rng.range_i(8, 18):
		map.set_tile(rng.range_i(2, w - 3), rng.range_i(2, h - 3), TownMap.T_GROUND_ALT)

	# **出口は 4 辺のどれか。** 下辺固定だと、入るたびに同じ向きから同じ景色になる。
	map.exit_pos = _place_exit(map, rng)
	map.start_pos = _inward_from(map, map.exit_pos)

	# 建物は「区画」に置く。出口から遠い区画を宿と店に使い、残りは空き地。
	#
	# 迷わせないのは「出口が分かること」であって「毎回同じ間取り」ではない。
	# 固定座標で実装したのが誤りで、到達性は verify（テスト）で守れば
	# 形は自由に振れる。
	var plots := _plots(map, rng)
	var placed := 0
	for plot in plots:
		if placed >= 2:
			break
		var door := _place_building(map, plot, TownMap.T_DOOR if placed == 0 else TownMap.T_SHOP)
		if door.x < 0:
			continue
		if placed == 0:
			map.inn_pos = door
		else:
			map.shop_pos = door
		placed += 1

	# 万一 2 つ置けなかったときの保険（詰ませない）。
	if map.inn_pos.x < 0:
		map.inn_pos = _fallback_door(map, TownMap.T_DOOR)
	if map.shop_pos.x < 0:
		map.shop_pos = _fallback_door(map, TownMap.T_SHOP)

	_place_folk(map, rng, danger)
	return map


## 出口を 4 辺のどれかに開ける。
## 出入口。**南辺の中央に固定する。**
##
## 前は四辺から乱数で選んでいたが、変える理由が無かった。町ごとに出口が飛ぶと
##
##   * 入った直後にどちらを向けばいいか分からない（毎回探し直す）、
##   * 出たつもりが別の辺で、世界地図の上を行ったり来たりする
##     （自動プレイが世界↔町を 8 回続けて往復した）、
##   * 「戻る場所」が覚えられないので町が土地として頭に残らない、
##
## という害だけがあった。町ごとの違いは**入口より先**の街路と地区で作る（C-8）。
## 画面の下端中央から入るのは、往年の RPG が一貫してそうしていた形でもある。
static func _place_exit(map: TownMap, _rng: DetRng) -> Vector2i:
	@warning_ignore("integer_division")
	var at := Vector2i(map.width / 2, map.height - 1)
	map.set_tile(at.x, at.y, TownMap.T_EXIT)
	return at


## 出口の 1 マス内側（入ってきて最初に立つ場所）。
##
## 出口は南辺なので**必ず真上**。近傍の並び順に頼ると、町の形によって
## 左右へずれて「入って正面が壁」になる。
static func _inward_from(map: TownMap, at: Vector2i) -> Vector2i:
	var inside := at + Vector2i(0, -1)
	if inside.y > 0:
		return inside
	@warning_ignore("integer_division")
	return Vector2i(map.width / 2, map.height / 2)


## 建物を置ける区画。出口から遠い順に返す（入口の真横に宿が建たない）。
static func _plots(map: TownMap, rng: DetRng) -> Array[Rect2i]:
	var plots: Array[Rect2i] = []
	for _try in 40:
		var bw := rng.range_i(5, 7)
		var bh := rng.range_i(3, 4)
		var x := rng.range_i(2, maxi(map.width - bw - 3, 2))
		var y := rng.range_i(2, maxi(map.height - bh - 4, 2))
		var plot := Rect2i(x, y, bw, bh)
		# 出口と、既に取った区画から離す（間を通れるように 2 マスあける）
		if plot.grow(2).has_point(map.exit_pos) or plot.grow(2).has_point(map.start_pos):
			continue
		var clash := false
		for other in plots:
			if other.grow(2).intersects(plot):
				clash = true
				break
		if clash:
			continue
		plots.append(plot)
	plots.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		var da := absi(a.position.x - map.exit_pos.x) + absi(a.position.y - map.exit_pos.y)
		var db := absi(b.position.x - map.exit_pos.x) + absi(b.position.y - map.exit_pos.y)
		return da > db)
	return plots


## 区画が取れなかったときの保険。壁際に扉だけ置く。
static func _fallback_door(map: TownMap, kind: int) -> Vector2i:
	for y in range(2, map.height - 2):
		for x in range(2, map.width - 2):
			if map.get_tile(x, y) == TownMap.T_GROUND and Vector2i(x, y) != map.start_pos:
				map.set_tile(x, y, kind)
				return Vector2i(x, y)
	return Vector2i(map.width / 2, map.height / 2)


## 建物 1 つ。区画を壁で埋め、下辺の中央を入口にする。
static func _place_building(map: TownMap, plot: Rect2i, entrance: int) -> Vector2i:
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			map.set_tile(x, y, TownMap.T_WALL)
	var door := Vector2i(plot.position.x + plot.size.x / 2, plot.end.y - 1)
	map.set_tile(door.x, door.y, entrance)
	# 看板を入口の隣に。何の建物かが近づく前に分かる。
	var sign_at := Vector2i(door.x + 2, door.y)
	if sign_at.x < plot.end.x:
		map.set_tile(sign_at.x, sign_at.y, TownMap.T_SIGN)
	return door


## 町人を置く。
##
## **必ず居る役 → 土地に合う役 → 残りから**の順で選ぶ。
## 用（宿・店・手掛かり）が足せることを先に保証し、そのうえで顔ぶれを振る。
static func _place_folk(map: TownMap, rng: DetRng, danger: int) -> void:
	var biome := String(map.biome)
	var roles: Array[String] = []
	roles.append_array(CORE_ROLES)
	for role in BIOME_ROLES.get(biome, []):
		if String(role) not in roles:
			roles.append(String(role))
	var rest: Array = FOLK_ROLES.filter(func(r: String) -> bool: return r not in roles)
	rng.shuffle(rest)
	var wanted := rng.range_i(FOLK_MIN, FOLK_MAX)
	for r in rest:
		if roles.size() >= wanted:
			break
		roles.append(String(r))

	var spots: Array[Vector2i] = []
	for _i in 120:
		if spots.size() >= roles.size():
			break
		var at := Vector2i(rng.range_i(2, map.width - 3), rng.range_i(2, map.height - 3))
		if map.get_tile(at.x, at.y) not in [TownMap.T_GROUND, TownMap.T_GROUND_ALT]:
			continue
		if at == map.start_pos or at == map.exit_pos:
			continue
		var near := false
		for other in spots:
			if absi(other.x - at.x) + absi(other.y - at.y) < 3:
				near = true
				break
		if near:
			continue
		# 人は壁と同じく通れない。入口固定で乱数列が変わったとき、宿の前を
		# 町人が塞ぐ町が実際に一つ出た。置くたびに必須地点への道を再検算する。
		map.folk[at] = {}
		var dist := map.distance_field(map.start_pos)
		var routes_kept := true
		for goal in [map.inn_pos, map.shop_pos, map.exit_pos]:
			if dist[goal.y * map.width + goal.x] < 0:
				routes_kept = false
				break
		if not routes_kept:
			map.folk.erase(at)
			continue
		spots.append(at)

	for i in spots.size():
		var role := String(roles[i % roles.size()])
		var pool: Array = LINES.get(role, ["……"])
		map.folk[spots[i]] = {
			"kind": role,
			"line": String(pool[rng.range_i(0, pool.size() - 1)]),
			"danger": danger,
		}
