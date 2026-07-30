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

enum Mode { TITLE, STRONGHOLD, EXPLORE, BATTLE, SHOP, MENU, SETTINGS, RESULT, EVENT }

var title: TitleView
var stronghold: StrongholdView
var shop: ShopView
var explore: ExploreView
var hud: ExploreHud
var battle: BattleView
var menu: FieldMenu
var settings: SettingsView
var result: ResultScreen
var event_view: EventView

var _mode: Mode = Mode.EXPLORE

## いま歩いている洞の 1 階ぶん（世界の上にいるときは null）。
var _map: DungeonMap = null

## いま居る町の中（町に居ないときは null）。
var _town: TownMap = null

## 階ごとに 1 本ずつ持つ乱数列。呼ぶたびに進むので、
## 同じ階で戦うたびに同じ敵が出る、という事故が起きない。
var _encounter_rng: DetRng = null
var _battle_rng: DetRng = null

## ローカル AI の窓口（唯一の接続点）。
var _ai: LocalAI = null

## いま頼んでいるのがイベントの表層か（封の名か）。
var _awaiting_event_text := false

## 封の番人と戦っているか / この洞の番人を倒したか。
## **城の主とは別扱い**（勝ってもランは終わらない）。
var _guardian_battle := false
var _guardian_beaten := false

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

	event_view = EventView.new()
	event_view.visible = false
	add_child(event_view)
	# 同じ窓を拍とイベントで使い回すので、返り先はここで振り分ける。
	# 同じ窓を 3 通りに使い回すので、返り先はここで振り分ける
	# （結果の窓 / 物語の拍 / イベントの選択）。
	event_view.chosen.connect(func(c: Dictionary) -> void:
		if _outcome_open:
			_close_outcome()
		elif _story_beat.is_empty():
			_on_event_choice(c)
		else:
			_on_story_choice(c))
	event_view.dismissed.connect(func() -> void:
		# **物語の拍と結果は見送れない**（飛ばせると話が飛ぶ／読めない）。
		if _outcome_open:
			_close_outcome()
		elif _story_beat.is_empty():
			_on_event_dismissed()
		else:
			_on_story_choice({}))

	# ローカル AI の窓口は 1 つだけ。戦記もクエスト文もここを通す。
	_ai = LocalAI.new()
	add_child(_ai)
	# 窓口は 1 つなので、返りは「いま何を頼んだか」で振り分ける。
	_ai.answered.connect(func(text: String) -> void:
		if _awaiting_event_text:
			_awaiting_event_text = false
			_on_event_text(text)
			return
		_on_quest_text(text)
		# 封の名が済んだら、続けてイベントの表層を頼む（印は _ask_event_text が立てる）。
		_ask_event_text())

	title.started.connect(_enter_stronghold)
	title.resumed.connect(_resume_run)
	stronghold.departed.connect(_start_run)
	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.boss_reached.connect(_on_boss_reached)
	explore.shop_entered.connect(_on_shop_entered)
	explore.site_entered.connect(_on_site_entered)
	explore.event_reached.connect(_on_event_reached)
	explore.talked.connect(_on_talked)
	explore.rumor = _rumor
	explore.inn_entered.connect(_on_inn)
	explore.town_left.connect(_on_town_left)
	# 町を出たら世界へ戻る（世界の上に立ち直す）。洞の出店ならその階へ戻るだけ。
	# 店を閉じたら、その場（町の中／洞の中）へ戻す。
	shop.closed.connect(func() -> void: _set_mode(Mode.EXPLORE))
	explore.chest_opened.connect(_on_chest)
	battle.battle_finished.connect(_on_battle_finished)
	explore.menu_requested.connect(_open_menu)
	explore.door_nearby.connect(_on_door_nearby)
	explore.poison_ticked.connect(_on_poison_tick)
	menu.closed.connect(_close_menu)
	menu.settings_requested.connect(_open_settings)
	menu.suspend_requested.connect(_suspend_run)
	menu.escape_requested.connect(_escape_site)
	title.settings_requested.connect(_open_settings)
	settings.closed.connect(_close_settings)
	result.dismissed.connect(_enter_stronghold)

	_make_curtain()
	_handle_debug_args()
	# 開発用の保存から立ち上げたときは、その場面のままにする。
	if not _loaded_from_dev and _mode == Mode.EXPLORE:
		_enter_title()


