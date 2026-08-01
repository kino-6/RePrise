class_name LocalAI
extends Node

## ローカル AI（Ollama）への唯一の窓口。
##
## 戦記もクエスト文もここを通す。接続点が 2 つあると、片方だけ
## タイムアウトを直したり、片方だけ think を切り忘れたりする。
##
## 守っている前提（AGENTS.md の不変条件）:
##
##   1. **構造はゲームが作り、AI は表示用の文字列だけ。** 渡すのは確定済みの
##      事実、返るのは文章。数値は受け取らない（`QuestText` が弾く）。
##   2. **失敗しても遅くてもゲームは成立する。** 呼ぶ前にテンプレートで
##      完成させておき、届いたら差し替えるだけ。届かなければそのまま。
##   3. **決定性に関与しない。** 出力は乱数列にもセーブにも入らない。
##      同じシードからは同じ世界・同じ配置が出る。違うのは呼び名だけ。

signal answered(text: String)

const URL := "http://localhost:11434/api/generate"

## 27B は品質が高いが遅い。待てるのは数秒なので 8B を既定にする。
const MODEL := "huihui_ai/qwen3-abliterated:8b"

var _request: HTTPRequest = null
var _timer := 0.0
var _pending := false
var _timeout := 8.0
var _label := ""


func _ready() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	_request.request_completed.connect(_on_completed)
	set_process(false)


## 頼む。返事は `answered` で 1 回だけ飛ぶ。届かなければ何も飛ばない。
##
## `label` は記録用（`--ai-debug` でどの依頼の返事かを見分ける）。
func ask(prompt: String, timeout: float = 8.0, label: String = "") -> bool:
	if _pending:
		return false
	_timeout = timeout
	_label = label
	_request.timeout = timeout
	var body := JSON.stringify({
		"model": MODEL,
		"prompt": prompt,
		"stream": false,
		# Qwen3 系は既定で思考ブロックを吐き、num_predict を思考だけで使い切って
		# 本文が空で返ってくる。思考は要らないので切る。
		"think": false,
		# 文章の揺れを抑える。表層の差は必要だが、比喩と文体まで毎回変えると
		# NPC や記録が別作品の文章に見える。
		"options": {"temperature": 0.35, "num_predict": 320},
	})
	var error := _request.request(URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		# Ollama が居ないだけ。警告も出さない（これは異常ではない）。
		return false
	_pending = true
	_timer = 0.0
	set_process(true)
	return true


func is_busy() -> bool:
	return _pending


func _process(delta: float) -> void:
	_timer += delta
	if _timer > _timeout + 1.0:
		_pending = false
		set_process(false)
		_request.cancel_request()


func _on_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	set_process(false)
	if code != 200:
		return
	var parsed := _parse_dictionary(body.get_string_from_utf8(), "Ollama応答")
	if parsed.is_empty():
		return
	var text := String(parsed.get("response", "")).strip_edges()
	if debug_enabled():
		print("[AI:%s] %d 文字" % [_label, text.length()])
		print(text)
	if text == "":
		return
	answered.emit(text)


static func debug_enabled() -> bool:
	return "--ai-debug" in OS.get_cmdline_user_args()


## 窓口を 1 つ作って `parent` へぶら下げる。**構築はここだけ**（D-3）。
##
## 接続点が散ると、片方だけタイムアウトを直したり、片方だけ `think` を
## 切り忘れたりする（実際に別々に書いていた）。窓口そのものは用途ごとに
## 分ける必要がある ―― 1 本にすると戦記の返事とクエスト文の返事が混ざる ――
## ので、**作る場所だけを 1 つにする**。
##
## `--no-ai` のときは null を返す。呼ぶ側は「窓口が無ければ頼まない」だけでよく、
## AI の有無を各所で判定しなくて済む。
static func create(parent: Node) -> LocalAI:
	if not enabled():
		return null
	var ai := LocalAI.new()
	parent.add_child(ai)
	return ai


## AI を使う設定か。**判定もここ 1 か所。**
static func enabled() -> bool:
	return "--no-ai" not in OS.get_cmdline_user_args()


## 返事から JSON を取り出す。モデルは前後に説明を付けてくる。
## 取れなければ空の辞書（呼び出し側はテンプレートのままにする）。
static func extract_json(text: String) -> Dictionary:
	# `JSON.parse_string()` は不正入力をGodotのERRORへ出す。AIの不正JSONは
	# 通信失敗と同じ通常のフォールバックなので、Errorを返す `JSON.parse()` で静かに落とす。
	# 前後に説明やコードフェンスがあっても、最初の釣り合ったJSONオブジェクトだけを試す。
	var cursor := 0
	while cursor < text.length():
		var start := text.find("{", cursor)
		if start < 0:
			break
		var finish := _matching_brace(text, start)
		if finish < 0:
			cursor = start + 1
			continue
		var parsed := _parse_dictionary(text.substr(start, finish - start + 1), "文章候補")
		if not parsed.is_empty():
			return parsed
		cursor = finish + 1
	return {}


## 文字列中の波括弧を数えず、`start` と対になる閉じ括弧を探す。
static func _matching_brace(text: String, start: int) -> int:
	var depth := 0
	var in_string := false
	var escaped := false
	for index in range(start, text.length()):
		var character := text.substr(index, 1)
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				in_string = false
			continue
		if character == "\"":
			in_string = true
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index
	return -1


## 外部入力用の、エラーログを出さない辞書JSON解析。
static func _parse_dictionary(text: String, label: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		if debug_enabled():
			print("[AI:%s] JSONを採用しない（%s / 行%d）" % [
				label, parser.get_error_message(), parser.get_error_line()
			])
		return {}
	return parser.data as Dictionary
