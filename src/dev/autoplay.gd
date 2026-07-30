class_name AutoPlay
extends Node

## 開発用の自動プレイ。実際のゲームに**入力だけ**を流し込んで通しを確認する。
##
##   godot --path . -- --play=90        # 90 秒ぶん遊んでコマ撮りする
##
## 内部を直接叩かず、人と同じ経路（キー入力）しか使わないのが要点。
## UI がどこかで詰まっていれば、そこから先へ進まなくなるので詰まりが検出できる。
## 撮ったコマは docs/preview/play/ に落ち、画面の遷移を目で追える。
##
## 乱数は DetRng を使う。同じ種からは同じ遊び方が再現されるので、
## 「あの操作で落ちた」を確実に追える。

## 何秒ごとにコマを撮るか。
const SHOT_INTERVAL := 1.2

## 1 秒あたりの入力回数。人が押す速さより少し速いくらい。
const INPUTS_PER_SECOND := 6.0

## 同じ画面に居座る上限（秒）。これを超えたら出口へ向かわせる。
## メニューに confirm を打ち続けると奥へ潜り続けて探索が進まなかった。
const LINGER_LIMIT := 6.0

const SHOT_DIR := "res://docs/preview/play"

var _rng: DetRng = null
var _main: Node = null
var _elapsed := 0.0
var _limit := 0.0
var _shot_timer := 0.0
var _input_timer := 0.0
var _shot_index := 0

## いま押しているキー。次のフレームで離す。
var _held := ""

## 画面の遷移を記録する。同じ画面に貼り付いたままなら詰まっている。
var _timeline: Array[String] = []
var _last_mode := ""
var _mode_time := 0.0
var _stuck_report: Array[String] = []

## 走らせるたびに数字で比べられるようにする集計。
var _deepest := 1
var _battles := 0
var _runs := 0
var _equipped := 0


func start(main_node: Node, seconds: float, seed_value: int = 12345) -> void:
	_main = main_node
	_limit = seconds
	_rng = DetRng.new(seed_value)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	# 自動プレイは人の 10 倍の速さで決定キーを叩くので、鳴らすと騒音にしかならない。
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	set_process(true)


func _process(delta: float) -> void:
	# 前のフレームで押したキーを離す。
	#
	# 押した直後に離すと、探索の移動（_process の中で Input.is_action_pressed を
	# 見ている）に 1 フレームも届かない。人が押している時間を作るために、
	# 離すのは必ず次のフレームにする。最初にこれを間違えて「60 秒歩かなかった」。
	if _held != "":
		var up := InputEventAction.new()
		up.action = _held
		up.pressed = false
		Input.parse_input_event(up)
		_held = ""

	_elapsed += delta
	_track_mode(delta)
	if _main != null and _main.has_method("dev_equipped_count"):
		_equipped = maxi(_equipped, int(_main.dev_equipped_count()))

	_input_timer -= delta
	if _input_timer <= 0.0:
		_input_timer = 1.0 / INPUTS_PER_SECOND
		_send_input()

	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_shot_timer = SHOT_INTERVAL
		_capture()

	if _elapsed >= _limit:
		_report()
		get_tree().quit()


# --------------------------------------------------------------------------


func _mode() -> String:
	return String(_main.dev_mode_name()) if _main != null and _main.has_method("dev_mode_name") else "?"


## 記録は画面名＋階層で取る。画面名だけだと「階を降りた」が記録に残らない。
func _status() -> String:
	return String(_main.dev_status()) if _main != null and _main.has_method("dev_status") else _mode()


func _track_mode(delta: float) -> void:
	var mode := _status()
	if mode != _last_mode:
		_timeline.append("%5.1fs %s" % [_elapsed, mode])
		if mode.begins_with("BATTLE"):
			_battles += 1
		if mode.begins_with("RESULT"):
			_runs += 1
		var at := mode.find("地下")
		if at >= 0:
			_deepest = maxi(_deepest, int(mode.substr(at + 2)))
		_last_mode = mode
		_mode_time = 0.0
		return
	_mode_time += delta
	# 同じ画面に 25 秒貼り付いたら、そこで詰まっている可能性が高い。
	if _mode_time > 25.0:
		_stuck_report.append("%5.1fs %s に %.0f 秒とどまっている" % [_elapsed, mode, _mode_time])
		_mode_time = 0.0


