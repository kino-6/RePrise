class_name PrologueView
extends Node2D

## 初回だけ再生する、操作付きのプロローグ。
##
## 説明文から始めず、終局の主と向き合った場面から始める。
## プレイヤーは決定キーで一撃を選び、その直後に世界の分断を目撃する。
## 表示文は Lore（原本は data/vocabulary.json）に置き、ここは構図だけを持つ。

signal finished

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const RUIN_BG: Texture2D = preload("res://assets/backgrounds/battle_bg_dungeon_depths.png")
const GATE_TEX: Texture2D = preload("res://assets/effects/event_world_gate.png")
const LORD_TEX: Texture2D = preload("res://assets/sprites/thorn_crowned_king.png")
const PARTY_TEX: Array[Texture2D] = [
	preload("res://assets/sprites/hero_soldier.png"),
	preload("res://assets/sprites/hero_priest.png"),
	preload("res://assets/sprites/hero_mage.png"),
	preload("res://assets/sprites/hero_thief.png"),
]

const TEXT_RECT := Rect2(8, 208, 496, 104)
const INPUT_LOCK := 0.18
const PORTRAIT := Vector2(24, 32)
const LORD_SIZE := Vector2(64, 64)

const SKY := Color8(0x07, 0x08, 0x16)
const VOID := Color8(0x02, 0x03, 0x0A)
const SILVER := Color8(0x9C, 0xB4, 0xE0)
const PALE := Color8(0xD8, 0xE8, 0xF0)
const CRACK := Color8(0xF8, 0xF0, 0xD0)
const STONE := Color8(0x28, 0x30, 0x48)
const STONE_DARK := Color8(0x13, 0x18, 0x28)
const WORLD_COLORS: Array[Color] = [
	Color8(0x38, 0x78, 0x4C),
	Color8(0xA0, 0x68, 0x38),
	Color8(0x50, 0x78, 0xA8),
	Color8(0x98, 0xA8, 0xC0),
	Color8(0x88, 0x38, 0x30),
	Color8(0x58, 0x40, 0x78),
]

var _beat := 0
var _time := 0.0
var _input_lock := 0.0
var _flash := 0.0


func open() -> void:
	_beat = 0
	_time = 0.0
	_input_lock = INPUT_LOCK
	_flash = 0.0
	set_process(true)
	set_process_unhandled_input(true)
	Sound.play_bgm("boss")
	queue_redraw()


func close() -> void:
	set_process(false)
	set_process_unhandled_input(false)


## 撮影用。保存状態に関係なく任意の拍を開ける。
func debug_open_beat(index: int) -> void:
	_beat = clampi(index, 0, maxi(Lore.PROLOGUE_BEATS.size() - 1, 0))
	_time = 0.0
	_input_lock = 0.0
	_flash = 0.0
	set_process(true)
	set_process_unhandled_input(false)
	_activate_beat()
	queue_redraw()


func current_beat() -> int:
	return _beat


func _process(delta: float) -> void:
	_time += delta
	if _input_lock > 0.0:
		_input_lock -= delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.8, 0.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _input_lock > 0.0:
		return
	# 初回の因果を飛ばすと、以後のランの意味が分からないままになる。
	# 8 拍だけなので cancel でのスキップは置かず、決定で一拍ずつ進める。
	if not event.is_action_pressed("confirm"):
		return
	Sound.play("confirm")
	if _beat >= Lore.PROLOGUE_BEATS.size() - 1:
		close()
		finished.emit()
		return
	_beat += 1
	_time = 0.0
	_input_lock = INPUT_LOCK
	_activate_beat()
	queue_redraw()


func _activate_beat() -> void:
	var scene := String(_entry().get("scene", ""))
	match scene:
		"confront":
			Sound.play("boss_gate")
		"attack":
			Sound.play("magic")
		"shatter":
			_flash = 1.0
			Sound.play("seal_break")
		"fragments":
			Sound.play_bgm("story")
		"fortress":
			Sound.play("story_open")


func _entry() -> Dictionary:
	if Lore.PROLOGUE_BEATS.is_empty():
		return {}
	return Lore.PROLOGUE_BEATS[clampi(_beat, 0, Lore.PROLOGUE_BEATS.size() - 1)]


