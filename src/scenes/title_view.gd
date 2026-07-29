class_name TitleView
extends Node2D

## タイトル画面。
##
## 起動して最初に出るので、この 1 枚で「何のゲームか」が伝わる必要がある。
## 4 人を並べて、レベルは失うが熟練は残るという一行を添えるだけに絞った。
##
## 続きがある（＝拠点に戦績が残っている）ときは、それも出す。
## ローグライトは「前回の続き」が動機なので、始める前に見せる価値がある。

signal started

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const PORTRAIT_SIZE := Vector2(24, 32)
const PORTRAITS := [
	preload("res://assets/sprites/hero_soldier.png"),
	preload("res://assets/sprites/hero_priest.png"),
	preload("res://assets/sprites/hero_mage.png"),
	preload("res://assets/sprites/hero_thief.png"),
]

const BLINK_CYCLE := 1.1
const INPUT_LOCK := 0.3

var _time := 0.0
var _input_lock := 0.0


func open() -> void:
	_time = 0.0
	_input_lock = INPUT_LOCK
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	_time += delta
	if _input_lock > 0.0:
		_input_lock -= delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	if Input.is_action_just_pressed("confirm"):
		Sound.play("confirm")
		close()
		started.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x08, 0x0A, 0x14), true)

	# 床の高さに横線を 2 本。奥行きだけ示して、絵は増やさない。
	for i in 2:
		var y := 150.0 + i * 3.0
		draw_rect(Rect2(0, y, PixelUI.SCREEN.x, 1), Color8(0x18, 0x20, 0x38), true)

	_draw_title()
	_draw_party()
	_draw_record()
	_draw_prompt()


## 題字だけを置く。説明もキャッチコピーも入れない。
## 何のゲームかは下に並んだ 4 人と、その下の戦績が伝える。
func _draw_title() -> void:
	var title := "RePrise"
	var width := PixelUI.text_width(title, 40)
	PixelUI.draw_text(self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 82), title, PixelUI.C_TEXT, 40)


func _draw_party() -> void:
	# 4 人を等間隔に。正面 1 コマだけ抜く。
	var spacing := 60.0
	var origin := (PixelUI.SCREEN.x - spacing * (PORTRAITS.size() - 1)) * 0.5
	for i in PORTRAITS.size():
		var at := Vector2(origin + i * spacing - PORTRAIT_SIZE.x * 0.5, 118)
		draw_texture_rect_region(
			PORTRAITS[i], Rect2(at.floor(), PORTRAIT_SIZE), Rect2(Vector2.ZERO, PORTRAIT_SIZE)
		)


func _draw_record() -> void:
	if GameState.runs_attempted <= 0:
		return
	var line := "最深 地下%d階　残響 %d　%d回の潜行" % [
		maxi(GameState.deepest_floor, 1), GameState.echo, GameState.runs_attempted
	]
	var width := PixelUI.text_width(line, 10)
	PixelUI.draw_text(
		self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 172), line, PixelUI.C_TEXT_DIM, 10
	)


func _draw_prompt() -> void:
	# 明滅させる。止まっている画面に 1 つだけ動きがあると、入力待ちだと分かる。
	if fmod(_time, BLINK_CYCLE) > BLINK_CYCLE * 0.78:
		return
	var text := "Ｚキーで はじめる"
	var width := PixelUI.text_width(text, 12)
	PixelUI.draw_text(
		self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 208), text, PixelUI.C_ACTIVE, 12
	)
