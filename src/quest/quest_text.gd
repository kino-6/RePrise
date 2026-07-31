class_name QuestNarrativeText
extends RefCounted

const WritingQuality := preload("res://src/game/writing_quality.gd")

## クエストの表示文だけを作り、AI の候補を項目ごとに検算する。
##
## 構造は QuestGenerator が既に確定している。ここが返すものには site id、
## 依存関係、正解、効果値を入れないため、AI の文章でゲームは変わらない。

const WORLD_HEAD := [
	"薄明", "玻璃", "風紋", "白樺", "遠雷", "灰雨", "水鏡", "星影",
]
const WORLD_TAIL := [
	"の世界", "の辺土", "の環", "の島", "の野",
]
const BOSS_HEAD := [
	"眠れる", "錆びた", "影負う", "冠なき", "灰まとう", "遠き",
]
const BOSS_TAIL := [
	"主", "番人", "王", "巨躯", "司祭", "獣",
]

const QUEST_TITLES := {
	QuestGenerator.THREE_SEALS: "三つの封",
	QuestGenerator.RELAY_FLAME: "継がれる火",
	QuestGenerator.TWO_PACTS: "二つの盟約",
	QuestGenerator.TRUE_RELIC: "まことの遺物",
}

const OBJECTIVE_TEXT := {
	"seal_low": ["根環の封", "城を縛る低地の封を解く。"],
	"seal_mid": ["雷晶の封", "城を縛る中地の封を解く。"],
	"seal_high": ["冠火の封", "城を縛る高地の封を解く。"],
	"relay_source": ["眠る火種", "低地の洞から火種を取り戻す。"],
	"relay_safe": ["鎮めの炉", "町の炉で火種を安全に整える。"],
	"relay_risky": ["荒ぶる炉", "洞の試練で火種を強く鍛える。"],
	"relay_beacon": ["空の灯台", "高地の洞で城への灯をともす。"],
	"pact_low": ["苔の守り", "低地の守護者と盟約を結ぶ。"],
	"pact_mid": ["嵐の守り", "中地の守護者と盟約を結ぶ。"],
	"pact_high": ["鋼の守り", "高地の守護者と盟約を結ぶ。"],
	"relic_low": ["苔の遺物", "低地の候補を確かめる。"],
	"relic_mid": ["月の遺物", "中地の候補を確かめる。"],
	"relic_high": ["灰の遺物", "高地の候補を確かめる。"],
}

const RUMOR_FLAVOR := [
	"旅人も同じ光を見たそうだ。",
	"古い道標にも印が残っている。",
	"夜になると遠くで音がする。",
	"この話を知る者はもう少ない。",
	"近道ほど魔物が多いらしい。",
	"帰った者は皆同じ方角を指した。",
]

const BAND_NAMES := {
	QuestGenerator.LOW: "低い",
	QuestGenerator.MID: "中ほど",
	QuestGenerator.HIGH: "高い",
}

const ASPECT_NAMES := {
	"venom": "毒の力",
	"haste": "速さ",
	"armor": "硬い守り",
}

## AI に書かせない語。外部作品の固有語と、思考過程の混入を止める。
const BANNED := [
	"ドラゴンクエスト", "ファイナルファンタジー", "クロノトリガー",
	"メラゾーマ", "ベホマ", "ホイミ", "ケアル", "ファイガ",
	"プロンプト", "思考過程", "システムメッセージ", "JSON",
]


static func fallback(quest: Dictionary, rng: DetRng) -> Dictionary:
	var objective_names: Array[String] = []
	var objective_reasons: Array[String] = []
	var rumor_flavor: Array[String] = []
	for node in quest.get("nodes", []):
		match String(node.get("role", "")):
			"objective":
				var pair: Array = OBJECTIVE_TEXT.get(
					String(node.get("text_key", "")), ["名なき印", "その場所を確かめる。"]
				)
				var fixed_name := String(node.get("fixed_name", ""))
				var fixed_reason := String(node.get("fixed_reason", ""))
				objective_names.append(fixed_name if fixed_name != "" else String(pair[0]))
				objective_reasons.append(
					fixed_reason if fixed_reason != "" else String(pair[1])
				)
			"rumor":
				rumor_flavor.append(String(
					RUMOR_FLAVOR[rng.range_i(0, RUMOR_FLAVOR.size() - 1)]
				))
	return {
		"world_name": "%s%s" % [
			WORLD_HEAD[rng.range_i(0, WORLD_HEAD.size() - 1)],
			WORLD_TAIL[rng.range_i(0, WORLD_TAIL.size() - 1)],
		],
		"quest_title": String(QUEST_TITLES.get(
			String(quest.get("archetype", "")), "名なき道"
		)),
		"boss_name": "%s%s" % [
			BOSS_HEAD[rng.range_i(0, BOSS_HEAD.size() - 1)],
			BOSS_TAIL[rng.range_i(0, BOSS_TAIL.size() - 1)],
		],
		"objective_names": objective_names,
		"objective_reasons": objective_reasons,
		"rumor_flavor": rumor_flavor,
		"rejected": [],
	}


