class_name EventView
extends Node2D

const EventOperationScript := preload("res://src/quest/event_operation.gd")

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
const TALK_RECT := Rect2(8, 154, 496, 108)

const INPUT_LOCK := 0.16
const OUTCOME_LINES_PER_PAGE := 8

var event: Dictionary = {}
var danger := 1

var _index := 0
var _input_lock := 0.0
## 選択肢の添字 -> 払えない理由。選べる手が一つあるからといって、別の
## 払えない手まで通さない。
var _blocked: Dictionary = {}
var _outcome_page := 0


## 物語の拍を開く。
##
## イベントと同じ窓を使う。**語り用にもう 1 枚作らない** ―― 出すものは同じ
## （何が起きているか / 選べる手 / その手で何が変わるか）で、違うのは
## 「変わるもの」が数値かどうかだけ。窓を 2 つにすると読み方も 2 つになる。
func open_story(beat: Dictionary, story: Dictionary, danger_here: int) -> bool:
	# 導入や反転を「次へ」だけで読ませない。物語窓は、後続プレイへ効く
	# 三択がある一拍に限る。それ以外は StoryOperation が地図上の目的にする。
	if String(beat.get("phase", "")) != "choice":
		push_error("選択の無い物語拍を EventView で開こうとした")
		return false
	var choices: Array = []
	for c in story.get("choices", []):
		choices.append({
			"id": String(c.get("id", "")),
			"label": String(c.get("label", "")),
			"keeps": String(c.get("preserves", "")),
			"loses": String(c.get("sacrifices", "")),
			"pays": String(c.get("immediate_cost", "")),
			# 物語上の結末だけでなく、主戦や移動へ届く実効果も選ぶ前に見せる。
			"runtime_effects": c.get("runtime_effects", []).duplicate(),
		})
	if choices.is_empty():
		push_error("物語の選択肢が無い")
		return false
	open({
		"story": true,
		"skin": {
			"title": String(story.get("skin", {}).get("title", "")),
			# 本文は人物の発話ではなく、出来事を要約する地の文。
			# 人物名を話者欄へ出すと、三人称の文を本人が話しているように見える。
			"actor": "",
			"cause": String(beat.get("line", "")),
			"flavor": "",
		},
		"choices": choices,
	}, danger_here)
	return true


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
		# 結果は文章へ連結しない。1件ずつの境界を保たないと、折り返しで
		# 「得／た」のように語の途中が別行へ送られる。
		"outcome_lines": body,
		"skin": {"title": title, "actor": "", "cause": "", "flavor": ""},
		"choices": [{
			"label": Terms.EVENT_CLOSE_CHOICE,
			"costs": [],
			"risks": [],
			"rewards": [],
		}],
	}, danger_here)


## 町の人・仕事場の短い説明。流れて消えるtoastではなく、読み終えるまで残す。
## 世界イベントより軽い窓にして、誰と話しているかと実際の効き目を同時に見せる。
func open_talk(speaker: String, lines: Array[String], danger_here: int) -> void:
	var body := lines.duplicate()
	if body.is_empty():
		body.append(Terms.EVENT_UNRESOLVED)
	open({
		"talk": true,
		"talk_lines": body,
		"skin": {"title": speaker, "actor": "", "cause": "", "flavor": ""},
		"choices": [{"label": Terms.EVENT_CLOSE_CHOICE}],
	}, danger_here)
func is_talk() -> bool:
	return bool(event.get("talk", false))


