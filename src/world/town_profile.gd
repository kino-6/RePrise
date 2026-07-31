class_name TownProfile
extends RefCounted

const TownDialogue := preload("res://src/world/town_dialogue.gd")

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
