class_name ChronicleAI
extends Node

const WritingQuality := preload("res://src/game/writing_quality.gd")

## 戦記をローカル AI に書かせる。**接続そのものは `LocalAI` が 1 つだけ持つ。**
##
## 守っている前提（AGENTS.md の不変条件）:
##
##   1. ゲームロジックには一切関与しない。渡すのは `Chronicle.facts_for_llm()` が
##      作る事実の構造だけで、返ってくるのは表示用の文章だけ。
##   2. 失敗しても遅くてもゲームは成立する。呼ぶ前にテンプレート版を表示しておき、
##      届いたら差し替えるだけ。届かなければテンプレートのまま。
##   3. 呼ぶのはラン終了画面だけ。もう操作するものが無い画面なので、
##      数秒の生成待ちが許される唯一の場所。
##
## 決定性には関与しない（文章はセーブにも乱数にも影響しない）。

signal written(lines: PackedStringArray)

## 文章の指示はここに置く。事実の構造（facts）には文体を混ぜない。
##
## 世界の前提（Lore.WORLD）も**事実とは分けて**渡す。前提を facts に混ぜると
## モデルが数値と同じ重さで扱い、設定のほうを膨らませはじめる。
## ここでは「地の文の背景」として置き、書いてよいのは事実だけだと念を押す。
const PROMPT := """あなたは現代の日本語RPGを担当するゲームライターです。
次の事実だけを使って、遠征の記録を3行で書いてください。

%s

制約:
- 各行34文字以内。改行で3行に区切る。
- 1行目に「危険度」とその数値、勝敗を書く。
- 2行目に獲得ゴールドの数値を書く。
- 3行目に一行の結果を書く。
- 自然で簡潔な現代日本語にする。主語と結果を省きすぎない。
- 雰囲気だけの比喩、意味深な独り言、説明のない抽象語を使わない。
- 古風な語尾、不自然な空白、三点リーダーを使わない。
- 事実に無いことを足さない。名前と職業は事実のものを使う。
- 前提は雰囲気づくりにだけ使う。前提から出来事を作らない。
- 見出し・記号・箇条書き・英語・思考過程を書かない。本文3行だけを返す。

事実:
%s
"""

## これを超えたら諦めてテンプレートのままにする。
const TIMEOUT := 8.0

## HTTP は持たない。**ローカル AI の窓口は LocalAI の 1 つだけ。**
## 接続点が 2 つあると、片方だけタイムアウトを直したり、
## 片方だけ think を切り忘れたりする（実際に別々に書いていた）。
var _ai: LocalAI = null
var _expected_facts: Dictionary = {}


func _ready() -> void:
	# **窓口を自分で作らない**（D-3）。作る場所は `LocalAI.create()` の 1 か所。
	_ai = LocalAI.create(self)
	if _ai != null:
		_ai.answered.connect(_on_answered)


## 生成を依頼する。返りは signal で、失敗したときは何も飛ばさない。
## 呼び出し側は既にテンプレート版を表示していること。
func request(summary: Dictionary) -> void:
	_expected_facts = Chronicle.facts_for_llm(summary)
	var facts := JSON.stringify(_expected_facts, "  ")
	_ai.ask(PROMPT % [Lore.WORLD, facts], TIMEOUT, "chronicle")


func _on_answered(text: String) -> void:
	var lines := _clean(text)
	if lines.is_empty():
		return
	written.emit(lines)


## 返ってきた文章を表示に使える形にする。
##
## モデルは指示しても余計なものを付けてくる（見出し、記号、思考の断片）。
## ここで落とす。落とし切れなければ空を返し、テンプレートのままにする。
func _clean(text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		# 箇条書きの記号と見出しを落とす
		line = line.trim_prefix("- ").trim_prefix("・").trim_prefix("* ")
		if line.begins_with("#") or line.begins_with("<"):
			continue
		# 事実の JSON をそのまま返してきた場合も捨てる
		if line.begins_with("{") or line.begins_with("\""):
			continue
		if line.length() > 44:
			line = line.substr(0, 44)
		if WritingQuality.ai_reason(line, "chronicle") != "":
			continue
		lines.append(line)
		if lines.size() >= 3:
			break
	# 途中の一行や、数値・勝敗が事実と一致しない文章は採用しない。
	# 自然な文でも事実を創作していれば、校正済みテンプレートのほうが安全。
	if lines.size() != 3 or not matches_facts(lines, _expected_facts):
		return PackedStringArray()
	return lines


## 文法だけでなく、戦記に必須の事実が本文へ残っているかを見る。
## AIが「城に包まれた」のような未提供の出来事を補っても、数値と勝敗を
## 回収できなければ表示せず、呼び出し元のテンプレートへ戻す。
static func matches_facts(lines: PackedStringArray, facts: Dictionary) -> bool:
	if lines.size() != 3 or facts.is_empty():
		return false
	var text := "\n".join(lines)
	if "危険度%d" % int(facts.get("danger", -1)) not in text:
		return false
	var gold := int(facts.get("gold", 0))
	if gold > 0 and "%dゴールド" % gold not in text:
		return false
	var outcome := String(facts.get("outcome", ""))
	match outcome:
		"全滅":
			if not _contains_any(text, ["全滅", "力尽き", "敗れ", "失われ"]):
				return false
		"生還":
			if not _contains_any(text, ["生還", "守った", "救った", "倒した"]):
				return false
		_:
			if outcome == "" or outcome not in text:
				return false
	return true


static func _contains_any(text: String, words: Array[String]) -> bool:
	for word in words:
		if word in text:
			return true
	return false
