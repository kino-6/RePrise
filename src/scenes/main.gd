class_name Main
extends Node2D

const ChestReward := preload("res://src/dungeon/chest_reward.gd")
const TownInteractionScript := preload("res://src/world/town_interaction.gd")
const EventOperationScript := preload("res://src/quest/event_operation.gd")
const StoryOperationScript := preload("res://src/quest/story_operation.gd")

## 画面の切り替えとランの進行。
##
## タイトル →（初回だけプロローグ）→ 拠点 → 世界 → 戦闘 → 世界 ……
## → 城で主 → 戦記 → 拠点、という輪を回すだけ。
##
## 世界と洞の中は**同じ Mode.EXPLORE** で扱う。ExploreView は地図の中身に
## 依存していないので、`explore.setup()` に渡す地図を差し替えるだけで
## 縮尺が変わる。世界用にモードを増やすと、暗転・メニュー・HUD の分岐が
## 全部 2 本になる（そして片方だけ直したバグが出る）。
## ゲームの中身はそれぞれの View と BattleSystem 側にある。
##
## 輪が拠点に戻るのが要点。失ったレベルと残った熟練度を並べて見せる場が無いと、
## メタ進行が数字の裏側だけで進んでしまう。

enum Mode {
	TITLE, PROLOGUE, STRONGHOLD, EXPLORE, BATTLE, SHOP, MENU, SETTINGS,
	RESULT, EVENT, GEAR, MAP,
}

var title: TitleView
var prologue: PrologueView
var stronghold: StrongholdView
var shop: ShopView
var explore: ExploreView
var hud: ExploreHud
var battle: BattleView
var menu: FieldMenu
var world_chart: WorldChartView
var settings: SettingsView
var result: ResultScreen
var event_view: EventView
var gear_offer: GearOfferView
var effect: EventEffect

var _mode: Mode = Mode.EXPLORE

## いま歩いている洞の 1 階ぶん（世界の上にいるときは null）。
var _map: DungeonMap = null
## 戻った階の箱・店・乱数を巻き戻さないため、洞を出るまで各階を保持する。
var _dungeon_floors: Dictionary = {}

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
## 紙芝居にせず、主戦の開戦文へ物語の一手を載せるための短い行。
var _battle_opening_context: Array[String] = []

## トランジションは絵だけでなく、入力を止めて初めて成立する。
##
## 画面を差し替える中点で ExploreView が再び active になり、覆いが開いている最中に
## `Input.is_action_pressed()` を拾って歩けていた。イベント入力を飲むだけでは、
## Input をポーリングする移動は止まらないため、View 自体も最後まで止める。
const TRANSITION_RELEASE_MIN := 0.08
const TRANSITION_RELEASE_MAX := 0.35

var _transition_input_locked := false
var _transition_visual_done := false
var _transition_release_elapsed := 0.0

## 実プレイ検査で施設の導線が本当に踏まれたかを数える。
## 「扉へ向かった」だけで成功扱いしないため、実処理側で加算する。
var _dev_inn_visits := 0
var _dev_shop_opens := 0
var _dev_talks := 0
var _dev_facility_visits := 0
var _dev_facility_uses := 0
var _dev_town_chests := 0
var _dev_last_talk_line := ""
var _dev_talked_roles: Dictionary = {}

## 町会話はEventViewの軽い会話窓を借りる。世界イベントの返り先と混ぜない印。
var _town_talk_open := false

## イベント報酬の解決中は、装備入手signalをその場で開かず後続列へ積む。
## 町・洞・移動の完了時は Mode.EXPLORE なので、この印が無いと装備窓が
## 完了結果を上書きする。
var _event_resolution_active := false

## EventOperation の戦闘として始めた戦いか。通常遭遇の勝利と混ぜない。
var _event_task_battle_active := false


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

	prologue = PrologueView.new()
	prologue.visible = false
	add_child(prologue)

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

	world_chart = WorldChartView.new()
	world_chart.visible = false
	add_child(world_chart)

	settings = SettingsView.new()
	settings.visible = false
	add_child(settings)

	result = ResultScreen.new()
	result.visible = false
	add_child(result)

	# 場面の節目の演出。**絵が無ければ何も出さない**ので、呼び出し側は
	# 成否を気にしなくてよい（進行にも乱数にもセーブにも触らない）。
	effect = EventEffect.new()
	add_child(effect)
	battle.effect = effect

	# 拾った装備を着けるか聞く画面（C-9）。**入手の経路はすべてここへ集まる。**
	gear_offer = GearOfferView.new()
	gear_offer.visible = false
	add_child(gear_offer)
	gear_offer.chosen.connect(_on_gear_offer_chosen)
	GameState.gear_gained.connect(_on_gear_gained)

	event_view = EventView.new()
	event_view.visible = false
	add_child(event_view)
	# 同じ窓を 3 通りに使い回すので、返り先はここで振り分ける
	# （結果の窓 / 物語の拍 / イベントの選択）。
	event_view.chosen.connect(func(c: Dictionary) -> void:
		if _cross_world_open:
			_on_cross_world_choice(c)
		elif _town_talk_open:
			_close_town_talk()
		elif _elite_reward_open:
			_on_elite_reward_choice(c)
		elif _outcome_open:
			_close_outcome()
		elif _story_beat.is_empty():
			_on_event_choice(c)
		else:
			_on_story_choice(c))
	event_view.dismissed.connect(func() -> void:
		# **物語の拍と結果は見送れない**（飛ばせると話が飛ぶ／読めない）。
		if _cross_world_open:
			# またぐ物語も見送れない。既定の手で閉じる。
			_on_cross_world_choice({})
		elif _town_talk_open:
			_close_town_talk()
		elif _elite_reward_open:
			# 格上を倒した報酬は捨てられない。取消なら先頭の装備を選ぶ。
			_on_elite_reward_choice(_elite_reward_choices()[0])
		elif _outcome_open:
			_close_outcome()
		elif _story_beat.is_empty():
			_on_event_dismissed()
		else:
			_on_story_choice({}))

	# ローカル AI の窓口は 1 つだけ。戦記もクエスト文もここを通す。
	# **窓口を自分で作らない**（D-3）。作る場所は `LocalAI.create()` の 1 か所。
	# `--no-ai` なら null が返り、以降は「頼まない」だけになる。
	_ai = LocalAI.create(self)
	# 窓口は 1 つなので、返りは「いま何を頼んだか」で振り分ける。
	if _ai != null:
		_ai.answered.connect(func(text: String) -> void:
			if _awaiting_event_text:
				_awaiting_event_text = false
				_on_event_text(text)
				return
			_on_quest_text(text)
			# 封の名が済んだら、続けてイベントの表層を頼む（印は _ask_event_text が立てる）。
			_ask_event_text())

	title.started.connect(_on_title_started)
	title.resumed.connect(_resume_run)
	prologue.finished.connect(_on_prologue_finished)
	stronghold.departed.connect(_start_run)
	explore.encounter_triggered.connect(_on_encounter)
	explore.descended.connect(_on_descend)
	explore.ascended.connect(_on_ascend)
	explore.boss_reached.connect(_on_boss_reached)
	explore.shop_entered.connect(_on_shop_entered)
	explore.site_entered.connect(_on_site_entered)
	explore.event_reached.connect(_on_event_reached)
	explore.talked.connect(_on_talked)
	explore.town_facility_used.connect(_on_town_facility)
	explore.town_chest_opened.connect(_on_town_chest)
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
	menu.map_requested.connect(_open_world_chart)
	menu.settings_requested.connect(_open_settings)
	menu.suspend_requested.connect(_suspend_run)
	menu.escape_requested.connect(_escape_site)
	world_chart.closed.connect(_open_menu)
	title.settings_requested.connect(_open_settings)
	settings.closed.connect(_close_settings)
	settings.save_erase_requested.connect(_erase_save_data)
	settings.run_abandon_requested.connect(_abandon_run)
	result.dismissed.connect(_enter_stronghold)

	_make_curtain()
	# **引数を捌いたかどうかで分ける。** 撮影は await を含むので、
	# 呼んだ直後に制御が戻る。そこでタイトルを出すと、撮ろうとした画面を
	# 上書きしてしまう（`--shot=town` がタイトルを撮っていた）。
	if not dev.handle_debug_args(self):
		_enter_title()


func _input(_event: InputEvent) -> void:
	if _transition_input_locked:
		# 各 View は _unhandled_input() を使う。ここで処理済みにすれば、
		# 覆いの下のメニュー・戦闘・設定へ同じ決定キーが届かない。
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _transition_input_locked or not _transition_visual_done:
		return
	_transition_release_elapsed += delta
	if _transition_release_elapsed < TRANSITION_RELEASE_MIN:
		return
	# 遷移を起こしたキーが離れるまで待つ。ただし自動プレイが毎フレーム入力しても
	# 永久ロックにならないよう、最大時間では必ず開ける。
	if not _transition_action_pressed() or _transition_release_elapsed >= TRANSITION_RELEASE_MAX:
		_unlock_transition_input()


func _transition_action_pressed() -> bool:
	for action in Settings.ACTIONS:
		if Input.is_action_pressed(String(action)):
			return true
	return false


func _begin_transition_input() -> void:
	_transition_input_locked = true
	_transition_visual_done = false
	_transition_release_elapsed = 0.0
	explore.set_active(false)
	if _curtain != null:
		_curtain.mouse_filter = Control.MOUSE_FILTER_STOP


