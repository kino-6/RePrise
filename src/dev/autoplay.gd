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

## この実行のコマを置く場所と、撮った順の一覧（P-2）。
## **実行ごとに分ける。** 混ざると、過去のランを今回の結果と読み違える。
var _run_dir := ""
var _manifest: Array[String] = []

## いま押しているキー。次のフレームで離す。
var _held := ""
var _held_keycode := 0
var _keypad_input := false
var _keypad_counts: Dictionary = {}

## 画面の遷移を記録する。同じ画面に貼り付いたままなら詰まっている。
var _timeline: Array[String] = []
var _last_status := ""
var _last_screen := ""
var _mode_time := 0.0
var _last_progress_signature := ""
var _stuck_report: Array[String] = []

## 走らせるたびに数字で比べられるようにする集計。
var _deepest := 1

## 町に入った回数と、中に居た時間。**町を素通りしていないかを見る。**
var _town_visits := 0
var _town_time := 0.0
var _talks := 0

## 直近の画面の並び。2 つの画面を往復する足踏みを見つけるために持つ。
# 町では「案内役2人＋仕事場」を順に開くため、EVENT↔EXPLORE が8遷移までは
# 正常に起きる。正規の町巡回を詰まり扱いせず、それを越えて往復する場合を拾う。
const OSCILLATION_WINDOW := 12
var _recent: Array[String] = []
var _oscillation_noted := false
var _battles := 0

## 1 戦の実時間。**秒で測らないと「速くなった」が言えない。**
## 手番数は Sim（tests/balance.gd）が測るが、実際に待たされる長さは
## 1 手番あたりの行数で決まるので、ここは画面側で測るしかない。
var _battle_started := -1.0
var _battle_seconds: Array[float] = []
var _event_started := -1.0
var _event_seconds: Array[float] = []
## 通常遭遇どうしの実歩数。イベント戦・番人・主戦は0なので含めない。
var _encounter_gaps: Array[int] = []
var _runs := 0
var _equipped := 0
var _shop_categories := {}

## さいきょう装備を掛け直したいか。開始時と、装備を拾った直後に立てる。
var _best_gear_due := true


## その場所の png と一覧を消す。**ここで作ったものだけ**を対象にする
## （ユーザーの保存や別実行の証跡は消さない ―― 実行ごとに場所が分かれている）。
static func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".png") or name.ends_with(".txt")):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


func start(
	main_node: Node, seconds: float, seed_value: int = 12345, keypad_input: bool = false
) -> void:
	_main = main_node
	_limit = seconds
	_rng = DetRng.new(seed_value)
	_keypad_input = keypad_input
	# **実行ごとに別の場所へ保存する**（P-2）。
	#
	# 以前は毎回 `000_<MODE>.png` から書いていて、既存を区別しなかった。
	# 再プレイ後に `000_TITLE.png` と `000_EXPLORE.png` が同居し、
	# **過去のランの画面を今回の結果と誤認した**（実際に起きた）。
	_run_dir = "%s/run_%d" % [SHOT_DIR, seed_value]
	DirAccess.make_dir_recursive_absolute(_run_dir)
	_clear_dir(_run_dir)   # 同じ種で撮り直したら、前回のぶんは置き換える
	# 自動プレイは人の 10 倍の速さで決定キーを叩くので、鳴らすと騒音にしかならない。
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	if _main.has_method("dev_reset_facility_metrics"):
		_main.dev_reset_facility_metrics()
	set_process(true)


