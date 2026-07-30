class_name TownProfile
extends RefCounted

## 町の意味を、間取りより先に決める設定。
##
## 生業・支配・問題・目印を別々の後付け抽選にすると、鉱山町なのに農夫だけが
## 立ち、帝国の役所があるのに警備がいない、といった食い違いが生まれる。
## ここで一組を確定し、TownGenerator は同じ組から景観・役・台詞を引く。

const INDUSTRIES := [
	{
		"id": "farming", "role": "farmer",
		"landmarks": ["great_tree", "well"],
		"lines": [
			"畑は この町の いのちだ。",
			"実りを 守るため ここに のこっている。",
		],
	},
	{
		"id": "mining", "role": "miner",
		"landmarks": ["forge", "bell"],
		"lines": [
			"山から 鉄を おろして 暮らしている。",
			"坑道の 音で その日の 稼ぎが わかる。",
		],
	},
	{
		"id": "trade", "role": "merchant",
		"landmarks": ["banner", "well"],
		"lines": [
			"街道が 生きていれば 町も 生きる。",
			"四つの土地の 品が ここで まじる。",
		],
	},
	{
		"id": "workshop", "role": "mechanic",
		"landmarks": ["gear", "forge"],
		"lines": [
			"古い からくりを 直して 食べている。",
			"歯車の 音が この町の 朝の鐘だ。",
		],
	},
	{
		"id": "pilgrimage", "role": "pilgrim",
		"landmarks": ["shrine", "bell"],
		"lines": [
			"門を めざす者が ここで 足を 休める。",
			"旅人の 祈りが この町を 支えている。",
		],
	},
	{
		"id": "beast_ranch", "role": "beastkeeper",
		"landmarks": ["pen", "great_tree"],
		"lines": [
			"けものと 荷を 運ぶのが ここの仕事だ。",
			"人より先に けものが 道の危険を 知る。",
		],
	},
	{
		"id": "ferry", "role": "ferryman",
		"landmarks": ["well", "banner"],
		"lines": [
			"水路が 途切れても 舟の技は のこる。",
			"橋の代わりに 遠回りの道を 教えている。",
		],
	},
	{
		"id": "imperial_supply", "role": "imperial_officer",
		"landmarks": ["gear", "banner"],
		"lines": [
			"帝国の 補給路は ここで 数え直す。",
			"人も 荷も 記録なしには 通さん。",
		],
	},
]

const RULERS := [
	{
		"id": "council", "role": "scribe",
		"lines": [
			"寄り合いで 決めたことは ここへ 記す。",
			"この町に 王はいない。記録が 約束になる。",
		],
	},
	{
		"id": "watch", "role": "guard",
		"lines": [
			"見張り台から 街道を 交代で 見ている。",
			"門を 閉じる時刻は わたしたちが 決める。",
		],
	},
	{
		"id": "guild", "role": "merchant",
		"lines": [
			"倉の鍵を 持つ者が 町を 動かしている。",
			"荷の順番を 守れば 争いは 起きない。",
		],
	},
	{
		"id": "imperial_bureau", "role": "imperial_officer",
		"lines": [
			"この町は 帝国の 規則で 動く。",
			"門と倉は すべて 管理局の ものだ。",
		],
	},
]

const PROBLEMS := [
	{
		"id": "shortage", "role": "refugee",
		"lines": [
			"食べ物が 足りない。よそ者まで 回らない。",
			"倉は あるのに 中身が ほとんど ない。",
		],
	},
	{
		"id": "broken_road", "role": "scout",
		"lines": [
			"北の道が 崩れた。印のある方へ 回れ。",
			"街道の 半分は もう 使えない。",
		],
	},
	{
		"id": "sickness", "role": "healer",
		"lines": [
			"水が 変わってから 熱を出す者が 増えた。",
			"宿では まず 手と傷を 洗ってくれ。",
		],
	},
	{
		"id": "requisition", "role": "imperial_officer",
		"lines": [
			"物資は 帝国に 先に 持っていかれる。",
			"次の 徴発で この町の 倉は 空になる。",
		],
	},
	{
		"id": "beast_attacks", "role": "beastkeeper",
		"lines": [
			"飼ったけものまで 夜になると おびえる。",
			"柵の外を 大きな足跡が 一周している。",
		],
	},
	{
		"id": "failing_mine", "role": "miner",
		"lines": [
			"坑道が 沈み、奥の支柱が もたない。",
			"掘れる場所より 埋まる場所の方が 多い。",
		],
	},
	{
		"id": "lost_records", "role": "scribe",
		"lines": [
			"町の 古い記録が 一夜で 消えた。",
			"昨日まで あった名前を だれも 思い出せない。",
		],
	},
	{
		"id": "dry_well", "role": "farmer",
		"lines": [
			"井戸の底が 見えるほど 水が 減った。",
			"雨を 待つだけでは 畑を 守れない。",
		],
	},
]

var industry_id := ""
var ruler_id := ""
var problem_id := ""
var landmark_id := ""
var biome_id := ""
var danger := 1
var industry_role := ""
var ruler_role := ""
var problem_role := ""
var industry_line := ""
var ruler_line := ""
var problem_line := ""


static func cycle_size() -> int:
	return INDUSTRIES.size()


static func generate(
	rng: DetRng, town_index: int, world_variant: int,
	biome: String, danger_value: int
) -> TownProfile:
	var profile := TownProfile.new()
	var industry: Dictionary = INDUSTRIES[
		posmod(world_variant + town_index, INDUSTRIES.size())
	]
	var problem: Dictionary = PROBLEMS[
		posmod(world_variant * 3 + town_index * 5, PROBLEMS.size())
	]
	var ruler_index := posmod(world_variant + town_index * 3, RULERS.size())
	if String(industry.id) == "imperial_supply":
		ruler_index = 3
	elif danger_value >= 7 and rng.chance(35):
		ruler_index = 1
	var ruler: Dictionary = RULERS[ruler_index]
	var landmarks: Array = industry.get("landmarks", ["well"])

	profile.industry_id = String(industry.id)
	profile.problem_id = String(problem.id)
	profile.ruler_id = String(ruler.id)
	profile.landmark_id = String(landmarks[rng.range_i(0, landmarks.size() - 1)])
	profile.biome_id = biome
	profile.danger = danger_value
	profile.industry_role = String(industry.role)
	profile.problem_role = String(problem.role)
	profile.ruler_role = String(ruler.role)
	profile.industry_line = _pick_line(rng, industry)
	profile.problem_line = _pick_line(rng, problem)
	profile.ruler_line = _pick_line(rng, ruler)
	return profile


static func _pick_line(rng: DetRng, source: Dictionary) -> String:
	var lines: Array = source.get("lines", [])
	return "" if lines.is_empty() else String(lines[rng.range_i(0, lines.size() - 1)])


func signature() -> String:
	return "%s:%s:%s" % [industry_id, problem_id, landmark_id]


func roles() -> Array[String]:
	var result: Array[String] = []
	for role in [industry_role, ruler_role, problem_role]:
		if role != "" and role not in result:
			result.append(role)
	return result


func line_for(role: String) -> String:
	# 問題の台詞を最優先する。町の現在形が、生業の一般論より先に見えるため。
	if role == problem_role:
		return problem_line
	if role == industry_role:
		return industry_line
	if role == ruler_role:
		return ruler_line
	return ""


func to_dict() -> Dictionary:
	return {
		"industry": industry_id,
		"ruler": ruler_id,
		"problem": problem_id,
		"landmark": landmark_id,
		"biome": biome_id,
		"danger": danger,
	}
