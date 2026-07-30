extends Node2D

## 画面の切り替えとランの進行。
##
## 拠点 → 世界 → 戦闘 → 世界 …… → 城で主 → 戦記 → 拠点、という輪を回すだけ。
##
## 世界と洞の中は**同じ Mode.EXPLORE** で扱う。ExploreView は地図の中身に
## 依存していないので、`explore.setup()` に渡す地図を差し替えるだけで
## 縮尺が変わる。世界用にモードを増やすと、暗転・メニュー・HUD の分岐が
## 全部 2 本になる（そして片方だけ直したバグが出る）。
## ゲームの中身はそれぞれの View と BattleSystem 側にある。
##
## 輪が拠点に戻るのが要点。失ったレベルと残った熟練度を並べて見せる場が無いと、
## メタ進行が数字の裏側だけで進んでしまう。

enum Mode { TITLE, STRONGHOLD, EXPLORE, BATTLE, SHOP, MENU, SETTINGS, RESULT }

var title: TitleView
var stronghold: StrongholdView
var shop: ShopView
var explore: ExploreView
var hud: ExploreHud
var battle: BattleView
var menu: FieldMenu
var settings: SettingsView
var result: ResultScreen

var _mode: Mode = Mode.EXPLORE

## いま歩いている洞の 1 階ぶん（世界の上にいるときは null）。
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
	# 音量とキーの割り当てを先に効かせる（最初の効果音が鳴る前に）。
	Settings.ensure_loaded()

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

	settings = SettingsView.new()
	settings.visible = false
	add_child(settings)

	result = ResultScreen.new()
	result.visible = false
	add_child(result)

	title.started.connect(_enter_stronghold)
	stronghold.departed.connect(_start_run)
	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.boss_reached.connect(_on_boss_reached)
	explore.shop_entered.connect(_on_shop_entered)
	explore.site_entered.connect(_on_site_entered)
	# 町を出たら世界へ戻る（世界の上に立ち直す）。洞の出店ならその階へ戻るだけ。
	shop.closed.connect(func() -> void:
		if String(GameState.site.get("kind", "")) == "town":
			_leave_site()
		else:
			_set_mode(Mode.EXPLORE))
	explore.chest_opened.connect(_on_chest)
	battle.battle_finished.connect(_on_battle_finished)
	explore.menu_requested.connect(_open_menu)
	explore.door_nearby.connect(_on_door_nearby)
	explore.poison_ticked.connect(_on_poison_tick)
	menu.closed.connect(_close_menu)
	menu.settings_requested.connect(_open_settings)
	title.settings_requested.connect(_open_settings)
	settings.closed.connect(_close_settings)
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
		var place := "世界"
		match String(GameState.site.get("kind", "")):
			"town":
				place = "町"
			"cave":
				place = "洞%d階" % int(GameState.site.get("floor", 1))
			"castle":
				place = "城"
		return "%s %s 危険度%d" % [dev_mode_name(), place, GameState.floor_number]
	return dev_mode_name()


## 開発用。パーティが身に着けている装備の数。自動プレイの集計に使う。
func dev_equipped_count() -> int:
	var total := 0
	for m in GameState.active_party():
		total += m.equipment.size()
	return total


## 開発用。「先へ進む一歩」。世界では城へ、洞では階段へ向かう。
## 自動プレイがこれで世界を横断する。届かなければ空文字。
func dev_step_to_exit() -> String:
	if _mode != Mode.EXPLORE:
		return ""
	if _map == null:
		if GameState.world == null:
			return ""
		return explore.dev_step_toward(GameState.world.castle_pos)
	return explore.dev_step_toward(_map.stairs_pos)


## 開発用。近くの店へ向かう一歩。世界では町、洞では出店。無ければ空文字。
func dev_step_to_shop() -> String:
	if _mode != Mode.EXPLORE:
		return ""
	if _map == null:
		var town := _nearest_town()
		return "" if town.x < 0 else explore.dev_step_toward(town)
	if _map.shop_pos.x < 0:
		return ""
	return explore.dev_step_toward(_map.shop_pos)


