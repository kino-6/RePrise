class_name EventView
extends Node2D

## 任意イベントの選択画面。
##
## 出すのは 3 つだけ ―― 何が起きているか、選べる手、その手で何を払い何を得るか。
## **払うものを隠さない。** 選んでから「そんなに減るのか」と気づく作りだと、
## 選択が賭けではなく罰になる。costs / risks / rewards を選ぶ前に並べる。
##
## 骨格（選択肢・効果）は `data/world_events.json`、
## 数値は `EventEffects`、表示用の言葉は AI か `DetRng` が選んだ skin。

signal chosen(choice: Dictionary)
signal dismissed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const CURSOR_TEX: Texture2D = preload("res://assets/ui/cursor.png")

const HEAD_RECT := Rect2(8, 8, 496, 92)
const LIST_RECT := Rect2(8, 106, 496, 122)
const DETAIL_RECT := Rect2(8, 234, 496, 78)
const OUTCOME_RECT := Rect2(8, 8, 496, 220)

const INPUT_LOCK := 0.16

var event: Dictionary = {}
var danger := 1

var _index := 0
var _input_lock := 0.0
var _blocked: Array[String] = []


## 物語の拍を開く。
##
## イベントと同じ窓を使う。**語り用にもう 1 枚作らない** ―― 出すものは同じ
## （何が起きているか / 選べる手 / その手で何が変わるか）で、違うのは
## 「変わるもの」が数値かどうかだけ。窓を 2 つにすると読み方も 2 つになる。
func open_story(beat: Dictionary, story: Dictionary, danger_here: int) -> void:
	var choices: Array = []
	if String(beat.get("phase", "")) == "choice":
		for c in story.get("choices", []):
			choices.append({
				"id": String(c.get("id", "")),
				"label": String(c.get("label", "")),
				# 物語の選択は数値ではなく、何を守り何を手放すかで示す。
				"keeps": String(c.get("preserves", "")),
				"loses": String(c.get("sacrifices", "")),
				"pays": String(c.get("immediate_cost", "")),
			})
	if choices.is_empty():
		choices = [{"id": "", "label": "……", "keeps": "", "loses": "", "pays": ""}]
	open({
		"story": true,
		"skin": {
			"title": String(story.get("skin", {}).get("title", "")),
			"actor": String(story.get("skin", {}).get("anchor_name", "")),
			"cause": String(beat.get("line", "")),
			"flavor": "",
		},
		"choices": choices,
	}, danger_here)


## 選んだあとの結果を、同じ窓で読ませる。
##
## **toast では流れて読めない。** 何を払って何を得たかは選択の答えなので、
## 消える表示に置くと、選んだ意味が確かめられないまま次へ進むことになる。
## 決定キーひとつで閉じる（読み終わるまで待つ）。
func open_outcome(title: String, lines: Array[String], danger_here: int) -> void:
	var body := lines.duplicate()
	if body.is_empty():
		body.append(Terms.EVENT_UNRESOLVED)
	open({
		"outcome": true,
		"skin": {"title": title, "actor": "", "cause": "　".join(body), "flavor": ""},
		"choices": [{"label": "とじる", "costs": [], "risks": [], "rewards": []}],
	}, danger_here)


func open(instance: Dictionary, danger_here: int) -> void:
	event = instance
	danger = danger_here
	_index = 0
	_input_lock = INPUT_LOCK
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock -= delta


func _choices() -> Array:
	return event.get("choices", [])


func _unhandled_input(e: InputEvent) -> void:
	if not e.is_pressed() or e.is_echo() or _input_lock > 0.0:
		return
	var rows := _choices().size()
	if rows == 0:
		return
	if e.is_action_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sound.play("cursor")
		queue_redraw()
	elif e.is_action_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sound.play("cursor")
		queue_redraw()
	elif e.is_action_pressed("confirm"):
		var picked: Dictionary = _choices()[_index]
		# 払えない手は選ばせない。理由をその場に出す。
		if not _blocked.is_empty():
			Sound.play("cancel")
			return
		Sound.play("confirm")
		close()
		chosen.emit(picked)
	elif e.is_action_pressed("cancel"):
		# 見送るのも一手。**必ず立ち去れること。**
		Sound.play("cancel")
		close()
		dismissed.emit()


func _skin(key: String) -> String:
	return String(event.get("skin", {}).get(key, ""))


func _draw() -> void:
	PixelUI.ui_frame()
	# 下の画面を暗く沈ませる。イベントは場面の上に開く窓。
	draw_rect(Rect2(Vector2.ZERO, Vector2(PixelUI.SCREEN)), Color(0, 0, 0.02, 0.55), true)
	if bool(event.get("outcome", false)):
		_draw_outcome()
		return
	_draw_head()
	_draw_list()
	_draw_detail()


## 結果は選択肢と同じ92pxの見出しへ押し込まない。
## 代償・危険・報酬・後続戦闘が重なると4行を越えるため、画面の大半を結果へ使う。
func _draw_outcome() -> void:
	PixelUI.draw_window(self, OUTCOME_RECT, WINDOW_TEX)
	var origin := PixelUI.content(OUTCOME_RECT).position
	PixelUI.draw_text(
		self, origin + Vector2(6, 0), _skin("title"), PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD
	)
	var lines := PixelUI.wrap(_skin("cause"), 470.0, PixelUI.SIZE_TEXT)
	for i in mini(lines.size(), 8):
		PixelUI.draw_text(
			self, origin + Vector2(6, 28 + i * 20), lines[i], PixelUI.C_TEXT
		)
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	PixelUI.draw_text(
		self, PixelUI.content(DETAIL_RECT).position + Vector2(8, 0),
		Terms.EVENT_CLOSE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)


