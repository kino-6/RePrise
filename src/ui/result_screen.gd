class_name ResultScreen
extends Node2D

## ラン終了画面。ここは「もう操作するものが無い」唯一の画面なので、
## 数秒の生成待ちが許される＝ローカル AI に文章を書かせる場所として最適。

signal dismissed

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")

## 戦記の行送り。折り返したぶんも同じ間隔で積む。
const LINE_STEP := 21

var lines: PackedStringArray = []
var title := ""
var _ready_to_dismiss := false


## 戦記をローカル AI に書かせるか。切りたいときは --no-ai を付けて起動する。
## 既定は入り。届かなければテンプレートのままなので、Ollama が無くても困らない。
var _ai: ChronicleAI = null


func show_summary(summary: Dictionary) -> void:
	title = "生還" if bool(summary.get("victory", false)) else "全滅"
	# まずテンプレート版を出す。生成はそのあとで差し替えるだけ。
	lines = Chronicle.write(summary)
	_request_ai(summary)
	_ready_to_dismiss = false
	set_process_unhandled_input(true)
	# 直後の入力で飛ばしてしまわないよう、一拍おいてから受け付ける
	get_tree().create_timer(0.6).timeout.connect(func() -> void: _ready_to_dismiss = true)
	queue_redraw()


## 生成を依頼する。届いたら 1 度だけ差し替える。
##
## テンプレートを消してから待つのではなく、**出したうえで**差し替える。
## 生成が失敗しても遅くても画面が空白にならない、というのがこの順番の理由。
func _request_ai(summary: Dictionary) -> void:
	if "--no-ai" in OS.get_cmdline_user_args():
		return
	if _ai == null:
		_ai = ChronicleAI.new()
		add_child(_ai)
		_ai.written.connect(_on_ai_written)
	_ai.request(summary)


func _on_ai_written(ai_lines: PackedStringArray) -> void:
	# 事実の行（何階で何を倒した）は残し、語りの部分だけ差し替える。
	var kept := PackedStringArray()
	for i in mini(lines.size(), 3):
		kept.append(lines[i])
	kept.append_array(ai_lines)
	lines = kept
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _ready_to_dismiss and event.is_action_pressed("confirm"):
		set_process_unhandled_input(false)
		dismissed.emit()


func _draw() -> void:
	PixelUI.ui_frame()
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x08, 0x0A, 0x14), true)

	UiPanel.begin(
		self, Rect2(16, 18, 480, 36), WINDOW_TEX, "―― %s ――" % title)

	# 戦記は覚えた技を全部並べるので、1 行が窓を越える。
	# `paragraph()` が折り返し、入らない行は捨てて数える（外へは描かない）。
	var body := UiPanel.begin(self, Rect2(16, 62, 480, 218), WINDOW_TEX)
	for line in lines:
		body.paragraph(line)

	if _ready_to_dismiss:
		var tail := "Ｚキーで つぎの たびへ"
		PixelUI.draw_text(
			self, Vector2((PixelUI.SCREEN.x - PixelUI.text_width(tail)) * 0.5, 288),
			tail, PixelUI.C_TEXT_DIM
		)
