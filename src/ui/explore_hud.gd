class_name ExploreHud
extends Node2D

## 探索中の情報表示。カメラと一緒に動かないよう、マップとは別の階層に置く。

const WINDOW_TEX: Texture2D = preload("res://assets/ui/window.png")
const TOAST_TIME := 1.8

var members: Array[PartyMember] = []

## 左上に出す 1 行。「洞 2階 / 危険度 5」のように、居場所と危険度を並べる。
##
## 危険度だけだと、同じ数字が世界の上にも洞の中にもあって混乱する。
## 居場所を先に書くと「深いところに居るから危ない」が読める。
var place_label := Terms.DANGER_AT % 1

var _toast := ""
var _toast_timer := 0.0


func _ready() -> void:
	set_process(true)


func refresh(
	party: Array[PartyMember], floor_no: int, place: String = ""
) -> void:
	members = party
	place_label = place if place != "" else Terms.DANGER_AT % floor_no
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
	PixelUI.ui_frame()
	# 居場所だけを常時表示する。
	#
	# ゴールドは店と入手通知で必要なときに読める。探索中まで右上へ固定すると、
	# その下にある宝箱・人物・入口を隠すため、常設しない。
	# 封の残りを足したぶん、見出しの窓を広げる（3px 溢れていた）。
	var head := Rect2(8, 8, 186, 32)
	PixelUI.draw_window(self, head, WINDOW_TEX)
	# `content()` が枠ぶんの余白を既に引いている。ここをさらに縮めると
	# 高さが本文1行を下回り、UiPanel が現在地を丸ごと捨ててしまう。
	UiPanel.inside(self, PixelUI.content(head)).line(
		place_label, PixelUI.C_TEXT)

	# パーティの体力（探索中も常に見えていないと引き際が判断できない）
	var status := Rect2(8, 268, 496, 44)
	PixelUI.draw_window(self, status, WINDOW_TEX)
	var inner := PixelUI.content(status)
	for i in members.size():
		var m := members[i]
		var base := inner.position + Vector2(6 + i * 122, 0)
		var ratio := float(m.hp) / maxf(float(m.max_hp()), 1.0)
		var name_color := PixelUI.C_TEXT if m.hp > 0 else PixelUI.C_HP_LOW
		# 毒は歩くたびに削るので、探索中こそ見えていないといけない。
		if m.poison_steps > 0 and m.hp > 0:
			name_color = PixelUI.C_MP
		# **1 人ぶんの持ち幅は 112px。** 4 人が横に並ぶので、名前が長い人が
		# 隣の人へ食い込むと誰の HP か分からなくなる。列として幅を渡す。
		var poisoned := m.poison_steps > 0 and m.hp > 0
		UiPanel.inside(self, Rect2(
			base, Vector2(58.0 if poisoned else 58.0, PixelUI.LINE)
		)).line(m.name, name_color)
		if poisoned:
			UiPanel.inside(self, Rect2(
				base + Vector2(62, 2), Vector2(30.0, PixelUI.LINE)
			)).line("どく", PixelUI.C_HP_LOW, PixelUI.SIZE_SUB)
		var hp_at := Vector2(62, 2) if not poisoned else Vector2(96, 2)
		UiPanel.inside(self, Rect2(
			base + hp_at, Vector2(112.0 - hp_at.x, PixelUI.LINE)
		)).line("%d/%d" % [m.hp, m.max_hp()], PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB)
		PixelUI.draw_gauge(self, Rect2(base.x, base.y + 19, 112, 5), ratio, PixelUI.hp_color(ratio))

	PixelUI.draw_notice(self, WINDOW_TEX, _toast, 212.0)
