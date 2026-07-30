class_name Notice
extends RefCounted

## 画面の中央に出る一言（買った / たりない / おぼえた）。
##
## 拠点・出店・探索メニューが同じものを 3 回持っていた（文字列 + 残り時間 +
## 消える処理 + 描画）。状態ごと 1 か所に集めて、各画面は set() と tick() と
## draw() を呼ぶだけにする。

const DEFAULT_TIME := 1.8

var text := ""
var _timer := 0.0


func set_text(value: String, seconds: float = DEFAULT_TIME) -> void:
	text = value
	_timer = seconds


func clear() -> void:
	text = ""
	_timer = 0.0


## 時間を進める。表示が消えたら true（呼び出し側が再描画を判断できる）。
func tick(delta: float) -> bool:
	if _timer <= 0.0:
		return false
	_timer -= delta
	if _timer > 0.0:
		return false
	text = ""
	return true


func draw(canvas: CanvasItem, texture: Texture2D, y: float) -> void:
	PixelUI.draw_notice(canvas, texture, text, y, PixelUI.C_ACTIVE)
