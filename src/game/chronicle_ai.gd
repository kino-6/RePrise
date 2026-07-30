class_name ChronicleAI
extends Node

## 戦記をローカル AI（Ollama）に書かせる。**唯一の LLM 接続点。**
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

const URL := "http://localhost:11434/api/generate"

## 27B は品質が高いが遅い。ラン終了画面で待てるのは数秒なので 8B を既定にする。
const MODEL := "huihui_ai/qwen3-abliterated:8b"

## これを超えたら諦めてテンプレートのままにする。
const TIMEOUT := 8.0

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

var _request: HTTPRequest = null
var _timer := 0.0
var _pending := false


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT
	add_child(_request)
	_request.request_completed.connect(_on_completed)
	set_process(false)


## 生成を依頼する。返りは signal で、失敗したときは何も飛ばさない。
## 呼び出し側は既にテンプレート版を表示していること。
func request(summary: Dictionary) -> void:
	if _pending:
		return
	var facts := JSON.stringify(Chronicle.facts_for_llm(summary), "  ")
	var body := JSON.stringify({
		"model": MODEL,
		"prompt": PROMPT % [Lore.WORLD, facts],
		"stream": false,
		# Qwen3 系は既定で思考ブロックを吐き、num_predict を思考だけで使い切って
		# 本文が空で返ってくる。思考は要らないので切る。
		"think": false,
		# 文体を安定させる。毎回まったく違う調子になると記録に見えない。
		"options": {"temperature": 0.7, "num_predict": 260},
	})
	var error := _request.request(URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		# Ollama が居ないだけ。警告も出さない（これは異常ではない）。
		return
	_pending = true
	_timer = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_timer += delta
	if _timer > TIMEOUT + 1.0:
		_give_up()


func _give_up() -> void:
	_pending = false
	set_process(false)
	_request.cancel_request()


func _on_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	set_process(false)
	if code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var text := String((parsed as Dictionary).get("response", "")).strip_edges()
	var lines := _clean(text)
	if "--ai-debug" in OS.get_cmdline_user_args():
		print("[戦記AI] 生の応答 %d 文字 / 採用 %d 行" % [text.length(), lines.size()])
		print(text)
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