func _transition_visual_finished() -> void:
	if not _transition_input_locked:
		return
	# BattleView は start() してもここまでは止まっている。覆いの裏で敵が行動し、
	# 最初に見えるものが攻撃エフェクトになる回帰を、この境界で防ぐ。
	if _mode == Mode.BATTLE and battle != null:
		battle.reveal_opening()
	_transition_visual_done = true
	_transition_release_elapsed = 0.0


func _unlock_transition_input() -> void:
	_transition_input_locked = false
	_transition_visual_done = false
	_transition_release_elapsed = 0.0
	if _curtain != null:
		_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if explore != null:
		explore.set_active(_mode == Mode.EXPLORE)


## 開発用。決まった画面へ直行して撮る／自動で遊ぶ／保存を読む（S-1）。
## 中身は `src/dev/dev_probe.gd` にある。**本編と同じファイルに置かない**
## ―― `--shot=` を足す作業はどのタスクでも起きるので、ここが衝突源になる。
var dev: DevProbe = DevProbe.new()


## 自動プレイが「いまどの画面か」を知るための窓口。開発用。
func dev_mode_name() -> String:
	return Mode.keys()[_mode]


## 開発用。画面と階層をまとめた 1 行。自動プレイの記録に使う。
## 画面名だけだと「階を降りた」が記録に出てこない。
func dev_status() -> String:
	# **戦闘中は開始時の場所を出す**（P-5）。
	#
	# `end_run()` がラン状態を危険度 1 へ戻したあとも画面はまだ主戦のままなので、
	# 現在値を読むと `BATTLE 城 危険度10 → BATTLE 城 危険度1 → RESULT` と記録され、
	# **「主戦中に場所が巻き戻った」と誤読できる**。プレイ本体の不具合ではないが、
	# 証跡としては弱い。開始時に控えたものを、戦いが終わるまで出す。
	if _mode == Mode.BATTLE and _battle_place != "":
		return "%s %s 危険度%d" % [dev_mode_name(), _battle_place, _battle_danger]
	if (
		_mode == Mode.EXPLORE or _mode == Mode.SHOP
		or (_mode == Mode.EVENT and not GameState.site.is_empty())
	):
		var base := "%s %s 危険度%d" % [
			dev_mode_name(), _place_name(), GameState.floor_number]
		var objective := StoryOperationScript.objective(GameState.story_task)
		if objective == "":
			objective = EventOperationScript.objective(GameState.event_task)
		return base if objective == "" else "%s 目的:%s" % [base, objective]
	return dev_mode_name()


## 開発用。画面が同じでも内部処理が進んでいるかを自動プレイへ渡す。
func dev_progress_signature() -> String:
	if _mode == Mode.BATTLE and battle.has_method("dev_progress_signature"):
		return "BATTLE:%s" % battle.dev_progress_signature()
	return dev_status()


## いま居る場所の呼び名（監査用）。
func _place_name() -> String:
	match String(GameState.site.get("kind", "")):
		"town":
			return "町"
		"cave":
			return "洞%d階" % int(GameState.site.get("floor", 1))
		"castle":
			return "城"
	return "世界"


## 戦闘を始めたときの場所と危険度（監査用の控え）。
var _battle_place := ""
var _battle_danger := 0


## 開発用。さいきょう装備を掛け直す。**自動プレイと装備画面で同じ処理を通す。**
func dev_apply_best_gear() -> int:
	var changed := BestGear.apply(GameState, GameState.active_party())
	if changed > 0:
		_refresh_hud()
	return changed


## 開発用。パーティが身に着けている装備の数。自動プレイの集計に使う。
func dev_equipped_count() -> int:
	var total := 0
	for m in GameState.active_party():
		total += m.equipment.size()
	return total


## 開発用。直前の通常遭遇までに実際に歩いた歩数を一度だけ返す。
func dev_take_encounter_gap() -> int:
	return explore.dev_take_encounter_gap()


## 開発用。目的地への「次の一歩」は DevProbe が決める（S-1）。
## 自動プレイ（`src/dev/autoplay.gd`）はここを窓口にする。
func dev_step_to_exit() -> String:
	return dev.step_to_exit(self)


func dev_step_to_shop() -> String:
	return dev.step_to_shop(self)


func dev_step_to_inn() -> String:
	return dev.step_to_inn(self)


func dev_step_to_town_facility() -> String:
	return dev.step_to_town_facility(self)


func dev_reset_facility_metrics() -> void:
	_dev_inn_visits = 0
	_dev_shop_opens = 0
	_dev_talks = 0
	_dev_facility_visits = 0
	_dev_facility_uses = 0
	_dev_town_chests = 0
	_dev_last_talk_line = ""
	_dev_talked_roles = {}


func dev_inn_visits() -> int:
	return _dev_inn_visits


func dev_shop_opens() -> int:
	return _dev_shop_opens


func dev_talks() -> int:
	return _dev_talks


func dev_facility_uses() -> int:
	return _dev_facility_uses


func dev_facility_visits() -> int:
	return _dev_facility_visits


func dev_town_chests() -> int:
	return _dev_town_chests


## 開発用。欲が呼んだ格上の数と、洞で開けた宝箱の数（R-3 の実入力監査）。
## **開けた数と湧いた数が両方要る** ―― 1 つ目で湧いていないことも証跡になる。
func dev_greed_summons() -> int:
	return _dev_greed_summons


func dev_chests_taken() -> int:
	return _dev_chests_taken


var _dev_greed_summons := 0
var _dev_chests_taken := 0


func dev_step_to_town_chest() -> String:
	return dev.step_to_town_chest(self)


func dev_shop_category() -> String:
	return shop.current_category() if _mode == Mode.SHOP else ""


func dev_menu_at_root() -> bool:
	return _mode == Mode.MENU and menu.is_root()


func dev_step_to_talk() -> String:
	return dev.step_to_talk(self)
# --------------------------------------------------------------------------


func _enter_title() -> void:
	Sound.play_bgm("title")
	title.open()
	_set_mode(Mode.TITLE)


func _on_title_started() -> void:
	if GameState.should_show_prologue():
		_enter_prologue()
	else:
		_enter_stronghold()


func _enter_prologue() -> void:
	prologue.open()
	_fade_to(Mode.PROLOGUE)


func _on_prologue_finished() -> void:
	GameState.mark_prologue_seen()
	_enter_stronghold()


## 拠点へ戻る。ラン中に呼ばれることは無い（end_run のあとだけ）。
func _enter_stronghold() -> void:
	Sound.play_bgm("stronghold")
	# 進行中でなければここで 1 つ選ぶ（次のランから始まる）。
	GameState.pick_cross_world_arc()

	# 拠点に置かれた段階を出す。**最後の段階だけ選ばせる。**
	var beat := GameState.cross_world_beat("stronghold")
	if not beat.is_empty():
		if GameState.cross_world_is_last():
			_open_cross_world_choice(beat)
			return
		stronghold.notify_story(GameState.cross_world_line(beat))
		GameState.advance_cross_world()

	stronghold.open()
	_fade_to(Mode.STRONGHOLD)


## またぐ物語の段階を、その場に重ねる（A-4）。
##
## 置き場は 6 つ（拠点・戦記・町 2 種・洞・主戦の直前）。**出す口はここ 1 つ**に
## する ―― 場所ごとに「段階を探して出して進める」を書くと、片方だけ
## `advance` を忘れて段階が止まる（実際に拠点の実装だけがあった）。
##
## 三択の決着以外はすべてその場の通知として流す。文章一枚で入力を止める
## 「紙芝居」をイベントとして数えず、町到達・洞探索・主戦という実プレイを進める。
##
## 段階が無ければ何もせず false。呼ぶ側は「無ければ素通り」でよい。
func _show_cross_world_beat(placement: String) -> bool:
	var beat := GameState.cross_world_beat(placement)
	if beat.is_empty():
		return false
	var line := GameState.cross_world_line(beat)
	if GameState.cross_world_is_last():
		# 最後の段階は選ばせる。どこで出会っても三択は同じ窓で。
		_open_cross_world_choice(beat)
		return true
	GameState.advance_cross_world()
	if placement == "castle_pre_boss":
		_battle_opening_context.append(
			"%sの記録が 決戦へ つながる" % GameState.cross_world_title()
		)
		return false
	hud.toast(line)
	return false   # 流すだけなので、呼ぶ側の流れは止めない


## 町に入ったときの置き場。危険度で 2 段に分ける（設計文書の表と同じ）。
func _town_placement() -> String:
	return "town_low" if GameState.floor_number <= TOWN_LOW_MAX else "town_mid"


## 危険度一〜四が「浅い町」。
const TOWN_LOW_MAX := 4

## 段階を読み終えたら主戦を始める、の控え。
var _pending_boss_after_beat := false

## 歩ける状態になってから聞く装備（C-9）。
##
## 店の中やラン開始直後に手へ入ることがある。捨てると「拾ったのに聞かれない」
## 経路ができて、「入手の経路を 1 つに集約する」という C-9 の前提が崩れる。
var _pending_gear: Array[String] = []

## 世界上で予告した格上の型と、勝利後に選ぶ戦利品。
var _pending_elite_rule_id := ""
var _pending_elite_reward := false
var _elite_reward_open := false


