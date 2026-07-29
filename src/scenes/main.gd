extends Node2D

## 画面の切り替えとランの進行。
##
## 探索 → 戦闘 → 探索 …… → 全滅 → 戦記 → 次のラン、という輪を回すだけ。
## ゲームの中身はそれぞれの View と BattleSystem 側にある。

enum Mode { EXPLORE, BATTLE, RESULT }

var explore: ExploreView
var hud: ExploreHud
var battle: BattleView
var result: ResultScreen

var _mode: Mode = Mode.EXPLORE
var _map: DungeonMap = null

## 階ごとに 1 本ずつ持つ乱数列。呼ぶたびに進むので、
## 同じ階で戦うたびに同じ敵が出る、という事故が起きない。
var _encounter_rng: DetRng = null
var _battle_rng: DetRng = null


func _ready() -> void:
	explore = ExploreView.new()
	add_child(explore)

	hud = ExploreHud.new()
	add_child(hud)

	battle = BattleView.new()
	battle.visible = false
	add_child(battle)

	result = ResultScreen.new()
	result.visible = false
	add_child(result)

	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.chest_opened.connect(_on_chest)
	battle.battle_finished.connect(_on_battle_finished)
	result.dismissed.connect(_start_run)

	_start_run()
	_handle_debug_args()


## 開発用。画面を 1 枚撮って終了する。
##   godot --path . -- --shot=explore
## GUI を触らずに見た目を確認できるので、ドット絵の調整に効く。
func _handle_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_capture(arg.trim_prefix("--shot="))
			return


func _capture(which: String) -> void:
	match which:
		"battle":
			_on_encounter()
			# 味方のコマンド選択が出るまで待つ（見せたいのはその画面なので）
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
		"result":
			result.show_summary(GameState.end_run(false))
			_set_mode(Mode.RESULT)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://docs/preview/screen_%s.png" % which
	DirAccess.make_dir_recursive_absolute("res://docs/preview")
	image.save_png(path)
	print("撮影: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	get_tree().quit()


# --------------------------------------------------------------------------


func _start_run() -> void:
	GameState.start_new_run()
	_enter_floor()


func _enter_floor() -> void:
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	_map = DungeonGenerator.generate(GameState.rng_for("terrain"), GameState.floor_number)
	var party := GameState.active_party()
	var leader_job := party[0].job_id if not party.is_empty() else "soldier"
	explore.setup(_map, _encounter_rng, leader_job)
	Sound.play_bgm("descent")
	_set_mode(Mode.EXPLORE)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	explore.visible = mode == Mode.EXPLORE
	hud.visible = mode == Mode.EXPLORE
	battle.visible = mode == Mode.BATTLE
	result.visible = mode == Mode.RESULT
	explore.set_active(mode == Mode.EXPLORE)
	if mode == Mode.EXPLORE:
		_refresh_hud()


func _refresh_hud() -> void:
	hud.refresh(GameState.active_party(), GameState.floor_number, GameState.gold)


# --------------------------------------------------------------------------


func _on_encounter() -> void:
	var members := GameState.active_party()
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))

	var foes := Encounter.build(_battle_rng, GameState.floor_number)
	if foes.is_empty():
		return

	var system := BattleSystem.new()
	system.start(party, foes, _battle_rng, GameState.floor_number)
	Sound.play("encounter")
	Sound.play_bgm("battle")
	battle.start(system, members)
	_set_mode(Mode.BATTLE)


func _on_battle_finished(victory: bool) -> void:
	if victory:
		Sound.play_bgm("descent")
		_set_mode(Mode.EXPLORE)
		return
	# 全滅。ここでランが終わり、熟練度だけが拠点に残る。
	Sound.play("defeat")
	Sound.play_bgm("stronghold")
	var summary := GameState.end_run(false)
	result.show_summary(summary)
	_set_mode(Mode.RESULT)


func _on_descend() -> void:
	Sound.play("stairs")
	GameState.descend()
	_enter_floor()


func _on_chest(amount: int) -> void:
	Sound.play("chest")
	GameState.gold += amount
	hud.toast("たからばこ！ %d ゴールド" % amount)
	_refresh_hud()
