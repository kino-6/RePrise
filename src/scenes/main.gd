extends Node2D

## 画面の切り替えとランの進行。
##
## 拠点 → 探索 → 戦闘 → 探索 …… → 全滅 → 戦記 → 拠点、という輪を回すだけ。
## ゲームの中身はそれぞれの View と BattleSystem 側にある。
##
## 輪が拠点に戻るのが要点。失ったレベルと残った熟練度を並べて見せる場が無いと、
## メタ進行が数字の裏側だけで進んでしまう。

enum Mode { STRONGHOLD, EXPLORE, BATTLE, SHOP, RESULT }

var stronghold: StrongholdView
var shop: ShopView
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

## 今の戦闘が主との戦いか。勝った時にランを閉じるかどうかがここで変わる。
var _boss_battle := false


func _ready() -> void:
	stronghold = StrongholdView.new()
	stronghold.visible = false
	add_child(stronghold)

	shop = ShopView.new()
	shop.visible = false
	add_child(shop)

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

	stronghold.departed.connect(_start_run)
	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.boss_reached.connect(_on_boss_reached)
	explore.shop_entered.connect(_on_shop_entered)
	shop.closed.connect(func() -> void: _set_mode(Mode.EXPLORE))
	explore.chest_opened.connect(_on_chest)
	battle.battle_finished.connect(_on_battle_finished)
	result.dismissed.connect(_enter_stronghold)

	_enter_stronghold()
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
		"stronghold":
			pass  # 起動直後がすでに拠点
		"job":
			stronghold.debug_open_job_menu(0)
		"explore":
			_start_run()
		"items":
			_start_run()
			GameState.add_item("herb", 3)
			GameState.add_item("water", 2)
			_on_encounter()
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
			battle.debug_open_item_menu()
		"shop":
			_start_run()
			GameState.gold = 300
			_enter_floor()
			# 出店のある階に当たるまで降りる（出店は半分くらいの階にしか出ない）
			while _map.shop_pos.x < 0 and GameState.floor_number < GameState.FINAL_FLOOR:
				GameState.descend()
				_enter_floor()
			_on_shop_entered()
		"deep":
			# 深層の敵の見え方を確認する。
			_start_run()
			while GameState.floor_number < GameState.FINAL_FLOOR - 1:
				GameState.descend()
			_enter_floor()
			for _i in 40:
				_on_encounter()
				if battle.visible:
					break
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
		"boss":
			_start_run()
			while GameState.floor_number < GameState.FINAL_FLOOR:
				GameState.descend()
			_enter_floor()
			_on_boss_reached()
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
		"win":
			_start_run()
			result.show_summary(GameState.end_run(true))
			_set_mode(Mode.RESULT)
		"commands":
			# 技が 1 ページに収まらないときの見え方を確認する。
			# 保存を挟まないので、この改変が名簿に残ることはない。
			_start_run()
			for m in GameState.active_party():
				for job_id in Database.job_ids():
					for entry in Database.job(job_id).get("mastery", []):
						var ability_id := String(entry.get("ability", ""))
						if ability_id != "" and ability_id not in m.learned:
							m.learned.append(ability_id)
			_on_encounter()
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
			# 1 ページ目は通常の戦闘撮影で見えている。確かめたいのは 7 個目以降。
			battle.debug_turn_page(1)
		"battle":
			_start_run()
			_on_encounter()
			# 味方のコマンド選択が出るまで待つ（見せたいのはその画面なので）
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
		"result":
			_start_run()
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


## 拠点へ戻る。ラン中に呼ばれることは無い（end_run のあとだけ）。
func _enter_stronghold() -> void:
	Sound.play_bgm("stronghold")
	stronghold.open()
	_set_mode(Mode.STRONGHOLD)


func _start_run() -> void:
	GameState.start_new_run()
	_enter_floor()


func _enter_floor() -> void:
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	_map = DungeonGenerator.generate(
		GameState.rng_for("terrain"),
		GameState.floor_number,
		GameState.floor_number >= GameState.FINAL_FLOOR
	)
	var party := GameState.active_party()
	var leader_job := party[0].job_id if not party.is_empty() else "soldier"
	explore.setup(_map, _encounter_rng, leader_job)
	Sound.play_bgm("descent")
	_set_mode(Mode.EXPLORE)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	stronghold.visible = mode == Mode.STRONGHOLD
	shop.visible = mode == Mode.SHOP
	explore.visible = mode == Mode.EXPLORE
	hud.visible = mode == Mode.EXPLORE
	battle.visible = mode == Mode.BATTLE
	result.visible = mode == Mode.RESULT
	explore.set_active(mode == Mode.EXPLORE)
	if mode != Mode.STRONGHOLD:
		stronghold.close()
	if mode != Mode.SHOP:
		shop.close()
	if mode == Mode.EXPLORE:
		_refresh_hud()


func _refresh_hud() -> void:
	hud.refresh(GameState.active_party(), GameState.floor_number, GameState.gold)


# --------------------------------------------------------------------------


func _on_encounter() -> void:
	_begin_battle(Encounter.build(_battle_rng, GameState.floor_number), false)


## 主の間へ踏み込んだ。ここで勝てばランが「生還」で終わる。
func _on_boss_reached() -> void:
	var foes := Encounter.build_boss(_battle_rng, GameState.floor_number)
	if foes.is_empty():
		# 主のデータが無い階に扉を置いてしまった場合の保険。詰ませない。
		push_warning("地下 %d 階に主がいない" % GameState.floor_number)
		hud.toast("扉は かたく とざされている…")
		return
	Sound.play("stairs")
	_begin_battle(foes, true)


func _begin_battle(foes: Array[Battler], is_boss: bool) -> void:
	if foes.is_empty():
		return
	var members := GameState.active_party()
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))

	_boss_battle = is_boss
	var system := BattleSystem.new()
	system.start(party, foes, _battle_rng, GameState.floor_number)
	Sound.play("encounter")
	Sound.play_bgm("battle")
	battle.start(system, members)
	_set_mode(Mode.BATTLE)


func _on_battle_finished(victory: bool) -> void:
	if victory and _boss_battle:
		# 主を倒した。ランが「生還」で終わる唯一の経路。
		_boss_battle = false
		Sound.play_bgm("stronghold")
		_finish_run(true)
		return
	if victory:
		Sound.play_bgm("descent")
		_set_mode(Mode.EXPLORE)
		return
	# 全滅。ここでランが終わり、熟練度だけが拠点に残る。
	_boss_battle = false
	Sound.play("defeat")
	Sound.play_bgm("stronghold")
	_finish_run(false)


func _finish_run(victory: bool) -> void:
	result.show_summary(GameState.end_run(victory))
	_set_mode(Mode.RESULT)


func _on_descend() -> void:
	Sound.play("stairs")
	GameState.descend()
	_enter_floor()


func _on_shop_entered() -> void:
	Sound.play("confirm")
	shop.open(_map, GameState.floor_number)
	_set_mode(Mode.SHOP)


func _on_chest(amount: int) -> void:
	Sound.play("chest")
	GameState.gold += amount
	hud.toast("たからばこ！ %d ゴールド" % amount)
	_refresh_hud()