## またぐ物語の最後の段階。三択を出して結末を決める。
##
## `EventView` を使い回す（世界内の拍と同じ作り）。**窓を増やさない。**
func _open_cross_world_choice(beat: Dictionary) -> void:
	var choices: Array = []
	for c in GameState.cross_world_choices():
		choices.append({
			"id": String(c.get("id", "")),
			"label": String(c.get("label", "")),
			"keeps": String(c.get("preserves", "")),
			"loses": String(c.get("sacrifices", "")),
			"pays": String(c.get("immediate_cost", "")),
		})
	if choices.is_empty():
		GameState.advance_cross_world()
		stronghold.open()
		_fade_to(Mode.STRONGHOLD)
		return
	_cross_world_open = true
	event_view.open({
		"story": true,
			"skin": {
				"title": GameState.cross_world_title(),
				# 横断ビートも人物の発話ではなく、出来事を要約する地の文。
				"actor": "",
				"cause": GameState.cross_world_line(beat),
				"flavor": "",
			},
		"choices": choices,
	}, GameState.floor_number)
	event_view.set_blocked([])
	Sound.play("confirm")
	_set_mode(Mode.EVENT)


var _cross_world_open := false


## またぐ物語の手を選んだ。結末を拠点で見せる。
func _on_cross_world_choice(choice: Dictionary) -> void:
	_cross_world_open = false
	var ending := GameState.advance_cross_world(String(choice.get("id", "")))
	stronghold.open()
	_fade_to(Mode.STRONGHOLD)
	if not ending.is_empty():
		stronghold.notify_story(String(ending.get("line", "")))


## クエスト文をローカル AI に頼むときの言い方。
##
## **構造は渡すが、決めさせない。** 封の数も帯も既に確定していて、
## AI が書くのは名と一文だけ。数を書かせないと明示するのは、
## 書いてきたものを `QuestText` が落とすより先に、そもそも書かせないため。
const QUEST_PROMPT := """あなたは現代の日本語RPGを担当するゲームライターです。
次の「封」に、名前と一文を付けてください。

%s

制約:
- 名前は10文字以内。地形や材質が想像できる具体的な名詞を使う。
- 一文は34文字以内。誰が、何を使い、どう守っているかを書く。
- 雰囲気だけの比喩、意味深な独り言、説明のない抽象語を使わない。
- 自然で簡潔な現代日本語にする。古風な語尾や不自然な空白を使わない。
- **数字を書かない。** 英字を書かない。記号・箇条書き・思考過程を書かない。
- 他社の作品に出てくる固有名詞を使わない。
- JSON だけを返す: {"seals":[{"name":"…","why":"…"},…3つ]}
"""


## 読み込んだ状態から画面を立ち上げる（中断の再開と同じ道）。
func _resume_loaded() -> void:
	_event_skinned = {}
	_awaiting_event_text = false
	# 中断データは世界種と現在階だけを持つ。別ランの階層キャッシュを混ぜない。
	_dungeon_floors.clear()
	_pending_greed_elite = ""
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
	_dungeon_floors.clear()
	_pending_greed_elite = ""
	dev.reset_run_gates()
	Sound.play("depart")
	_ask_quest_text()
	# 開発用の状態指定（--dev-level=8 など）。指定が無ければ何もしない。
	var applied := DevCheats.apply_to_run(GameState)
	if not applied.is_empty():
		print("開発指定: %s" % "　".join(applied))
	# 世界の門。**ランの始まりはここだけ**なので、節目として演出を置く。
	effect.play("world_gate")
	# 「封の言い伝え」を買っているぶん、出撃前から在り処が分かっている。
	if dev.save_name != "":
		if GameState.dev_save(dev.save_name):
			print("開発用の保存: %s" % dev.save_name)
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
func _enter_floor(arrive_from_below: bool = false) -> void:
	# 洞に主の間は置かない。**主が居るのは世界の終点（城）だけ。**
	# 寄り道の底にも主を置くと、寄り道が本筋と同じ重さになって
	# 「寄るか急ぐか」の判断が消える。洞の見返りは宝箱と出店。
	# 洞の中の絵はその土地の生物相から来る（雪原の洞は雪原の絵）。
	_guardian_battle = false
	_show_cross_world_beat("cave_mid")
	var cave_floor := int(GameState.site.get("floor", 1))
	if _dungeon_floors.has(cave_floor):
		var saved_floor: Dictionary = _dungeon_floors[cave_floor]
		_map = saved_floor["map"]
		_encounter_rng = saved_floor["encounter_rng"]
		_battle_rng = saved_floor["battle_rng"]
	else:
		_encounter_rng = GameState.rng_for("encounter")
		_battle_rng = GameState.rng_for("battle")
		_map = DungeonGenerator.generate(GameState.rng_for("terrain"), GameState.floor_number, false)
		_map.biome = String(GameState.site.get("tileset", "dungeon"))
		_dungeon_floors[cave_floor] = {
			"map": _map,
			"encounter_rng": _encounter_rng,
			"battle_rng": _battle_rng,
		}
	_door_warned = false
	var arrival := _map.down_arrival_pos if arrive_from_below else Vector2i(-1, -1)
	explore.setup(_map, _encounter_rng, _leader_job(), arrival)
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
## 拠点地へ入る直前の世界座標。町・洞から出たらここへ戻す。
## 内部の町は南入口へ正規化したまま、ワールド上の接近方向だけを保つ。
var _site_return_pos := Vector2i(-1, -1)


func _on_site_entered(
	pos: Vector2i, from: Vector2i = Vector2i(-1, -1)
) -> void:
	if from.x >= 0 and from != pos:
		_site_return_pos = from
	GameState.world_pos = pos
	# 引き受けた物語の工程へ戻る。説明や選択肢へは巻き戻さない。
	if StoryOperationScript.is_at(GameState.story_task, pos):
		GameState.world_pos = pos
		_enter_story_task_site()
		return

	# **物語がいちばん先。** 拍 → 実操作 → 町や洞の中身、の順に出す。
	var beat := GameState.story_beat_at(pos)
	if not beat.is_empty():
		GameState.stand_on_world(pos)
		_open_story(beat)
		return

	# 一度引き受けたイベントは選択肢へ戻さない。町／洞へ入り直すか、
	# 戦闘から退いたなら同じ敵へ再挑戦する。
	if EventOperationScript.is_at(GameState.event_task, pos):
		GameState.world_pos = pos
		if String(GameState.event_task.get("kind", "")) == EventOperationScript.FIGHT:
			_pending_fight_grade = int(GameState.event_task.get("fight_grade", 1))
			_continue_pending_flow()
		else:
			_enter_event_task_site()
		return

	# 拠点地にイベントが重なっていれば、中へ入る前にそれを出す。
	# 済んだら踏み直しで町や洞へ入れる。
	if GameState.world != null and not GameState.world.event_at(pos).is_empty() \
			and not GameState.event_done.has(pos) and GameState.event_task.is_empty() \
			and GameState.story_task.is_empty():
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
			_dungeon_floors.clear()
			var seal := GameState.seal_here()
			if not seal.is_empty() and not bool(seal.get("broken", false)):
				hud.toast("%s の けはい。%s" % [
					String(seal.get("name", "封")), String(seal.get("why", ""))
				])
			_enter_floor()
		"castle":
			# 終点。**封が残っていると扉は開かない。**
			# ここで通してしまうと、洞へ寄る理由が宝箱だけに戻る。
			var left := GameState.seals_remaining()
			if left > 0:
				Sound.play("cancel")
				hud.toast("とびらは 固く 閉ざされている。封が あと %d つ。" % left)
				# **1 マス外へ出す。** 城のマスに立ったままだと、一歩動くたびに
				# また扉を叩いて足踏みになる（町で直したのと同じ穴で、
				# 自動プレイが城の前から動けなくなっていた）。
				GameState.world_pos = (
					_site_return_pos
					if _site_return_pos.x >= 0
					else GameState.step_outside_site(pos)
				)
				_site_return_pos = Vector2i(-1, -1)
				GameState.site = {}
				_enter_world()
				explore.suppress_site_once(pos)
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
	if GameState.world == null or _ai == null or _ai.is_busy():
		return
	var facts := JSON.stringify(QuestText.facts_for_llm(GameState.world), "  ")
	_ai.ask(QUEST_PROMPT % facts, 8.0, "quest")


## イベントの表層を AI に頼む。**構造は渡さない**（id・選択肢・数値は含めない）。
## `WorldEventCatalog.facts_for_ai()` が既にそこまで削ってある。
const EVENT_PROMPT := """あなたは現代の日本語RPGを担当するゲームライターです。
次の出来事に、題・関係者・原因・情景を付けてください。

%s

制約:
- それぞれ指定の文字数以内。自然で簡潔な現代日本語にする。
- actorは職業や立場が分かる人物名詞にする。
- causeは原因となった主体と行動を一文で具体的に書く。
- flavorは現場で見える物、聞こえる音、匂いのどれかを具体的に書く。
- 雰囲気だけの比喩、意味深な独り言、説明のない抽象語を使わない。
- 古風な語尾、不自然な空白、三点リーダーを使わない。
- **数字を書かない。** 英字を書かない。記号・箇条書き・思考過程を書かない。
- 他社の作品に出てくる固有名詞を使わない。
- JSON だけを返す: {"title":"…","actor":"…","cause":"…","flavor":"…"}
"""