func _process(delta: float) -> void:
	# 前のフレームで押したキーを離す。
	#
	# 押した直後に離すと、探索の移動（_process の中で Input.is_action_pressed を
	# 見ている）に 1 フレームも届かない。人が押している時間を作るために、
	# 離すのは必ず次のフレームにする。最初にこれを間違えて「60 秒歩かなかった」。
	if _held != "":
		if _held_keycode != 0:
			var key_up := InputEventKey.new()
			key_up.physical_keycode = _held_keycode
			key_up.pressed = false
			Input.parse_input_event(key_up)
		else:
			var action_up := InputEventAction.new()
			action_up.action = _held
			action_up.pressed = false
			Input.parse_input_event(action_up)
		_held = ""
		_held_keycode = 0

	_elapsed += delta
	_track_mode(delta)
	# **さいきょう装備は人と同じ処理を呼ぶ。** 自動プレイが独自に着せると、
	# 測っている強さと遊べる強さが別物になる（毒で手番が消えていたのと同じ事故）。
	if _best_gear_due and _main != null and _main.has_method("dev_apply_best_gear"):
		if String(_main.dev_mode_name()) == "EXPLORE":
			_best_gear_due = false
			_main.dev_apply_best_gear()
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
	var status := _status()
	var screen := _mode()
	if status.contains("町"):
		_town_time += delta

	if status != _last_status:
		_timeline.append("%5.1fs %s" % [_elapsed, status])
		if status.contains("町") and not _last_status.contains("町"):
			_town_visits += 1
		# **表示を変えたらここも変える。** 「地下 N 階」を探したままだったので、
		# 危険度 10 まで行っても「最も危険 1」と出ていた（2 度目の同じ抜け）。
		var at := status.find("危険度")
		if at >= 0:
			# 後ろに「目的: 3/3歩」が続いても、その数字を危険度へ連結しない。
			# int("1 ... 3/3") は 133 と解釈され、実測ログが嘘になっていた。
			var danger_text := status.substr(at + 3).get_slice(" ", 0)
			_deepest = maxi(_deepest, int(danger_text))

		# **2 状態のあいだを往復しているのも詰まり。**
		_recent.append(status)
		while _recent.size() > OSCILLATION_WINDOW:
			_recent.pop_front()
		_check_oscillation()
		_last_status = status

	if screen != _last_screen:
		# 「とじる」を押した直後にメニューから出られていれば成功と数える
		if _close_expect and _last_screen == "MENU":
			if screen == "EXPLORE":
				_close_ok += 1
			_close_expect = false
		if screen == "BATTLE":
			_battles += 1
			_battle_started = _elapsed
			if _main != null and _main.has_method("dev_take_encounter_gap"):
				var gap := int(_main.dev_take_encounter_gap())
				if gap > 0:
					_encounter_gaps.append(gap)
		elif _battle_started >= 0.0:
			# 戦闘から出た。掛かった秒を控える。
			_battle_seconds.append(_elapsed - _battle_started)
			_battle_started = -1.0
		if screen == "EVENT":
			_event_started = _elapsed
		elif _event_started >= 0.0:
			_event_seconds.append(_elapsed - _event_started)
			_event_started = -1.0
		if screen == "RESULT":
			_runs += 1
		if screen == "SHOP":
			_shop_visit_categories.clear()
		_last_screen = screen
		_mode_time = 0.0
		_last_progress_signature = _progress_signature()
		return
	# 戦闘は同じ画面のまま数十秒続く。画面滞在ではなく、行動・ログが
	# 25秒まったく進まなかった時だけ停止とみなす。
	if screen == "BATTLE":
		var progress := _progress_signature()
		_mode_time = progress_wait(
			_mode_time, _last_progress_signature, progress, delta
		)
		_last_progress_signature = progress
	else:
		_mode_time += delta
	# 同じ画面に 25 秒貼り付いたら、そこで詰まっている可能性が高い。
	if _mode_time > 25.0:
		_stuck_report.append(
			"%5.1fs %s に %.0f 秒とどまっている"
			% [_elapsed, status, _mode_time]
		)
		_mode_time = 0.0


func _progress_signature() -> String:
	return (
		String(_main.dev_progress_signature())
		if _main != null and _main.has_method("dev_progress_signature")
		else _status()
	)


