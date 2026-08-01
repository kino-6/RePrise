class_name DevProbe
extends RefCounted

## 開発用の入口と、自動プレイへの道案内（S-1）。
##
## **本編は 1 行もここに無い。** `main.gd` が 3009 行のうち 965 行を
## 開発足場に使っていて、`--shot=` を足す作業はどのタスクでも起きるため、
## 同じ場所を複数のエージェントが同時に書き換える一番の原因になっていた。
##
## ここが持つのは 3 つだけ。
##
##   * 起動時の開発指定（`--shot=` / `--play=` / `--dev-load=` ほか）
##   * 自動プレイの開始点（`--play-start=` の fixture）
##   * 自動プレイが目的地へ向かうための「次の一歩」
##
## 画面を撮る手順は `src/dev/capture_scenes.gd` にある。
## 計測カウンタ（宿・店・会話の回数）は数える場所が本編の中なので `main.gd` に残す。


## 自動プレイの種（`--seed=`）。実行ごとにコマの置き場が変わる。
var play_seed := 12345
## 通しでは再現しづらい遷移だけを、入口から実入力で監査する開始点。
var play_start := ""
## 空なら従来の操作名入力。keypad なら物理テンキーを実際に流す。
var play_input := ""
## `--dev-save=` の名前。ランを始めたところで書き出す。
var save_name := ""
## `--dev-load=` で状態を読み込んだか。読み込んだならタイトルを出さない。
var loaded_from_dev := false
## 洞の往復だけを狙う実入力Gate。通常プレイの自動操縦は常に下りを選ぶ。
var cave_return := false
var cave_return_phase := false
## 洞イベントだけを実入力監査するとき、実行地点の直前へ置く。
var event_cave_gate := false
## 自動プレイを宝箱へ向かわせる印（R-3 の実入力監査のときだけ立てる）。
var greed_chests := false


## ランを始め直すときに、実入力Gateの印だけを落とす。
func reset_run_gates() -> void:
	cave_return = false
	cave_return_phase = false


## 開発用の引数を捌く。**何か捌いたら true**（呼び出し側がタイトルを出さない）。

func handle_debug_args(main: Main) -> bool:
	# **先に全部の引数を見る。** 下の輪は最初に当たった指定で return するので、
	# 「--play=12 --dev-save=probe」のように後ろへ書くと読まれなかった。
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dev-save="):
			save_name = arg.trim_prefix("--dev-save=")
		if arg.begins_with("--seed="):
			play_seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--play-start="):
			play_start = arg.trim_prefix("--play-start=")
		if arg.begins_with("--input="):
			play_input = arg.trim_prefix("--input=")

	for arg in OS.get_cmdline_user_args():
		# 開発用。「この世界のこの場面」を保存／読み込みする。
		#   godot --path . -- --dev-load=boss1
		# **読み込んだあとも他の指定を続ける。** ここで return すると
		# 「--dev-load=x --play=10」の自動プレイが始まらず、headless が終わらない。
		if arg.begins_with("--dev-load="):
			if GameState.dev_load(arg.trim_prefix("--dev-load=")):
				print("開発用の保存から再開: %s" % arg.trim_prefix("--dev-load="))
				main._resume_loaded()
				loaded_from_dev = true
			continue
		if arg.begins_with("--shot="):
			CaptureScenes.run(main, arg.trim_prefix("--shot="))
			return true
		if arg.begins_with("--inspect="):
			# 撮影と同じ決定的な状態へ直接入り、終了せずそのまま操作する。
			# 秒数自動プレイは通し回帰だけにし、個別画面の確認はこれで行う。
			CaptureScenes.run(main, arg.trim_prefix("--inspect="), true)
			return true
		if arg.begins_with("--play="):
			# **種を渡せるようにする**（P-2）。実行ごとにコマの置き場が分かれるので、
			# 別の種で 2 回走らせれば、それぞれの成果物を混ぜずに比べられる。
			start_autoplay(main, float(arg.trim_prefix("--play=")), play_seed)
			return true
	return loaded_from_dev