## AI 候補を fallback へ項目単位で上書きする。
## candidate に steps / gate / reward などがあっても読まない。
static func apply_ai(fallback_text: Dictionary, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = fallback_text.duplicate(true)
	var rejected: Array = []

	_replace_scalar(result, candidate, "world_name", 12, rejected)
	_replace_scalar(result, candidate, "quest_title", 14, rejected)
	_replace_scalar(result, candidate, "boss_name", 12, rejected)
	_replace_array(result, candidate, "objective_names", 10, rejected)
	_replace_array(result, candidate, "objective_reasons", 34, rejected)
	_replace_array(result, candidate, "rumor_flavor", 34, rejected)

	# 目的名が重なると、違う場所が同じものに見える。重複した項目だけ戻す。
	var seen := {}
	var names: Array = result.get("objective_names", [])
	var fallback_names: Array = fallback_text.get("objective_names", [])
	for i in names.size():
		var name := String(names[i])
		if seen.has(name):
			rejected.append({"field": "objective_names[%d]" % i, "reason": "duplicate"})
			names[i] = fallback_names[i]
			name = String(names[i])
		seen[name] = true
	result["objective_names"] = names
	result["rejected"] = rejected
	return result


## 攻略に必要な文は Script が組み立てる。
## AI の rumor_flavor はこの後ろへ添えるだけなので、矛盾しても攻略不能にならない。
static func critical_lines(quest: Dictionary, text: Dictionary) -> Array[String]:
	var objective_index := {}
	var objective_nodes: Array = []
	for node in quest.get("nodes", []):
		if String(node.get("role", "")) == "objective":
			objective_index[String(node.get("id", ""))] = objective_nodes.size()
			objective_nodes.append(node)

	var names: Array = text.get("objective_names", [])
	var out: Array[String] = []
	for node in quest.get("nodes", []):
		if String(node.get("role", "")) != "rumor":
			continue
		var target_id := String(node.get("reveals", ""))
		var target_i := int(objective_index.get(target_id, -1))
		var target_name := "その印"
		var target: Dictionary = {}
		if target_i >= 0 and target_i < names.size():
			target_name = String(names[target_i])
			target = objective_nodes[target_i]

		match String(node.get("clue_kind", "")):
			"location":
				var band := String(BAND_NAMES.get(String(target.get("band", "")), "遠い"))
				out.append("%sは %s地の洞にある。" % [target_name, band])
			"choice":
				out.append("火は 町で鎮めるか 洞で鍛えられる。")
			"boss_aspect":
				var aspect := String(ASPECT_NAMES.get(
					String(target.get("boss_aspect", "")), "力"
				))
				out.append("%sを残せば 主に%sが残る。" % [target_name, aspect])
			"false_candidate":
				out.append("%sは まことの遺物ではない。" % target_name)
			_:
				out.append("%sの手掛かりがある。" % target_name)
	return out


static func _replace_scalar(
	result: Dictionary, candidate: Dictionary, field: String, limit: int, rejected: Array
) -> void:
	if not candidate.has(field):
		return
	var value := String(candidate.get(field, "")).strip_edges()
	var reason := _invalid_reason(value, limit)
	if reason == "":
		reason = WritingQuality.ai_reason(value, field)
	if reason == "":
		result[field] = value
	else:
		rejected.append({"field": field, "reason": reason})


static func _replace_array(
	result: Dictionary, candidate: Dictionary, field: String, limit: int, rejected: Array
) -> void:
	var proposed = candidate.get(field, null)
	if not proposed is Array:
		if candidate.has(field):
			rejected.append({"field": field, "reason": "not_array"})
		return
	var current: Array = result.get(field, [])
	var count := mini(current.size(), proposed.size())
	for i in count:
		var value := String(proposed[i]).strip_edges()
		var reason := _invalid_reason(value, limit)
		if reason == "":
			reason = WritingQuality.ai_reason(value, field)
		if reason == "":
			current[i] = value
		else:
			rejected.append({"field": "%s[%d]" % [field, i], "reason": reason})
	result[field] = current


static func _invalid_reason(value: String, limit: int) -> String:
	if value == "":
		return "empty"
	if value.length() > limit:
		return "too_long"
	if "\n" in value or "\r" in value:
		return "line_break"
	for banned in BANNED:
		if banned in value:
			return "banned"
	for i in value.length():
		var code := value.unicode_at(i)
		if code >= 0x30 and code <= 0x39:
			return "number"
		if code >= 0xFF10 and code <= 0xFF19:
			return "number"
		if (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A):
			return "latin"
		if value[i] in ["{", "}", "[", "]", "<", ">"]:
			return "symbol"
	return ""
