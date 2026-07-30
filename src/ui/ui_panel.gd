class_name UiPanel
extends RefCounted

## 窓ひとつぶんの割り付け。**はみ出しと重なりを構造的に起こさないための土台。**
##
## それまでは `PixelUI.draw_text()` を手計算の座標で 151 回呼んでいて、
## 幅で切っていたのは 7 回だけだった。`draw_text()` は幅を取らないので、
## **内容が長ければ枠を突き抜けるのが既定**だった。縦も手で足していたので、
## 行が重なるのも防げなかった。実際に出た指摘はどちらもこれが素で出たもの ――
## 「つよさ で文字が重なる」「銀の砦で枠からはみ出る」「転職の画面がはみ出る」。
##
## ここが持つ保証は 3 つ。
##
##   * **必ず内側に収める。** 幅を超える文字は `…` で詰めてから描く。
##     GPU で切り落とす手もあるが、字が途中で切れて汚い。
##     詰めるのは実機の RPG でもやっていたことで、こちらのほうが読める。
##   * **行は行高で進む。** 縦位置を手で足さないので重ならない。
##   * **左右 2 列がぶつかったら左を詰める。** 右（数値）は消えては困る。
##     「文字が重なる」の直接の原因がこれだった。
##
## 高さが足りなくなったら `overflowed()` が true になる。
## **黙って外へ描かない** ―― 描かずに、あとから数えられる形で残す。

var _canvas: CanvasItem
var _inner: Rect2
var _y: float = 0.0
var _overflow := 0


## 窓を描いて、その内側を持つ割り付けを返す。
##
## `title` を渡すと見出しを 1 行目に置く。`texture` は窓の地。
## 最後に描いた（詰めたあとの）文字。**単独テストが結果を読むための窓口。**
var last_text := ""


static func begin(
	canvas: CanvasItem, rect: Rect2, texture: Texture2D = null,
	title: String = "", pad: float = 3.0
) -> UiPanel:
	if texture != null:
		PixelUI.draw_window(canvas, rect, texture)
	var panel := UiPanel.new()
	panel._canvas = canvas
	panel._inner = PixelUI.content(rect, pad)
	panel._y = panel._inner.position.y
	if title != "":
		panel.line(title, PixelUI.C_ACTIVE, PixelUI.SIZE_HEAD)
	return panel


## 枠を描かずに、与えられた矩形の中だけを割り付ける。
##
## 窓の中をさらに 2 段に分けるときや、窓の外（HUD）に置くときに使う。
static func inside(canvas: CanvasItem, inner: Rect2) -> UiPanel:
	var panel := UiPanel.new()
	panel._canvas = canvas
	panel._inner = inner
	panel._y = inner.position.y
	return panel


## 内側の矩形。列を自分で組みたいときに読む。
func inner() -> Rect2:
	return _inner


## 次の行の上端。
func cursor_y() -> float:
	return _y


## 残りの高さ。
func remaining() -> float:
	return _inner.end.y - _y


## 入りきらなかった行があるか。**関門はここを見る。**
func overflowed() -> bool:
	return _overflow > 0


func dropped() -> int:
	return _overflow


## 幅に収める。**黙って詰めない** ―― 詰めたことを PixelUI に記録させる。
##
## 詰まっているのは割り付けの誤りなので、遊ぶ側に見えなくなった代わりに
## 開発側にも黙るのでは、関門を外したのと同じ。
static func _shrink(text: String, width: float, size: int) -> String:
	if PixelUI.text_width(text, size) <= width + PixelUI.OVERFLOW_SLACK:
		return text
	PixelUI.note_clipped(text)
	return PixelUI.clip(text, width, size)


## 1 行置く。幅を超える分は `…` で詰める。
func line(
	text: String, color: Color = PixelUI.C_TEXT, size: int = PixelUI.SIZE_TEXT,
	indent: float = 0.0
) -> void:
	var height := PixelUI.text_height(size)
	if _y + height > _inner.end.y + PixelUI.OVERFLOW_SLACK:
		# **入らないものは描かない。** 外へ描くと窓の外に文字が出る。
		_overflow += 1
		return
	var width := _inner.size.x - indent
	var shown := _shrink(text, width, size)
	last_text = shown
	# **描き手が居なくても割り付けは進む。** `_canvas` が null なら測るだけ。
	# 単独テスト（`tests/test_window_system.gd`）が窓を立てずに検査できる。
	if _canvas != null:
		PixelUI.draw_text(
			_canvas, Vector2(_inner.position.x + indent, _y), shown, color, size)
	_y += PixelUI.LINE