## 開発用。画面を 1 枚撮って終了する。
##   godot --path . -- --shot=explore
## GUI を触らずに見た目を確認できるので、ドット絵の調整に効く。
func _handle_debug_args() -> void:
	# **先に全部の引数を見る。** 下の輪は最初に当たった指定で return するので、
	# 「--play=12 --dev-save=probe」のように後ろへ書くと読まれなかった。
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dev-save="):
			_dev_save_name = arg.trim_prefix("--dev-save=")

	for arg in OS.get_cmdline_user_args():
		# 開発用。「この世界のこの場面」を保存／読み込みする。
		#   godot --path . -- --dev-load=boss1
		# **読み込んだあとも他の指定を続ける。** ここで return すると
		# 「--dev-load=x --play=10」の自動プレイが始まらず、headless が終わらない。
		if arg.begins_with("--dev-load="):
			if GameState.dev_load(arg.trim_prefix("--dev-load=")):
				print("開発用の保存から再開: %s" % arg.trim_prefix("--dev-load="))
				_resume_loaded()
				_loaded_from_dev = true
			continue
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
	# 町は閉じた広場なので、酔歩では出口に当たらない（40 秒 居座った）。
	# 町に居るあいだは出口へ向かわせる。
	if _town != null:
		return explore.dev_step_toward(_town.exit_pos)
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
		"story":
			# 物語の 1 拍目。語りが窓に収まっているかを見る。
			_start_run()
			var b0: Dictionary = GameState.world.story.get("beats", [])[0]
			var at0 := GameState.world.pos_of_site_id(String(b0.get("site_id", "")))
			GameState.world_pos = at0
			_open_story(b0)
		"choicebeat":
			# 「代償の選択」の拍。守るもの・手ばなすものが読めるかを見る。
			_start_run()
			var beats: Array = GameState.world.story.get("beats", [])
			for i in beats.size():
				if String(beats[i].get("phase", "")) == "choice":
					GameState.world.story_beat = i
					GameState.world_pos = GameState.world.pos_of_site_id(
						String(beats[i].get("site_id", "")))
					_open_story(beats[i])
					break
		"event":
			# イベントの選択画面。払うものが選ぶ前に見えているかを確かめる。
			_start_run()
			for pos in GameState.world.events:
				_open_event(pos)
				break
		"town":
			# 町の中の見え方（宿・店・人）を確かめる
			_start_run()
			var town_at := _first_site("town")
			if town_at.x >= 0:
				_on_site_entered(town_at)
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
			# てんしょくの一覧の見え方を確かめる
			_start_run()
			# 熟練を積んだ状態で撮る。★ が最大まで並ぶのはこのときだけ。
			for m in GameState.active_party():
				while m.level < 7:
					m.gain_exp(m.exp_to_next())
				# 全職の熟練を積む（★ が最大まで並ぶ状態を作る）。
				for job_id in Database.job_ids():
					m.job_exp[job_id] = 9999
			_open_menu()
			menu.debug_open_jobs()
		"status":
			# つよさ の重なりを見る
			_start_run()
			for m in GameState.active_party():
				while m.level < 12:
					m.gain_exp(m.exp_to_next())
			_open_menu()
			menu.debug_open_status()
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
			# 物語を通した状態で戦記を見る（終幕が回収されているか）。
			GameState.world.story_beat = 6
			var cs: Array = GameState.world.story.get("choices", [])
			if not cs.is_empty():
				GameState.world.story_choice = String(cs[0].get("id", ""))
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
	# はみ出しの検出結果。--ui-check を付けたときだけ出る。
	if PixelUI.ui_check_enabled():
		var bad := PixelUI.ui_violations()
		if bad.is_empty():
			print("  はみ出し: なし")
		else:
			for note in bad:
				print("  はみ出し: %s" % note)
	get_tree().quit()


