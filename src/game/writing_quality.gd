extends RefCounted

## 実行時AIの文章を「文字数は正しいが、意味が通らない」状態で通さない。
##
## これは創作の採点器ではない。ゲーム内で特に事故になりやすい
## AI由来の癖だけを、保守的に検出する。落ちた項目は既存の手書き文へ戻る。

const OPAQUE_PHRASES := [
	"名もない",
	"誰も知らない",
	"何かが",
	"何かの",
	"どこかで",
	"すべては",
	"運命に導か",
	"世界が呼ん",
	"世界がささや",
	"意味のない",
	"理由もなく",
	"それだけだ",
	"見届けよ",
	"無数の明日",
	"世界の綴じ目",
	"あり得た未来",
]

const ARCHAIC_PHRASES := [
	"せぬ",
	"であろう",
	"なのだ",
	"わしら",
	"おぬし",
	"そなた",
	"つかん",
]

const ABSTRACT_WORDS := [
	"記憶",
	"残響",
	"運命",
	"真実",
	"存在",
	"世界",
	"未来",
	"過去",
	"魂",
	"希望",
	"絶望",
]

const OBSERVABLE_WORDS := [
	"道", "橋", "水", "川", "火", "煙", "雨", "雪", "風", "土", "石",
	"木", "草", "鐘", "音", "声", "匂い", "足跡", "灯", "光", "影", "荷",
	"扉", "門", "壁", "塔", "井戸", "屋根", "車輪", "歯車", "獣", "鳥",
	"人", "兵", "商人", "旅人",
]

const ACTOR_ENDINGS := [
	"人", "者", "師", "兵", "士", "守", "番", "工", "官", "員", "長",
	"商人", "旅人", "猟師", "薬師", "斥候", "技師", "巡礼者", "御者",
	"子ども", "少年", "少女", "住民", "老人",
]

## 音や声そのものを、人の動作「静かにしている」の主語にしない。
## 「鳥は静かにしている」は成立するが、「さえずりは静かにしている」は
## 主語と述語の組み合わせが崩れている。単語の禁止ではなく係り受けの事故を止める。
const SOUND_SUBJECTS := ["音", "声", "響き", "さえずり", "足音", "物音", "鳴き声"]


static func ai_reason(text: String, field: String = "") -> String:
	var normalized := text.strip_edges()
	if normalized == "":
		return "empty"
	if " " in normalized or "　" in normalized:
		return "spacing"
	if "…" in normalized or "..." in normalized:
		return "ellipsis"
	for phrase in OPAQUE_PHRASES:
		if phrase in normalized:
			return "opaque"
	for phrase in ARCHAIC_PHRASES:
		if phrase in normalized:
			return "archaic"

	var abstract_count := 0
	for word in ABSTRACT_WORDS:
		if word in normalized:
			abstract_count += 1
	if abstract_count >= 3:
		return "abstract_stack"

	if field == "actor" and not _ends_with_any(normalized, ACTOR_ENDINGS):
		return "actor_not_role"
	if field == "flavor" and not _contains_any(normalized, OBSERVABLE_WORDS):
		return "flavor_not_observable"
	if field == "flavor" and "静かにしている" in normalized:
		for subject in SOUND_SUBJECTS:
			if "%sは" % subject in normalized or "%sが" % subject in normalized:
				return "predicate_mismatch"
	return ""


static func _contains_any(text: String, words: Array) -> bool:
	for word in words:
		if String(word) in text:
			return true
	return false


static func _ends_with_any(text: String, words: Array) -> bool:
	for word in words:
		if text.ends_with(String(word)):
			return true
	return false
