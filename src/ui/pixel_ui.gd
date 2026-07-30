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

# --------------------------------------------------------------------------
# はみ出し検出（`--ui-check` を付けたときだけ働く）
#
# 「枠から文字がはみ出ている」は何度も出た。目で見て気づける類ではあるが、
# 画面が増えるほど見落とすし、直したあとに別の画面で再発する。
# **測る側を用意して、機械に見つけさせる。**
#
# 仕組みは単純で、`draw_window` が描いた窓の内側を覚えておき、
# `draw_text` のたびに「文字の始点を含む窓」を探して、文字の右端と下端が
# その内側に収まっているかを見る。呼び出し側は 1 行も変えなくてよい。
# --------------------------------------------------------------------------

## 枠からの許容（1px は詰めすぎの調整で出るので許す）。
const OVERFLOW_SLACK := 1.5

static var _ui_check := -1
static var _windows: Array[Rect2] = []

## 開きかけの窓（`opening()` が印を付ける）。ここに在る窓は測らない。
static var _animating: Dictionary = {}
static var _violations: Array[String] = []

## 描いた文字の位置（窓ごと）。**文字どうしの重なりを見るために持つ。**
##
## 枠の中に収まっていても、隣の列の文字に食い込めば読めない。
## 枠だけ見ていたので、てんしょく の ★ が隣の職業名に届いているのを
## 通してしまった。**「枠から出ない」と「重ならない」は別の条件。**
static var _texts: Array = []


static func ui_check_enabled() -> bool:
	if _ui_check < 0:
		_ui_check = 1 if "--ui-check" in OS.get_cmdline_user_args() else 0
	return _ui_check == 1


## 検出した違反の一覧（撮影やテストが読む）。
static func ui_violations() -> Array[String]:
	return _violations


## 1 フレームの始まり。**各 View の `_draw()` 冒頭で呼ぶ。**
##
## もとは「最初の窓が再登場したら次のフレーム」と推測していたが、画面によって
## 取りこぼした（戦記でテンプレート文と AI 文が重なっていると誤報した）。
## 開きかけの窓で学んだのと同じで、**推測より印**。
## 呼び忘れても壊れない（前のフレームの文字が残るだけで、誤報が増える方向）。
static func ui_frame() -> void:
	# **窓も捨てる。** 溜めたままだと前の画面の窓に収まっていると誤認するし、
	# 同じ矩形が毎フレーム積み上がる。窓は自分の `_draw()` の中で
	# 文字より先に描かれるので、フレーム頭で捨てて困らない。
	_windows.clear()
	if ui_check_enabled():
		_texts.clear()


static func ui_check_reset() -> void:
	_clipped.clear()
	_windows.clear()
	_violations.clear()
	_animating.clear()
	_texts.clear()


## その位置を含むいちばん小さい窓（無ければ空）。
##
## 窓が重なっている画面があるので、**始点を含む最小のもの**を相手にする。
static func _host_window(top_left: Vector2) -> Rect2:
	var host := Rect2()
	var found := false
	for w in _windows:
		if not w.has_point(top_left + Vector2(1, 1)):
			continue
		if not found or w.get_area() < host.get_area():
			host = w
			found = true
	return host if found else Rect2()


## 窓の右端に収まるよう詰める。窓の外に置いた文字（HUD の見出しなど）は触らない。
static func _fit(top_left: Vector2, text: String, size: int) -> String:
	if text == "":
		return text
	var host := _host_window(top_left)
	if host.size == Vector2.ZERO:
		return text
	var room := host.end.x - top_left.x
	if room <= 0.0 or text_width(text, size) <= room + OVERFLOW_SLACK:
		return text
	var cut := clip(text, room, size)
	var note := "「%s」を詰めた（窓 %s）" % [text.substr(0, 18), str(host)]
	if note not in _clipped:
		_clipped.append(note)
	return cut