# --------------------------------------------------------------------------


func _enter_title() -> void:
	Sound.play_bgm("title")
	title.open()
	_set_mode(Mode.TITLE)


## 拠点へ戻る。ラン中に呼ばれることは無い（end_run のあとだけ）。
func _enter_stronghold() -> void:
	Sound.play_bgm("stronghold")
	stronghold.open()
	_fade_to(Mode.STRONGHOLD)


## クエスト文をローカル AI に頼むときの言い方。
##
## **構造は渡すが、決めさせない。** 封の数も帯も既に確定していて、
## AI が書くのは名と一文だけ。数を書かせないと明示するのは、
## 書いてきたものを `QuestText` が落とすより先に、そもそも書かせないため。
const QUEST_PROMPT := """あなたは SFC 期の日本語 RPG の名づけ役です。
次の「封」に、名前と一文を付けてください。

%s

制約:
- 名前は 10 文字以内。ひらがな主体で、漢字は易しいものだけ。
- 一文は 34 文字以内。その封が城の主を守っている理由を書く。
- **数字を書かない。** 英字を書かない。記号・箇条書き・思考過程を書かない。
- 他社の作品に出てくる固有名詞を使わない。
- JSON だけを返す: {"seals":[{"name":"…","why":"…"},…3つ]}
"""


## 開発用。`--dev-save=名前` を付けて起動すると、ランを始めた直後に保存する。
var _dev_save_name := ""

## 開発用の保存から立ち上げたか（そのときはタイトルへ戻さない）。
var _loaded_from_dev := false


## 読み込んだ状態から画面を立ち上げる（中断の再開と同じ道）。
func _resume_loaded() -> void:
	_event_skinned = {}
	_awaiting_event_text = false
	if String(GameState.site.get("kind", "")) == "cave":
		_enter_floor()
	else:
		GameState.site = {}
		_enter_world()


## 中断から再開する。読めなければ拠点へ落とす（詰ませない）。
func _resume_run() -> void:
	if not GameState.resume():
		hud.toast("つづきが 読めなかった。")
		_enter_stronghold()
		return
	# 世界は種から作り直したので、いま居る場所へ立ち直すだけでよい。
	_resume_loaded()


func _start_run() -> void:
	GameState.start_new_run()
	Sound.play("depart")
	_ask_quest_text()
	# 開発用の状態指定（--dev-level=8 など）。指定が無ければ何もしない。
	var applied := DevCheats.apply_to_run(GameState)
	if not applied.is_empty():
		print("開発指定: %s" % "　".join(applied))
	# 「封の言い伝え」を買っているぶん、出撃前から在り処が分かっている。
	if _dev_save_name != "":
		if GameState.dev_save(_dev_save_name):
			print("開発用の保存: %s" % _dev_save_name)
	var told := GameState.reveal_known_seals()
	if not told.is_empty():
		hud.toast("言い伝え: %s" % " ".join(told))
	_enter_world()


func _leader_job() -> String:
	var party := GameState.active_party()
	return party[0].job_id if not party.is_empty() else "soldier"


## 世界の上へ出る（門に着いたとき、町や洞から出たとき）。
func _enter_world() -> void:
	GameState.stand_on_world(GameState.world_pos)
	_map = null
	_town = null
	_door_warned = false
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	explore.setup(GameState.world, _encounter_rng, _leader_job(), GameState.world_pos)
	Sound.play_bgm("world")
	_fade_to(Mode.EXPLORE)