func _ask_event_text() -> void:
	if GameState.world == null or _ai == null or _ai.is_busy():
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
	if reply.is_empty():
		# この1件は既定文のままにし、残りのイベント候補は続けて頼む。
		_ask_event_text()
		return
	if not GameState.world.events.has(_event_skin_pos):
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
	_dev_last_talk_line = ""
	_dev_talked_roles = {}
	var town_index := int(GameState.site.get("index", 0))
	_town = TownGenerator.generate(
		GameState.rng_for("town"), GameState.floor_number,
		String(GameState.site.get("tileset", "dungeon")),
		town_index,
		posmod(GameState.run_seed, TownProfile.cycle_size())
	)
	if GameState.town_actions_done.has(
		TownInteractionScript.supply_chest_key(town_index, _town)
	):
		_town.clear_supply_chest()
	_map = null
	_encounter_rng = GameState.rng_for("encounter")
	explore.setup(_town, _encounter_rng, _leader_job())
	Sound.play_bgm("town")
	_show_cross_world_beat(_town_placement())
	# 町名は左上へ常設している。入場位置へ同じ名を重ねると、
	# 24x32の主人公を覆い、人物アートが見える前に隠してしまう。
	_fade_to(Mode.EXPLORE)


## 町の人との会話。地元の一言と、いまのランに基づく実用情報を2行へ分ける。
## toastで流さず、決定するまで残る会話窓で読ませる。
func _on_talked(person: Dictionary) -> void:
	_dev_talks += 1
	if String(GameState.event_task.get("kind", "")) == EventOperationScript.TOWN_CONTACT:
		_complete_event_task()
		return
	var town_index := int(GameState.site.get("index", 0))
	var talk_data: Dictionary = TownInteractionScript.talk(
		GameState, _town, town_index, person
	)
	var lines: Array[String] = []
	for raw_line in talk_data.get("lines", []):
		var line := String(raw_line).strip_edges()
		if line != "":
			lines.append(line)
	var role := String(talk_data.get("role", ""))
	if role != "":
		_dev_talked_roles[role] = true
	_dev_last_talk_line = " ".join(lines)
	Sound.play("confirm")
	_open_town_talk(String(talk_data.get("speaker", Terms.TOWN_PERSON)), lines)


## 中央の仕事場。町の生業ごとに別の準備が一度だけできる。
func _on_town_facility() -> void:
	if _town == null:
		return
	_dev_facility_visits += 1
	var town_index := int(GameState.site.get("index", 0))
	var result_data: Dictionary = TownInteractionScript.use_facility(
		GameState, _town, town_index,
		GameState.rng_for("town_facility:%d" % town_index)
	)
	if bool(result_data.get("changed", false)):
		_dev_facility_uses += 1
		Sound.play("learn")
	else:
		Sound.play("confirm")
	# 仕事場そのものが利用済みでも、調査という実入力と物語固有の地図効果は成立する。
	# 「先に町へ寄ったせいで物語が詰む」経路を作らない。
	if String(GameState.story_task.get("kind", "")) == StoryOperationScript.TOWN_ACTION:
		_complete_story_task()
	explore.queue_redraw()
	var lines: Array[String] = []
	for raw_line in result_data.get("lines", []):
		lines.append(String(raw_line))
	_open_town_talk(String(result_data.get("speaker", Terms.TOWN_WORKPLACE)), lines)


## 町に一つだけある旅人用の物資箱。案内札は反応せず、宝箱の絵だけが開く。
func _on_town_chest() -> void:
	if _town == null:
		return
	var town_index := int(GameState.site.get("index", 0))
	var result_data: Dictionary = TownInteractionScript.open_supply_chest(
		GameState, _town, town_index,
		GameState.rng_for("town_supply_chest:%d" % town_index)
	)
	if bool(result_data.get("changed", false)):
		_dev_town_chests += 1
		Sound.play("chest")
	else:
		Sound.play("confirm")
	var lines: Array[String] = []
	for raw_line in result_data.get("lines", []):
		lines.append(String(raw_line))
	_open_town_talk(String(result_data.get("speaker", Terms.TOWN_SUPPLY_CHEST)), lines)


func _open_town_talk(speaker: String, lines: Array[String]) -> void:
	_town_talk_open = true
	# 会話へ切り替えた同じフレームでも、下段に現在の仲間を残す。
	# 町入場の暗転完了を待つ実プレイでは更新済みだが、素早い入力や撮影では
	# 空のHUDが一瞬出ていた。会話窓を開く側で状態を確定させる。
	_refresh_hud()
	event_view.open_talk(speaker, lines, GameState.floor_number)
	_set_mode(Mode.EVENT)


func _close_town_talk() -> void:
	_town_talk_open = false
	_set_mode(Mode.EXPLORE)


## 宿。**全回復と毒の治療はここだけ**。出店は購入と補給に専念させる。
##
## ゴールドは取らない。危険な街道を町まで戻った手間が代金であり、宿へ戻るか、
## 手持ちの道具で先へ進むかがラン中の判断になる。イベントで得た世話・物資・
## 「よく休んだ」効果もここでだけ清算する。
func _on_inn() -> void:
	_dev_inn_visits += 1
	var service := EventEffects.consume_inn(GameState, GameState.rng_for("event_inn"))
	if bool(service.get("blocked", false)):
		Sound.play("cancel")
		hud.toast(" ".join(service.get("lines", [])))
		return
	for m in GameState.active_party():
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		m.cure_poison()
	Sound.play("learn")
	_refresh_hud()
	var lines: Array = ["ゆっくり やすんだ。みな 元気に なった。"]
	lines.append_array(service.get("lines", []))
	hud.toast(" ".join(lines))


## 町を出て世界へ戻る。
func _on_town_left() -> void:
	Sound.play("stairs")
	_town = null
	_leave_site()


## 拠点地から世界へ戻る。**必ず 1 マス外へ出す**（出た直後に再突入しないため）。
func _leave_site() -> void:
	var site_pos := GameState.world_pos
	GameState.world_pos = (
		_site_return_pos
		if _site_return_pos.x >= 0
		else GameState.step_outside_site(site_pos)
	)
	_site_return_pos = Vector2i(-1, -1)
	GameState.site = {}
	_dungeon_floors.clear()
	_enter_world()
	explore.suppress_site_once(site_pos)


## 画面の切り替えに挟む暗転の長さ（片道）。
## SFC 期は必ず暗転を挟んでいて、これが無いと画面が「差し替わった」ように見える。
const FADE_TIME := 0.14


## 暗転の幕。最前面に置いた黒い板で、透明度だけを動かす。
var _curtain: ColorRect = null

## 進行中の暗転。**最後に頼まれた画面が必ず勝つ**ようにするために持つ。
## 飛んでいる暗転を放っておくと、そのコールバックがあとから来た切り替えを
## 上書きする（戦記を出したのに探索画面が出た、という不具合が実際に起きた）。
var _fade_tween: Tween = null

## 遭遇のモザイク。幕とは別に持つ（幕は黒板、こちらは画面そのものを崩す）。
var _transition: ScreenTransition = null


func _make_curtain() -> void:
	_transition = ScreenTransition.new()
	add_child(_transition)
	_transition.finished.connect(_transition_visual_finished)
	_curtain = ColorRect.new()
	_curtain.color = Color(0, 0, 0, 0)
	_curtain.size = Vector2(PixelUI.SCREEN)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.z_index = 100
	add_child(_curtain)


## 暗転を挟んで画面を切り替える。
## 撮影（--shot）や自動プレイでも同じ経路を通るので、待ち時間は短く保つ。
## どの切り替えでどの覆いを使うか（B-3）。
##
## **4 枚を「場面ごとに意味のある形」で割り当てる。** 絵の中身は
## `docs/asset_generation_npc_effects.md` にある。
##
##   銀青のアイリスが閉じる → 拠点と世界の行き来（門をくぐる）
##   年代記の頁がめくれる   → 戦記・結果（記録に移る）
##   黒鉄の歯車が閉じる     → 城と主戦（帝国の側へ入る）
##   角形の画素が増殖する   → 町や洞の出入り（場所が変わるだけ）
##
## 無い画面は素の暗転のまま。**全部に演出を付けない**（毎回同じ長さの間が
## 挟まると、切り替えそのものが重く感じる）。
const COVERS := {
	Mode.STRONGHOLD: "iris_gate",
	Mode.RESULT: "page_turn",
}

## 洞・町・世界の出入りは**遭遇と同じモザイク**にする。
##
## 最初は角形の画素が増殖する覆い（`pixel_dissolve`）を当てたが、覆いが甘く、
## 中途半端な演出は無いほうがましだった。モザイクは画面の中身を残したまま
## 崩れるので、**入る前と後が繋がる** ―― 場所を移る演出としてもこちらが強い。
const MOSAIC_MODES: Array[Mode] = [Mode.EXPLORE]


func _fade_to(mode: Mode) -> void:
	# 幕が下りるのを待たずに歩みを止める。
	#
	# 暗転を入れるまでは「切り替え＝即座」だったので気づかなかったが、
	# 幕の裏で切り替える形にすると、その 0.3 秒のあいだ入力が生きたままになる。
	# 実際に「遭遇したのに歩けて、そのまま階段へ降りられる」状態だった。
	if _curtain == null:
		_set_mode(mode)
		return
	_cancel_fade()
	_begin_transition_input()
	# 城へ入るときだけは歯車。**行き先ではなく行為で選ぶ**ので、
	# Mode の表とは別に見る（城も町も同じ Mode.EXPLORE）。
	var kind := String(COVERS.get(mode, ""))
	if mode == Mode.EXPLORE and String(GameState.site.get("kind", "")) == "castle":
		kind = "gear_shutter"
	if kind != "" and _transition != null and _transition.play_cover(
		kind, _apply_mode.bind(mode)
	):
		return
	if mode in MOSAIC_MODES and _transition != null and _transition.available():
		_transition.play(_apply_mode.bind(mode))
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
	# 幕の裏で切り替えるのは _apply_mode。_set_mode を呼ぶと自分の暗転を
	# 自分で殺してしまい、幕が上がらなくなる。
	_fade_tween.tween_callback(_apply_mode.bind(mode))
	_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
	_fade_tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(_transition_visual_finished)


