class_name TurnOrderBar
extends Node2D

## 行動順バー。CTB の心臓部を、そのままプレイヤーに見せる装置。
##
## ATB の緊張感の正体は「時間」ではなく「順番の奪い合い」なので、
## 順番を可視化してしまえばターン制のまま同じ駆け引きが成立する。
## 重い技を撃つと自分の札が右へ流れる、という因果が目で見えることが重要。

const PLATE_W := 33
const PLATE_H := 16
const GAP := 2
const MAX_SHOWN := 10

var order: Array[Battler] = []


func set_order(list: Array[Battler]) -> void:
	order = list
	queue_redraw()


func _draw() -> void:
	if order.is_empty():
		return

	PixelUI.draw_text(self, Vector2(3, 13), "順", PixelUI.C_TEXT_DIM, 11)

	var x := 18.0
	for i in mini(order.size(), MAX_SHOWN):
		var b := order[i]
		var plate := Rect2(x, 2, PLATE_W, PLATE_H)
		var base := PixelUI.C_ALLY if b.is_ally else PixelUI.C_ENEMY

		# 先頭＝今から動く者だけを金枠で立てる
		var is_current := i == 0
		draw_rect(plate, PixelUI.C_SHADOW, true)
		draw_rect(Rect2(plate.position + Vector2.ONE, plate.size - Vector2(2, 2)), base, true)
		if is_current:
			draw_rect(plate, PixelUI.C_ACTIVE, false, 1.0)

		var label := _short_name(b)
		var color := PixelUI.C_ACTIVE if is_current else PixelUI.C_TEXT
		PixelUI.draw_text(self, Vector2(x + 3, 14), label, color, 11)

		# 手番が近いほど不透明に。奥行きが出て「これから起きること」の順序が読める。
		if not is_current:
			var fade := Color(0, 0, 0, 0.10 * i)
			draw_rect(Rect2(plate.position + Vector2.ONE, plate.size - Vector2(2, 2)), fade, true)

		x += PLATE_W + GAP


## 29px の札に収まるよう名前を詰める。
func _short_name(b: Battler) -> String:
	var n := b.name
	return n if n.length() <= 2 else n.substr(0, 2)