## 洞の 1 階ぶんへ入る。
func _enter_floor() -> void:
	_encounter_rng = GameState.rng_for("encounter")
	_battle_rng = GameState.rng_for("battle")
	# 洞に主の間は置かない。**主が居るのは世界の終点（城）だけ。**
	# 寄り道の底にも主を置くと、寄り道が本筋と同じ重さになって
	# 「寄るか急ぐか」の判断が消える。洞の見返りは宝箱と出店。
	# 洞の中の絵はその土地の生物相から来る（雪原の洞は雪原の絵）。
	_guardian_battle = false
	_map = DungeonGenerator.generate(GameState.rng_for("terrain"), GameState.floor_number, false)
	_map.biome = String(GameState.site.get("tileset", "dungeon"))
	_door_warned = false
	explore.setup(_map, _encounter_rng, _leader_job())
	Sound.play_bgm("cave")
	_fade_to(Mode.EXPLORE)


## 戦闘や物語のあと、いま立っている場所の曲へ戻す。
func _play_field_bgm() -> void:
	if _town != null:
		Sound.play_bgm("town")
	elif _map != null:
		Sound.play_bgm("cave")
	else:
		Sound.play_bgm("world")


## 世界で拠点地を踏んだ。町・洞・城で行き先が変わる。
func _on_site_entered(pos: Vector2i) -> void:
	GameState.world_pos = pos
	# **物語がいちばん先。** 拍 → イベント → 町や洞の中身、の順に出す。
	# 逆にすると、町へ入ったあとに拍が始まって場面が入れ替わる。
	var beat := GameState.story_beat_at(pos)
	if not beat.is_empty():
		GameState.stand_on_world(pos)
		_open_story(beat)
		return

	# 拠点地にイベントが重なっていれば、中へ入る前にそれを出す。
	# 済んだら踏み直しで町や洞へ入れる。
	if GameState.world != null and not GameState.world.event_at(pos).is_empty() 			and not GameState.event_done.has(pos):
		GameState.stand_on_world(pos)
		_open_event(pos)
		return
	var entered := GameState.enter_site(pos)
	match String(entered.get("kind", "")):
		"town":
			# 町は安全地帯。今の出店をそのまま宿つきの町として使う。
			_open_town()
		"cave":
			_guardian_beaten = false
			var seal := GameState.seal_here()
			if not seal.is_empty() and not bool(seal.get("broken", false)):
				hud.toast("%s の けはい。%s" % [
					String(seal.get("name", "封")), String(seal.get("why", ""))
				])
			_enter_floor()
		"castle":
			# 城に結ばれた拍（finale / epilogue）は主戦より先に出す。
			var castle_beat := GameState.story_beat_at(pos)
			if not castle_beat.is_empty():
				GameState.stand_on_world(pos)
				_open_story(castle_beat)
				return
			# 終点。**封が残っていると扉は開かない。**
			# ここで通してしまうと、洞へ寄る理由が宝箱だけに戻る。
			var left := GameState.seals_remaining()
			if left > 0:
				Sound.play("cancel")
				hud.toast("とびらは 固く 閉ざされている。封が あと %d つ。" % left)
				GameState.site = {}
				return
			hud.toast("城の門が ひらいた。ここから先は 戻れない。")
			_on_boss_reached()
		_:
			# 門。踏んでも何も起きない（世界の上に立ったまま）。
			GameState.site = {}


## クエスト文を頼む。**待たせない。**
##
## 世界は既にテンプレートの名前で完成していて、すぐ遊べる。
## 数秒後に届いたら表示だけ差し替える（構造は動かないので途中でも安全）。
## 届かなければテンプレートのまま、というだけ。
func _ask_quest_text() -> void:
	if GameState.world == null or _ai.is_busy():
		return
	var facts := JSON.stringify(QuestText.facts_for_llm(GameState.world), "  ")
	_ai.ask(QUEST_PROMPT % facts, 8.0, "quest")


