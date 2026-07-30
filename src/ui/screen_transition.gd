class_name ScreenTransition
extends ColorRect

## 遭遇の切り替え ―― 画面をモザイクに崩して戻す。
##
## 調査と根拠は `docs/screen_transition_design.md`。要点だけ再掲する。
##
## SFC の明度レジスタは**暗くする方向にしか無い**（既定が最大輝度）。
## 白く飛ばすのはハードの機能ではなく、わざわざやる部類の演出だった。
## 一方 FC は全画面演出がパレット差し替えしか無く、必然的に閃光へ寄る。
## **白く 2 回瞬く画面が「FC っぽい」のは趣味ではなく出自の問題**なので、
## 白を捨ててモザイク（`$2106` 相当）に替える。
##
## 守ること:
##
##   * **失敗しても進行を変えない。** シェーダが無ければ `play()` は false を
##     返し、呼び出し側は素の暗転へ落ちる。演出は飾りで、乱数にもセーブにも
##     触らない（`EventEffect` と同じ約束）。
##   * **切り替えは必ず起きる。** 絵が出せなくても `apply` は呼ぶ。
##     演出の失敗で戦闘に入れない、が最悪の壊れ方。
##   * **短く。** 遭遇は 1 ラン中に何十回も通る。

const SHADER_PATH := "res://src/ui/mosaic.gdshader"

## 粒の段。実機は 1〜16 画素で、途中の 3.7 画素のような粒は無い。
## 後半を粗く飛ばして「引きずり込まれる」加速をつける。
const BLOCKS: Array[float] = [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 11.0, 16.0]

## 明度の段数。実機の INIDISP と同じ 16 段（0..15）。
## 滑らかに補間すると現代のフェードになる。段つきがあの手触りを作る。
const BRIGHT_STEPS := 15.0

const IN_TIME := 0.30
const OUT_TIME := 0.20

## 場面転換の覆い。遭遇より少しだけ長い ―― こちらは前後を切るのが仕事なので、
## 覆いきった一瞬が要る。それでも長くはしない（何十回も通る）。
const COVER_IN_TIME := 0.32
const COVER_OUT_TIME := 0.26

var _tween: Tween = null

## 場面転換の覆い（B-3）。遭遇のモザイクとは別物なので、別の子に描かせる。
## **同じ CanvasItem に描くとモザイクのシェーダが覆いにも掛かる。**
var _cover: Cover = null


## 8 コマのアトラスを全画面へ引き伸ばして覆う板。
##
## `assets/transitions/*.png` は 64x40 の 8 コマを横に並べた 512x40 で、
## 画面（512x320）のちょうど 1/8 なので**整数倍（8 倍）**で拡大できる。
## 半端な倍率だとドットが滲むので、この寸法は動かさないこと。
class Cover:
	extends Node2D

	const FRAMES := 8
	const CELL := Vector2(64, 40)
	const DIR := "res://assets/transitions/"

	const COVER_SHADER := "res://src/ui/transition_cover.gdshader"

	## 締めに入る割合。ここから先は全面を覆う（差し替えを隠す一瞬）。
	const SEAL_FROM := 0.8

	var _tex: Texture2D = null
	var _at := 0

	static var _cache: Dictionary = {}

	static func texture_of(kind: String) -> Texture2D:
		if _cache.has(kind):
			return _cache[kind]
		var path := "%s%s.png" % [DIR, kind]
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_cache[kind] = tex
		return tex

	func _ready() -> void:
		z_index = 99
		visible = false
		# **アトラスは輝度のマスク。** そのまま描くと絵が乗るだけで覆いにならない。
		var shader: Shader = (
			load(COVER_SHADER) if ResourceLoader.exists(COVER_SHADER) else null)
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			material = mat

	## `t` は 0（覆っていない）〜 1（覆いきった）。
	func show_at(kind: String, t: float) -> bool:
		_tex = texture_of(kind)
		if _tex == null:
			return false
		_at = clampi(int(t * float(FRAMES)), 0, FRAMES - 1)
		if material != null:
			# 終わりぎわだけ塗り潰す。覆いきった一瞬が無いと、その裏で
			# 画面を差し替えたのが見えてしまう。
			material.set_shader_parameter(
				"seal", clampf((t - SEAL_FROM) / (1.0 - SEAL_FROM), 0.0, 1.0))
		visible = true
		queue_redraw()
		return true

	func hide_cover() -> void:
		visible = false
		_tex = null

	func _draw() -> void:
		if _tex == null:
			return
		var scale := Vector2(PixelUI.SCREEN) / CELL
		draw_texture_rect_region(
			_tex,
			Rect2(Vector2.ZERO, CELL * scale),
			Rect2(_at * CELL.x, 0, CELL.x, CELL.y)
		)


