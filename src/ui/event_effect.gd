class_name EventEffect
extends Node2D

## 場面の節目に 1 度だけ流す小さな演出（`assets/effects/event_*.png`）。
##
## 192x48 のアトラスを 4 コマとして左から右へ再生する。
##
## 守ること:
##
##   * **失敗しても進行を変えない。** 絵が無ければ何も出さずに終わる。
##     演出は飾りで、乱数にもセーブにもイベントの結果にも触らない。
##   * **入力を止めない。** 上に重ねるだけで、押した手は通る
##     （演出のために待たされるのがいちばん嫌われる）。
##   * **1 度きり。** 同じ場面で重ねて出さない。

const DIR := "res://assets/effects/"
const FRAMES := 4
## コマの大きさ。場面の演出は 48、戦闘のエフェクトは 32。
## `play()` で渡す（アトラスごとに違う）。
const FRAME_SIZE := Vector2(48, 48)
const FX_FRAME_SIZE := Vector2(32, 32)

## 1 コマの長さ。4 コマで 0.4 秒（場面の切り替えを待たせない長さ）。
const FRAME_TIME := 0.10

## 何倍で出すか。敵と同じく整数倍（半端な倍率はドットが滲む）。
const SCALE := 2.0

var _tex: Texture2D = null
var _time := 0.0
var _at := Vector2.ZERO
var _cell := FRAME_SIZE

static var _cache: Dictionary = {}


func _ready() -> void:
	z_index = 90   # 窓より上、暗転の幕より下
	set_process(false)
	visible = false


## 名前の頭で置き場を分ける。`fx_` は戦闘、それ以外は場面の節目。
static func texture_of(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := ""
	if name.begins_with("fx_"):
		path = "%s%s.png" % [DIR, name]
	else:
		path = "%sevent_%s.png" % [DIR, name]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[name] = tex
	return tex


## 演出を出す。`at` は中心（省略すると画面の中央）。
##
## 絵が無ければ**何もしない**（呼び出し側は成否を気にしなくてよい）。
func play(name: String, at: Vector2 = Vector2.ZERO) -> void:
	var tex := texture_of(name)
	if tex == null:
		return
	_tex = tex
	_cell = FX_FRAME_SIZE if name.begins_with("fx_") else FRAME_SIZE
	_time = 0.0
	_at = at if at != Vector2.ZERO else Vector2(PixelUI.SCREEN) * 0.5
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _time >= FRAME_TIME * FRAMES:
		visible = false
		set_process(false)
		_tex = null
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var index := clampi(int(_time / FRAME_TIME), 0, FRAMES - 1)
	var size := _cell * SCALE
	# 終わりぎわだけ薄くする。ぷつりと消えると「絵が抜けた」ように見える。
	var fade := clampf((FRAME_TIME * FRAMES - _time) / FRAME_TIME, 0.0, 1.0)
	draw_texture_rect_region(
		_tex,
		Rect2((_at - size * 0.5).floor(), size),
		Rect2(index * _cell.x, 0, _cell.x, _cell.y),
		Color(1, 1, 1, fade)
	)