## 開発用。人と同じ入力だけを流し込んで通しを確認する（src/dev/autoplay.gd）。
func start_autoplay(main: Main, seconds: float, seed_value: int = 12345) -> void:
	# 名前付き保存からの再開でなければ、人と同じくタイトルから始める。
	# ここを省くと初期 Mode.EXPLORE のまま地図なし画面へ入力してしまう。
	if play_start == "battle":
		# 遭遇の「モザイク→開戦文→初手」だけを短く繰り返せる入口。
		# 戦闘開始後は AutoPlay が人と同じ入力だけを送る。
		main._start_run()
		var foes := Encounter.build(
			main._battle_rng, GameState.floor_number, 100, GameState.biome_here())
		for foe in foes:
			foe.agi = 999  # 敵先手の通知も同じ試走で確認する。
		main._begin_battle(foes, false)
	elif play_start == "event_task":
		# 選択 → 実移動3歩 → 完了結果を、内部APIで飛ばさず入力だけで通す。
		main._start_run()
		GameState.add_item("herb", 1)
		var definition := WorldEventCatalog.event_by_id("broken_bridge")
		var instance := WorldEventCatalog.instantiate(
			definition, DetRng.new(seed_value), {"biome": GameState.biome_here()}
		)
		main._event_pos = GameState.world.start_pos
		GameState.world.events[main._event_pos] = instance
		main._open_event(main._event_pos)
	elif play_start == "event_town":
		main._start_run()
		GameState.add_item("herb", 1)
		var town_at := first_site("town")
		var definition := WorldEventCatalog.event_by_id("tainted_well")
		var instance := WorldEventCatalog.instantiate(
			definition, DetRng.new(seed_value), {"biome": GameState.biome_here()}
		)
		main._event_pos = town_at
		GameState.world_pos = town_at
		GameState.world.events[town_at] = instance
		main._open_event(town_at)
	elif play_start == "event_cave":
		main._start_run()
		event_cave_gate = true
		var cave_at := first_site("cave")
		var definition := WorldEventCatalog.event_by_id("twin_altar")
		var instance := WorldEventCatalog.instantiate(
			definition, DetRng.new(seed_value), {"biome": GameState.biome_here()}
		)
		main._event_pos = cave_at
		GameState.world_pos = cave_at
		GameState.world.events[cave_at] = instance
		main._open_event(cave_at)
	elif play_start == "event_fight":
		main._start_run()
		var definition := WorldEventCatalog.event_by_id("broken_bridge")
		var instance := WorldEventCatalog.instantiate(
			definition, DetRng.new(seed_value), {"biome": GameState.biome_here()}
		)
		# 実入力の先頭決定で、格上戦を含む手へ入るfixture。
		instance["choices"] = [instance.get("choices", [])[2]]
		main._event_pos = GameState.world.start_pos
		GameState.world.events[main._event_pos] = instance
		main._open_event(main._event_pos)
	elif play_start == "greed":
		# 欲が呼ぶ格上（R-3）を**実入力だけ**で通す。宝箱は押し当てて開けるので、
		# 内部APIを呼ばずに 1 つ目 → 予告 → 2 つ目 → 格上戦まで辿れる。
		prepare_greed_floor(main)
	elif play_start == "cave_return":
		prepare_cave_return(main, true)
	elif play_start == "cave_exit":
		prepare_cave_return(main, false)
	elif not loaded_from_dev:
		main._enter_title()
	var driver := AutoPlay.new()
	main.add_child(driver)
	driver.start(main, maxf(seconds, 5.0), seed_value, play_input == "keypad")