## 文字が窓の内側に収まっているかを見る。
static func _note_text(top_left: Vector2, text: String, size: int) -> void:
	if not ui_check_enabled() or text.strip_edges() == "":
		return
	var extent := font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var box := Rect2(top_left, extent)
	# 始点を含むいちばん小さい窓を相手にする（窓が重なっている画面があるため）。
	var host := Rect2()
	var found := false
	for w in _windows:
		if not w.has_point(top_left + Vector2(1, 1)):
			continue
		if not found or w.get_area() < host.get_area():
			host = w
			found = true
	if not found:
		return  # 窓の外に直接置いている文字（HUD の見出しなど）は対象外
	var over_x := box.end.x - host.end.x
	var over_y := box.end.y - host.end.y
	if over_x > OVERFLOW_SLACK or over_y > OVERFLOW_SLACK:
		var note := "「%s」が %.0fx%.0f はみ出し（窓 %s）" % [
			text.substr(0, 18), maxf(over_x, 0.0), maxf(over_y, 0.0), str(host)
		]
		if note not in _violations:
			_violations.append(note)

	# 同じ窓に描いた他の文字と重なっていないか。
	# 縦は行送りで詰めることがあるので、**横の重なりだけ**を見る
	# （縦を見ると、詰めた一覧が全部違反になって使えなくなる）。
	for other in _texts:
		if other["host"] != host:
			continue
		var b: Rect2 = other["box"]
		# **同じ文字が同じ場所に来たのは、次のフレームの描き直し。**
		# 毎フレーム記録しているので、これを弾かないと自分自身と重なる。
		if String(other["text"]) == text and b.position.distance_to(box.position) < 1.0:
			return
		# 同じ行と見なす縦の差。
		#
		# **4px より広げてはいけない。** 9px にしたら誤検出が溢れた ―― 戦闘画面は
		# 同じ窓（MESSAGE_RECT）をメッセージとコマンドで描き分けるので、
		# フレームの区切りが取りこぼされると別状態の文字どうしが並んで見える。
		# サイズ違いの接触（見出し 17px と添え物 12px が 6px 差）は取りこぼすが、
		# 誤検出だらけのゲートは誰も読まないので、狭いほうを選ぶ。
		var same_row := absf(b.position.y - box.position.y) < 4.0
		if not same_row:
			continue
		var overlap := minf(b.end.x, box.end.x) - maxf(b.position.x, box.position.x)
		if overlap > OVERFLOW_SLACK:
			var clash := "「%s」と「%s」が %.0f 重なる" % [
				String(other["text"]).substr(0, 12), text.substr(0, 12), overlap
			]
			if clash not in _violations:
				_violations.append(clash)
	_texts.append({"host": host, "box": box, "text": text})


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
## 窓の外へ文字が出た回数。**切り詰めた回数**であって、はみ出した回数ではない。
##
## 横のはみ出しは `draw_text` が自動で `…` に詰めるので、遊ぶ側には見えない。
## だが**詰まっていること自体が割り付けの誤り**なので、数えて関門に見せる。
static var _clipped: Array[String] = []


static func clipped() -> Array[String]:
	return _clipped


## 詰めたことを控える。`UiPanel` が列の幅で詰めたときにも通る。
static func note_clipped(text: String) -> void:
	var note := "「%s」を詰めた" % text.substr(0, 18)
	if note not in _clipped:
		_clipped.append(note)


## 文字を置く。**窓からはみ出す分は自動で `…` に詰める。**
##
## 以前は幅を取らず、151 か所の呼び出しのうち幅で切っていたのは 7 か所だけだった。
## つまり**内容が長ければ枠を突き抜けるのが既定**で、「銀の砦で枠から文字が
## はみ出る」「転職の画面がはみ出る」はどちらもそれが素で出たもの。
## 呼ぶ側の注意に頼るのをやめ、ここで収める。
##
## 縦は詰められない（下へ溢れた文字は消すしかなく、消すと黙って欠ける）ので、
## そちらは `_note_text` が違反として挙げたまま。縦は `UiPanel` が
## 「入らない行は描かずに数える」ことで構造的に防ぐ。
static func draw_text(
	canvas: CanvasItem, top_left: Vector2, text: String,
	color: Color = C_TEXT, size: int = SIZE_TEXT
) -> void:
	text = _fit(top_left, text, size)
	_note_text(top_left, text, size)
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