## 単独Gate用。画面ではなく進行署名が変わったら待ち時間をゼロへ戻す。
static func progress_wait(
	waited: float, previous: String, current: String, delta: float
) -> float:
	return 0.0 if current != previous else waited + delta


## 画面ごとに「人がやりそうなこと」を送る。
## 賢く遊ぶのが目的ではなく、行き止まりを踏み抜くのが目的。
func _send_input() -> void:
	# 状態の 1 行（「EXPLORE 町 危険度2」）は場所の判別にも使う。
	var status: String = _main.dev_status() if _main != null else ""
	match _mode():
		"TITLE", "PROLOGUE", "RESULT":
			_press("confirm")
		"STRONGHOLD":
			# 名簿の上ではキャンセルで「出撃する」へ飛べる。そこから決定で潜る。
			if _rng.chance(35):
				_press("cancel")
			else:
				_press("confirm")
		"EXPLORE":
			# **町では用を足してから出る。** 素通りしていると NPC も宿も店も
			# 一度も踏まれず、「絵はあるが出ない」を検出できない
			# （実測で町の滞在が 0.3 秒だった）。
			if status.contains("町"):
				_press(_town_step())
			elif _town_entered >= 0.0:
				# 町を出た。次に入ったときのために印を戻す。
				_town_entered = -1.0
				_town_leaving = false
			elif _rng.chance(3):
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
			# 4 分類を左右入力で一巡する。乱数任せでは最初の「どうぐ」だけを
			# 見て店を出ても気付けない。消耗品だけ実際に1回購入を試す。
			var category := (
				String(_main.dev_shop_category())
				if _main.has_method("dev_shop_category")
				else ""
			)
			if category != "" and not _shop_visit_categories.has(category):
				_shop_visit_categories[category] = true
				_shop_categories[category] = true
				_press("confirm" if category == "item" else "ui_right")
			elif _shop_visit_categories.size() >= 4 or _mode_time > LINGER_LIMIT:
				_press("cancel")
			else:
				_press("ui_right")
		"MENU":
			# 乱数の入力では「そうび → 人 → スロット → 品」の 4 段を踏み抜けない。
			# ときどき決まった手順で潜らせて、装備の付け替えまで確かめる。
			if not _scripted.is_empty():
				_press(String(_scripted.pop_front()))
			elif _mode_time > LINGER_LIMIT or _rng.chance(18):
				_press("cancel")
			elif _rng.chance(25):
				_scripted = EQUIP_STEPS.duplicate()
				_press(String(_scripted.pop_front()))
			elif (
				_rng.chance(30)
				and _main.has_method("dev_menu_at_root")
				and bool(_main.dev_menu_at_root())
			):
				# 「とじる」で閉じられるかを試す
				_close_tries += 1
				_close_expect = true
				_scripted = CLOSE_STEPS.duplicate()
				_press(String(_scripted.pop_front()))
			elif _rng.chance(45):
				_press(_rng.pick(["ui_up", "ui_down"]))
			else:
				_press("confirm")
		"GEAR":
			# 拾った装備を聞かれている（C-9）。**選ばずに閉じる。**
			# ここで人と同じく仲間を選ぶこともできるが、どの仲間が最善かを
			# 自動プレイが判断すると `BestGear` と二重になる。閉じてから
			# `dev_apply_best_gear()` を呼ぶので、結果は同じところへ行く。
			_press("cancel")
			_best_gear_due = true
		"SETTINGS":
			# **設定は遊びの輪の外**。ここで confirm を押し続けると
			# キー割り当ての待ち状態に入って出られなくなる（実際に 25 秒張り付いた）。
			# 出口へ向かうのが唯一の正しい振る舞い。
			_press("cancel")
		"EVENT":
			# 読む前に決定を連打すると、出来事を「謎の選択肢が一瞬出た」
			# としか検査できない。最低1秒は本文と選択肢を画面に残す。
			if _mode_time >= 1.0:
				# 先頭が支払不能でも決定連打で貼り付かない。ときどき次の手へ動き、
				# 実際の「払えない選択肢」も通し検査する。
				_press("ui_down" if int(_mode_time * INPUTS_PER_SECOND) % 5 == 0
					else "confirm")
		"MAP":
			if _mode_time >= 0.8:
				_press("cancel")
		_:
			_press("confirm")