## 左と右を 1 行に置く。**ぶつかったら左を詰める。**
##
## 右は数値（Lv、値段、残り）なので、消えると意味が変わる。
## 左は名前なので、`…` で詰めても伝わる。
func row(
	left: String, right: String, left_color: Color = PixelUI.C_TEXT,
	right_color: Color = PixelUI.C_TEXT_DIM, size: int = PixelUI.SIZE_TEXT,
	indent: float = 0.0
) -> void:
	var height := PixelUI.text_height(size)
	if _y + height > _inner.end.y + PixelUI.OVERFLOW_SLACK:
		_overflow += 1
		return
	var right_width := PixelUI.text_width(right, size)
	# 右の手前に 1 文字ぶんの隙間を置く。詰めた `…` と数値がくっつくと読めない。
	var gap := PixelUI.text_width("　", size) * 0.5
	var left_room := _inner.size.x - indent - right_width - gap
	var shown := _shrink(left, maxf(left_room, 0.0), size)
	last_text = shown
	if _canvas != null:
		PixelUI.draw_text(
			_canvas, Vector2(_inner.position.x + indent, _y), shown, left_color, size)
		if right != "":
			PixelUI.draw_text_right(
				_canvas, Vector2(_inner.end.x, _y), right, right_color, size)
	_y += PixelUI.LINE


## 折り返して複数行置く。長さが読めない文章（イベント文、戦記、AI の文）に使う。
func paragraph(
	text: String, color: Color = PixelUI.C_TEXT, size: int = PixelUI.SIZE_TEXT
) -> void:
	# **折り返し幅を 1 文字ぶん狭く取る。** `wrap()` は行頭に置けない字
	# （、。）」など）を前の行へ送り返すので、指定した幅をわずかに超える行が出る。
	# 幅どおりに頼むと、そのぶんが `line()` 側で `…` に詰まって関門が鳴った。
	var room := _inner.size.x - PixelUI.text_width("あ", size)
	for row_text in PixelUI.wrap(text, room, size):
		line(row_text, color, size)


## 帯（HP/MP など）を 1 行ぶんの高さで置く。
func gauge(label: String, ratio: float, fill: Color, previous: float = -1.0) -> void:
	if _y + PixelUI.LINE > _inner.end.y + PixelUI.OVERFLOW_SLACK:
		_overflow += 1
		return
	var label_width := 0.0
	if label != "":
		label_width = PixelUI.text_width(label) + 4.0
		if _canvas != null:
			PixelUI.draw_text(_canvas, Vector2(_inner.position.x, _y), label)
	if _canvas == null:
		_y += PixelUI.LINE
		return
	PixelUI.draw_gauge(
		_canvas,
		Rect2(
			_inner.position.x + label_width, _y + 4.0,
			_inner.size.x - label_width, 6.0
		),
		ratio, fill, previous
	)
	_y += PixelUI.LINE


## 行を空ける。既定は 1 行ぶん。
func skip(pixels: float = PixelUI.LINE) -> void:
	_y += pixels


## 次の行を任意の位置から始める。表を組むときに使う。
func move_to(y: float) -> void:
	_y = y


## 内側を縦に 2 つへ割る。上を返し、下は `rest` で受け取る。
func split_v(at: float) -> Array[UiPanel]:
	var top := Rect2(_inner.position, Vector2(_inner.size.x, at))
	var bottom := Rect2(
		Vector2(_inner.position.x, _inner.position.y + at),
		Vector2(_inner.size.x, _inner.size.y - at)
	)
	return [UiPanel.inside(_canvas, top), UiPanel.inside(_canvas, bottom)]


## 内側を横に割る。列を組むときに使う（`gap` は列の間）。
func columns(count: int, gap: float = 6.0) -> Array[UiPanel]:
	var out: Array[UiPanel] = []
	var each := (_inner.size.x - gap * float(count - 1)) / float(maxi(count, 1))
	for i in count:
		out.append(UiPanel.inside(_canvas, Rect2(
			Vector2(_inner.position.x + (each + gap) * float(i), _y),
			Vector2(each, _inner.end.y - _y)
		)))
	return out