func _ready() -> void:
	color = Color(1, 1, 1, 1)
	size = Vector2(PixelUI.SCREEN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 99   # 窓より上、暗転の幕（100）より下
	visible = false
	var shader: Shader = load(SHADER_PATH) if ResourceLoader.exists(SHADER_PATH) else null
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("screen_size", Vector2(PixelUI.SCREEN))
		material = mat
	# **覆いは子にしない。** この ColorRect は普段 `visible = false` なので、
	# 子にすると一緒に消えて一度も描かれない（実際そうなっていて、
	# 画面に写っていたのは世界地図の門だった）。兄弟として置く。
	# 木を触っている最中なので次のフレームへ回す。
	_cover = Cover.new()
	get_parent().add_child.call_deferred(_cover)


## 使える状態か。呼び出し側が素の暗転と選ぶために公開する。
func available() -> bool:
	return material != null


## 場面転換の覆い（B-3）。指定した絵で覆い、`apply` を挟んで開く。
##
## 遭遇はモザイク（`play()`）、場面の切り替えはこちら。**分けているのは
## 意味が違うから** ―― モザイクは「いまいた場所から引きずり込まれる」で
## 前後が繋がるが、場面転換は前後を**切る**のが仕事。
##
## 絵が無ければ false を返す（呼び出し側は素の暗転へ落ちる）。
func play_cover(kind: String, apply: Callable) -> bool:
	if _cover == null or _cover.material == null or Cover.texture_of(kind) == null:
		return false
	cancel()
	_cover.show_at(kind, 0.0)
	_tween = create_tween()
	_tween.tween_method(
		func(t: float) -> void: _cover.show_at(kind, t), 0.0, 1.0, COVER_IN_TIME)
	_tween.tween_callback(apply)
	_tween.tween_method(
		func(t: float) -> void: _cover.show_at(kind, 1.0 - t), 0.0, 1.0, COVER_OUT_TIME)
	_tween.tween_callback(_finish)
	return true


## モザイクで崩し、`apply` を挟んで戻す。
##
## 使えないときは **`apply` を即座に呼んで** false を返す。
## 呼び出し側は「false なら自分で暗転を足す」だけでよい。
func play(apply: Callable) -> bool:
	if not available():
		apply.call()
		return false
	cancel()
	_set_in(0.0)
	visible = true
	_tween = create_tween()
	_tween.tween_method(_set_in, 0.0, 1.0, IN_TIME)
	_tween.tween_callback(apply)
	_tween.tween_method(_set_out, 0.0, 1.0, OUT_TIME)
	_tween.tween_callback(_finish)
	return true


## 進行中の演出を止める。**あとから来た切り替えが必ず勝つ**ようにするため、
## 幕（`_curtain`）を消すときに一緒に呼ぶ。
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_finish()


func _finish() -> void:
	visible = false
	if _cover != null:
		_cover.hide_cover()
	_apply(1.0, 1.0)


func _set_in(t: float) -> void:
	# 明るさは終わりぎわで一気に落とす（t*t）。最初から暗いと、
	# 崩れていく地形が見えないまま終わってしまう。
	_apply(_block_at(t), 1.0 - t * t)


func _set_out(t: float) -> void:
	_apply(_block_at(1.0 - t), t)


func _block_at(t: float) -> float:
	var index := clampi(int(t * float(BLOCKS.size())), 0, BLOCKS.size() - 1)
	return BLOCKS[index]


func _apply(block: float, brightness: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("block", block)
	# 16 段に量子化する。実機に中間の明るさは無い。
	material.set_shader_parameter(
		"brightness", roundf(clampf(brightness, 0.0, 1.0) * BRIGHT_STEPS) / BRIGHT_STEPS
	)