## 開発用。「先へ進む一歩」。世界では城へ、洞では階段へ向かう。
## 自動プレイがこれで世界を横断する。届かなければ空文字。
func step_to_exit(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE:
		return ""
	# 町は閉じた広場なので、酔歩では出口に当たらない（40 秒 居座った）。
	# 町に居るあいだは出口へ向かわせる。
	if main._town != null:
		return main.explore.dev_step_toward(main._town.exit_pos)
	if main._map == null:
		if GameState.world == null:
			return ""
		return main.explore.dev_step_toward(GameState.world.castle_pos)
	# 欲の格上を実入力で通すときだけ、階段より宝箱を先に取りに行かせる。
	# `route()` は目的地だけ通行不可でも通すので、最後の一歩が箱を押し当てる。
	if greed_chests and not main._map.chests.is_empty():
		return main.explore.dev_step_toward(main._map.chests[0])
	if cave_return:
		if int(GameState.site.get("floor", 1)) >= 2:
			cave_return_phase = true
		if cave_return_phase:
			return main.explore.dev_step_toward(main._map.upstairs_pos)
	return main.explore.dev_step_toward(main._map.stairs_pos)


## 開発用。近くの店へ向かう一歩。世界では町、洞では出店。無ければ空文字。
func step_to_shop(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE:
		return ""
	if main._town != null:
		return main.explore.dev_step_toward(main._town.shop_pos)
	if main._map == null:
		var town := nearest_town(main)
		return "" if town.x < 0 else main.explore.dev_step_toward(town)
	if main._map.shop_pos.x < 0:
		return ""
	return main.explore.dev_step_toward(main._map.shop_pos)


## 開発用。町の宿へ向かう一歩。町以外なら空文字。
func step_to_inn(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE or main._town == null:
		return ""
	return main.explore.dev_step_toward(main._town.inn_pos)


## 開発用。町固有の仕事場へ向かう一歩。
func step_to_town_facility(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE or main._town == null:
		return ""
	return main.explore.dev_step_toward(main._town.landmark_pos)


func step_to_town_chest(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE or main._town == null:
		return ""
	if main._town.supply_chest_pos.x < 0:
		return ""
	return main.explore.dev_step_toward(main._town.supply_chest_pos)


## 開発用。町で最も近い住人へ向かう一歩。
func step_to_talk(main: Main) -> String:
	if main._mode != Main.Mode.EXPLORE or main._town == null or main._town.folk.is_empty():
		return ""
	var nearest := Vector2i(-1, -1)
	var best_length := -1
	for raw_pos in main._town.folk:
		var pos: Vector2i = raw_pos
		var role := String(main._town.folk[pos].get("kind", ""))
		if main._dev_talked_roles.has(role):
			continue
		var route := main._town.route(main.explore.player_pos, pos)
		if not route.is_empty() and (best_length < 0 or route.size() < best_length):
			nearest = pos
			best_length = route.size()
	return "" if nearest.x < 0 else main.explore.dev_step_toward(nearest)


## 開発用。その種類の拠点地のうち、門にいちばん近いもの。撮影に使う。
static func first_site(kind: String) -> Vector2i:
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


## 2階以上ある洞のうち、門にいちばん近いもの。階段往復の実入力Gateに使う。
static func first_deep_cave() -> Vector2i:
	if GameState.world == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := -1
	for raw_pos in GameState.world.sites:
		var data: Dictionary = GameState.world.sites[raw_pos]
		if String(data.get("kind", "")) != "cave" or int(data.get("danger", 1)) < 3:
			continue
		var at: Vector2i = raw_pos
		var d := absi(at.x - GameState.world.start_pos.x) + absi(at.y - GameState.world.start_pos.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = at
	return best


## 下り直前／上り直前へ置くが、遷移そのものはAutoPlayの実キー入力で踏ませる。
func prepare_cave_return(main: Main, start_at_down: bool) -> void:
	main._start_run()
	var cave := first_deep_cave()
	if cave.x < 0:
		return
	main._site_return_pos = GameState.step_outside_site(cave)
	GameState.world_pos = cave
	GameState.enter_site(cave)
	main._dungeon_floors.clear()
	main._enter_floor()
	cave_return = true
	cave_return_phase = not start_at_down
	if start_at_down:
		main.explore.setup(
			main._map, main._encounter_rng, main._leader_job(), main._map.down_arrival_pos
		)


## 欲の格上（R-3）を実入力で通すための足場。**宝箱が 2 つ以上ある階**へ置く。
##
## 1 つでは 2 つ目が無く、0 個の階では何も起きない。階を選ぶだけで、
## 開けるのも湧かせるのも通常の経路（`ExploreView` → `_on_chest`）に任せる。
func prepare_greed_floor(main: Main) -> void:
	main._start_run()
	var cave := first_deep_cave()
	if cave.x < 0:
		cave = first_site("cave")
	if cave.x < 0:
		return
	main._site_return_pos = GameState.step_outside_site(cave)
	GameState.world_pos = cave
	GameState.enter_site(cave)
	main._dungeon_floors.clear()
	main._enter_floor()
	for _step in GameState.cave_depth() - 1:
		if main._map != null and main._map.chests.size() >= 2:
			break
		GameState.descend()
		main._enter_floor()
	greed_chests = true


## 世界でいちばん近い町。自動プレイが買い物を試すのに使う。
func nearest_town(main: Main) -> Vector2i:
	if GameState.world == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := -1
	for pos in GameState.world.sites:
		if String(GameState.world.sites[pos].get("kind", "")) != "town":
			continue
		var at: Vector2i = pos
		var d := absi(at.x - main.explore.player_pos.x) + absi(at.y - main.explore.player_pos.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = at
	return best
