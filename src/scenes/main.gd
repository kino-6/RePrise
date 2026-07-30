extends Node2D

## 画面の切り替えとランの進行。
##
## 拠点 → 探索 → 戦闘 → 探索 …… → 全滅 → 戦記 → 拠点、という輪を回すだけ。
## ゲームの中身はそれぞれの View と BattleSystem 側にある。
##
## 輪が拠点に戻るのが要点。失ったレベルと残った熟練度を並べて見せる場が無いと、
## メタ進行が数字の裏側だけで進んでしまう。

enum Mode { TITLE, STRONGHOLD, EXPLORE, BATTLE, SHOP, MENU, RESULT }

var title: TitleView
var stronghold: StrongholdView
var shop: ShopView
var explore: ExploreView
var hud: ExploreHud
var battle: BattleView
var menu: FieldMenu
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
	# 「RePrise  v0.1.0」。どのビルドを触っているかがウィンドウ枠だけで分かる。
	# 数字の原本は project.godot（src/game/version.gd 参照）。
	#
	# DisplayServer.window_set_title() ではなく Window.title へ入れる。
	# 前者はルート Window があとから自分の title を流し込むときに上書きされ、
	# 既定の「RePrise (DEBUG)」に戻ってしまう。
	get_window().title = GameVersion.window_title()

	title = TitleView.new()
	title.visible = false
	add_child(title)

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

	menu = FieldMenu.new()
	menu.visible = false
	add_child(menu)

	result = ResultScreen.new()
	result.visible = false
	add_child(result)

	title.started.connect(_enter_stronghold)
	stronghold.departed.connect(_start_run)
	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.boss_reached.connect(_on_boss_reached)
	explore.shop_entered.connect(_on_shop_entered)
	shop.closed.connect(func() -> void: _set_mode(Mode.EXPLORE))
	explore.chest_opened.connect(_on_chest)
	battle.battle_finished.connect(_on_battle_finished)
	explore.menu_requested.connect(_open_menu)
	menu.closed.connect(_close_menu)
	result.dismissed.connect(_enter_stronghold)

	_make_curtain()
	_enter_title()
	_handle_debug_args()


## 開発用。画面を 1 枚撮って終了する。
##   godot --path . -- --shot=explore
## GUI を触らずに見た目を確認できるので、ドット絵の調整に効く。
func _handle_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_capture(arg.trim_prefix("--shot="))
			return
		if arg.begins_with("--play="):
			_start_autoplay(float(arg.trim_prefix("--play=")))
			return


## 開発用。人と同じ入力だけを流し込んで通しを確認する（src/dev/autoplay.gd）。
func _start_autoplay(seconds: float) -> void:
	var driver := AutoPlay.new()
	add_child(driver)
	driver.start(self, maxf(seconds, 5.0))


## 自動プレイが「いまどの画面か」を知るための窓口。開発用。
func dev_mode_name() -> String:
	return Mode.keys()[_mode]


## 開発用。画面と階層をまとめた 1 行。自動プレイの記録に使う。
## 画面名だけだと「階を降りた」が記録に出てこない。
func dev_status() -> String:
	if _mode == Mode.EXPLORE or _mode == Mode.BATTLE or _mode == Mode.SHOP:
		return "%s 地下%d階" % [dev_mode_name(), GameState.floor_number]
	return dev_mode_name()


## 開発用。パーティが身に着けている装備の数。自動プレイの集計に使う。
func dev_equipped_count() -> int:
	var total := 0
	for m in GameState.active_party():
		total += m.equipment.size()
	return total


## 開発用。この階の出口（階段、最終階なら主の間の扉）へ向かう次の一歩。
## 自動プレイがこれで階を降りる。届かなければ空文字。
func dev_step_to_exit() -> String:
	if _mode != Mode.EXPLORE or _map == null:
		return ""
	return explore.dev_step_toward(_map.stairs_pos)


## 開発用。この階に出店があればそこへ向かう一歩。無ければ空文字。
func dev_step_to_shop() -> String:
	if _mode != Mode.EXPLORE or _map == null or _map.shop_pos.x < 0:
		return ""
	return explore.dev_step_toward(_map.shop_pos)