## 遭遇の演出。画面をモザイクに崩して戦闘へ移る。
##
## **以前は白く 2 回瞬かせていた。やめた。** 調査の結論は
## `docs/screen_transition_design.md` にあるが、短く言うとこうなる ――
## SFC の明度レジスタは暗くする方向にしか無く、白飛びはハードの機能ではない。
## 逆に FC は全画面演出がパレット差し替えしか無く、必然的に閃光へ寄る。
## **白い閃光が「FC っぽい」のは趣味ではなく出自の問題**だった。
##
## モザイクは画面の中身を残したまま覆うので、歩いていた地形が粗く溶けて
## 戦闘へ繋がる。暗転や閃光が前後を**切る**のに対し、モザイクは**繋ぐ**。
func _flash_into_battle() -> void:
	# 遭遇の瞬間に歩みを止める（理由は _fade_to と同じ）。
	_cancel_fade()
	_begin_transition_input()
	if _transition != null and _transition.available():
		_transition.play(_apply_mode.bind(Mode.BATTLE))
		return
	# シェーダが使えない環境では素の暗転へ落ちる。**切り替えは必ず起きる。**
	if _curtain == null:
		_set_mode(Mode.BATTLE)
		battle.reveal_opening()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
	_fade_tween.tween_callback(_apply_mode.bind(Mode.BATTLE))
	_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
	_fade_tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(_transition_visual_finished)


## 装備が手に入った（C-9）。**宝箱・イベント・店のどれもここへ来る。**
##
## 探索中でなければ聞かない ―― 店の中や戦闘の直後に窓が割り込むと、
## いま何をしていたか分からなくなる。手持ちには入っているので失われない。
func _on_gear_gained(id: String) -> void:
	if _mode != Mode.EXPLORE or _event_resolution_active \
			or not GameState.event_task.is_empty():
		# **取りこぼさない。** 歩ける状態へ戻ったときに聞く。
		_pending_gear.append(id)
		return
	if GameState.active_party().is_empty():
		return
	gear_offer.open(id, GameState.active_party())
	_set_mode(Mode.GEAR)


func _on_gear_offer_chosen(member_index: int) -> void:
	if member_index >= 0:
		var members := GameState.active_party()
		if member_index < members.size():
			var member: PartyMember = members[member_index]
			# **断っても拾ったものは失わない**ので、着けるときだけ手持ちから抜く。
			if GameState.equip_gear(member, gear_offer.gear_id):
				hud.toast("%sは%sを装備した" % [
					member.name,
					Database.gear(gear_offer.gear_id).get("name", gear_offer.gear_id),
				])
	gear_offer.close()
	_refresh_hud()
	_continue_pending_flow()


## 結果のあとに残る処理を、装備確認→戦闘→探索の順で1つずつ進める。
##
## 装備入手 signal はイベント窓の最中に鳴る。以前は一度 EXPLORE に戻したため、
## 装備窓を開く deferred call と戦闘開始が競争し、遅い装備窓が戦闘を隠した。
func _continue_pending_flow() -> void:
	if not _pending_gear.is_empty() and not GameState.active_party().is_empty():
		var next_gear: String = _pending_gear.pop_front()
		gear_offer.open(next_gear, GameState.active_party())
		_set_mode(Mode.GEAR)
		return
	if _pending_boss_after_beat:
		_pending_boss_after_beat = false
		_on_boss_reached()
		return
	if _pending_fight_grade > 0:
		var grade := _pending_fight_grade
		_pending_fight_grade = 0
		_on_event_encounter(grade)
		return
	# 欲が呼んだ格上（R-3）。**取った物を確かめてから来る。**
	if _pending_greed_elite != "":
		var kind_id := _pending_greed_elite
		_pending_greed_elite = ""
		_begin_greed_battle(kind_id)
		return
	# 町／洞のイベントは選択窓で終わらせず、実際の地図へ入ってから
	# 人物との接触または探索で完了させる。
	if not GameState.event_task.is_empty() and GameState.site.is_empty():
		var task_kind := String(GameState.event_task.get("kind", ""))
		if task_kind in [
			EventOperationScript.TOWN_CONTACT, EventOperationScript.CAVE_SEARCH
		]:
			_enter_event_task_site()
			return
	_set_mode(Mode.EXPLORE)
	_show_event_task_objective()


func _enter_event_task_site() -> void:
	var task: Dictionary = GameState.event_task
	var at := EventOperationScript.position(task)
	var entered := GameState.enter_site(at)
	match String(entered.get("kind", "")):
		"town":
			_open_town()
		"cave":
			_guardian_beaten = false
			_dungeon_floors.clear()
			_enter_floor()
			if dev.event_cave_gate and _map != null:
				# 状態を直接完了させず、階段へ入る最後の一歩はAutoPlayの実キーで踏む。
				explore.setup(
					_map, _encounter_rng, _leader_job(), _map.down_arrival_pos
				)
				dev.event_cave_gate = false
		_:
			# 地図生成の不整合でも詰ませない。現場へ戻して行動を続けられる。
			GameState.site = {}
			_set_mode(Mode.EXPLORE)
	_show_event_task_objective.call_deferred()


## 飛んでいる暗転を捨てて幕を上げる。
func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if _transition != null:
		# 演出も一緒に止める。**あとから来た切り替えが必ず勝つ**ようにするため。
		_transition.cancel()
	if _curtain != null:
		_curtain.color = Color(0, 0, 0, 0)
	_unlock_transition_input()


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
	prologue.visible = mode == Mode.PROLOGUE
	stronghold.visible = mode == Mode.STRONGHOLD
	shop.visible = mode == Mode.SHOP
	menu.visible = mode == Mode.MENU
	world_chart.visible = mode == Mode.MAP
	settings.visible = mode == Mode.SETTINGS
	# メニュー中も探索の絵は出したままにする（メニューを半透明にしてあるので、
	# 下にダンジョンが見える）。HUD は二重になるので隠す。
	explore.visible = mode == Mode.EXPLORE or mode == Mode.MENU
	hud.visible = mode == Mode.EXPLORE or (
		mode == Mode.EVENT and event_view.is_talk()
	)
	battle.visible = mode == Mode.BATTLE
	result.visible = mode == Mode.RESULT
	# イベントは場面の上に開く窓。下の絵は残す。
	event_view.visible = mode == Mode.EVENT
	if mode == Mode.EVENT:
		explore.visible = true
	# 装備を聞く窓も場面の上に開く。**開いているあいだは歩けない**ので、
	# 選んでいる最中に遭遇や階段が割り込まない。
	gear_offer.visible = mode == Mode.GEAR
	if mode == Mode.GEAR:
		explore.visible = true
	else:
		gear_offer.close()
	# 遷移の中点で探索画面へ切り替わっても、覆いが完全に開くまでは動かさない。
	# 戦いを離れたら監査用の控えを外す（P-5）。**戦闘中だけの値**。
	if mode != Mode.BATTLE:
		_battle_place = ""
	explore.set_active(
		mode == Mode.EXPLORE
		and not _transition_input_locked
		and _pending_gear.is_empty()
	)
	# 保留していた装備をここで聞く（C-9）。歩ける状態になったので。
	if mode == Mode.EXPLORE and not _pending_gear.is_empty():
		_continue_pending_flow.call_deferred()
	if mode != Mode.TITLE:
		title.close()
	if mode != Mode.PROLOGUE:
		prologue.close()
	if mode != Mode.STRONGHOLD:
		stronghold.close()
	if mode != Mode.SHOP:
		shop.close()
	if mode != Mode.MENU:
		menu.close()
	if mode != Mode.MAP:
		world_chart.close()
	if mode != Mode.SETTINGS:
		settings.close()
	if mode != Mode.EVENT:
		event_view.close()
	if mode == Mode.EXPLORE:
		_refresh_hud()


## 物語の拍を始める。三択だけは選択窓、それ以外は地図上の実操作へ直結する。
func _open_story(beat: Dictionary) -> void:
	if String(beat.get("phase", "")) != "choice":
		_begin_story_operation(beat, {})
		return
	_story_beat = beat
	if not event_view.open_story(beat, GameState.world.story, GameState.floor_number):
		_story_beat = {}
		return
	event_view.set_blocked([])
	Sound.play_bgm("story")
	Sound.play("story_open")
	_set_mode(Mode.EVENT)


var _story_beat: Dictionary = {}


## 物語の手を選んだ。ここでは報酬も進行も確定せず、現地の工程へ渡す。
func _on_story_choice(choice: Dictionary) -> void:
	var id := String(choice.get("id", ""))
	if id == "":
		push_error("物語の選択肢に id が無い")
		return
	# 選んだ手は世界が覚える。終幕でこれを回収する。
	GameState.world.story_choice = id
	Sound.play("story_choice")
	var beat := _story_beat
	_story_beat = {}
	_begin_story_operation(beat, choice)


