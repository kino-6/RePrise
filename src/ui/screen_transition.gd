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

var _tween: Tween = null


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


## 使える状態か。呼び出し側が素の暗転と選ぶために公開する。
func available() -> bool:
	return material != null


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
