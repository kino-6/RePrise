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
	T_SNOW = 9,
	T_DESERT = 10,
	T_SWAMP = 11,
	T_LAVA = 12,    ## 通れない。世界で赤いのはここだけなので遠目でも危険と読める
	T_ROAD = 13,    ## 門と城を結ぶ街道。町と洞の枝道も同じタイルを使う
}

## 危険度の上限。今の 10 階ぶんの難度曲線をそのまま使うための数字。
## data/*.json の floor_min / floor_max もこの目盛りで書かれている。
const MAX_DANGER := 10

## 終点の位置。
var castle_pos: Vector2i = Vector2i(-1, -1)

## 門から城までの本街道。枝道は含めない。
##
## 地図上の T_ROAD だけでは町が上書きした箇所を復元できないため、
## 旅程そのものを順序付きで持つ。世界はシードから再生成するので保存対象ではない。
var main_road: Array[Vector2i] = []

## 拠点地（位置 -> {"kind": "town"/"cave"/"castle", "danger": int, "index": int}）。
var sites: Dictionary = {}

## マスごとの危険度 1..MAX_DANGER。海と届かない土地は 0。
var danger: PackedByteArray = PackedByteArray()

## 訪れた拠点地。町の在庫や洞の踏破を覚えておくのに使う。
var visited: Dictionary = {}

## この世界の中核シナリオ（六拍）。`data/story_arcs.json` から生成。
##
## 単発イベントを何件並べても、守りたくなるのは「世界」ではなく
## そこで知った一人・一つの約束なので、ランに 1 本だけ通した筋を持つ。
## 拍の順序は固定、変わるのはどの骨格・どの土地・誰の名前か。
var story: Dictionary = {}

## いま何拍目か（0 から。`story.beats` の添字）。
var story_beat := 0

## 「代償の選択」で選んだ手の id（未選択なら空）。
var story_choice := ""


## 拠点地の id（"town:0" / "cave:2" / "castle:0"）。
## 物語の拍はこの id で土地に結ばれている（座標ではない）。
func site_id_at(pos: Vector2i) -> String:
	var site := site_at(pos)
	if site.is_empty():
		return ""
	return "%s:%d" % [String(site.get("kind", "")), int(site.get("index", 0))]


## id から位置を引く。見つからなければ (-1,-1)。
func pos_of_site_id(id: String) -> Vector2i:
	for pos in sites:
		if site_id_at(pos) == id:
			return pos
	return Vector2i(-1, -1)


## 次に起きる拍（終わっていれば空）。
func next_beat() -> Dictionary:
	var beats: Array = story.get("beats", [])
	return beats[story_beat] if story_beat < beats.size() else {}


## 世界に置いたイベント（位置 -> instantiate() した 1 件）。
##
## 街道は世界のマス、町と洞はその拠点地のマスに置く。
## 骨格は `data/world_events.json`、表層は `DetRng` が選んだもの。
var events: Dictionary = {}


func event_at(pos: Vector2i) -> Dictionary:
	return events.get(pos, {})


## 城の主を守る封。**3 つ解くまで城の扉は開かない。**
##
## 各要素は {"pos": 洞の位置, "band": 帯の名, "danger": int, "name": String,
##          "why": String, "broken": bool}。
## 数（3）と帯（低・中・高）は固定で、名と由来だけが世界ごとに変わる。
## 固定の部分が 1 ラン の長さと難度曲線を保証し、変わる部分が毎回の顔になる。
var seals: Array = []


func seals_broken() -> int:
	var count := 0
	for s in seals:
		if bool(s.get("broken", false)):
			count += 1
	return count


func seals_remaining() -> int:
	return seals.size() - seals_broken()


## その洞に封があるか（無ければ空）。
func seal_at(pos: Vector2i) -> Dictionary:
	for s in seals:
		if s.get("pos") == pos:
			return s
	return {}

## マスごとの生物相（`BIOMES` の添字）。
##
## **地形を「模様」から「情報」に変えるのがこれの役目。**
## 危険度だけだと、遠くが危ないことしか分からない。生物相を持たせると
## 「雪原だから氷の敵が出る」まで読めるようになり、見た目が備えに繋がる。
## 洞の中の地形もここから決まる（雪原の洞は雪原の絵になる）。
var biomes: PackedByteArray = PackedByteArray()