## 開発用。その種類の拠点地のうち、門にいちばん近いもの。撮影に使う。
func _first_site(kind: String) -> Vector2i:
	if GameState.world == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := -1
	for pos in GameState.world.sites:
		if String(GameState.world.sites[pos].get("kind", "")) != kind:
			continue
		var at: Vector2i = pos
		var d := absi(at.x - GameState.world.start_pos.x) + absi(at.y - GameState.world.start_pos.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = at
	return best


## 世界でいちばん近い町。自動プレイが買い物を試すのに使う。
func _nearest_town() -> Vector2i:
	if GameState.world == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := -1
	for pos in GameState.world.sites:
		if String(GameState.world.sites[pos].get("kind", "")) != "town":
			continue
		var at: Vector2i = pos
		var d := absi(at.x - explore.player_pos.x) + absi(at.y - explore.player_pos.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = at
	return best


func _capture(which: String) -> void:
	match which:
		"title":
			pass  # 起動直後がタイトル
		"stronghold":
			_enter_stronghold()
		"job":
			_enter_stronghold()
			stronghold.debug_open_job_menu(0)
		"depart":
			# 潜る理由の 3 行が名簿と重なっていないかを見るため
			_enter_stronghold()
			stronghold.debug_open_depart()
		"upgrade":
			_enter_stronghold()
			stronghold.debug_open_upgrades()
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
			# 町の品書きを撮る。世界の最初の町へ直に入る。
			_start_run()
			GameState.gold = 300
			var town := _first_site("town")
			if town.x >= 0:
				_on_site_entered(town)
		"world":
			# 世界の全景。歩ける地形と拠点地の見分けを確かめる。
			_start_run()
		"cave":
			_start_run()
			var cave := _first_site("cave")
			if cave.x >= 0:
				_on_site_entered(cave)
		"deep":
			# 終点近くの敵の見え方を確認する。
			_start_run()
			GameState.floor_number = GameState.FINAL_FLOOR - 1
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
			GameState.floor_number = GameState.FINAL_FLOOR
			_enter_world()
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
		"jobmenu":
			# てんしょくの一覧と代償の表示を確かめる
			_start_run()
			for m in GameState.active_party():
				while m.level < 7:
					m.gain_exp(m.exp_to_next())
			_open_menu()
			menu.debug_open_jobs()
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
		"settings":
			settings.open()
			_set_mode(Mode.SETTINGS)
		"upgrade":
			_enter_stronghold()
			GameState.echo = 42
			stronghold.debug_open_upgrades()
		"win":
			_start_run()
			# 記録の見え方を確かめたいので、それらしい戦績を入れておく
			GameState.kills = 24
			GameState.gold_earned = 380
			GameState.floor_number = GameState.FINAL_FLOOR
			GameState.deepest_floor = GameState.FINAL_FLOOR
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
			GameState.floor_number = 7
			GameState.deepest_floor = 7
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
	_enter_world()


func _leader_job() -> String:
	var party := GameState.active_party()
	return party[0].job_id if not party.is_empty() else "soldier"


## 世界の上へ出る（門に着いたとき、町や洞から出たとき）。
func _enter_world() -> void:
	GameState.stand_on_world(GameState.world_pos)
	_map = null
	_door_warned = false
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	explore.setup(GameState.world, _encounter_rng, _leader_job(), GameState.world_pos)
	Sound.play_bgm("descent")
	_fade_to(Mode.EXPLORE)


## 洞の 1 階ぶんへ入る。
func _enter_floor() -> void:
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	# 洞に主の間は置かない。**主が居るのは世界の終点（城）だけ。**
	# 寄り道の底にも主を置くと、寄り道が本筋と同じ重さになって
	# 「寄るか急ぐか」の判断が消える。洞の見返りは宝箱と出店。
	# 洞の中の絵はその土地の生物相から来る（雪原の洞は雪原の絵）。
	_map = DungeonGenerator.generate(GameState.rng_for("terrain"), GameState.floor_number, false)
	_map.biome = String(GameState.site.get("tileset", "dungeon"))
	_door_warned = false
	explore.setup(_map, _encounter_rng, _leader_job())
	Sound.play_bgm("descent")
	_fade_to(Mode.EXPLORE)


## 世界で拠点地を踏んだ。町・洞・城で行き先が変わる。
func _on_site_entered(pos: Vector2i) -> void:
	GameState.world_pos = pos
	var entered := GameState.enter_site(pos)
	match String(entered.get("kind", "")):
		"town":
			# 町は安全地帯。今の出店をそのまま宿つきの町として使う。
			_open_town()
		"cave":
			_enter_floor()
		"castle":
			# 終点。ここが 1 ラン の終わり方（勝てば生還、負ければ全滅）。
			hud.toast("城の門が ひらいた。ここから先は 戻れない。")
			_on_boss_reached()
		_:
			# 門。踏んでも何も起きない（世界の上に立ったまま）。
			GameState.site = {}


## 町。出店と宿を兼ねる（世界の上にある安全地帯）。
##
## 在庫は町ごとに世界が覚える。出入りで戻ると買い占めができてしまうし、
## 別の町では品が違ってほしい。
func _open_town() -> void:
	Sound.play("confirm")
	var key := "town:%d" % int(GameState.site.get("index", 0))
	if not GameState.world.visited.has(key):
		GameState.world.visited[key] = {}
	shop.open(GameState.world.visited[key], GameState.floor_number)
	_set_mode(Mode.SHOP)


## 拠点地から世界へ戻る。
func _leave_site() -> void:
	GameState.site = {}
	_enter_world()


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
	# 幕が下りるのを待たずに歩みを止める。
	#
	# 暗転を入れるまでは「切り替え＝即座」だったので気づかなかったが、
	# 幕の裏で切り替える形にすると、その 0.3 秒のあいだ入力が生きたままになる。
	# 実際に「遭遇したのに歩けて、そのまま階段へ降りられる」状態だった。
	explore.set_active(false)
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
	# 遭遇の瞬間に歩みを止める（理由は _fade_to と同じ）。
	explore.set_active(false)
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
	settings.visible = mode == Mode.SETTINGS
	# メニュー中も探索の絵は出したままにする（メニューを半透明にしてあるので、
	# 下にダンジョンが見える）。HUD は二重になるので隠す。
	explore.visible = mode == Mode.EXPLORE or mode == Mode.MENU
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
	if mode != Mode.SETTINGS:
		settings.close()
	if mode == Mode.EXPLORE:
		_refresh_hud()


## 歩いたぶんの毒。倒れはしないが、削られながら出店へ急ぐことになる。
func _on_poison_tick() -> void:
	var hurt := 0
	for m in GameState.active_party():
		hurt += m.step_poison()
	if hurt > 0:
		_refresh_hud()


## 主の間が隣に来た。踏むと戻れないので、踏む前に知らせる。
## 同じ階で何度も出ると邪魔なので、1 階につき 1 回だけ。
var _door_warned := false


func _on_door_nearby() -> void:
	if _door_warned:
		return
	_door_warned = true
	hud.toast("おおきな扉が ある。ここから先は 戻れない。")


## 探索中のメニュー。歩きを止めてから開く。
func _open_menu() -> void:
	menu.open()
	_set_mode(Mode.MENU)


func _close_menu() -> void:
	_set_mode(Mode.EXPLORE)


## 設定はどの画面からでも開ける。閉じたら開く前の画面へ戻す。
var _mode_before_settings: Mode = Mode.TITLE


func _open_settings() -> void:
	_mode_before_settings = _mode
	settings.open()
	# 下の画面は残したまま重ねる（設定は場面ではなく、上に開く窓）。
	_set_mode(Mode.SETTINGS)
	title.visible = _mode_before_settings == Mode.TITLE
	menu.visible = _mode_before_settings == Mode.MENU
	explore.visible = _mode_before_settings in [Mode.EXPLORE, Mode.MENU]


func _close_settings() -> void:
	if _mode_before_settings == Mode.MENU:
		menu.open()
	elif _mode_before_settings == Mode.TITLE:
		title.open()
	_set_mode(_mode_before_settings)


func _refresh_hud() -> void:
	hud.refresh(
		GameState.active_party(), GameState.floor_number, GameState.gold, _place_label()
	)


## HUD の左上に出す 1 行。居場所と危険度を並べる。
##
## 世界の上では**生物相の名**を出す（「雪原 危険度 7」）。
## そこに何が出るかは生物相で決まるので、名前が見えていれば備えられる。
func _place_label() -> String:
	var danger := Terms.DANGER_AT % GameState.floor_number
	match String(GameState.site.get("kind", "")):
		"cave":
			return "%s%s　%s" % [
				String(GameState.site.get("place", "")),
				Terms.CAVE_FLOOR % int(GameState.site.get("floor", 1)), danger,
			]
		"castle":
			return "%s　%s" % [Terms.CASTLE, danger]
	var place := GameState.place_name()
	return danger if place == "" else "%s　%s" % [place, danger]


# --------------------------------------------------------------------------


func _on_encounter() -> void:
	# その土地の生物相で敵が変わる。雪原なら氷に強いもの、火山なら火に強いもの。
	# 地形を見て備えられる、というのが生物相を持たせた理由。
	_begin_battle(
		Encounter.build(_battle_rng, GameState.floor_number, 100, GameState.biome_here()), false
	)


## 主の間へ踏み込んだ。ここで勝てばランが「生還」で終わる。
func _on_boss_reached() -> void:
	var foes := Encounter.build_boss(_battle_rng, GameState.floor_number)
	if foes.is_empty():
		# 主のデータが無い階に扉を置いてしまった場合の保険。詰ませない。
		push_warning("危険度 %d に主がいない" % GameState.floor_number)
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


## 洞の階段。いちばん深い階まで来たら、次は下ではなく外へ出る。
func _on_descend() -> void:
	Sound.play("stairs")
	if int(GameState.site.get("floor", 1)) >= GameState.cave_depth():
		hud.toast("洞を ぬけた。")
		_leave_site()
		return
	GameState.descend()
	_enter_floor()


## 洞の中の出店。在庫はその階が持つ（降りれば品が戻る）。
func _on_shop_entered() -> void:
	if _map == null:
		return
	Sound.play("confirm")
	shop.open(_map.shop_stock, GameState.floor_number)
	_set_mode(Mode.SHOP)


## 宝箱の中身。
##
## 金だけだと「開ける手間に対して薄い」ので、装備と道具も出す。
## 出店にしか装備が無いと、道中の宝箱を開ける理由が弱かった。
## 抽選はこの階の乱数から引くので、同じシードなら同じ中身が出る。
func _on_chest(amount: int) -> void:
	Sound.play("chest")
	var roll := _battle_rng.range_i(0, 99)

	# 深い階ほど装備が出やすい。1 階で 22%、10 階で 40% ほど。
	#
	# 最初は 12% から始めていたが、実際に遊ぶと「宝箱は金しか出ない」と感じる。
	# 3 回開けて 3 回とも金なら、中身の種類は無いのと同じ。
	if roll < 20 + GameState.floor_number * 2:
		var pool := Database.gear_ids_for_floor(GameState.floor_number)
		if not pool.is_empty():
			var gear_id := String(_battle_rng.pick(pool))
			GameState.add_gear(gear_id)
			hud.toast("たからばこ！ %s" % Database.gear(gear_id).get("name", gear_id))
			_refresh_hud()
			return

	if roll < 68:
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