## 一拍を実行中の目的へ変え、その場所の地図へ入る。
func _begin_story_operation(beat: Dictionary, choice: Dictionary) -> void:
	var task := StoryOperationScript.build(
		GameState.world.story, beat, choice, GameState.world_pos
	)
	if not StoryOperationScript.valid(task):
		push_error("物語の実行工程が不正: %s" % String(beat.get("id", "")))
		return
	GameState.story_task = task
	_story_beat = {}
	_play_field_bgm()
	_set_mode(Mode.EXPLORE)
	_enter_story_task_site()


## 実行中の物語目的が結びついた町・洞・城へ入る。
func _enter_story_task_site() -> void:
	var task: Dictionary = GameState.story_task
	if not StoryOperationScript.valid(task):
		return
	var at := StoryOperationScript.position(task)
	var entered := GameState.enter_site(at)
	match String(task.get("kind", "")):
		StoryOperationScript.TOWN_ACTION:
			if String(entered.get("kind", "")) == "town":
				_open_town()
		StoryOperationScript.CAVE_SEARCH:
			if String(entered.get("kind", "")) == "cave":
				_guardian_beaten = false
				_dungeon_floors.clear()
				_enter_floor()
		StoryOperationScript.BOSS:
			# 物語の決戦も通常の城門条件を迂回しない。
			var left := GameState.seals_remaining()
			if left > 0:
				Sound.play("cancel")
				hud.toast("とびらは 固く 閉ざされている。封が あと %d つ。" % left)
				GameState.world_pos = (
					_site_return_pos
					if _site_return_pos.x >= 0
					else GameState.step_outside_site(at)
				)
				_site_return_pos = Vector2i(-1, -1)
				GameState.site = {}
				_enter_world()
				explore.suppress_site_once(at)
				return
			hud.toast("城の門が ひらいた。ここから先は 戻れない。")
			_battle_opening_context.append(String(task.get("cue", "")))
			_on_boss_reached()
		_:
			push_error("画面で実行できない物語工程: %s" % task.get("kind", ""))
	_show_story_task_objective.call_deferred()


## 町／洞でプレイヤーが実際に目的を果たしたときだけ、一拍を進める。
func _complete_story_task(first_line: String = "") -> void:
	if not StoryOperationScript.valid(GameState.story_task):
		return
	var task: Dictionary = GameState.story_task.duplicate(true)
	var lines: Array[String] = EventEffects.grant(
		GameState, task.get("runtime_effects", []), GameState.floor_number, _battle_rng
	)
	GameState.story_task = {}
	GameState.advance_story()
	var result := String(task.get("result", "")).strip_edges()
	if result != "":
		lines.push_front(result)
	if first_line != "":
		lines.push_front(first_line)
	if not lines.is_empty():
		hud.toast("\n".join(lines))
	_refresh_hud()


func _show_story_task_objective() -> void:
	var objective := StoryOperationScript.objective(GameState.story_task)
	if objective != "":
		hud.toast(objective)
	_refresh_hud()


## 街道のイベントを踏んだ。
func _on_event_reached(pos: Vector2i) -> void:
	GameState.world_pos = pos
	GameState.stand_on_world(pos)
	if not GameState.story_task.is_empty():
		_set_mode(Mode.EXPLORE)
		_show_story_task_objective()
		return
	# 引き受け済みなら、同じ場所で再び選択肢を出さない。
	if EventOperationScript.is_at(GameState.event_task, pos):
		if String(GameState.event_task.get("kind", "")) == EventOperationScript.FIGHT:
			_pending_fight_grade = int(GameState.event_task.get("fight_grade", 1))
			_continue_pending_flow()
		else:
			_set_mode(Mode.EXPLORE)
			_show_event_task_objective()
		return
	if not GameState.event_task.is_empty():
		# 同時に二件を引き受けて後の選択で上書きしない。先の目的を終えれば、
		# この出来事は未完のまま残り、踏み直して選べる。
		_set_mode(Mode.EXPLORE)
		_show_event_task_objective()
		return
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
	if not GameState.story_task.is_empty():
		_show_story_task_objective()
		return
	if not GameState.event_task.is_empty():
		_show_event_task_objective()
		return
	var found := _event_at(at)
	if found.is_empty():
		return
	_event_pos = at
	event_view.open(found, GameState.floor_number)
	event_view.set_blocked(_blocked_for(found))
	Sound.play("event")
	_set_mode(Mode.EVENT)


## いま選んでいる手が払えるか。EventView は GameState を知らないので、ここで調べる。
func _blocked_for(found: Dictionary) -> Dictionary:
	var choices: Array = found.get("choices", [])
	var blocked := {}
	for i in choices.size():
		var reasons := EventEffects.unpayable(
			GameState, choices[i].get("costs", []), GameState.floor_number
		)
		if not reasons.is_empty():
			blocked[i] = reasons
	return blocked


var _event_pos := Vector2i(-1, -1)


## 手を選んだ。代償を払い、**実行する目的**を引き受ける。
##
## 報酬はここでは渡さない。街道を進む／町で話す／洞を調べる／戦いに勝つ、の
## どれかを実入力で終えたときだけ `_complete_event_task()` が渡す。
func _on_event_choice(choice: Dictionary) -> void:
	var instance := _event_at(_event_pos)
	var cost_fight_grade := EventEffects.fight_grade(choice.get("costs", []))
	var visible_elite_challenge := (
		bool(instance.get("visible_elite", false)) and cost_fight_grade >= 2
	)
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

	var fight_grade := maxi(cost_fight_grade, EventEffects.fight_grade(fired))
	if visible_elite_challenge:
		# 戦利品は勝利後に三択で渡す。戦うと決めた時点では増やさない。
		_pending_elite_rule_id = String(instance.get("elite_rule_id", ""))
		_pending_elite_reward = true
	elif bool(choice.get("defer", false)):
		# 明示的な見送りだけは目的を作らず、再訪できる。
		lines.append(Terms.EVENT_DEFER_OUTCOME)
	else:
		GameState.event_task = EventOperationScript.build(
			instance, choice, fired, _event_pos, danger
		)
		lines.append(Terms.EVENT_TASK_STARTED %
			EventOperationScript.objective(GameState.event_task))

	# 戦いを含む手は開始説明を読んだあとに戦闘へ入る。
	if fight_grade > 0:
		lines.append("身がまえる 間もなく、敵が 来た。")
		_pending_fight_grade = fight_grade
	if lines.is_empty():
		# この行へ来た選択肢は品質 Gate の漏れ。無言で成功に見せない。
		lines.append(Terms.EVENT_UNRESOLVED)
	_refresh_hud()
	# これは結果ではなく開始確認。実行工程を終えるまでイベントは済みにしない。
	_story_beat = {}
	event_view.open_outcome(String(choice.get("label", "")), lines, danger)
	_outcome_open = true
	_set_mode(Mode.EVENT)


## 危険が実際に起きる確率。**並べておいて起きないなら飾りになる。**
const RISK_ODDS := 45

var _pending_fight_grade := 0
var _outcome_open := false


func _elite_reward_choices() -> Array:
	return [
		{
			"id": "gear", "label": Terms.ELITE_REWARD_GEAR,
			"costs": ["none"], "risks": [], "rewards": ["equipment"],
		},
		{
			"id": "supply", "label": Terms.ELITE_REWARD_SUPPLY,
			"costs": ["none"], "risks": [], "rewards": ["item", "heal"],
		},
		{
			"id": "route", "label": Terms.ELITE_REWARD_ROUTE,
			"costs": ["none"], "risks": [], "rewards": ["map_reveal", "route_safe"],
		},
	]


func _open_elite_reward() -> void:
	_elite_reward_open = true
	event_view.open({
		"elite_reward": true,
		"skin": {
			"title": Terms.ELITE_REWARD_TITLE, "actor": "",
			"cause": Terms.ELITE_REWARD_CAUSE, "flavor": "",
		},
		"choices": _elite_reward_choices(),
	}, GameState.floor_number)
	event_view.set_blocked([])
	_set_mode(Mode.EVENT)


func _on_elite_reward_choice(choice: Dictionary) -> void:
	_elite_reward_open = false
	var picked: Dictionary = choice if not choice.is_empty() else _elite_reward_choices()[0]
	var lines: Array[String] = EventEffects.grant(
		GameState, picked.get("rewards", []), GameState.floor_number, _battle_rng
	)
	if lines.is_empty():
		lines.append(Terms.EVENT_UNRESOLVED)
	_refresh_hud()
	_story_beat = {}
	event_view.open_outcome(String(picked.get("label", "")), lines, GameState.floor_number)
	_outcome_open = true
	_set_mode(Mode.EVENT)


## 選んだ手の傾向を覚え、前に同じ傾向を選んでいれば一言返す。
func _remember_choice() -> String:
	var event := _event_at(_event_pos)
	return _remember_event_tags(event.get("tags", []))


func _remember_event_tags(tags: Array) -> String:
	var echoed := ""
	for raw in tags:
		var tag := String(raw)
		if GameState.chose_tag_before(tag) and echoed == "":
			echoed = "まえに 似た えらび方を したのを、道の者が 覚えていた。"
		GameState.event_tags[tag] = int(GameState.event_tags.get(tag, 0)) + 1
	return echoed