func _capture(which: String) -> void:
	match which:
		"title":
			pass  # 起動直後がタイトル
		"stronghold":
			_enter_stronghold()
		"job":
			_enter_stronghold()
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
			# 主の絵を撮るのが目的なので、開幕で壊滅しない程度に育てておく。
			# 敵 AI が範囲攻撃を選ぶようになってから、レベル 1 では 1 手で全滅する。
			for m in GameState.active_party():
				while m.level < 20:
					m.gain_exp(m.exp_to_next())
				m.hp = m.max_hp()
				m.mp = m.max_mp()
			while GameState.floor_number < GameState.FINAL_FLOOR:
				GameState.descend()
			_enter_floor()
			_on_boss_reached()
			for _i in 60:
				await get_tree().create_timer(0.1).timeout
				if battle.is_awaiting_command():
					break
		"menu":
			_start_run()
			GameState.add_item("herb", 3)
			GameState.add_gear("short_sword")
			GameState.add_gear("leather_vest")
			_open_menu()
		"equip":
			_start_run()
			GameState.add_gear("war_axe")
			GameState.add_gear("flame_dagger")
			_open_menu()
			menu.debug_open_equip()
		"party":
			_enter_stronghold()
			GameState.echo = 90
			stronghold.debug_open_party()
		"upgrade":
			_enter_stronghold()
			GameState.echo = 42
			stronghold.debug_open_upgrades()
		"win":
			_start_run()
			# 記録の見え方を確かめたいので、それらしい戦績を入れておく
			GameState.kills = 24
			GameState.gold_earned = 380
			while GameState.floor_number < GameState.FINAL_FLOOR:
				GameState.descend()
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
			# 技が増えたときのサブウィンドウの見え方を確かめる。
			battle.debug_open_spell_menu()
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
		"chronicle":
			# ローカル AI が書いた戦記を確かめる（届かなければテンプレートのまま）。
			_start_run()
			GameState.kills = 18
			GameState.gold_earned = 240
			while GameState.floor_number < 7:
				GameState.descend()
			result.show_summary(GameState.end_run(false))
			_set_mode(Mode.RESULT)
	# 戦記の撮影だけは、ローカル AI の文章が届くのを少し待つ。
	await get_tree().create_timer(9.0 if which == "chronicle" else 0.7).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://docs/preview/screen_%s.png" % which
	DirAccess.make_dir_recursive_absolute("res://docs/preview")
	image.save_png(path)
	print("撮影: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	get_tree().quit()


# --------------------------------------------------------------------------


func _enter_title() -> void:
	Sound.play_bgm("stronghold")
	title.open()
	_set_mode(Mode.TITLE)


## 拠点へ戻る。ラン中に呼ばれることは無い（end_run のあとだけ）。
func _enter_stronghold() -> void:
	Sound.play_bgm("stronghold")
	stronghold.open()
	_fade_to(Mode.STRONGHOLD)


func _start_run() -> void:
	GameState.start_new_run()
	# 開発用の状態指定（--dev-level=8 など）。指定が無ければ何もしない。
	var applied := DevCheats.apply_to_run(GameState)
	if not applied.is_empty():
		print("開発指定: %s" % "　".join(applied))
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
	_fade_to(Mode.EXPLORE)


## 画面の切り替えに挟む暗転の長さ（片道）。
## SFC 期は必ず暗転を挟んでいて、これが無いと画面が「差し替わった」ように見える。
const FADE_TIME := 0.14


## 暗転の幕。最前面に置いた黒い板で、透明度だけを動かす。
var _curtain: ColorRect = null

## 進行中の暗転。**最後に頼まれた画面が必ず勝つ**ようにするために持つ。
## 飛んでいる暗転を放っておくと、そのコールバックがあとから来た切り替えを
## 上書きする（戦記を出したのに探索画面が出た、という不具合が実際に起きた）。
var _fade_tween: Tween = null


func _make_curtain() -> void:
	_curtain = ColorRect.new()
	_curtain.color = Color(0, 0, 0, 0)
	_curtain.size = Vector2(PixelUI.SCREEN)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.z_index = 100
	add_child(_curtain)


## 暗転を挟んで画面を切り替える。
## 撮影（--shot）や自動プレイでも同じ経路を通るので、待ち時間は短く保つ。
func _fade_to(mode: Mode) -> void:
	if _curtain == null:
		_set_mode(mode)
		return
	_cancel_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	# 幕の裏で切り替えるのは _apply_mode。_set_mode を呼ぶと自分の暗転を
	# 自分で殺してしまい、幕が上がらなくなる。
	_fade_tween.tween_callback(_apply_mode.bind(mode))
	_fade_tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)