## メニューを「とじる」で閉じる手順。閉じられたかどうかを数える。
## 「とじる で閉じられない」という報告を、目でなく回数で確かめるために置いた。
## 上へ 1 つで末尾（とじる）へ回り込む。キャンセルは使わない
## （キャンセルでも閉じてしまうので、それでは「とじる」を試したことにならない）。
const CLOSE_STEPS: Array[String] = ["ui_up", "confirm"]

var _close_tries := 0
var _close_ok := 0
var _close_expect := false


## 装備を付け替えるまでの手順。
## そうび（2 つ下）→ 先頭の人 → ぶきのスロット → 一覧の 1 つ目 → 戻る。
const EQUIP_STEPS: Array[String] = [
	"cancel", "ui_down", "ui_down", "confirm",
	"confirm", "confirm", "ui_down", "confirm", "cancel",
]

var _scripted: Array[String] = []


## 歩く向き。毎回振り直すと酔歩になって同じ場所を往復するだけになり、
## 階段にも出店にも辿り着かない（最初の版がそうだった）。
## 人と同じように、しばらく同じ向きへ歩き続ける。
const WALK_KEYS := ["ui_up", "ui_down", "ui_left", "ui_right"]

var _walk_dir := ""
var _walk_left := 0
## 町に入ってから何秒ねばるか。用（人に話す・宿・店）を試すのに要る時間。
const TOWN_DWELL := 12.0

var _town_entered := -1.0

## 出口へ向かっている最中か。**滞在の再開を止めるための印。**
var _town_leaving := false
## 0: 宿 / 1: 住人1 / 2: 住人2 / 3: 仕事場 / 4: 物資箱 / 5: 店 / 6: 出口。
var _town_phase := 0
var _town_inn_baseline := 0
var _town_shop_baseline := 0
var _town_talk_baseline := 0
var _town_facility_baseline := 0
var _town_chest_baseline := 0
var _shop_visit_categories := {}


