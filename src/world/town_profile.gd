class_name TownProfile
extends RefCounted

const TownDialogue := preload("res://src/world/town_dialogue.gd")

## 間取りの型（P-4）。**台詞を読まなくても、形で町が違うと分かるように。**
##
## それまでは生業も支配も違うのに、どの町も「広場の左右に横長の建物を 1 棟ずつ」
## だった。色と人物は変わっても**輪郭が同じ**なので、並べて見ると同じ町に見える。
## 内部指紋 50 通りという関門は座標差を見ていたが、
## **人が見て別の町と分かるか**は見ていなかった。
##
##   market     市場広場型   … 広場が主役。2 棟が広場へ face する
##   waystation 街道宿場型   … 主街路沿いに縦に並ぶ。入口寄りと奥
##   workshop   工房街型     … 2 棟をひと塊に。向かいが作業場（空地）
##   terrace    段丘・水辺型 … 対角へ離す。あいだに帯（水辺・段丘）が通る
const LAYOUTS := ["market", "waystation", "workshop", "terrace"]

## 生業ごとの、取りうる型の組。**生業だけでは足りない。**
##
## 生業は生物相で絞られるので、1 つの世界（同じような土地）では 4 種類ほどしか
## 出ない。生業だけで型を決めると、**その世界の町が 1〜2 種類の形に偏る**
## （実際、洞の生物相では 200 町のうち 149 が同じ型になった）。
##
## そこで**生業と支配の 2 要素**で決める ―― 生業が「どんな土地の使い方か」を、
## 支配が「まとまりの厳しさ」を決める、という筋。乱数は引かない。
const LAYOUT_BY_INDUSTRY := {
	"trade": ["market", "waystation"],
	"guild": ["market", "workshop"],
	"council": ["market", "terrace"],
	"pilgrimage": ["waystation", "market"],
	"ferry": ["waystation", "terrace"],
	"watch": ["waystation", "workshop"],
	"imperial_bureau": ["waystation", "market"],
	"mining": ["workshop", "terrace"],
	"workshop": ["workshop", "market"],
	"imperial_supply": ["workshop", "waystation"],
	"farming": ["terrace", "market"],
	"beast_ranch": ["terrace", "waystation"],
}

## 支配のうち、**引き締まった側**（1 つ目の型を採る）。
## それ以外は緩い側として 2 つ目を採る。
const TIGHT_RULERS := ["council", "watch"]


static func layout_family(industry_id: String, ruler_id: String = "") -> String:
	if not LAYOUT_BY_INDUSTRY.has(industry_id):
		return "market"
	var pair: Array = LAYOUT_BY_INDUSTRY[industry_id]
	return String(pair[0] if ruler_id in TIGHT_RULERS else pair[1])

## 町の意味を、間取りより先に決める設定。
##
## 生業・支配・問題・目印を別々の後付け抽選にすると、鉱山町なのに農夫だけが
## 立ち、帝国の役所があるのに警備がいない、といった食い違いが生まれる。
## ここで一組を確定し、TownGenerator は同じ組から景観・役・台詞を引く。

const INDUSTRIES := [
	{
		"id": "farming", "role": "farmer",
		"landmarks": ["great_tree", "well"],
	},
	{
		"id": "mining", "role": "miner",
		"landmarks": ["forge", "bell"],
	},
	{
		"id": "trade", "role": "merchant",
		"landmarks": ["banner", "well"],
	},
	{
		"id": "workshop", "role": "mechanic",
		"landmarks": ["gear", "forge"],
	},
	{
		"id": "pilgrimage", "role": "pilgrim",
		"landmarks": ["shrine", "bell"],
	},
	{
		"id": "beast_ranch", "role": "beastkeeper",
		"landmarks": ["pen", "great_tree"],
	},
	{
		"id": "ferry", "role": "ferryman",
		"landmarks": ["well", "banner"],
	},
	{
		"id": "imperial_supply", "role": "imperial_officer",
		"landmarks": ["gear", "banner"],
	},
]

const RULERS := [
	{
		"id": "council", "role": "scribe",
	},
	{
		"id": "watch", "role": "guard",
	},
	{
		"id": "guild", "role": "merchant",
	},
	{
		"id": "imperial_bureau", "role": "imperial_officer",
	},
]

const PROBLEMS := [
	{
		"id": "shortage", "role": "refugee",
	},
	{
		"id": "broken_road", "role": "scout",
	},
	{
		"id": "sickness", "role": "healer",
	},
	{
		"id": "requisition", "role": "imperial_officer",
	},
	{
		"id": "beast_attacks", "role": "beastkeeper",
	},
	{
		"id": "failing_mine", "role": "miner",
	},
	{
		"id": "lost_records", "role": "scribe",
	},
	{
		"id": "dry_well", "role": "farmer",
	},
]

var industry_id := ""

## 間取りの型（P-4）。生業から決まるので、**同じ生業なら同じ形**になる。
var layout := "market"
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
	profile.industry_line = _pick_line(rng, "industries", industry)
	profile.layout = layout_family(profile.industry_id, profile.ruler_id)
	profile.problem_line = _pick_line(rng, "problems", problem)
	profile.ruler_line = _pick_line(rng, "rulers", ruler)
	return profile


static func _pick_line(
	rng: DetRng, group: String, source: Dictionary
) -> String:
	var lines: Array = TownDialogue.profile_lines(group, String(source.get("id", "")))
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