## イベントの表層を AI に頼む。**構造は渡さない**（id・選択肢・数値は含めない）。
## `WorldEventCatalog.facts_for_ai()` が既にそこまで削ってある。
const EVENT_PROMPT := """あなたは SFC 期の日本語 RPG の名づけ役です。
次の出来事に、題・関係者・原因・情景を付けてください。

%s

制約:
- それぞれ指定の文字数以内。ひらがな主体で、漢字は易しいものだけ。
- **数字を書かない。** 英字を書かない。記号・箇条書き・思考過程を書かない。
- 他社の作品に出てくる固有名詞を使わない。
- JSON だけを返す: {"title":"…","actor":"…","cause":"…","flavor":"…"}
"""


func _ask_event_text() -> void:
	if GameState.world == null or _ai.is_busy():
		return
	for pos in GameState.world.events:
		if _event_skinned.has(pos):
			continue
		_event_skin_pos = pos
		var facts := JSON.stringify(
			WorldEventCatalog.facts_for_ai(GameState.world.events[pos]), "  "
		)
		# **頼んだ側で印を立てる。** 受け取る側で立てると、返りが来る前に
		# 次を頼んだ瞬間に取り違える（実際に封の名の処理へ流れ込んだ）。
		if _ai.ask(EVENT_PROMPT % facts, 8.0, "event"):
			_event_skinned[pos] = true
			_awaiting_event_text = true
		return


var _event_skinned: Dictionary = {}
var _event_skin_pos := Vector2i(-1, -1)


func _on_event_text(text: String) -> void:
	var reply := LocalAI.extract_json(text)
	if reply.is_empty() or not GameState.world.events.has(_event_skin_pos):
		return
	var before: Dictionary = GameState.world.events[_event_skin_pos]
	GameState.world.events[_event_skin_pos] = WorldEventCatalog.apply_ai_skin(before, reply)
	if LocalAI.debug_enabled():
		print("[AI:event] 却下 %s" % str(
			GameState.world.events[_event_skin_pos].get("rejected", [])))
	# 次のイベントの表層を続けて頼む（1 件ずつ、待たせない）。
	_ask_event_text()


func _on_quest_text(text: String) -> void:
	var reply := LocalAI.extract_json(text)
	if reply.is_empty():
		return
	var report := QuestText.apply_to_world(GameState.world, reply)
	if LocalAI.debug_enabled():
		print("[AI:quest] 採用 %d 項目 / 却下 %s" % [int(report["taken"]), str(report["rejected"])])


## 町の中へ入る。
##
## 品書きを直接開いていたころは、町が場所として存在していなかった。
## 中を歩けるようにすると、宿・店・人が別々の場所になり、
## 「誰に話すか」「何を先にするか」がそのまま行動になる。
func _open_town() -> void:
	Sound.play("confirm")
	_town = TownGenerator.generate(
		GameState.rng_for("town"), GameState.floor_number,
		String(GameState.site.get("tileset", "dungeon"))
	)
	_map = null
	_encounter_rng = GameState.rng_for("encounter")
	explore.setup(_town, _encounter_rng, _leader_job())
	Sound.play_bgm("town")
	hud.toast(_town.town_name)
	_fade_to(Mode.EXPLORE)


## 町の人の一言。
##
## 物知りだけは**封の在り処**を教える。これが町に寄る理由になる
## （それ以外の役は世間話のままにする。全員が案内役だと町が掲示板になる）。
func _on_talked(line: String) -> void:
	Sound.play("confirm")
	hud.toast(line)


## 物知りの台詞を、まだ解けていない封の手掛かりに差し替える。
func _rumor() -> String:
	if GameState.world == null:
		return ""
	for s in GameState.world.seals:
		if bool(s.get("broken", false)):
			continue
		var at: Vector2i = s.get("pos", Vector2i(-1, -1))
		var place := GameState.world.biome_name_at(at.x, at.y)
		return "%s は %s の 洞に あるという。" % [String(s.get("name", "封")), place]
	return "封は すべて やぶれた。あとは 城だけだ。"


## 宿。**取り上げるものは無いので、ゴールドも取らない。**
## 町まで戻ってきた手間がそのまま代金、という扱いにする。
func _on_inn() -> void:
	for m in GameState.active_party():
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		m.cure_poison()
	Sound.play("learn")
	_refresh_hud()
	hud.toast("ゆっくり やすんだ。みな 元気に なった。")