## 窓の中の階調。上を明るく、下を沈ませる。
##
## **半透明にしただけでは後期 SFC にならない。** 透過は要素のひとつでしかなく、
## DQ6 の窓が richer に見えたのは、透過に加えて「中の階調」「面取り」「落ち影」が
## 全部乗っていたから。単色の板に枠を描くと、透けていてもファミコンに見える。
const WINDOW_TOP := Color8(0x30, 0x4C, 0x9C)
const WINDOW_BOTTOM := Color8(0x0C, 0x14, 0x3C)

## 階調を何段で塗るか。**わざと段にする。**
## SFC の階調は実際に段になっていて、滑らかに繋ぐとむしろ時代がずれる。
const WINDOW_BANDS := 12

## 面取りの色。内側の上辺と左辺に明線、下辺と右辺に暗線を置くと厚みが出る。
const WINDOW_BEVEL_LIGHT := Color8(0x6C, 0x90, 0xE0)
const WINDOW_BEVEL_DARK := Color8(0x06, 0x0A, 0x20)

## 窓の落ち影。背景から浮かせる。
const WINDOW_SHADOW := Vector2(3, 3)


## 青い窓を 9-slice で描く。
##
## 単純な draw_texture_rect だと枠ごと引き伸ばされ、角の 1px 線が太くなって
## 一気に「ドット絵でないもの」に見える。角は等倍、辺は 1 方向だけ、
## 中央は両方向へ伸ばす。
##
## 順番は 落ち影 → 枠 → 中の階調 → 面取り。階調を枠より先に塗ると枠が沈む。
static func draw_window(
	canvas: CanvasItem, rect: Rect2, texture: Texture2D, alpha: float = WINDOW_ALPHA
) -> void:
	if true:
		# **開きかけの窓は測らない。** `opening()` が縦に縮めた矩形を渡してくるので、
		# その最中の文字は必ず外に出る（誤検出になる）。開き終わった窓は
		# 高さが整数なので、端数のものを除けば見分けられる。
		var seen := content(rect)
		# is_equal_approx の許容では 100.9996 を「整数」と見てしまう。
		# 開きかけの窓を確実に外すため、判定はこちらで厳しく置く。
		# 高さだけでなく**位置も**整数であることを見る。開きかけの窓は上下へ
		# 伸びるので、位置も端数になる（高さ 15.00027 / 位置 98.49986 のように）。
		var settled := (
			absf(seen.size.y - roundf(seen.size.y)) < 0.0001
			and absf(seen.position.y - roundf(seen.position.y)) < 0.0001
		)
		if settled and seen not in _windows:
			_windows.append(seen)

	# 1. 落ち影。背景の上に置かれている、と読めるようにする。
	canvas.draw_rect(
		Rect2(rect.position + WINDOW_SHADOW, rect.size), Color(0.0, 0.0, 0.03, alpha * 0.5), true
	)

	# 2. 枠（9-slice）
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

	# 3. 中の階調
	var inner := rect.grow(-FRAME)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var step := inner.size.y / float(WINDOW_BANDS)
	for i in WINDOW_BANDS:
		var k := float(i) / float(maxi(WINDOW_BANDS - 1, 1))
		var band := Rect2(
			inner.position.x, floorf(inner.position.y + step * i),
			inner.size.x, ceilf(step) + 1.0
		)
		canvas.draw_rect(band, Color(WINDOW_TOP.lerp(WINDOW_BOTTOM, k), alpha * 0.8), true)

	# 4. 面取り。1px の明暗 2 本で厚みが出る（枠の絵を描き替えずに済む）。
	var light := Color(WINDOW_BEVEL_LIGHT, alpha * 0.85)
	var dark := Color(WINDOW_BEVEL_DARK, alpha * 0.85)
	canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), light, true)
	canvas.draw_rect(Rect2(inner.position, Vector2(1, inner.size.y)), light, true)
	canvas.draw_rect(
		Rect2(inner.position.x, inner.end.y - 1, inner.size.x, 1), dark, true
	)
	canvas.draw_rect(
		Rect2(inner.end.x - 1, inner.position.y, 1, inner.size.y), dark, true
	)


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
## ゲージ。**単色の帯にしない。**
##
## 後期 SFC のバーは、上端に明線・下端に暗線が入った円柱状の階調だった。
## 5px しかない帯でも、上 1px を明るく・下 1px を暗くするだけで管に見える。
##
## `previous` に前の割合を渡すと、減ったぶんを暗い色で残す（残像）。
## 数字を読まなくても「いま何点減ったか」が幅で分かる。
static func draw_gauge(
	canvas: CanvasItem, rect: Rect2, ratio: float, fill: Color, previous: float = -1.0
) -> void:
	canvas.draw_rect(rect, C_SHADOW, true)
	var inner := Rect2(rect.position + Vector2.ONE, rect.size - Vector2(2, 2))
	canvas.draw_rect(inner, Color8(0x14, 0x24, 0x58), true)

	var now := clampf(ratio, 0.0, 1.0)
	# 減ったぶんの残像。いまの値より広いときだけ描く。
	if previous > now:
		var ghost := Rect2(inner.position, Vector2(inner.size.x * clampf(previous, 0.0, 1.0), inner.size.y))
		canvas.draw_rect(ghost, Color(fill.darkened(0.55), 0.85), true)

	var width := inner.size.x * now
	if width <= 0.0:
		return
	var bar := Rect2(inner.position, Vector2(width, inner.size.y))
	canvas.draw_rect(bar, fill, true)
	# 上に明線、下に暗線。これで平らな帯が管になる。
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x, 1)), fill.lightened(0.45), true)
	if bar.size.y >= 3.0:
		canvas.draw_rect(
			Rect2(bar.position.x, bar.end.y - 1, bar.size.x, 1), fill.darkened(0.4), true
		)