## 行動工程を終えた。ここが任意イベント報酬の唯一の配布点。
func _complete_event_task(done_line: String = "") -> void:
	if not EventOperationScript.valid(GameState.event_task):
		return
	var task: Dictionary = GameState.event_task.duplicate(true)
	var at := EventOperationScript.position(task)
	var current_world_pos := GameState.world_pos
	var lines: Array[String] = []
	lines.append(done_line if done_line != "" else
		EventOperationScript.completion_line(String(task.get("kind", ""))))

	# 生物相の変更などは、3歩進んだ到着地点ではなく出来事が起きた地点へ返す。
	GameState.world_pos = at
	_event_resolution_active = true
	lines.append_array(EventEffects.grant(
		GameState,
		task.get("rewards", []),
		int(task.get("danger", GameState.floor_number)),
		_battle_rng
	))
	_event_resolution_active = false
	GameState.world_pos = current_world_pos

	var echoed := _remember_event_tags(task.get("tags", []))
	if echoed != "":
		lines.append(echoed)
	GameState.event_done[at] = true
	GameState.event_task = {}
	_event_pos = at
	_event_task_battle_active = false
	_refresh_hud()
	Sound.play("learn")
	event_view.open_outcome(
		String(task.get("choice_label", task.get("event_title", ""))),
		lines,
		int(task.get("danger", GameState.floor_number))
	)
	_outcome_open = true
	_set_mode(Mode.EVENT)


func _advance_event_task_travel() -> void:
	if String(GameState.event_task.get("kind", "")) != EventOperationScript.TRAVEL:
		return
	var task: Dictionary = GameState.event_task.duplicate(true)
	task["progress"] = mini(
		int(task.get("progress", 0)) + 1, int(task.get("goal", 1))
	)
	task["ready"] = int(task["progress"]) >= int(task.get("goal", 1))
	GameState.event_task = task
	_refresh_hud()
	if bool(task.get("ready", false)):
		_complete_ready_event_task.call_deferred()
	else:
		_show_event_task_objective()


func _complete_ready_event_task() -> void:
	if (
		_mode == Mode.EXPLORE
		and bool(GameState.event_task.get("ready", false))
	):
		_complete_event_task()


func _show_event_task_objective() -> void:
	if GameState.event_task.is_empty():
		return
	var objective := EventOperationScript.objective(GameState.event_task)
	if objective != "":
		hud.toast(Terms.EVENT_TASK_STARTED % objective)


## 結果の窓を閉じた。戦いが要るならここで入る。
func _close_outcome() -> void:
	_outcome_open = false
	_continue_pending_flow()


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
	# 世界の街道を実際に歩いたぶんだけ進める。町や洞の足踏みは護送・迂回の
	# 進行に数えない。
	if _town == null and _map == null:
		_advance_event_task_travel()


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


func _open_world_chart() -> void:
	if GameState.world == null:
		_set_mode(Mode.EXPLORE)
		return
	var at := GameState.world_pos
	if _town == null and _map == null and explore.map is WorldMap:
		at = explore.player_pos
	world_chart.open(
		GameState.world,
		at,
		GameState.event_map_reveals > 0
	)
	_set_mode(Mode.MAP)


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
		hud.toast("今は中断できない。")
		_set_mode(Mode.EXPLORE)
		return
	Sound.play("confirm")
	GameState.run_active = false
	_enter_title()


## 設定はどの画面からでも開ける。閉じたら開く前の画面へ戻す。
var _mode_before_settings: Mode = Mode.TITLE


func _open_settings() -> void:
	_mode_before_settings = _mode
	settings.open(
		_mode_before_settings == Mode.TITLE,
		GameState.has_save_data(),
		_mode_before_settings == Mode.MENU and GameState.run_active
	)
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


func _erase_save_data() -> void:
	var erased := GameState.erase_save_data()
	settings.finish_save_erase(erased)
	if erased:
		# 記録行と「つづきから」をその場で消す。
		title.queue_redraw()


## 設定の二段階確認を通ったときだけランを閉じる。
##
## 「全滅」ではないので物語へ敗北印は付けない。一方、失う物／残る物の処理は
## 必ず GameState.end_run() に集約し、別の後始末経路を増やさない。
func _abandon_run() -> void:
	if not GameState.run_active:
		_close_settings()
		return
	_finish_run(false, "abandoned")


func _refresh_hud() -> void:
	var objective := StoryOperationScript.objective(GameState.story_task)
	if objective == "":
		objective = EventOperationScript.objective(GameState.event_task)
	hud.refresh(
		GameState.active_party(), GameState.floor_number, _place_label(),
		objective
	)


## HUD の左上に出す 1 行。居場所と危険度を並べる。
##
## 世界の上では**生物相の名**を出す（「雪原 危険度 7」）。
## そこに何が出るかは生物相で決まるので、名前が見えていれば備えられる。
func _place_label() -> String:
	var danger := Terms.DANGER_AT % GameState.floor_number
	var site_kind := String(GameState.site.get("kind", ""))
	match site_kind:
		"cave":
			return "%s%s　%s" % [
				String(GameState.site.get("place", "")),
				Terms.CAVE_FLOOR % int(GameState.site.get("floor", 1)), danger,
			]
		"castle":
			return "%s　%s" % [Terms.CASTLE, danger]
	var place := GameState.place_name()
	# 町では生物相ではなく固有名を残す。入場通知が消えたあとも、
	# どの Profile の町に居るかを画面だけで判別できるようにする。
	if site_kind == "town" and _town != null:
		place = _town.town_name
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


## イベントが約束した戦闘。強敵を選んだのに通常遭遇へ落とさない。
func _on_event_encounter(grade: int) -> void:
	var foes := (
		Encounter.build_elite(
			_battle_rng, GameState.floor_number, 100, GameState.biome_here(),
			_pending_elite_rule_id
		)
		if grade >= 2 else
		Encounter.build(
			_battle_rng, GameState.floor_number, 100, GameState.biome_here()
		)
	)
	_event_task_battle_active = (
		String(GameState.event_task.get("kind", "")) == EventOperationScript.FIGHT
	)
	_pending_elite_rule_id = ""
	_begin_battle(foes, false)


## 主の間へ踏み込んだ。ここで勝てばランが「生還」で終わる。
func _on_boss_reached() -> void:
	var foes := Encounter.build_boss(_battle_rng, GameState.floor_number)
	if foes.is_empty():
		# 主のデータが無い階に扉を置いてしまった場合の保険。詰ませない。
		push_warning("危険度 %d に主がいない" % GameState.floor_number)
		hud.toast("扉は かたく とざされている…")
		return
	# **主戦の直前に段階を挟む。** 読み終えてから扉が開く
	# （`_close_outcome` が控えを見て `_on_boss_reached` を呼び直す）。
	if _show_cross_world_beat("castle_pre_boss"):
		return
	Sound.play("boss_gate")
	effect.play("imperial_alarm")
	_begin_battle(foes, true)


func _begin_battle(foes: Array[Battler], is_boss: bool) -> void:
	# 監査用に、始めた場所を控える（P-5）。
	_battle_place = _place_name()
	_battle_danger = GameState.floor_number
	if foes.is_empty():
		return
	var members := GameState.active_party()
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))

	_boss_battle = is_boss
	# 難しさは通常・イベント・番人・主の全経路へ同じ順番で掛ける。
	# そのあとイベント弱体を掛ければ、プレイヤーが得た支援は難度に関係なく効く。
	GameState.apply_run_difficulty(foes)
	EventEffects.prepare_battle(GameState, party, foes, is_boss)
	var system := BattleSystem.new()
	system.start(
		party, foes, _battle_rng, GameState.floor_number,
		GameState.inherit_signs
	)
	Sound.play("encounter")
	Sound.play_bgm("boss" if is_boss else "battle")
	# **型付き配列は三項演算子で渡さない。** `x if c else [] as Array[String]` は
	# 実行時に素の `Array` になり、`Array[String]` を受ける引数で必ず弾かれる
	# （通常遭遇も含めて**戦闘が 1 回も始まらなくなっていた**）。
	# 受け取る型の変数を先に作り、そこへ入れてから渡す。
	var opening_lines: Array[String] = []
	if is_boss:
		opening_lines.assign(_battle_opening_context)
	battle.start(system, members, opening_lines)
	_battle_opening_context.clear()
	_flash_into_battle()


func _on_battle_finished(victory: bool) -> void:
	if victory and _boss_battle:
		# 主を倒した。ランが「生還」で終わる唯一の経路。
		if String(GameState.story_task.get("kind", "")) == StoryOperationScript.BOSS:
			GameState.story_task = {}
			GameState.advance_story()
			# 後日談は別の「次へ」画面にせず、この直後の戦記で選択結果と一緒に回収する。
			var epilogue := GameState.world.next_beat()
			if String(epilogue.get("operation", {}).get("kind", "")) \
					== StoryOperationScript.CHRONICLE:
				GameState.advance_story()
		_boss_battle = false
		Sound.play("victory")
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
		if _pending_elite_reward:
			_pending_elite_reward = false
			if battle.was_escaped():
				# 逃げても印は消えない。脇道へ戻れば同じ型へ再挑戦できる。
				_set_mode(Mode.EXPLORE)
			else:
				GameState.event_done[_event_pos] = true
				_open_elite_reward()
			return
		if _event_task_battle_active:
			_event_task_battle_active = false
			if battle.was_escaped():
				# 代償は支払い済みだが報酬はまだ。現場へ戻れば同じ戦いへ挑める。
				_set_mode(Mode.EXPLORE)
				hud.toast(Terms.EVENT_TASK_RETRY)
			else:
				_complete_event_task()
			return
		_set_mode(Mode.EXPLORE)
		if bool(GameState.event_task.get("ready", false)):
			_complete_ready_event_task.call_deferred()
		return
	_guardian_battle = false
	_event_task_battle_active = false
	# 敗北を命の綱でしのいでも、勝利報酬は渡さない。イベントは未完のまま残る。
	_pending_elite_reward = false
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
	# 敗北音のあとに戦闘曲を引きずらない。暗く沈む一拍を無音にする。
	Sound.stop_bgm()
	_finish_run(false, "defeat")