func open(instance: Dictionary, danger_here: int) -> void:
	event = instance
	danger = danger_here
	_index = 0
	_blocked = {}
	_outcome_page = 0
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
		if bool(event.get("outcome", false)) and _outcome_page + 1 < _outcome_pages():
			_outcome_page += 1
			Sound.play("confirm")
			queue_redraw()
			return
		var picked: Dictionary = _choices()[_index]
		# 払えない手は選ばせない。理由をその場に出す。
		if not _current_blocked().is_empty():
			Sound.play("cancel")
			return
		Sound.play("confirm")
		close()
		chosen.emit(picked)
	elif e.is_action_pressed("cancel"):
		# 結果が複数頁なら、取消でも未読分を飛ばさず次へ送る。
		if bool(event.get("outcome", false)) and _outcome_page + 1 < _outcome_pages():
			_outcome_page += 1
			Sound.play("confirm")
			queue_redraw()
			return
		if bool(event.get("elite_reward", false)):
			Sound.play("cancel")
			return
		# 物語で唯一開くのは、後続プレイを変える三択。取消で既定値へ落としたり
		# 閉じたままにせず、どの結果を引き受けるか選ぶまで残す。
		if bool(event.get("story", false)):
			Sound.play("cancel")
			return
		# 見送るのも一手。**必ず立ち去れること。**
		Sound.play("cancel")
		close()
		dismissed.emit()


func _skin(key: String) -> String:
	return String(event.get("skin", {}).get(key, ""))


func _draw() -> void:
	PixelUI.ui_frame()
	if is_talk():
		_draw_talk()
		return
	# 下の画面を暗く沈ませる。イベントは場面の上に開く窓。
	draw_rect(Rect2(Vector2.ZERO, Vector2(PixelUI.SCREEN)), Color(0, 0, 0.02, 0.55), true)
	if bool(event.get("outcome", false)):
		_draw_outcome()
		return
	_draw_head()
	_draw_list()
	_draw_detail()


func _draw_talk() -> void:
	# 地図と話者を見失わない程度にだけ暗くし、会話窓は下HUDの直上へ置く。
	draw_rect(Rect2(Vector2.ZERO, Vector2(PixelUI.SCREEN.x, TALK_RECT.position.y)),
		Color(0, 0, 0.02, 0.18), true)
	var panel := UiPanel.begin(self, TALK_RECT, WINDOW_TEX, _skin("title"), 7.0)
	panel.skip(3.0)
	var lines: Array = event.get("talk_lines", [])
	for i in mini(lines.size(), 2):
		panel.line(String(lines[i]), PixelUI.C_TEXT if i == 0 else PixelUI.C_ACTIVE)
	UiPanel.inside(self, Rect2(
		TALK_RECT.position + Vector2(12, TALK_RECT.size.y - 23),
		Vector2(TALK_RECT.size.x - 24, PixelUI.LINE)
	)).line(Terms.TOWN_TALK_CLOSE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)