## 遭遇の演出。白く 2 回瞬かせてから戦闘へ移る。
##
## 暗転だけだと「画面が切り替わった」で終わってしまう。SFC 期の遭遇は
## 必ず画面全体に一撃入れてから戦闘に入っていて、それが緊張の合図になっていた。
func _flash_into_battle() -> void:
	if _curtain == null:
		_set_mode(Mode.BATTLE)
		return
	_cancel_fade()
	_curtain.color = Color(1, 1, 1, 0)
	_fade_tween = create_tween()
	for _i in 2:
		_fade_tween.tween_property(_curtain, "color:a", 0.85, 0.05)
		_fade_tween.tween_property(_curtain, "color:a", 0.0, 0.06)
	# 幕を黒に戻してから暗転で入る（白のまま暗転すると眩しいだけになる）
	_fade_tween.tween_callback(func() -> void: _curtain.color = Color(0, 0, 0, 0))
	_fade_tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	_fade_tween.tween_callback(_apply_mode.bind(Mode.BATTLE))
	_fade_tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)


## 飛んでいる暗転を捨てて幕を上げる。
func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if _curtain != null:
		# 幕は黒に戻す。白のまま残すと次の暗転が白飛びになる。
		_curtain.color = Color(0, 0, 0, 0)


## 画面を切り替える（暗転なし）。
##
## **最後に頼まれた画面が必ず勝つ。** 飛んでいる暗転はここで捨てる。
## 放っておくと、そのコールバックがあとから来た切り替えを上書きする
## （戦記を出したのに探索画面が出た、という不具合が実際に起きた）。
func _set_mode(mode: Mode) -> void:
	_cancel_fade()
	_apply_mode(mode)


func _apply_mode(mode: Mode) -> void:
	_mode = mode
	title.visible = mode == Mode.TITLE
	stronghold.visible = mode == Mode.STRONGHOLD
	shop.visible = mode == Mode.SHOP
	menu.visible = mode == Mode.MENU
	explore.visible = mode == Mode.EXPLORE
	hud.visible = mode == Mode.EXPLORE
	battle.visible = mode == Mode.BATTLE
	result.visible = mode == Mode.RESULT
	explore.set_active(mode == Mode.EXPLORE)
	if mode != Mode.TITLE:
		title.close()
	if mode != Mode.STRONGHOLD:
		stronghold.close()
	if mode != Mode.SHOP:
		shop.close()
	if mode != Mode.MENU:
		menu.close()
	if mode == Mode.EXPLORE:
		_refresh_hud()


## 探索中のメニュー。歩きを止めてから開く。
func _open_menu() -> void:
	menu.open()
	_set_mode(Mode.MENU)


func _close_menu() -> void:
	_set_mode(Mode.EXPLORE)


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
	_flash_into_battle()


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
	_fade_to(Mode.RESULT)


func _on_descend() -> void:
	Sound.play("stairs")
	GameState.descend()
	_enter_floor()


func _on_shop_entered() -> void:
	Sound.play("confirm")
	shop.open(_map, GameState.floor_number)
	_set_mode(Mode.SHOP)


## 宝箱の中身。
##
## 金だけだと「開ける手間に対して薄い」ので、装備と道具も出す。
## 出店にしか装備が無いと、道中の宝箱を開ける理由が弱かった。
## 抽選はこの階の乱数から引くので、同じシードなら同じ中身が出る。
func _on_chest(amount: int) -> void:
	Sound.play("chest")
	var roll := _battle_rng.range_i(0, 99)

	# 深い階ほど装備が出やすい。1 階で 15%、10 階で 33% ほど。
	if roll < 12 + GameState.floor_number * 2:
		var pool := Database.gear_ids_for_floor(GameState.floor_number)
		if not pool.is_empty():
			var gear_id := String(_battle_rng.pick(pool))
			GameState.add_gear(gear_id)
			hud.toast("たからばこ！ %s" % Database.gear(gear_id).get("name", gear_id))
			_refresh_hud()
			return

	if roll < 45:
		var items := Database.item_ids_for_floor(GameState.floor_number)
		if not items.is_empty():
			var item_id := String(_battle_rng.pick(items))
			GameState.add_item(item_id)
			hud.toast("たからばこ！ %s" % Database.item(item_id).get("name", item_id))
			_refresh_hud()
			return

	GameState.earn_gold(amount)
	hud.toast("たからばこ！ %d %s" % [amount, Terms.GOLD])
	_refresh_hud()
