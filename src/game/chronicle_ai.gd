class_name ChronicleAI
extends Node

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
const PROMPT := """あなたは SFC 期の日本語 RPG の語り部です。
次の事実だけを使って、ラン（潜行）の記録を 3 行で書いてください。

%s

制約:
- 各行 34 文字以内。改行で 3 行に区切る。
- ひらがな主体、漢字は易しいものだけ。
- 事実に無いことを足さない。名前と職業は事実のものを使う。
- 前提は雰囲気づくりにだけ使う。前提から出来事を作らない。
- 見出し・記号・箇条書き・英語・思考過程を書かない。本文 3 行だけを返す。

事実:
%s
"""

## これを超えたら諦めてテンプレートのままにする。
const TIMEOUT := 8.0

## HTTP は持たない。**ローカル AI の窓口は LocalAI の 1 つだけ。**
## 接続点が 2 つあると、片方だけタイムアウトを直したり、
## 片方だけ think を切り忘れたりする（実際に別々に書いていた）。
var _ai: LocalAI = null


func _ready() -> void:
	_ai = LocalAI.new()
	add_child(_ai)
	_ai.answered.connect(_on_answered)


## 生成を依頼する。返りは signal で、失敗したときは何も飛ばさない。
## 呼び出し側は既にテンプレート版を表示していること。
func request(summary: Dictionary) -> void:
	var facts := JSON.stringify(Chronicle.facts_for_llm(summary), "  ")
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
		lines.append(line)
		if lines.size() >= 3:
			break
	return lines
