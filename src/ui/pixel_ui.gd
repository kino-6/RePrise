class_name PixelUI
extends RefCounted

## ドット絵の画面に馴染む UI 部品。
##
## フォントは Windows 標準の MS ゴシックを、アンチエイリアスとサブピクセル配置を
## 切って使う。日本語のドットフォントを自作すると数千字を描く羽目になるが、
## この設定なら小サイズで十分に「SFC の文字」に見える。
##
## 文字の座標は**左上**で指定する。draw_string はベースライン基準なので、
## そのまま渡すと窓枠に文字がめり込む（実際にそうなっていた）。
## 変換は draw_text の中で 1 回だけ行い、各画面には持ち込まない。

# 画面の基準サイズ。
#
# 384x240 から上げてある。漢字は 14px 未満で画数が潰れる（下記 SIZE_* 参照）ため、
# 384 幅では「読める文字」を並べると 1 行に入る字数が足りなくなった。
# タイル 16px / キャラ 24x32 は据え置きなので、絵の資産はそのまま使える。
const SCREEN := Vector2i(512, 320)

# 文字サイズ。tests/_font_probe.gd で実測して決めた。
#
# MS ゴシックの漢字は 13px を下回ると画数が団子になって読めない
# （銀・響・深・階が特にひどい）。だから規約を 2 つ置く。
#   * 漢字を出してよいのは SIZE_TEXT 以上
#   * SIZE_SUB は かな・数字・記号だけ
const SIZE_HEAD := 17  ## 窓の見出し
const SIZE_TEXT := 14  ## 本文と一覧（漢字を出してよい下限）
const SIZE_SUB := 12  ## 添え物の数値（かなと数字のみ）

## 標準の行送り。詰めたいときだけ各画面で上書きする。
const LINE := 18

## 窓の枠が実際に塗られている厚み（window.png の外周）。
## 9-slice の margin は 8 だが、絵として線が乗っているのは外周 4px ほど。
## 文字はここより内側に置く。
const FRAME := 4.0

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