## 町を出て世界へ戻る。
func _on_town_left() -> void:
	Sound.play("stairs")
	_town = null
	_leave_site()


## 拠点地から世界へ戻る。**必ず 1 マス外へ出す**（出た直後に再突入しないため）。
func _leave_site() -> void:
	GameState.world_pos = GameState.step_outside_site(GameState.world_pos)
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
	# イベントは場面の上に開く窓。下の絵は残す。
	event_view.visible = mode == Mode.EVENT
	if mode == Mode.EVENT:
		explore.visible = true
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
	if mode != Mode.EVENT:
		event_view.close()
	if mode == Mode.EXPLORE:
		_refresh_hud()


## 物語の拍を開く。
func _open_story(beat: Dictionary) -> void:
	_story_beat = beat
	event_view.open_story(beat, GameState.world.story, GameState.floor_number)
	event_view.set_blocked([])
	Sound.play_bgm("story")
	Sound.play("story_open")
	_set_mode(Mode.EVENT)


var _story_beat: Dictionary = {}


## 拍で手を選んだ（選択の無い拍では空の手が来る）。
func _on_story_choice(choice: Dictionary) -> void:
	var id := String(choice.get("id", ""))
	if id != "":
		# 選んだ手は世界が覚える。終幕でこれを回収する。
		GameState.world.story_choice = id
		Sound.play("story_choice")
		hud.toast(String(choice.get("label", "")))
	GameState.advance_story()
	_story_beat = {}
	# 拍が済んだら、その場所の続き（イベント／町／洞）へそのまま進む。
	var at := GameState.world_pos
	_play_field_bgm()
	_set_mode(Mode.EXPLORE)
	if not _event_at(at).is_empty():
		_open_event(at)
	elif GameState.world.site_at(at).get("kind", "") != "":
		_on_site_entered(at)


## 街道のイベントを踏んだ。
func _on_event_reached(pos: Vector2i) -> void:
	GameState.world_pos = pos
	GameState.stand_on_world(pos)
	_open_event(pos)


## その場所のイベント（無ければ空）。一度きり。
##
## 立っている場所ではなく**渡された場所**を見る。GameState.world_pos に
## 頼ると、まだそこへ立っていない呼び出し（撮影など）で空になる。
func _event_at(at: Vector2i) -> Dictionary:
	if GameState.world == null:
		return {}
	var found := GameState.world.event_at(at)
	if found.is_empty() or GameState.event_done.has(at):
		return {}
	return found


## イベントを開く。**払えない手は選べないようにしてから出す。**
func _open_event(at: Vector2i) -> void:
	var found := _event_at(at)
	if found.is_empty():
		return
	_event_pos = at
	event_view.open(found, GameState.floor_number)
	event_view.set_blocked(_blocked_for(found))
	Sound.play("event")
	_set_mode(Mode.EVENT)


## いま選んでいる手が払えるか。EventView は GameState を知らないので、ここで調べる。
func _blocked_for(found: Dictionary) -> Array[String]:
	var choices: Array = found.get("choices", [])
	if choices.is_empty():
		return []
	# 先頭の手だけを見るのではなく、全部払えないときだけ止める。
	# （1 つでも選べるなら画面は開いてよい）
	var any_ok := false
	for c in choices:
		if EventEffects.unpayable(GameState, c.get("costs", []), GameState.floor_number).is_empty():
			any_ok = true
			break
	if any_ok:
		return []
	return EventEffects.unpayable(
		GameState, choices[0].get("costs", []), GameState.floor_number
	)


var _event_pos := Vector2i(-1, -1)


