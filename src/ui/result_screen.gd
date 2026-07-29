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


func show_summary(summary: Dictionary) -> void:
	title = "生還" if bool(summary.get("victory", false)) else "全滅"
	lines = Chronicle.write(summary)
	_ready_to_dismiss = false
	set_process_unhandled_input(true)
	# 直後の入力で飛ばしてしまわないよう、一拍おいてから受け付ける
	get_tree().create_timer(0.6).timeout.connect(func() -> void: _ready_to_dismiss = true)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _ready_to_dismiss and event.is_action_pressed("confirm"):
		set_process_unhandled_input(false)
		dismissed.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x08, 0x0A, 0x14), true)

	var head := Rect2(16, 18, 480, 36)
	PixelUI.draw_window(self, head, WINDOW_TEX)
	PixelUI.draw_text(
		self, PixelUI.content(head).position + Vector2(8, 0),
		"―― %s ――" % title, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD
	)

	var body := Rect2(16, 62, 480, 218)
	PixelUI.draw_window(self, body, WINDOW_TEX)
	var inner := PixelUI.content(body)

	# 戦記は覚えた技を全部並べるので、1 行が窓を越える。必ず折り返す。
	var drawn: PackedStringArray = []
	for line in lines:
		drawn.append_array(PixelUI.wrap(line, inner.size.x - 16.0))
	var room := int((inner.size.y - 8.0) / LINE_STEP)
	for i in mini(drawn.size(), room):
		PixelUI.draw_text(self, inner.position + Vector2(8, 4 + i * LINE_STEP), drawn[i], PixelUI.C_TEXT)

	if _ready_to_dismiss:
		var tail := "Ｚキーで つぎの たびへ"
		PixelUI.draw_text(
			self, Vector2((PixelUI.SCREEN.x - PixelUI.text_width(tail)) * 0.5, 288),
			tail, PixelUI.C_TEXT_DIM
		)
