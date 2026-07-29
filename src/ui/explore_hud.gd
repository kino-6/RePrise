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
	var head := Rect2(6, 6, 112, 24)
	PixelUI.draw_window(self, head, WINDOW_TEX)
	PixelUI.draw_text(self, head.position + Vector2(10, 16), "地下 %d 階" % floor_number, PixelUI.C_TEXT, 12)

	var purse := Rect2(266, 6, 112, 24)
	PixelUI.draw_window(self, purse, WINDOW_TEX)
	PixelUI.draw_text(self, purse.position + Vector2(10, 16), "%d ゴールド" % gold, PixelUI.C_TEXT, 12)

	# パーティの体力（探索中も常に見えていないと引き際が判断できない）
	var status := Rect2(6, 200, 372, 34)
	PixelUI.draw_window(self, status, WINDOW_TEX)
	for i in members.size():
		var m := members[i]
		var base := status.position + Vector2(10 + i * 92, 15)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		PixelUI.draw_text(self, base, m.name, name_color, 11)
		PixelUI.draw_text(self, base + Vector2(48, 0), "%d/%d" % [m.hp, m.max_hp()], PixelUI.C_TEXT_DIM, 10)
		PixelUI.draw_gauge(self, Rect2(base.x, base.y + 4, 84, 5), ratio, PixelUI.hp_color(ratio))

	if _toast != "":
		var box := Rect2(82, 158, 220, 26)
		PixelUI.draw_window(self, box, WINDOW_TEX)
		PixelUI.draw_text(self, box.position + Vector2(12, 17), _toast, PixelUI.C_TEXT, 12)
