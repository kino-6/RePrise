class_name MenuList
extends RefCounted

## 縦に並ぶ一覧の共通部分。
##
## 「カーソルを行の左に置く」「入る行数だけ切り出す」「続きがあることを示す」を
## 拠点・出店・戦闘・メニューで別々に書いていた。数式が 4 か所にあると、
## 1 か所だけ直して他が溢れる（実際に職業を 15 に増やしたときそうなった）。

## カーソルを行の左に置くときのずれ。文字の左上からの相対で持つ。
const CURSOR_OFFSET := Vector2(-15, 2)


## 入る行数だけ切り出すときの先頭行。
##
## カーソルを窓の中央付近に保つ。端に来たらそこで止める（行き過ぎると
## 一覧の末尾で空行が並ぶ）。
static func top_of(index: int, total: int, visible: int) -> int:
	if total <= visible:
		return 0
	@warning_ignore("integer_division")
	var centered := index - visible / 2
	return clampi(centered, 0, total - visible)


## 表示する行の範囲（先頭と、その次に来る行）。
static func range_of(index: int, total: int, visible: int) -> Array[int]:
	var top := top_of(index, total, visible)
	return [top, mini(top + visible, total)]


## 選択カーソル。**2 倍に引き伸ばして描く。**
##
## 8x8 の等倍だと 14px の文字の隣で小さすぎて、どの行を選んでいるか
## 一目で分からない（「→ が小さい」と言われた）。整数倍なのでドットは崩れない。
const CURSOR_SCALE := 2.0


static func draw_cursor(canvas: CanvasItem, texture: Texture2D, row_top_left: Vector2) -> void:
	var size := texture.get_size() * CURSOR_SCALE
	# 2 倍にしたぶん、行の中心に来るように左と上へ寄せ直す。
	# 2 倍にしたぶんは**下へだけ**寄せ直す。左へ引くと枠に食い込む
	# （8px ぶん左に出て、窓の縁を跨いだ）。
	var at := row_top_left + CURSOR_OFFSET - Vector2(size.x * 0.25, size.y * 0.25 - 2.0)
	canvas.draw_texture_rect(texture, Rect2(at.floor(), size), false)


## 「いま何番目か」を右下に出す。続きがあることを隠すと、
## 見えない選択肢を選べない状態になって一番たちが悪い。
static func draw_position(
	canvas: CanvasItem, inner: Rect2, index: int, total: int, visible: int
) -> void:
	if total <= visible:
		return
	PixelUI.draw_text_right(
		canvas, Vector2(inner.end.x - 2, inner.end.y - 14),
		"%d/%d" % [index + 1, total], PixelUI.C_TEXT_DIM, PixelUI.SIZE_SUB
	)