## 手を選んだ。払って、得て、要るなら戦う。
func _on_event_choice(choice: Dictionary) -> void:
	GameState.event_done[_event_pos] = true
	var danger := GameState.floor_number
	var lines: Array[String] = []
	lines.append_array(EventEffects.pay(GameState, choice.get("costs", []), danger))

	# **危険は実際に振る。** 並べておいて起きないなら、それは危険ではなく飾り。
	var fired: Array = []
	for raw in choice.get("risks", []):
		var token := String(raw)
		if not _battle_rng.chance(RISK_ODDS):
			continue
		fired.append(token)
		lines.append("%s。" % EventEffects.label(token, "risk"))
	if not fired.is_empty():
		lines.append_array(EventEffects.pay(GameState, fired, danger))
	elif not choice.get("risks", []).is_empty():
		lines.append("あぶないところは 起きなかった。")

	lines.append_array(
		EventEffects.grant(GameState, choice.get("rewards", []), danger, _battle_rng)
	)

	# 前に同じ傾向を選んでいたら一言添える（世界が覚えている感じを作る）。
	var echoed := _remember_choice()
	if echoed != "":
		lines.append(echoed)
	if GameState.event_shop_bonus > 0:
		pass  # 町の品数は ShopView が読む
	_refresh_hud()

	# 戦いを含む手は、そのまま戦闘へ入る（払ったあとに逃げられない）。
	var fights := _fight_token(choice.get("costs", [])) or _fight_token(choice.get("risks", []))
	if fights:
		lines.append("身がまえる 間もなく、敵が 来た。")
	_pending_fight = fights
	# **結果は同じ窓で読ませる。** toast だと流れて、選んだ意味が確かめられない。
	_story_beat = {}
	event_view.open_outcome(String(choice.get("label", "")), lines, danger)
	_outcome_open = true
	_set_mode(Mode.EVENT)


## 危険が実際に起きる確率。**並べておいて起きないなら飾りになる。**
const RISK_ODDS := 45

var _pending_fight := false
var _outcome_open := false


## 選んだ手の傾向を覚え、前に同じ傾向を選んでいれば一言返す。
func _remember_choice() -> String:
	var event := _event_at(_event_pos)
	var tags: Array = event.get("tags", [])
	var echoed := ""
	for raw in tags:
		var tag := String(raw)
		if GameState.chose_tag_before(tag) and echoed == "":
			echoed = "まえに 似た えらび方を したのを、道の者が 覚えていた。"
		GameState.event_tags[tag] = int(GameState.event_tags.get(tag, 0)) + 1
	return echoed


## 結果の窓を閉じた。戦いが要るならここで入る。
func _close_outcome() -> void:
	_outcome_open = false
	_set_mode(Mode.EXPLORE)
	if _pending_fight:
		_pending_fight = false
		_on_encounter()


func _fight_token(list: Array) -> bool:
	for token in list:
		if String(token) in ["normal_fight", "elite_fight"]:
			return true
	return false


## 見送った。**必ず立ち去れる**（踏み直せばまた開く）。
func _on_event_dismissed() -> void:
	_set_mode(Mode.EXPLORE)


## 歩いたぶんの毒。倒れはしないが、削られながら出店へ急ぐことになる。
func _on_poison_tick() -> void:
	GameState.step_event_effects()
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


## 洞から出る。**用が済んだ洞を最深部まで歩かせない。**
##
## 封を取ったあとの洞は用が無いので、入口へ戻る手を用意する。
## まだ封が残っている洞では使わせない（それは近道になってしまう）。
func _escape_site() -> void:
	if not GameState.can_escape_site():
		hud.toast("まだ ここには 用が ある。")
		_set_mode(Mode.EXPLORE)
		return
	Sound.play("stairs")
	hud.toast("洞を あとにした。")
	_leave_site()