## 町の中の 1 歩。
##
## **素通りさせない。** 実測で町の滞在が 0.3 秒しかなく、NPC も宿も店も
## 一度も踏まれていなかった（「絵はあるが出ない」を検出できない）。
## しばらく中を歩き回って人にぶつかり（＝話しかけ）、ねばり終えたら出口へ向かう。
## 酔歩では閉じた広場から出られないので、出るときは経路に従う。
func _town_step() -> String:
	if _town_entered < 0.0:
		_town_entered = _elapsed
		_town_leaving = false
		_town_phase = 0
		_town_inn_baseline = (
			int(_main.dev_inn_visits())
			if _main.has_method("dev_inn_visits")
			else 0
		)
		_town_shop_baseline = (
			int(_main.dev_shop_opens())
			if _main.has_method("dev_shop_opens")
			else 0
		)
		_town_talk_baseline = (
			int(_main.dev_talks())
			if _main.has_method("dev_talks")
			else 0
		)
		_town_facility_baseline = (
			int(_main.dev_facility_visits())
			if _main.has_method("dev_facility_visits")
			else 0
		)
		_town_chest_baseline = (
			int(_main.dev_town_chests())
			if _main.has_method("dev_town_chests")
			else 0
		)
	if _town_phase == 0:
		if (
			_main.has_method("dev_inn_visits")
			and int(_main.dev_inn_visits()) > _town_inn_baseline
		):
			_town_phase = 1
		else:
			var to_inn := String(_main.dev_step_to_inn())
			if to_inn != "":
				return to_inn
			_town_phase = 1
	if _town_phase == 1:
		if (
			_main.has_method("dev_talks")
			and int(_main.dev_talks()) >= _town_talk_baseline + 1
		):
			_town_phase = 2
		else:
			var to_talk := String(_main.dev_step_to_talk())
			if to_talk != "":
				return to_talk
			_town_phase = 2
	if _town_phase == 2:
		if (
			_main.has_method("dev_talks")
			and int(_main.dev_talks()) >= _town_talk_baseline + 2
		):
			_town_phase = 3
		else:
			var to_second_talk := String(_main.dev_step_to_talk())
			if to_second_talk != "":
				return to_second_talk
			_town_phase = 3
	if _town_phase == 3:
		if (
			_main.has_method("dev_facility_visits")
			and int(_main.dev_facility_visits()) > _town_facility_baseline
		):
			_town_phase = 4
		else:
			var to_facility := String(_main.dev_step_to_town_facility())
			if to_facility != "":
				return to_facility
			_town_phase = 4
	if _town_phase == 4:
		if (
			_main.has_method("dev_town_chests")
			and int(_main.dev_town_chests()) > _town_chest_baseline
		):
			_town_phase = 5
		else:
			var to_chest := String(_main.dev_step_to_town_chest())
			if to_chest != "":
				return to_chest
			_town_phase = 5
	if _town_phase == 5:
		if (
			_main.has_method("dev_shop_opens")
			and int(_main.dev_shop_opens()) > _town_shop_baseline
		):
			_town_phase = 6
			_town_leaving = true
		else:
			var to_shop := String(_main.dev_step_to_shop())
			if to_shop != "":
				return to_shop
			_town_phase = 6
			_town_leaving = true
	# **出ると決めたら出きるまで出口へ向かう。**
	#
	# 以前は滞在時間が切れた回に `_town_entered` を戻していたので、
	# 出口へ 1 歩進んだ次の呼び出しでまた滞在が始まっていた。
	# 出口が 1 歩より遠い町からは、酔歩がたまたま外へ出るまで抜けられない。
	# 実際に 90 秒とどまり続けた（強い装備で先へ進めるようになって初めて出た）。
	if _town_leaving or _elapsed - _town_entered > TOWN_DWELL:
		_town_leaving = true
		var out: String = _main.dev_step_to_exit()
		if out != "":
			return out
	# 施設が欠けた町でも、滞在上限に達したら酔歩で固まらない。
	return String(_rng.pick(["ui_up", "ui_down", "ui_left", "ui_right"]))





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


## 同じ 2 画面を往復し続けていないか。
##
## 「入れない場所から追い返されて、また入る」が起きると、画面は変わり続けるので
## 貼り付き判定に掛からない。**変化しているのに進んでいない**状態を見つける。
func _check_oscillation() -> void:
	if _oscillation_noted or _recent.size() < OSCILLATION_WINDOW:
		return
	var seen := {}
	for m in _recent:
		# **戦闘を含む往復は正常。** 歩く↔戦うはゲームが動いている姿そのもので、
		# これを詰まりと呼ぶと本物の足踏みが埋もれる。
		if m.begins_with("BATTLE"):
			return
		seen[m] = true
	if seen.size() > 2:
		return
	_oscillation_noted = true
	_stuck_report.append(
		"%5.1fs %s を往復している（%d 回連続で 2 画面だけ）"
		% [_elapsed, "↔".join(seen.keys()), OSCILLATION_WINDOW]
	)


func _press(action: String) -> void:
	if _keypad_input:
		var keycode := Settings.primary_keypad_key(action)
		if keycode != 0:
			var key_down := InputEventKey.new()
			key_down.physical_keycode = keycode
			key_down.pressed = true
			Input.parse_input_event(key_down)
			_held = action
			_held_keycode = keycode
			_keypad_counts[action] = int(_keypad_counts.get(action, 0)) + 1
			return
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	_held = action


func _capture() -> void:
	# 描き終わったフレームを撮る。await の中で撮ると 1 フレーム古い絵になる。
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var shot_name := "%03d_%s.png" % [_shot_index, _mode()]
	image.save_png("%s/%s" % [_run_dir, shot_name])
	_manifest.append(shot_name)
	_shot_index += 1