func _draw() -> void:
	PixelUI.ui_frame()
	draw_rect(Rect2(Vector2.ZERO, Vector2(PixelUI.SCREEN)), VOID, true)
	var scene := String(_entry().get("scene", "assault"))
	match scene:
		"assault", "confront", "attack":
			_draw_final_chamber(scene)
		"shatter":
			_draw_shatter()
		"fragments":
			_draw_fragments()
		"fortress":
			_draw_fortress(false, false)
		"many_worlds":
			_draw_fortress(true, false)
		"oath":
			_draw_fortress(true, true)
	_draw_scene_label()
	_draw_text_window()
	if _flash > 0.0:
		draw_rect(
			Rect2(Vector2.ZERO, Vector2(PixelUI.SCREEN)),
			Color(0.92, 0.95, 1.0, _flash),
			true
		)


func _draw_final_chamber(scene: String) -> void:
	draw_texture_rect(RUIN_BG, Rect2(0, 0, 512, 176), false)
	draw_rect(Rect2(0, 176, 512, 32), Color8(0x0B, 0x0C, 0x12), true)
	if scene == "assault":
		draw_rect(Rect2(0, 0, 512, 208), Color(0.01, 0.01, 0.04, 0.28), true)

	var lord_bob := sin(_time * 2.2) * 2.0
	draw_texture_rect_region(
		LORD_TEX,
		Rect2(Vector2(346, 42 + lord_bob), LORD_SIZE * 2.0),
		Rect2(Vector2.ZERO, LORD_SIZE)
	)
	_draw_party(Vector2(72, 126), 2, scene == "attack")

	if scene == "confront":
		# 主が掲げる世界分断の力。完全な円にせず、既に傷がある。
		var center := Vector2(410, 39)
		draw_arc(center, 18, 0.25, TAU - 0.35, 24, CRACK, 3.0)
		draw_line(center + Vector2(-3, -17), center + Vector2(5, -4), CRACK, 2.0)
	elif scene == "attack":
		var pulse := 0.45 + sin(_time * 5.0) * 0.15
		draw_circle(Vector2(177, 146), 22 + pulse * 5, Color(0.6, 0.78, 1.0, 0.12), false, 2.0)
		draw_line(Vector2(191, 140), Vector2(226, 116), Color(0.82, 0.92, 1.0, pulse), 3.0)


func _draw_party(origin: Vector2, scale: int, lunging: bool) -> void:
	for i in PARTY_TEX.size():
		var row := 2  # 右向き。主へ向き合う。
		var offset := Vector2(i * 48, (i % 2) * 7)
		if lunging:
			offset.x += 8 + i * 2
		var at := origin + offset
		draw_texture_rect_region(
			PARTY_TEX[i],
			Rect2(at.floor(), PORTRAIT * scale),
			Rect2(0, row * PORTRAIT.y, PORTRAIT.x, PORTRAIT.y)
		)


func _draw_shatter() -> void:
	draw_rect(Rect2(0, 0, 512, 208), SKY, true)
	var center := Vector2(256, 96)
	_draw_world(center, 54, Color8(0x38, 0x68, 0x70))
	# 中央から伸びる亀裂。位置は固定し、演出がゲーム乱数へ触れないようにする。
	for points in [
		[Vector2(256, 43), Vector2(248, 69), Vector2(264, 88), Vector2(254, 112), Vector2(270, 145)],
		[Vector2(205, 86), Vector2(232, 91), Vector2(249, 82)],
		[Vector2(307, 72), Vector2(277, 83), Vector2(266, 103), Vector2(299, 122)],
	]:
		for i in range(1, points.size()):
			draw_line(points[i - 1], points[i], CRACK, 3.0)
	# 最後の一撃は届いたが、対象そのものが割れていく。
	draw_line(Vector2(112, 164), Vector2(218, 112), PALE, 5.0)
	draw_line(Vector2(122, 170), Vector2(222, 119), Color8(0x70, 0x98, 0xD0), 2.0)
	_draw_party(Vector2(55, 132), 2, true)


func _draw_fragments() -> void:
	draw_rect(Rect2(0, 0, 512, 208), VOID, true)
	var centers := [
		Vector2(84, 55), Vector2(188, 92), Vector2(305, 49),
		Vector2(421, 91), Vector2(128, 160), Vector2(355, 161),
	]
	for i in centers.size():
		var drift := Vector2(0, sin(_time * 1.7 + i) * 3)
		_draw_world(centers[i] + drift, 23 + (i % 2) * 5, WORLD_COLORS[i])
	# 回収される前の四人。世界のあいだを落ちている。
	for i in PARTY_TEX.size():
		var at := Vector2(219 + i * 22, 105 + (i % 2) * 13)
		draw_texture_rect_region(
			PARTY_TEX[i], Rect2(at, PORTRAIT), Rect2(0, 0, PORTRAIT.x, PORTRAIT.y)
		)