func _finish_run(victory: bool, outcome: String = "") -> void:
	# **全滅は物語を打ち切らない**（打ち切ると失敗したランが無かったことになる）。
	# 自分で帰還を選んだランを「全滅した」と記録するのは別の物語になる。
	if not victory and outcome != "abandoned":
		GameState.note_cross_world_setback("run_lost")

	# またぐ物語の「ラン結果」の段階は戦記に載せる。
	# 拠点の通知だと、ラン終了直後の画面をまたいで消えてしまう。
	var summary := GameState.end_run(victory, outcome)
	var beat := GameState.cross_world_beat("run_result")
	if not beat.is_empty():
		summary["cross_world_line"] = GameState.cross_world_line(beat)
		# 最後の段階でなければここで進める（最後は拠点で選ばせる）。
		if not GameState.cross_world_is_last():
			GameState.advance_cross_world()
	# 閉じた型の結末を戦記へ（A-6）。**毎回すべて載せる** ―― またぐ物語は
	# 何ラン越しの話なので、閉じたランでしか読めないと積み重ねが見えない。
	summary["cross_world_endings"] = CrossWorldArc.endings_for_chronicle(
		GameState.cross_world)
	result.show_summary(summary)
	_transition_to_result(outcome == "defeat" or (outcome == "" and not victory))


## 戦記へ移る専用経路。演出の途中で年代記の紋を先に出さず、
## 画面が切り替わった瞬間にだけ部品を開く。
func _transition_to_result(defeat: bool) -> void:
	_cancel_fade()
	_begin_transition_input()
	var apply := func() -> void:
		Sound.play_bgm("chronicle")
		_apply_mode(Mode.RESULT)
		effect.play("chronicle_echo", Vector2(PixelUI.SCREEN.x * 0.5, 46.0))

	if defeat and _transition != null and _transition.available():
		_transition.play_defeat(apply)
		return
	if not defeat and _transition != null and _transition.play_cover("page_turn", apply):
		return

	# シェーダや覆い絵が無い環境でも進行は止めない。全滅だけは同じ一拍を
	# 素の黒幕で保ち、「急に結果へ差し替わる」見え方を避ける。
	if _curtain == null:
		apply.call()
		_transition_visual_finished()
		return
	_fade_tween = create_tween()
	if defeat:
		_fade_tween.tween_property(
			_curtain, "color:a", 1.0, ScreenTransition.DEFEAT_DIM_TIME
		)
		_fade_tween.tween_interval(ScreenTransition.DEFEAT_HOLD_TIME)
		_fade_tween.tween_callback(apply)
		_fade_tween.tween_interval(ScreenTransition.DEFEAT_RESULT_HOLD)
		_fade_tween.tween_property(
			_curtain, "color:a", 0.0, ScreenTransition.DEFEAT_REVEAL_TIME
		)
	else:
		_fade_tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
		_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
		_fade_tween.tween_callback(apply)
		_fade_tween.tween_interval(ScreenTransition.MOSAIC_SWAP_HOLD * 0.5)
		_fade_tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(_transition_visual_finished)


## 洞の階段。いちばん深い階まで来たら、次は下ではなく外へ出る。
func _on_descend() -> void:
	Sound.play("stairs")
	if String(GameState.story_task.get("kind", "")) == StoryOperationScript.CAVE_SEARCH:
		# 目的地へ着いたことを先に確定し、次に踏んだとき通常の階段として使う。
		_complete_story_task()
		return
	if String(GameState.event_task.get("kind", "")) == EventOperationScript.CAVE_SEARCH:
		# 階段へ辿り着いたこと自体が探索の実行証拠。結果を読んでから、もう一度
		# 階段を踏めば通常どおり降りられる。
		_complete_event_task()
		return
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
			effect.play("seal_break")
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


## 洞の上り階段。2階以降は直前の階へ、1階では入場前の世界位置へ戻る。
func _on_ascend() -> void:
	Sound.play("stairs")
	if GameState.ascend():
		_enter_floor(true)
	else:
		_leave_site()


## 店。町なら町の在庫（世界が覚える）、洞の中ならその階の在庫。
func _on_shop_entered() -> void:
	if GameState.run_contract_enabled("closed_market"):
		Sound.play("cancel")
		hud.toast(Terms.SHOP_CLOSED_BY_CONTRACT)
		return
	Sound.play("confirm")
	if _town != null:
		var key := "town:%d" % int(GameState.site.get("index", 0))
		if not GameState.world.visited.has(key):
			GameState.world.visited[key] = {}
		shop.open(GameState.world.visited[key], GameState.floor_number)
		_dev_shop_opens += 1
		_set_mode(Mode.SHOP)
		return
	if _map == null:
		return
	shop.open(_map.shop_stock, GameState.floor_number)
	_dev_shop_opens += 1
	_set_mode(Mode.SHOP)


## 宝箱の中身。
##
## ラン内で失う資源なので、必ずゴールドに加えて装備か物資束も出す。
## 抽選はこの階の乱数から引くので、同じシードなら同じ中身が出る。
func _on_chest(amount: int, summons_elite: bool = false) -> void:
	Sound.play("chest")
	_dev_chests_taken += 1
	# 呼んでしまう箱の中身は、装備窓を横取りさせずに列へ積む（D-9 と同じ道）。
	# ここを素通しにすると、装備を選ぶ窓と戦闘開始が競争して片方が消える。
	var was_resolving := _event_resolution_active
	_event_resolution_active = _event_resolution_active or summons_elite
	var reward: Dictionary = ChestReward.roll(_battle_rng, GameState.floor_number, amount)
	var gold_amount := int(reward.get("gold", 0))
	GameState.earn_gold(gold_amount)

	var bonus_text := ""
	var gear_id := String(reward.get("gear", ""))
	var item_id := String(reward.get("item", ""))
	if gear_id != "":
		GameState.add_gear(gear_id)
		bonus_text = String(Database.gear(gear_id).get("name", gear_id))
	elif item_id != "":
		var count := int(reward.get("item_count", 1))
		GameState.add_item(item_id, count)
		bonus_text = "%s %dこ" % [Database.item(item_id).get("name", item_id), count]
	_event_resolution_active = was_resolving

	var found := "%d %s" % [gold_amount, Terms.GOLD]
	if bonus_text != "":
		found = "%s / %s" % [bonus_text, found]
	var message := "たからばこ！ %s" % found
	# **予告は湧く前に出す。** 取った物と同じ一言に載せる ―― 別々に出すと
	# あとの一言が前の一言を消して、どちらか片方しか読めない。
	# 読み逃しても、残りの箱に付いた赤い印が「これ以上は呼ぶ」を残し続ける。
	if not summons_elite and _map != null and not _map.chests.is_empty() \
			and GreedWatch.summons(_map.chests_taken):
		message = "%s\n%s" % [message, Terms.GREED_WARNING]
	hud.toast(message)
	_refresh_hud()
	if String(GameState.story_task.get("kind", "")) == StoryOperationScript.CAVE_SEARCH:
		# 箱の中身を物語結果で上書きしない。最初の行として同じ通知へ残す。
		_complete_story_task(message)
	if String(GameState.event_task.get("kind", "")) == EventOperationScript.CAVE_SEARCH:
		_complete_event_task()
	if summons_elite:
		_summon_greed_elite()


## 欲が呼んだ格上を控えへ積む（R-3）。
##
## その場で `_begin_battle` を呼ばない。宝箱の装備窓がまだ開くところなので、
## 割り込むと窓と戦闘が競争する。**装備を確かめてから敵が来る**順に揃える。
func _summon_greed_elite() -> void:
	if _map == null:
		return
	# 型は DetRng だけで決める。同じ種・同じ洞・同じ階・同じ順番なら同じ型。
	# `_battle_rng` を使わないので、呼んでも他の抽選はずれない。
	_pending_greed_elite = GreedWatch.kind_id(
		GameState.rng_for("greed").fork("take:%d" % _map.chests_taken)
	)
	if _pending_greed_elite == "":
		return
	# 結果窓が開いている（洞の調べ物を同時に終えた）ときは、閉じたときに
	# `_close_outcome` が同じ列を進める。ここで割り込まない。
	if _mode == Mode.EXPLORE:
		_continue_pending_flow()


## 控えている欲の格上の型（空なら無い）。
var _pending_greed_elite := ""


func _begin_greed_battle(kind_id: String) -> void:
	var foes := Encounter.build_elite(
		_battle_rng, GameState.floor_number, 100, GameState.biome_here(), kind_id
	)
	if foes.is_empty():
		_set_mode(Mode.EXPLORE)
		return
	_dev_greed_summons += 1
	hud.toast(Terms.GREED_SUMMONED % GreedWatch.kind_name(kind_id))
	_begin_battle(foes, false)
