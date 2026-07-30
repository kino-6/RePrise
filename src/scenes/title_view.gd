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
## 中断から再開する。
signal resumed
signal settings_requested

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
	if event.is_action_pressed("confirm"):
		Sound.play("confirm")
		close()
		# 中断があれば、決定はそちらへ。**続きがあるのに新しく始めさせない。**
		if GameState.has_suspend():
			resumed.emit()
		else:
			started.emit()
	elif event.is_action_pressed("cancel"):
		Sound.play("confirm")
		close()
		settings_requested.emit()


func _draw() -> void:
	PixelUI.ui_frame()
	draw_rect(Rect2(0, 0, PixelUI.SCREEN.x, PixelUI.SCREEN.y), Color8(0x08, 0x0A, 0x14), true)

	# 床の高さに横線を 2 本。奥行きだけ示して、絵は増やさない。
	for i in 2:
		var y := 202.0 + i * 3.0
		draw_rect(Rect2(0, y, PixelUI.SCREEN.x, 1), Color8(0x18, 0x20, 0x38), true)

	_draw_title()
	_draw_party()
	_draw_record()
	_draw_prompt()
	_draw_version()


## 題字だけを置く。説明もキャッチコピーも入れない。
## 何のゲームかは下に並んだ 4 人と、その下の戦績が伝える。
func _draw_title() -> void:
	var title := "RePrise"
	var width := PixelUI.text_width(title, 52)
	PixelUI.draw_text(self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 74), title, PixelUI.C_TEXT, 52)


func _draw_party() -> void:
	# 4 人を等間隔に。正面 1 コマだけ抜く。2 倍に引き伸ばして、
	# タイトルで顔がちゃんと見えるようにする（整数倍なのでドットは崩れない）。
	var spacing := 96.0
	var origin := (PixelUI.SCREEN.x - spacing * (PORTRAITS.size() - 1)) * 0.5
	for i in PORTRAITS.size():
		var at := Vector2(origin + i * spacing - PORTRAIT_SIZE.x, 138)
		draw_texture_rect_region(
			PORTRAITS[i], Rect2(at.floor(), PORTRAIT_SIZE * 2.0), Rect2(Vector2.ZERO, PORTRAIT_SIZE)
		)


func _draw_record() -> void:
	if GameState.runs_attempted <= 0:
		return
	var line := "%s %s　%s %d　%s" % [
		Terms.DEEPEST, "%d" % maxi(GameState.deepest_floor, 1),
		Terms.ECHO, GameState.echo,
		Terms.RUNS_TOTAL % GameState.runs_attempted,
	]
	var width := PixelUI.text_width(line)
	PixelUI.draw_text(
		self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 228), line, PixelUI.C_TEXT_DIM
	)


## 版を隅に出す。**不具合報告のときに、どのビルドかが画面から分かる。**
## タイトルバーは配布物だと隠れることがあるので、画面にも置く。
func _draw_version() -> void:
	var text := GameVersion.full()
	PixelUI.draw_text(
		self, Vector2(6, PixelUI.SCREEN.y - 18), text, PixelUI.C_SHADOW.lerp(
			PixelUI.C_TEXT_DIM, 0.7
		), PixelUI.SIZE_SUB
	)


func _draw_prompt() -> void:
	# 明滅させる。止まっている画面に 1 つだけ動きがあると、入力待ちだと分かる。
	if fmod(_time, BLINK_CYCLE) > BLINK_CYCLE * 0.78:
		return
	var text := "Ｚキーで はじめる　　Ｘキーで せってい"
	if GameState.has_suspend():
		text = "Ｚキーで つづきから　　Ｘキーで せってい"
	var width := PixelUI.text_width(text, PixelUI.SIZE_HEAD)
	PixelUI.draw_text(
		self, Vector2((PixelUI.SCREEN.x - width) * 0.5, 274), text, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD
	)