## 窓を開くときの拡大。t は 0..1。
##
## 一瞬で出ると板が貼られたように見える。SFC 期の窓は必ず縦に開いた。
## 中心から上下へ伸ばすので、開き終わりが指定した矩形と一致する。
static func opening(rect: Rect2, t: float) -> Rect2:
	var ratio := clampf(t, 0.08, 1.0)
	var height := rect.size.y * ratio
	var shrunk := Rect2(
		rect.position.x, rect.position.y + (rect.size.y - height) * 0.5,
		rect.size.x, height
	)
	# 開きかけの窓は**はみ出し検出の対象から外す**。
	#
	# 縮んだ窓に通常の文字を描くのだから、必ず外に出る（誤検出になる）。
	# 端数で見分けようとしたが、途中でちょうど整数の寸法になる瞬間があって
	# 取りこぼした。**縮めた本人が印を付けるのが確実。**
	if ui_check_enabled() and ratio < 1.0:
		_animating[content(shrunk)] = true
	return shrunk


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


## 幅に収まるところまで切って、末尾に … を付ける。
##
## 折り返せない場所（一覧の 1 行）で使う。**溢れた文字は読めないので出さない。**
static func clip(text: String, width: float, size: int = SIZE_TEXT) -> String:
	if text_width(text, size) <= width:
		return text
	var cut := text
	while cut.length() > 1 and text_width(cut + "…", size) > width:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "…"


static func hp_color(ratio: float) -> Color:
	return C_HP_LOW if ratio <= 0.25 else C_HP_OK