## 結果は選択肢と同じ92pxの見出しへ押し込まない。
## 代償・危険・報酬・後続戦闘が重なると4行を越えるため、画面の大半を結果へ使う。
func _draw_outcome() -> void:
	PixelUI.draw_window(self, OUTCOME_RECT, WINDOW_TEX)
	# **折り返し幅を手で書かない。** 470 という数字は窓の寸法を変えると
	# ただちに古くなる（枠を縮めても文字はそのまま溢れる）。
	# `paragraph()` は窓の内側から幅を取り、入らない行は捨てて数える。
	var panel := UiPanel.inside(self, PixelUI.content(OUTCOME_RECT).grow(-6.0))
	panel.line(_skin("title"), PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	panel.skip(6.0)
	var lines := _outcome_lines()
	var first := _outcome_page * OUTCOME_LINES_PER_PAGE
	var last := mini(first + OUTCOME_LINES_PER_PAGE, lines.size())
	for i in range(first, last):
		# 1 結果ずつ改行する。通常は1行、長い外部文だけ安全に折り返す。
		panel.paragraph(String(lines[i]))
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	UiPanel.inside(self, PixelUI.content(DETAIL_RECT).grow(-4.0)).line(
		Terms.EVENT_CONTINUE if _outcome_page + 1 < _outcome_pages() else Terms.EVENT_CLOSE,
		PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)


func _outcome_lines() -> Array:
	var lines: Array = event.get("outcome_lines", [])
	return lines if not lines.is_empty() else [Terms.EVENT_UNRESOLVED]


func _outcome_pages() -> int:
	return maxi(1, ceili(float(_outcome_lines().size()) / OUTCOME_LINES_PER_PAGE))


func _draw_head() -> void:
	PixelUI.draw_window(self, HEAD_RECT, WINDOW_TEX)
	var panel := UiPanel.inside(self, PixelUI.content(HEAD_RECT).grow(-6.0))
	# 題と語り手を 1 行に。**ぶつかったら題を詰める**（語り手は名前なので短い）。
	panel.row(
		_skin("title"), _skin("actor"),
		PixelUI.C_ACTIVE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_HEAD
	)
	panel.skip(4.0)
	# 何が起きているか。原因と情景。**入らない行は捨てて数える。**
	panel.paragraph(_skin("cause") + " " + _skin("flavor"))


func _draw_list() -> void:
	PixelUI.draw_window(self, LIST_RECT, WINDOW_TEX)
	var origin := PixelUI.content(LIST_RECT).position
	for i in _choices().size():
		var c: Dictionary = _choices()[i]
		var at := origin + Vector2(16, 4 + i * 26)
		var on := i == _index
		if on:
			MenuList.draw_cursor(self, CURSOR_TEX, at)
		# 払うものと得るものを、その行に添える。**選ぶ前に見える位置に置く。**
		# 右（代価）を守り、詰まるのは選択肢の文のほう。
		UiPanel.inside(self, Rect2(
			at, Vector2(PixelUI.content(LIST_RECT).end.x - 6.0 - at.x, PixelUI.LINE)
		)).row(
			String(c.get("label", "")), _summary(c),
			PixelUI.C_TEXT if on else PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM
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
	# 物語の手も実ゲームへ効く。結末の説明だけで済ませず、直近の効き目を添える。
	if bool(event.get("story", false)):
		var effects: Array = choice.get("runtime_effects", [])
		var effect := (
			EventEffects.label(String(effects[0]), "reward")
			if not effects.is_empty() else ""
		)
		return (
			"" if effect == ""
			else PixelUI.clip(
				"%s: %s" % [Terms.EVENT_GAIN, effect],
				286.0,
				PixelUI.SIZE_TEXT
			)
		)
	var pay := _tokens(choice.get("costs", []), "cost")
	var gains: Array = choice.get("rewards", [])
	var count := 0
	for token in gains:
		if String(token) != "none":
			count += 1
	var got := Terms.NONE if count == 0 else _first_token(gains, "reward")
	if count > 1:
		got += " " + Terms.EVENT_OTHER_COUNT % (count - 1)
	return PixelUI.clip(
		"%s → %s" % [pay if pay != "" else Terms.NONE, got],
		286.0,
		PixelUI.SIZE_TEXT
	)


func _first_token(list: Array, kind: String) -> String:
	for token in list:
		if String(token) != "none":
			return EventEffects.label(String(token), kind)
	return Terms.NONE


func _tokens(list: Array, kind: String) -> String:
	var parts: Array[String] = []
	for token in list:
		if String(token) == "none":
			continue
		parts.append(EventEffects.label(String(token), kind))
	return "・".join(parts)


## 詳細窓の左半分の幅。「あぶない」を右半分へ逃がすための境目。
const DETAIL_HALF_W := 242.0


## 詳細窓の 1 行。**幅は窓の内側から取る**（窓の寸法を変えても古くならない）。
func _detail(origin: Vector2, dy: float, width: float = -1.0) -> UiPanel:
	var inner := PixelUI.content(DETAIL_RECT)
	var room := width if width > 0.0 else inner.end.x - origin.x - 16.0
	return UiPanel.inside(self, Rect2(
		origin + Vector2(8, dy), Vector2(room, PixelUI.LINE)))


func _draw_detail() -> void:
	PixelUI.draw_window(self, DETAIL_RECT, WINDOW_TEX)
	var origin := PixelUI.content(DETAIL_RECT).position
	if _choices().is_empty():
		return
	var c: Dictionary = _choices()[_index]

	# 物語の拍は、払う・失う・のこす を文で出す（トークンではない）。
	if bool(event.get("story", false)):
		var rows := [
			[Terms.EVENT_STORY_COST, String(c.get("pays", ""))],
			[Terms.EVENT_STORY_KEEP, String(c.get("keeps", ""))],
			[Terms.EVENT_STORY_LOSE, String(c.get("loses", ""))],
		]
		var shown := 0
		for row in rows:
			if String(row[1]) == "":
				continue
			_detail(origin, shown * 18).line(
				"%s: %s" % [row[0], row[1]],
				PixelUI.C_HP_LOW if row[0] == Terms.EVENT_STORY_LOSE else PixelUI.C_TEXT,
				PixelUI.SIZE_TEXT
			)
			shown += 1
		if shown == 0:
			_detail(origin, 0).line(
				Terms.EVENT_CONTINUE, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		return

	if bool(c.get("defer", false)):
		_detail(origin, 0).line(
			Terms.EVENT_DEFER_DETAIL, PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		return

	var risks := _tokens(c.get("risks", []), "risk")
	# 左半分に「はらう」、右半分に「あぶない」。**列として幅を渡す**ので、
	# 手で 218 や 470 と書いていた数字が要らなくなる（窓を変えると古くなる数字）。
	# **左右に割らず、行で分ける。** 半分の幅（242px）だと 14px の漢字が入らず、
	# 12px へ下げると潰れる（D-5）。縦に 1 行使うほうが読める。
	_detail(origin, 0).row(
		"%s: %s" % [Terms.EVENT_PAY,
			_tokens(c.get("costs", []), "cost")
			if not c.get("costs", []).is_empty() else Terms.NONE
		],
		"%s: %s" % [Terms.EVENT_RISK, risks if risks != "" else Terms.NONE],
		PixelUI.C_TEXT_DIM,
		PixelUI.C_HP_LOW if risks != "" else PixelUI.C_TEXT_DIM
	)
	# 代価と報酬は data 側の語（漢字を含む）。**14px より下げない**（D-5）。
	_detail(origin, 18).line(
		"%s: %s" % [
			Terms.EVENT_GAIN, _tokens(c.get("rewards", []), "reward")
		],
		PixelUI.C_TEXT
	)
	# 払えないときは、その理由を最優先で出す。
	var blocked := _current_blocked()
	if not blocked.is_empty():
		_detail(origin, 38).line(
			"%s: %s" % [Terms.EVENT_MISSING, "・".join(blocked)],
			PixelUI.C_HP_LOW,
			PixelUI.SIZE_TEXT
		)
		return
	var final_hint := Terms.ELITE_REWARD_CONFIRM
	if not bool(event.get("elite_reward", false)):
		# 「決定したら数値が増えて終了」ではない。選択後に必要な実行工程を
		# 決める前から見せ、報酬を受け取る条件として読めるようにする。
		final_hint = EventOperationScript.preview(event, c)
	_detail(origin, 38).line(final_hint, PixelUI.C_TEXT_DIM)
func _current_blocked() -> Array[String]:
	var reasons: Array[String] = []
	reasons.assign(_blocked.get(_index, []))
	return reasons


## 払えない理由を外から入れる（GameState を知らないので自分では調べない）。
## Dictionary は選択肢ごと、旧呼出しの配列は全選択肢共通として受ける。
func set_blocked(reasons: Variant) -> void:
	_blocked = {}
	if reasons is Dictionary:
		_blocked = reasons.duplicate(true)
	elif reasons is Array and not reasons.is_empty():
		for i in _choices().size():
			_blocked[i] = reasons.duplicate()
	queue_redraw()