func _draw_head() -> void:
	PixelUI.draw_window(self, HEAD_RECT, WINDOW_TEX)
	var origin := PixelUI.content(HEAD_RECT).position
	PixelUI.draw_text(self, origin + Vector2(6, 0), _skin("title"), PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	var who := _skin("actor")
	if who != "":
		PixelUI.draw_text_right(
			self, Vector2(PixelUI.content(HEAD_RECT).end.x - 4, origin.y + 4), who,
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
	# 何が起きているか。原因と情景を 2 行で。
	var lines := PixelUI.wrap(_skin("cause") + " " + _skin("flavor"), 470.0, PixelUI.SIZE_TEXT)
	for i in mini(lines.size(), 4 if bool(event.get("outcome", false)) else 3):
		PixelUI.draw_text(self, origin + Vector2(6, 26 + i * 20), lines[i], PixelUI.C_TEXT)


func _draw_list() -> void:
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	var origin := PixelUI.content(LIST_RECT).position
	for i in _choices().size():
		var c: Dictionary = _choices()[i]
		var at := origin + Vector2(16, 4 + i * 26)
		var on := i == _index
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		PixelUI.draw_text(
			self, at, String(c.get("label", "")),
			PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM
		)
		# 払うものと得るものを、その行に添える。**選ぶ前に見える位置に置く。**
		PixelUI.draw_text(
			self, at + Vector2(180, 2), _summary(c), PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)


## 行に添える 1 行。**枠に収まる長さで切る。**
##
## 全部並べると窓から溢れた（実際に溢れた）。行では「払う → 得るものの数」まで、
## 中身は下の詳細窓に出す。溢れた文字は読めないので、出さないほうがよい。
func _summary(choice: Dictionary) -> String:
	if bool(event.get("outcome", false)):
		return ""
	if bool(choice.get("defer", false)):
		return Terms.EVENT_DEFER_SUMMARY
	# 物語の手は数値を持たない。守るものだけを添える。
	if bool(event.get("story", false)):
		var keeps := String(choice.get("keeps", ""))
		return "" if keeps == "" else PixelUI.clip("のこす: %s" % keeps, 286.0, PixelUI.SIZE_SUB)
	var pay := _tokens(choice.get("costs", []), "cost")
	var gains: Array = choice.get("rewards", [])
	var count := 0
	for token in gains:
		if String(token) != "none":
			count += 1
	var got := "なし" if count == 0 else _first_token(gains, "reward")
	if count > 1:
		got += " ほか%d" % (count - 1)
	return PixelUI.clip("%s → %s" % [pay if pay != "" else "なし", got], 286.0, PixelUI.SIZE_SUB)


func _first_token(list: Array, kind: String) -> String:
	for token in list:
		if String(token) != "none":
			return EventEffects.label(String(token), kind)
	return "なし"


func _tokens(list: Array, kind: String) -> String:
	var parts: Array[String] = []
	for token in list:
		if String(token) == "none":
			continue
		parts.append(EventEffects.label(String(token), kind))
	return "・".join(parts)


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(DETAIL_RECT).position
	if _choices().is_empty():
		return
	var c: Dictionary = _choices()[_index]

	# 物語の拍は、払う・失う・のこす を文で出す（トークンではない）。
	if bool(event.get("story", false)):
		var rows := [
			["はらう", String(c.get("pays", ""))],
			["のこす", String(c.get("keeps", ""))],
			["手ばなす", String(c.get("loses", ""))],
		]
		var shown := 0
		for row in rows:
			if String(row[1]) == "":
				continue
			PixelUI.draw_text(
				self, origin + Vector2(8, shown * 18),
				PixelUI.clip("%s: %s" % [row[0], row[1]], 470.0, PixelUI.SIZE_SUB),
				PixelUI.C_HP_LOW if row[0] == "手ばなす" else PixelUI.C_TEXT, PixelUI.SIZE_SUB
			)
			shown += 1
		if shown == 0:
			PixelUI.draw_text(
				self, origin + Vector2(8, 0), "Ｚで つづける", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
			)
		return

	if bool(c.get("defer", false)):
		PixelUI.draw_text(
			self, origin + Vector2(8, 0),
			Terms.EVENT_DEFER_DETAIL, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		return

	var risks := _tokens(c.get("risks", []), "risk")
	PixelUI.draw_text(
		self, origin + Vector2(8, 0),
		"はらう: %s" % [_tokens(c.get("costs", []), "cost") if not c.get("costs", []).is_empty() else "なし"],
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)
	PixelUI.draw_text(
		self, origin + Vector2(8, 18),
		PixelUI.clip("もらう: %s" % [_tokens(c.get("rewards", []), "reward")], 470.0, PixelUI.SIZE_SUB),
		PixelUI.C_TEXT, PixelUI.SIZE_SUB
	)
	# 右半分に置くので、残り幅で切る（切らずに置いたら 20px 出た）。
	PixelUI.draw_text(
		self, origin + Vector2(250, 0),
		PixelUI.clip("あぶない: %s" % [risks if risks != "" else "なし"], 218.0, PixelUI.SIZE_SUB),
		PixelUI.C_HP_LOW if risks != "" else PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)
	# 払えないときは、その理由を最優先で出す。
	if not _blocked.is_empty():
		PixelUI.draw_text(
			self, origin + Vector2(8, 38), "たりない: %s" % "・".join(_blocked),
			PixelUI.C_HP_LOW, PixelUI.SIZE_SUB
		)
		return
	PixelUI.draw_text(
		self, origin + Vector2(8, 38), "Ｚで きめる　Ｘで 見送る", PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)


## 払えない理由を外から入れる（GameState を知らないので自分では調べない）。
func set_blocked(reasons: Array[String]) -> void:
	_blocked = reasons
	queue_redraw()