## ラン途中で保存して閉じる。
##
## **世界そのものは書かない。** 決定性があるので種から作り直せる。
## 書き出したらタイトルへ戻る（そのまま遊び続けられると、同じ中断から
## 二度始められてしまう）。
func _suspend_run() -> void:
	if not GameState.save_suspend():
		hud.toast("いまは ちゅうだんできない。")
		_set_mode(Mode.EXPLORE)
		return
	Sound.play("confirm")
	GameState.run_active = false
	_enter_title()


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
	var head := danger if place == "" else "%s　%s" % [place, danger]
	# 封の残りを常に見せる。何をすれば先へ進めるかが画面から読めること。
	var left := GameState.seals_remaining()
	return head if left <= 0 else "%s　封%d" % [head, left]


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
	Sound.play("boss_gate")
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
	Sound.play_bgm("boss" if is_boss else "battle")
	battle.start(system, members)
	_flash_into_battle()


func _on_battle_finished(victory: bool) -> void:
	if victory and _boss_battle:
		# 主を倒した。ランが「生還」で終わる唯一の経路。
		_boss_battle = false
		Sound.play("victory")
		Sound.play_bgm("chronicle")
		_finish_run(true)
		return
	if victory and _guardian_battle:
		# 封の番人を倒した。**ここで印を立てないと、階段を踏むたびに
		# 番人が出続けて封が永久に解けない**（実際そうなっていた）。
		# 城の主とは別扱いで、勝ってもランは終わらない。
		_guardian_battle = false
		_guardian_beaten = true
		_play_field_bgm()
		hud.toast("番人は しずまった。もう一度 おくへ。")
		_set_mode(Mode.EXPLORE)
		return
	if victory:
		_guardian_battle = false
		_play_field_bgm()
		_set_mode(Mode.EXPLORE)
		return
	_guardian_battle = false
	# 全滅。**「命の綱」があれば 1 度だけ肩代わりする。**
	# 恒久強化が能力値に触れないという前提を崩さずに、拠点の投資を
	# 「勝てるようになる」ではなく「もう一度立てる」へ効かせる軸。
	if GameState.spend_lifeline():
		_boss_battle = false
		Sound.play("learn")
		Sound.play_bgm("descent")
		hud.toast("命の綱が 切れた。まだ 立てる。")
		_refresh_hud()
		_set_mode(Mode.EXPLORE)
		return
	_boss_battle = false
	Sound.play("defeat")
	Sound.play_bgm("chronicle")
	_finish_run(false)


func _finish_run(victory: bool) -> void:
	result.show_summary(GameState.end_run(victory))
	_fade_to(Mode.RESULT)


## 洞の階段。いちばん深い階まで来たら、次は下ではなく外へ出る。
func _on_descend() -> void:
	Sound.play("stairs")
	if int(GameState.site.get("floor", 1)) >= GameState.cave_depth():
		# 洞の底。封があるなら、まず番人と戦う。
		var seal := GameState.seal_here()
		if not seal.is_empty() and not bool(seal.get("broken", false)) 				and not _guardian_beaten:
			var keeper := Encounter.build_guardian(
				_battle_rng, GameState.floor_number, GameState.biome_here()
			)
			if not keeper.is_empty():
				hud.toast("%s が 封を まもっている。" % String(seal.get("name", "封")))
				_guardian_battle = true
				_begin_battle(keeper, false)
				return
		if not seal.is_empty() and not bool(seal.get("broken", false)):
			GameState.break_seal()
			Sound.play("seal_break")
			var left := GameState.seals_remaining()
			if left > 0:
				hud.toast("%s が やぶれた。のこり %d。" % [String(seal.get("name", "封")), left])
			else:
				hud.toast("%s が やぶれた。城の とびらが ひらく。" % String(seal.get("name", "封")))
		else:
			hud.toast("洞を ぬけた。")
		_leave_site()
		return
	GameState.descend()
	_enter_floor()


## 店。町なら町の在庫（世界が覚える）、洞の中ならその階の在庫。
func _on_shop_entered() -> void:
	Sound.play("confirm")
	if _town != null:
		var key := "town:%d" % int(GameState.site.get("index", 0))
		if not GameState.world.visited.has(key):
			GameState.world.visited[key] = {}
		shop.open(GameState.world.visited[key], GameState.floor_number)
		_set_mode(Mode.SHOP)
		return
	if _map == null:
		return
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