## 画面ごとに「人がやりそうなこと」を送る。
## 賢く遊ぶのが目的ではなく、行き止まりを踏み抜くのが目的。
func _send_input() -> void:
	match _mode():
		"TITLE", "RESULT":
			_press("confirm")
		"STRONGHOLD":
			# 名簿の上ではキャンセルで「出撃する」へ飛べる。そこから決定で潜る。
			if _rng.chance(35):
				_press("cancel")
			else:
				_press("confirm")
		"EXPLORE":
			if _rng.chance(3):
				_press("confirm")  # メニューを開ける
			else:
				_press(_explore_step())
		"BATTLE":
			if _rng.chance(20):
				_press(_rng.pick(["ui_right", "ui_down", "ui_left", "ui_up"]))
			elif _rng.chance(10):
				_press("cancel")
			else:
				_press("confirm")
		"SHOP":
			# 買い物は実際に踏ませる。すぐ立ち去ると装備も道具も試されない。
			if _mode_time > LINGER_LIMIT or _rng.chance(8):
				_press("cancel")
			elif _rng.chance(45):
				_press(_rng.pick(["ui_up", "ui_down"]))
			else:
				_press("confirm")
		"MENU":
			# 奥（そうび・つよさ）まで潜らせたいが、居座られると探索が進まない。
			# 長居したら出口へ向かわせる（人も見終わったら閉じる）。
			if _mode_time > LINGER_LIMIT or _rng.chance(18):
				_press("cancel")
			elif _rng.chance(45):
				_press(_rng.pick(["ui_up", "ui_down"]))
			else:
				_press("confirm")
		_:
			_press("confirm")


## 歩く向き。毎回振り直すと酔歩になって同じ場所を往復するだけになり、
## 階段にも出店にも辿り着かない（最初の版がそうだった）。
## 人と同じように、しばらく同じ向きへ歩き続ける。
const WALK_KEYS := ["ui_up", "ui_down", "ui_left", "ui_right"]

var _walk_dir := ""
var _walk_left := 0


## 探索の一歩。
##
## 素の酔歩だと 3 分遊んでも 1 階から出られなかったので、基本は出口へ向かう。
## ただし全部を最短経路にすると出店も宝箱も踏まないため、ときどき寄り道する。
func _explore_step() -> String:
	if _rng.chance(12):
		# 出店があるなら覗きに行く（買い物の UI を踏むため）
		var to_shop := String(_main.dev_step_to_shop())
		if to_shop != "":
			return to_shop
	if _rng.chance(20):
		return _walk()
	var step := String(_main.dev_step_to_exit())
	return step if step != "" else _walk()


func _walk() -> String:
	if _walk_left <= 0 or _walk_dir == "":
		_walk_dir = String(_rng.pick(WALK_KEYS))
		_walk_left = _rng.range_i(6, 16)
	_walk_left -= 1
	return _walk_dir


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	_held = action


func _capture() -> void:
	# 描き終わったフレームを撮る。await の中で撮ると 1 フレーム古い絵になる。
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%03d_%s.png" % [SHOT_DIR, _shot_index, _mode()])
	_shot_index += 1


func _report() -> void:
	print("=== 自動プレイ %.0f 秒 ===" % _elapsed)
	print("画面の遷移:")
	for line in _timeline:
		print("  " + line)
	if _stuck_report.is_empty():
		print("詰まり: なし")
	else:
		print("詰まり:")
		for line in _stuck_report:
			print("  " + line)
	print("---")
	print("最深      : 地下 %d 階" % _deepest)
	print("戦闘      : %d 回" % _battles)
	print("ランの終了 : %d 回" % _runs)
	print("装備      : 最大 %d 個" % _equipped)
	print("コマ: %s に %d 枚" % [SHOT_DIR, _shot_index])
