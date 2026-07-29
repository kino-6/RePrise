class_name PixelUI
extends RefCounted

## ドット絵の画面に馴染む UI 部品。
##
## フォントは Windows 標準の MS ゴシックを、アンチエイリアスとサブピクセル配置を
## 切って使う。日本語のドットフォントを自作すると数千字を描く羽目になるが、
## この設定なら小サイズで十分に「SFC の文字」に見える。

const FONT_SIZE := 12
const LINE_HEIGHT := 14

# 画面の基準サイズ（後期 SFC 相当）
const SCREEN := Vector2i(384, 240)

# assets/ の生成パレットと同じ色を使う。ここがずれると UI だけ浮く。
const C_TEXT := Color8(0xF8, 0xF8, 0xF8)
const C_TEXT_DIM := Color8(0x9C, 0xB4, 0xE0)
const C_SHADOW := Color8(0x00, 0x08, 0x14)
const C_ALLY := Color8(0x26, 0x48, 0xA0)
const C_ENEMY := Color8(0x8A, 0x28, 0x28)
const C_ACTIVE := Color8(0xE0, 0xB0, 0x48)
const C_HP_OK := Color8(0x38, 0xB4, 0x6C)
const C_HP_LOW := Color8(0xE0, 0x60, 0x30)
const C_MP := Color8(0x4A, 0x78, 0xC8)

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["MS Gothic", "ＭＳ ゴシック", "Yu Gothic UI", "Meiryo"])
		# ドット絵の隣でぼやけないよう、にじみの原因を全部止める
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.hinting = TextServer.HINTING_NORMAL
		f.allow_system_fallback = true
		_font = f
	return _font


## 影付きの文字。SFC の UI はほぼ必ず 1px の影が入っていて、
## これがあるだけで背景に負けず読めるようになる。
static func draw_text(
	canvas: CanvasItem, pos: Vector2, text: String,
	color: Color = C_TEXT, size: int = FONT_SIZE
) -> void:
	canvas.draw_string(font(), pos + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, C_SHADOW)
	canvas.draw_string(font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_width(text: String, size: int = FONT_SIZE) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


const WINDOW_MARGIN := 8.0


## 青い窓を 9-slice で描く。
##
## 単純な draw_texture_rect だと枠ごと引き伸ばされ、角の 1px 線が太くなって
## 一気に「ドット絵でないもの」に見える。角は等倍、辺は 1 方向だけ、
## 中央は両方向へ伸ばす。
static func draw_window(canvas: CanvasItem, rect: Rect2, texture: Texture2D) -> void:
	var tex := texture.get_size()
	var m := WINDOW_MARGIN
	var src_x := [0.0, m, tex.x - m, tex.x]
	var src_y := [0.0, m, tex.y - m, tex.y]
	var dst_x := [rect.position.x, rect.position.x + m, rect.end.x - m, rect.end.x]
	var dst_y := [rect.position.y, rect.position.y + m, rect.end.y - m, rect.end.y]

	for i in 3:
		for j in 3:
			var src := Rect2(src_x[i], src_y[j], src_x[i + 1] - src_x[i], src_y[j + 1] - src_y[j])
			var dst := Rect2(dst_x[i], dst_y[j], dst_x[i + 1] - dst_x[i], dst_y[j + 1] - dst_y[j])
			if dst.size.x > 0.0 and dst.size.y > 0.0:
				canvas.draw_texture_rect_region(texture, dst, src)


## HP / MP のゲージ。数値だけより残量が一目で分かる。
static func draw_gauge(
	canvas: CanvasItem, rect: Rect2, ratio: float, fill: Color
) -> void:
	canvas.draw_rect(rect, C_SHADOW, true)
	var inner := Rect2(rect.position + Vector2.ONE, rect.size - Vector2(2, 2))
	canvas.draw_rect(inner, Color8(0x18, 0x30, 0x70), true)
	inner.size.x = maxi(int(inner.size.x * clampf(ratio, 0.0, 1.0)), 0)
	if inner.size.x > 0:
		canvas.draw_rect(inner, fill, true)


static func hp_color(ratio: float) -> Color:
	return C_HP_LOW if ratio <= 0.25 else C_HP_OK