func _report() -> void:
	print("=== 自動プレイ %.0f 秒 ===" % _elapsed)
	if _keypad_input:
		var counts: Array[String] = []
		for action in ["ui_up", "ui_down", "ui_left", "ui_right", "confirm", "cancel"]:
			if int(_keypad_counts.get(action, 0)) > 0:
				counts.append("%s %d回" % [Settings.action_label(action), int(_keypad_counts[action])])
		print("入力      : テンキー（%s）" % " / ".join(counts))
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
	print("最も危険  : 危険度 %d" % _deepest)
	print("町に入った: %d 回（滞在 %.0f 秒）" % [_town_visits, _town_time])
	if _main != null and _main.has_method("dev_inn_visits"):
		print("宿を利用  : %d 回" % int(_main.dev_inn_visits()))
	if _main != null and _main.has_method("dev_shop_opens"):
		print("店を利用  : %d 回" % int(_main.dev_shop_opens()))
	if _main != null and _main.has_method("dev_talks"):
		print("住人と話す: %d 回" % int(_main.dev_talks()))
	if _main != null and _main.has_method("dev_facility_uses"):
		print("仕事場利用: %d 回（接触 %d 回）" % [
			int(_main.dev_facility_uses()), int(_main.dev_facility_visits())
		])
	if _main != null and _main.has_method("dev_town_chests"):
		print("町の物資箱: %d 回" % int(_main.dev_town_chests()))
	# 欲が呼んだ格上（R-3）。**開けた数と湧いた数を並べる**（1 つ目では湧かない）。
	if _main != null and _main.has_method("dev_greed_summons"):
		print("洞の宝箱  : %d 個開けて 格上 %d 体" % [
			int(_main.dev_chests_taken()), int(_main.dev_greed_summons())
		])
	print("店の分類  : %d / 4（%s）" % [
		_shop_categories.size(), "・".join(_shop_categories.keys())
	])
	print("戦闘      : %d 回" % _battles)
	if not _encounter_gaps.is_empty():
		var shortest := _encounter_gaps[0]
		var gap_total := 0
		for gap in _encounter_gaps:
			shortest = mini(shortest, gap)
			gap_total += gap
		print("通常遭遇の間隔: 最短 %d 歩 / 平均 %.1f 歩（%d 件）" % [
			shortest, float(gap_total) / _encounter_gaps.size(), _encounter_gaps.size()
		])
	if not _battle_seconds.is_empty():
		var total := 0.0
		var longest := 0.0
		for s in _battle_seconds:
			total += s
			longest = maxf(longest, s)
		print("戦闘の長さ: 平均 %.1f 秒 / 最長 %.1f 秒（%d 戦を計測）" % [
			total / _battle_seconds.size(), longest, _battle_seconds.size()])
	if not _event_seconds.is_empty():
		var event_total := 0.0
		for seconds in _event_seconds:
			event_total += seconds
		print("出来事の滞在: 平均 %.1f 秒（%d 件）" % [
			event_total / _event_seconds.size(), _event_seconds.size()
		])
	print("ランの終了 : %d 回" % _runs)
	print("装備      : 最大 %d 個" % _equipped)
	print("メニューを閉じた: %d 回（とじるを試した %d 回）" % [_close_ok, _close_tries])
	# **一覧を残す**（P-2）。どれが今回のぶんかを機械で選べるようにする。
	# これが無いと「最新 N 枚を時刻で選ぶ」に戻り、過去のランと混ざる。
	var listing := FileAccess.open("%s/manifest.txt" % _run_dir, FileAccess.WRITE)
	if listing != null:
		for shot in _manifest:
			listing.store_line(String(shot))
		listing.close()
	print("コマ: %s に %d 枚（manifest.txt に一覧）" % [_run_dir, _shot_index])