## 生物相の定義。
##
## `tiles` は塗りに使う候補（重複させると出やすくなる）。
## `danger` はその生物相が現れてよい危険度の帯。
## `element` はそこに出る敵の傾向で、`data/monsters.json` の `biomes` と噛み合う。
## `tileset` は洞の中の絵（`assets/tiles/<名前>.png`。無ければ既定に落ちる）。
## 生物相の定義。**名前は `data/vocabulary.json` から読む**ので const にできない
## （造語は差し替えの対象なので、名前だけ外に出す。id と数値は動かさない）。
static var BIOMES: Array = [
	{
		"id": "grassland", "name": Vocabulary.word("biomes", "grassland", "草原"), "danger": [1, 4],
		"tiles": [T_PLAIN, T_PLAIN, T_PLAIN, T_FOREST], "tileset": "grassland",
	},
	{
		"id": "forest", "name": Vocabulary.word("biomes", "forest", "森林"), "danger": [2, 6],
		"tiles": [T_FOREST, T_FOREST, T_PLAIN, T_HILL], "tileset": "grassland",
	},
	{
		"id": "wetland", "name": Vocabulary.word("biomes", "wetland", "湿地"), "danger": [3, 7],
		"tiles": [T_SWAMP, T_SWAMP, T_FOREST, T_PLAIN], "tileset": "wetland",
	},
	{
		"id": "badland", "name": Vocabulary.word("biomes", "badland", "荒地"), "danger": [4, 8],
		"tiles": [T_HILL, T_HILL, T_DESERT, T_MOUNTAIN], "tileset": "dungeon",
	},
	{
		"id": "desert", "name": Vocabulary.word("biomes", "desert", "砂漠"), "danger": [5, 9],
		"tiles": [T_DESERT, T_DESERT, T_HILL, T_MOUNTAIN], "tileset": "dungeon",
	},
	{
		"id": "snowfield", "name": Vocabulary.word("biomes", "snowfield", "雪原"), "danger": [6, 10],
		"tiles": [T_SNOW, T_SNOW, T_HILL, T_MOUNTAIN], "tileset": "snowfield",
	},
	{
		"id": "volcano", "name": Vocabulary.word("biomes", "volcano", "火山"), "danger": [7, 10],
		"tiles": [T_LAVA, T_HILL, T_MOUNTAIN, T_DESERT], "tileset": "volcano",
	},
]


func biome_index_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return clampi(int(biomes[y * width + x]), 0, BIOMES.size() - 1)


func biome_at(x: int, y: int) -> Dictionary:
	return BIOMES[biome_index_at(x, y)]


func biome_id_at(x: int, y: int) -> String:
	return String(biome_at(x, y).get("id", "grassland"))


func biome_name_at(x: int, y: int) -> String:
	return String(biome_at(x, y).get("name", ""))


func set_biome(x: int, y: int, index: int) -> void:
	if in_bounds(x, y):
		biomes[y * width + x] = clampi(index, 0, BIOMES.size() - 1)


func _init(w: int = 0, h: int = 0, _fill: int = 0) -> void:
	super(w, h, T_SEA)
	danger = PackedByteArray()
	danger.resize(w * h)
	danger.fill(0)
	biomes = PackedByteArray()
	biomes.resize(w * h)
	biomes.fill(0)


## 海は渡れない。山と溶岩も越えられない
## （世界に形を与えるのは通れない場所のほう）。
func is_walkable(x: int, y: int) -> bool:
	var t := get_tile(x, y)
	return t != T_SEA and t != T_MOUNTAIN and t != T_LAVA


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


## 地図に載せてよい拠点地。
##
## 町と城は街道の基礎情報として最初から見える。洞は封の言い伝えや
## 地図イベントで所在を知ったものだけを出し、未知の寄り道は探索に残す。
func chart_site_visible(pos: Vector2i) -> bool:
	var kind := String(site_at(pos).get("kind", ""))
	if kind in ["town", "castle"]:
		return true
	if kind != "cave":
		return false
	var seal := seal_at(pos)
	return not seal.is_empty() and (
		bool(seal.get("known", false)) or bool(seal.get("broken", false))
	)


## 地形ごとの遭遇しやすさ（歩数に足す重み）。
##
## 草原は歩きやすく、森と丘は出やすい。全部同じにすると、地形が
## ただの模様になってしまう。**通れる/通れない以外の意味を持たせる。**
func encounter_weight(x: int, y: int) -> int:
	match get_tile(x, y):
		T_PLAIN:
			return 1
		T_DESERT:
			return 2
		T_HILL:
			return 2
		T_SNOW:
			return 3
		T_FOREST:
			return 3
		T_SWAMP:
			return 4  # いちばん歩きにくい。沼を通る道は近くても高くつく
		T_ROAD:
			return 1  # 道は安全地帯ではない。草原と同じ歩数で遭遇判定へ入る
		_:
			return 0  # 拠点地の上は安全


func glyphs() -> Dictionary:
	return { T_SEA: "~", T_PLAIN: ".", T_FOREST: "f", T_HILL: "n", T_MOUNTAIN: "^",
		T_GATE: "G", T_TOWN: "T", T_CAVE: "o", T_CASTLE: "C",
		T_SNOW: "*", T_DESERT: ":", T_SWAMP: "%", T_LAVA: "!", T_ROAD: "=" }