## 影付きの文字。位置は**左上**で指定する。
##
## SFC の UI はほぼ必ず 1px の影が入っていて、これがあるだけで背景に負けず読める。
static func draw_text(
	canvas: CanvasItem, top_left: Vector2, text: String,
	color: Color = C_TEXT, size: int = SIZE_TEXT
) -> void:
	var at := Vector2(top_left.x, top_left.y + font().get_ascent(size)).floor()
	canvas.draw_string(font(), at + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, C_SHADOW)
	canvas.draw_string(font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 右端を揃えて置く。数値を右寄せするために使う。
static func draw_text_right(
	canvas: CanvasItem, right_top: Vector2, text: String,
	color: Color = C_TEXT, size: int = SIZE_TEXT
) -> void:
	draw_text(canvas, Vector2(right_top.x - text_width(text, size), right_top.y), text, color, size)


static func text_width(text: String, size: int = SIZE_TEXT) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func text_height(size: int = SIZE_TEXT) -> float:
	return font().get_ascent(size) + font().get_descent(size)


## 幅に収まるよう折り返す。
##
## 日本語は分かち書きしないので、単語境界ではなく 1 文字ずつ測って折る。
## 戦記（chronicle）は覚えた技を全部並べるので長さが読めず、実際に溢れていた。
## 将来ここに LLM の文章が流れてくる予定なので、長さを前提にしない。
##
## 行頭に置きたくない字（句読点や閉じ括弧）だけは前の行に残す。
const NO_LINE_HEAD := "、。，．）」』】ぁぃぅぇぉっゃゅょ・！？"


static func wrap(text: String, max_width: float, size: int = SIZE_TEXT) -> PackedStringArray:
	var lines: PackedStringArray = []
	var line := ""
	for i in text.length():
		var ch := text[i]
		if text_width(line + ch, size) <= max_width or line == "":
			line += ch
			continue
		# 行頭に来てはいけない字なら、1 字だけ前の行へ食い込ませる
		if NO_LINE_HEAD.contains(ch):
			line += ch
			lines.append(line)
			line = ""
			continue
		lines.append(line)
		line = ch
	if line != "":
		lines.append(line)
	return lines


## 窓の内側。文字はここを基準に置けば、どのサイズでも枠に触れない。
static func content(rect: Rect2, pad := 3.0) -> Rect2:
	return rect.grow(-(FRAME + pad))


const WINDOW_MARGIN := 8.0

## 窓の不透明度。
##
## 後期 SFC の画面が richer に見えた理由のひとつが、PPU のカラーマス
## （加算・減算合成）による半透明の窓。不透明な板を置くのはファミコンの作法で、
## 下の絵が透けるだけで一気に世代が変わる。
##
## 0.7 を下回ると文字の影が背景に負けて読みにくくなるので、そこが下限。
const WINDOW_ALPHA := 0.72


## 青い窓を 9-slice で描く。
##
## 単純な draw_texture_rect だと枠ごと引き伸ばされ、角の 1px 線が太くなって
## 一気に「ドット絵でないもの」に見える。角は等倍、辺は 1 方向だけ、
## 中央は両方向へ伸ばす。
static func draw_window(
	canvas: CanvasItem, rect: Rect2, texture: Texture2D, alpha: float = WINDOW_ALPHA
) -> void:
	var tint := Color(1.0, 1.0, 1.0, alpha)
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
				canvas.draw_texture_rect_region(texture, dst, src, tint)


## 画面の中央に出す一言（買った / たりない / おぼえた など）。
##
## 拠点・出店・探索メニュー・探索 HUD で同じ形の窓を 4 回書いていたので集約した。
## 幅は文字に合わせて伸ばす。中央寄せの箱は、幅を固定すると必ずどこかで溢れる。
static func draw_notice(
	canvas: CanvasItem, texture: Texture2D, text: String, y: float,
	color: Color = C_TEXT
) -> void:
	if text == "":
		return
	var width := text_width(text) + 36.0
	var box := Rect2((SCREEN.x - width) * 0.5, y, width, 36)
	draw_window(canvas, box, texture)
	draw_text(canvas, content(box).position + Vector2(8, 1), text, color)


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


## 窓を開くときの拡大。t は 0..1。
##
## 一瞬で出ると板が貼られたように見える。SFC 期の窓は必ず縦に開いた。
## 中心から上下へ伸ばすので、開き終わりが指定した矩形と一致する。
static func opening(rect: Rect2, t: float) -> Rect2:
	var ratio := clampf(t, 0.08, 1.0)
	var height := rect.size.y * ratio
	return Rect2(
		rect.position.x, rect.position.y + (rect.size.y - height) * 0.5,
		rect.size.x, height
	)


## 画面全体の光。強い魔法が当たった瞬間に 1 枚だけ重ねる。
## SFC 期は加算合成で画面を白く飛ばしていた。ここでは白の重ねで近似する。
static func draw_flash(canvas: CanvasItem, strength: float) -> void:
	if strength <= 0.0:
		return
	canvas.draw_rect(
		Rect2(Vector2.ZERO, SCREEN), Color(1.0, 1.0, 1.0, clampf(strength, 0.0, 0.6)), true
	)


## 縦のグラデーション。
##
## 一色で塗った背景は「絵が置かれていない」ように見える。SFC 期は背景に
## 必ず階調が入っていて、それだけで奥行きが出る。帯で塗るので負荷はゼロ。
static func draw_gradient(
	canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color, bands: int = 16
) -> void:
	var step := rect.size.y / float(maxi(bands, 1))
	for i in bands:
		var t := float(i) / float(maxi(bands - 1, 1))
		canvas.draw_rect(
			Rect2(rect.position.x, rect.position.y + i * step, rect.size.x, ceil(step)),
			top.lerp(bottom, t), true
		)


static func hp_color(ratio: float) -> Color:
	return C_HP_LOW if ratio <= 0.25 else C_HP_OK
