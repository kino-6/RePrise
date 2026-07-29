class_name ExploreHud
extends Node2D

## 探索中の情報表示。カメラと一緒に動かないよう、マップとは別の階層に置く。

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const TOAST_TIME := 1.8

var members: Array[PartyMember] = []
var floor_number := 1
var gold := 0

var _toast := ""
var _toast_timer := 0.0


func _ready() -> void:
	set_process(true)


func refresh(party: Array[PartyMember], floor_no: int, gold_amount: int) -> void:
	members = party
	floor_number = floor_no
	gold = gold_amount
	queue_redraw()


func toast(text: String) -> void:
	_toast = text
	_toast_timer = TOAST_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast = ""
			queue_redraw()


func _draw() -> void:
	# 階層と所持金
	var head := Rect2(8, 8, 150, 32)
	PixelUI.draw_window(self, head, WINDOW_TEX)
	PixelUI.draw_text(
		self, PixelUI.content(head).position + Vector2(6, 1),
		Terms.FLOOR % floor_number, PixelUI.C_TEXT
	)

	var purse := Rect2(354, 8, 150, 32)
	PixelUI.draw_window(self, purse, WINDOW_TEX)
	PixelUI.draw_text_right(
		self, Vector2(PixelUI.content(purse).end.x - 4, PixelUI.content(purse).position.y + 1),
		"%d %s" % [gold, Terms.GOLD], PixelUI.C_TEXT
	)

	# パーティの体力（探索中も常に見えていないと引き際が判断できない）
	var status := Rect2(8, 268, 496, 44)
	PixelUI.draw_window(self, status, WINDOW_TEX)
	var inner := PixelUI.content(status)
	for i in members.size():
		var m := members[i]
		var base := inner.position + Vector2(6 + i * 122, 0)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		PixelUI.draw_text(self, base, m.name, name_color)
		PixelUI.draw_text(
			self, base + Vector2(62, 2), "%d/%d" % [m.hp, m.max_hp()],
			PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
		)
		PixelUI.draw_gauge(self, Rect2(base.x, base.y + 19, 112, 5), ratio, PixelUI.hp_color(ratio))

	if _toast != "":
		var width := PixelUI.text_width(_toast) + 36.0
		var box := Rect2((PixelUI.SCREEN.x - width) * 0.5, 212, width, 36)
		PixelUI.draw_window(self, box, WINDOW_TEX)
		PixelUI.draw_text(self, PixelUI.content(box).position + Vector2(8, 1), _toast, PixelUI.C_TEXT)