func _draw_world(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius + 3, Color8(0x9C, 0xB4, 0xE0), false, 2.0)
	draw_circle(center, radius, color, true)
	draw_arc(center, radius * 0.72, 0.25, 2.8, 12, color.lightened(0.3), 2.0)
	draw_line(
		center + Vector2(-radius * 0.75, radius * 0.15),
		center + Vector2(radius * 0.72, -radius * 0.24),
		color.darkened(0.28),
		3.0
	)


func _draw_fortress(show_worlds: bool, oath: bool) -> void:
	draw_rect(Rect2(0, 0, 512, 208), SKY, true)
	# 世界の外に残った砦。左右の塔と中央の門だけへ形を絞る。
	draw_rect(Rect2(28, 48, 112, 160), STONE_DARK, true)
	draw_rect(Rect2(372, 48, 112, 160), STONE_DARK, true)
	draw_rect(Rect2(112, 83, 288, 125), STONE, true)
	for x in range(36, 484, 24):
		var y0 := 58 if x < 140 or x >= 372 else 93
		draw_line(Vector2(x, y0), Vector2(x, 204), STONE.lightened(0.12), 1.0)
	for y in range(64, 204, 18):
		draw_line(Vector2(30, y), Vector2(482, y), STONE_DARK, 2.0)

	# world_gate は 48x48 が 4 コマ。最も開いた 3 コマ目を整数倍で使う。
	draw_texture_rect_region(
		GATE_TEX, Rect2(184, 28, 144, 144), Rect2(96, 0, 48, 48)
	)
	if show_worlds:
		var positions := [Vector2(80, 38), Vector2(426, 35), Vector2(72, 142), Vector2(439, 143)]
		for i in positions.size():
			_draw_world(positions[i], 18, WORLD_COLORS[i])

	var party_origin := Vector2(154, 139) if not oath else Vector2(148, 132)
	for i in PARTY_TEX.size():
		var row := 3 if oath else 0  # 誓いでは門へ背を向けず、上向きに立つ。
		var at := party_origin + Vector2(i * 48, (i % 2) * 6)
		draw_texture_rect_region(
			PARTY_TEX[i],
			Rect2(at, PORTRAIT * 2.0),
			Rect2(0, row * PORTRAIT.y, PORTRAIT.x, PORTRAIT.y)
		)


func _draw_scene_label() -> void:
	var location := String(_entry().get("location", ""))
	draw_rect(Rect2(8, 8, 250, 28), Color(0.02, 0.03, 0.08, 0.82), true)
	# 題と場所は外部化した文（`Lore` / `data`）なので長さを前提にしない。
	# 題は帯の中（250px）に、場所は画面の右端へ。
	UiPanel.inside(self, Rect2(16, 11, 234, PixelUI.LINE)).line(
		Lore.PROLOGUE_TITLE, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	if location != "":
		UiPanel.inside(self, Rect2(256, 13, 240, PixelUI.LINE)).row(
			"", location, PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM)


func _draw_text_window() -> void:
	PixelUI.draw_window(self, TEXT_RECT, WINDOW_TEX)
	var origin := PixelUI.content(TEXT_RECT).position
	var speaker := String(_entry().get("speaker", ""))
	var inner := PixelUI.content(TEXT_RECT)
	var panel := UiPanel.inside(self, Rect2(
		origin + Vector2(8, 1), Vector2(inner.size.x - 16.0, inner.size.y - 2.0)))
	panel.line(speaker, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	panel.skip(6.0)
	# **折り返し幅を手で書かない。** 468 は窓の寸法を変えると古くなる。
	# 入らない行は `paragraph()` が捨てて数える。
	for raw_line in _entry().get("lines", []):
		panel.paragraph(String(raw_line))

	if fmod(_time, 1.0) > 0.78:
		return
	var prompt := String(_entry().get("prompt", ""))
	UiPanel.inside(self, Rect2(
		origin + Vector2(8, 76), Vector2(inner.size.x - 16.0, PixelUI.LINE)
	# 序章の文は `Lore` 側（漢字を含む）。**14px より下げない**（D-5）。
	)).row("", prompt, PixelUI.C_TEXT_DIM, PixelUI.C_TEXT_DIM)
