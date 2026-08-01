extends SceneTree

## 任意イベント64型と AI 表層差し替えの境界を検査する。
##
##   godot --headless --script res://tests/test_world_events.gd

const WEC = preload("res://src/quest/world_event_catalog.gd")
const EO = preload("res://src/quest/event_operation.gd")
const SAG = preload("res://src/quest/story_arc_generator.gd")
const SO = preload("res://src/quest/story_operation.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	if _run_invalid_fixture():
		return
	print("=== 世界イベント生成テスト ===")
	_test_catalog()
	_test_effect_gate()
	_test_operation_gate()
	_test_story_operation_gate()
	_test_selection()
	_test_instantiation()
	_test_ai_boundary()
	print("---")
	print("成功 %d / 失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## 完了Gateの偽陰性確認用。意図的に壊した入力なら終了コード1にする。
##   godot --headless --script res://tests/test_world_events.gd -- --fixture=inert
func _run_invalid_fixture() -> bool:
	if "--fixture=instant" in OS.get_cmdline_user_args():
		var source := FileAccess.get_file_as_string("res://src/scenes/main.gd")
		var at := source.find("func _on_event_choice")
		var broken := source.insert(at + 24, "\n\tEventEffects.grant(GameState, [], 1, null)\n")
		var errors := _operation_source_errors(broken)
		print("=== 世界イベント即時完了 壊したfixture ===")
		print("\n".join(errors))
		quit(1 if not errors.is_empty() else 0)
		return true
	if "--fixture=paper_story" in OS.get_cmdline_user_args():
		var broken_story := SAG.load_catalog().duplicate(true)
		broken_story["arcs"][0]["beats"][0]["operation"] = {
			"kind": "dialogue", "objective": "話を聞く", "result": "話を聞いた",
		}
		var story_errors := SAG.validate_catalog(broken_story)
		print("=== 物語イベント品質 壊しfixture ===")
		print("\n".join(story_errors))
		quit(1 if not story_errors.is_empty() else 0)
		return true
	if "--fixture=inert" not in OS.get_cmdline_user_args():
		return false
	var broken := WEC.load_catalog().duplicate(true)
	var choice: Dictionary = broken["events"][0]["choices"][0]
	choice["costs"] = ["none"]
	choice["risks"] = []
	choice["rewards"] = ["none"]
	choice.erase("defer")
	var errors := WEC.validate_catalog(broken)
	print("=== 世界イベント品質 壊したfixture ===")
	print("\n".join(errors))
	quit(1 if not errors.is_empty() else 0)
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  OK   %s" % label)
	else:
		_failed += 1
		print("  FAIL %s %s" % [label, detail])


func _test_catalog() -> void:
	var catalog := WEC.load_catalog()
	var errors := WEC.validate_catalog(catalog)
	_check("カタログは検算を通る", errors.is_empty(), str(errors))
	var events: Array = catalog.get("events", [])
	_check("任意イベントを64型持つ", events.size() == WEC.EXPECTED_TOTAL)

	var counts := {}
	var minimum_combinations_ok := true
	var every_choice_has_tradeoff := true
	for event in events:
		var category := String(event.get("category", ""))
		counts[category] = int(counts.get(category, 0)) + 1
		var combinations := 1
		for key in WEC.SKIN_KEYS:
			combinations *= event.get("skin", {}).get(key, []).size()
		minimum_combinations_ok = minimum_combinations_ok and combinations >= 81
		for choice in event.get("choices", []):
			every_choice_has_tradeoff = (
				every_choice_has_tradeoff
				and choice.has("costs")
				and choice.has("risks")
				and choice.has("rewards")
			)
	for category in WEC.CATEGORY_ORDER:
		_check("%s は16型" % category,
			int(counts.get(category, 0)) == WEC.EXPECTED_PER_CATEGORY)
	_check("全型がAIなしでも81通り以上の表層を持つ", minimum_combinations_ok)
	_check("全選択肢にコスト・危険・報酬が明示される", every_choice_has_tradeoff)


## 「トークン名を知っている」ではなく、実際にラン状態が変わることを検査する。
## ここが今回の完了 Gate。表示だけ追加しても fingerprint が同じなら赤になる。
func _test_effect_gate() -> void:
	var catalog := WEC.load_catalog()
	var tested := 0
	for pair in [
		["allowed_costs", "cost"],
		["allowed_risks", "risk"],
		["allowed_rewards", "reward"],
	]:
		for raw in catalog.get(String(pair[0]), []):
			var token := String(raw)
			var kind := EventEffects.resolution_kind(token)
			var state = _effect_state()
			var before := _effect_fingerprint(state)
			var lines: Array[String] = []
			if String(pair[1]) == "reward":
				lines = EventEffects.grant(state, [token], 3, DetRng.new(700 + tested))
			else:
				lines = EventEffects.pay(state, [token], 3)
			var after := _effect_fingerprint(state)
			if kind == "state":
				_check(
					"%s/%s は状態を変えて結果を返す" % [String(pair[1]), token],
					before != after and not lines.is_empty(),
					"before=%s after=%s lines=%s" % [before, after, str(lines)]
				)
			elif kind == "fight":
				_check(
					"%s/%s は戦闘予約として解決する" % [String(pair[1]), token],
					before == after and lines.is_empty()
				)
			else:
				_check(
					"%s/%s は明示的な none だけ" % [String(pair[1]), token],
					token == "none" and before == after
				)
			tested += 1

	var defer_count := 0
	var unresolved_choices: Array[String] = []
	var choice_count := 0
	for event in catalog.get("events", []):
		for choice in event.get("choices", []):
			choice_count += 1
			var deferred := bool(choice.get("defer", false))
			if deferred:
				defer_count += 1
			if (
				not EventEffects.choice_has_consequence(choice)
				or EventEffects.choice_completes_event(choice) == deferred
			):
				unresolved_choices.append("%s/%s" % [
					String(event.get("id", "")), String(choice.get("id", ""))
				])
	_check(
		"全%d選択肢が完了理由か再訪可能な保留を持つ" % choice_count,
		unresolved_choices.is_empty(), str(unresolved_choices.slice(0, 8))
	)
	_check("効果ゼロの撤退手2件だけが再訪可能", defer_count == 2, "defer=%d" % defer_count)

	# 壊した fixture も同じ検査器へ通す。正常入力だけ通る Gate は完成扱いにしない。
	var inert: Dictionary = catalog.duplicate(true)
	var inert_choice: Dictionary = inert["events"][0]["choices"][0]
	inert_choice["costs"] = ["none"]
	inert_choice["risks"] = []
	inert_choice["rewards"] = ["none"]
	inert_choice.erase("defer")
	var inert_errors := WEC.validate_catalog(inert)
	_check(
		"効果ゼロを完了扱いするfixtureは落ちる",
		_has_error(inert_errors, "状態変化・戦闘・明示的な保留")
	)

	var unknown: Dictionary = catalog.duplicate(true)
	unknown["allowed_rewards"].append("phantom_reward")
	var unknown_choice: Dictionary = unknown["events"][0]["choices"][0]
	unknown_choice["rewards"] = ["phantom_reward"]
	var unknown_errors := WEC.validate_catalog(unknown)
	_check(
		"allowedへ足しただけの未実装トークンfixtureは落ちる",
		_has_error(unknown_errors, "実行器に無い")
	)

	# 表示上の「手強い戦い」と実戦を一致させる。
	var normal := Encounter.build(DetRng.new(909), 5, 100, "")
	var elite := Encounter.build_elite(DetRng.new(909), 5, 100, "")
	_check(
		"elite_fight は同じ編成の実能力が通常戦より高い",
		not normal.is_empty()
		and normal.size() == elite.size()
		and elite[0].source_id == normal[0].source_id
		and elite[0].max_hp > normal[0].max_hp
		and elite[0].atk > normal[0].atk
	)
	_check(
		"発火した危険だけから戦闘段階を決める",
		EventEffects.fight_grade([]) == 0
		and EventEffects.fight_grade(["normal_fight"]) == 1
		and EventEffects.fight_grade(["normal_fight", "elite_fight"]) == 2
	)
	var bias_reaches_runtime := false
	for seed_value in range(1, 400):
		var safe := Encounter.should_meet(DetRng.new(seed_value), 14, 14, -3)
		var unsafe := Encounter.should_meet(DetRng.new(seed_value), 14, 14, 3)
		if not safe and unsafe:
			bias_reaches_runtime = true
			break
	_check("道の安全／危険が実際の遭遇判定を変える", bias_reaches_runtime)

	var prepared = _effect_state()
	prepared.event_boons.assign(["temporary_attack", "temporary_guard", "temporary_ally"])
	prepared.event_boss_intel = 1
	prepared.event_boss_weaken = 1
	var allies: Array[Battler] = [prepared.active_party()[0].to_battler(0)]
	var foes := Encounter.build_boss(DetRng.new(31), 10)
	var ally_atk := allies[0].atk
	var boss_hp := foes[0].max_hp
	var boss_agi := foes[0].agi
	EventEffects.prepare_battle(prepared, allies, foes, true)
	_check(
		"一時援護と主戦準備が実際のBattlerを変える",
		allies[0].atk > ally_atk
		and foes[0].max_hp < boss_hp
		and foes[0].agi < boss_agi
	)

	var blocked = _effect_state()
	blocked.event_service_loss = 1
	var denied := EventEffects.consume_inn(blocked, DetRng.new(5))
	_check(
		"service_loss は次の宿を実際に断る",
		bool(denied.get("blocked", false)) and blocked.event_service_loss == 0
	)
	var helped = _effect_state()
	helped.event_town_service = 1
	helped.event_inn_bonus = 1
	var stock_before: int = helped.inventory.size()
	var supplied := EventEffects.consume_inn(helped, DetRng.new(5))
	_check(
		"town_service と inn_bonus は宿で物資と効果になる",
		not bool(supplied.get("blocked", false))
		and helped.inventory.size() > stock_before
		and "temporary_guard" in helped.event_boons
	)
	var empty_risk = _effect_state()
	empty_risk.inventory.clear()
	empty_risk.gear_stock.clear()
	var hp_before: int = empty_risk.active_party()[0].hp
	var fallback_lines: Array[String] = EventEffects.pay(
		empty_risk, ["item", "equipment"], 3
	)
	_check(
		"失う物が無い危険も素通りせず負傷へフォールバックする",
		empty_risk.active_party()[0].hp < hp_before and fallback_lines.size() == 2
	)

	# 結果は全角空白で1文へ潰さず、1件ずつ描画する。装備確認と後続戦闘も
	# 同じ継続関数で直列化し、deferred call が戦闘を上書きしない。
	var event_view_source := FileAccess.get_file_as_string("res://src/scenes/event_view.gd")
	var main_source := FileAccess.get_file_as_string("res://src/scenes/main.gd")
	_check("イベント結果は配列のまま保持する",
		event_view_source.contains("\"outcome_lines\": body")
		and not event_view_source.contains("\"cause\": \"　\".join(body)"))
	_check("イベント後処理は一つの直列フローを通る",
		main_source.contains("func _continue_pending_flow")
		and main_source.contains("gear_offer.open(next_gear")
		and main_source.contains("_continue_pending_flow()"))
	_check("格上の戦利品は勝利後の三択へ接続される",
		main_source.contains("func _elite_reward_choices")
		and main_source.contains("if _pending_elite_reward")
		and main_source.contains("_open_elite_reward()")
		and main_source.contains("battle.was_escaped()"))


## D-1で抜けたGate。「効果がある」だけでなく、選択後にプレイヤーが行う工程を
## 全選択肢へ割り当て、報酬配布がその完了点にしか無いことを検査する。
func _test_operation_gate() -> void:
	var catalog := WEC.load_catalog()
	var covered := 0
	var missing: Array[String] = []
	for event in catalog.get("events", []):
		for choice in event.get("choices", []):
			if bool(choice.get("defer", false)):
				continue
			var task := EO.build(event, choice, [], Vector2i(4, 5), 3)
			if not EO.valid(task) or EO.objective(task) == "" or EO.preview(event, choice) == "":
				missing.append("%s/%s" % [event.get("id", ""), choice.get("id", "")])
			covered += 1
	_check("保留を除く全%d選択肢に実行工程がある" % covered,
		missing.is_empty(), str(missing.slice(0, 8)))

	var road := WEC.event_by_id("broken_bridge")
	var town := WEC.event_by_id("tainted_well")
	var cave := WEC.event_by_id("twin_altar")
	_check("街道の非戦闘手は実移動になる",
		EO.kind_for(road, road.choices[0]) == EO.TRAVEL)
	_check("町の非戦闘手は人物接触になる",
		EO.kind_for(town, town.choices[0]) == EO.TOWN_CONTACT)
	_check("洞の非戦闘手は現地探索になる",
		EO.kind_for(cave, cave.choices[0]) == EO.CAVE_SEARCH)
	_check("戦闘を払う手は勝利が完了条件になる",
		EO.kind_for(road, road.choices[2]) == EO.FIGHT)

	var main_source := FileAccess.get_file_as_string("res://src/scenes/main.gd")
	var source_errors := _operation_source_errors(main_source)
	_check("選択時には報酬を配らない",
		not ("選択時に報酬を配っている" in source_errors), str(source_errors))
	_check("報酬配布は実行工程の完了点にある",
		not ("実行工程の完了点に報酬が無い" in source_errors), str(source_errors))
	var event_view_source := FileAccess.get_file_as_string("res://src/scenes/event_view.gd")
	_check("支払不能は選択肢ごとに止める",
		event_view_source.contains("_blocked.get(_index")
		and event_view_source.contains("not _current_blocked().is_empty()"))
	_check("実行中の目的を別イベントで上書きしない",
		main_source.contains("and GameState.event_task.is_empty()")
		and main_source.contains("if not GameState.event_task.is_empty():"))


func _operation_source_errors(source: String) -> Array[String]:
	var errors: Array[String] = []
	var choice_start := source.find("func _on_event_choice")
	var choice_end := source.find("const RISK_ODDS", choice_start)
	var complete_start := source.find("func _complete_event_task")
	var complete_end := source.find("func _advance_event_task_travel", complete_start)
	if choice_start < 0 or choice_end < 0:
		errors.append("選択処理が無い")
	elif source.substr(choice_start, choice_end - choice_start).contains("EventEffects.grant"):
		errors.append("選択時に報酬を配っている")
	if complete_start < 0 or complete_end < 0:
		errors.append("実行工程の完了処理が無い")
	elif not source.substr(
		complete_start, complete_end - complete_start
	).contains("EventEffects.grant"):
		errors.append("実行工程の完了点に報酬が無い")
	return errors


## 「文章を読み、次へを押して終了」を再導入できないようにするGate。
## 一世界物語は全拍に実操作、三択にはラン状態へ届く効果を要求する。
func _test_story_operation_gate() -> void:
	var catalog := SAG.load_catalog()
	var errors := SAG.validate_catalog(catalog)
	_check("一世界物語カタログは実操作Gateを通る", errors.is_empty(), str(errors.slice(0, 8)))

	var beat_count := 0
	var choice_count := 0
	var operation_errors: Array[String] = []
	for arc in catalog.get("arcs", []):
		for beat in arc.get("beats", []):
			beat_count += 1
			for error in SO.definition_errors(beat):
				operation_errors.append("%s/%s" % [arc.get("id", ""), error])
		for choice in arc.get("choices", []):
			choice_count += 1
			for error in SO.choice_errors(choice):
				operation_errors.append("%s/%s" % [arc.get("id", ""), error])
	_check("全%d拍が町・洞・主戦・戦記の工程を持つ" % beat_count,
		beat_count == 36 and operation_errors.is_empty(), str(operation_errors.slice(0, 8)))
	_check("全%d択が後続プレイを変える" % choice_count,
		choice_count == 18 and operation_errors.is_empty())

	var state = _effect_state()
	var story: Dictionary = state.world.story
	var town_task := SO.build(story, story.beats[0], {}, Vector2i(4, 5))
	var before := _effect_fingerprint(state)
	EventEffects.grant(
		state, town_task.get("runtime_effects", []), state.floor_number, DetRng.new(811)
	)
	_check("非選択拍の実操作もラン状態を変える",
		SO.valid(town_task) and before != _effect_fingerprint(state))
	state.story_task = town_task
	_check("実行中の物語目的は中断データへ残る",
		state.to_suspend().get("story_task", {}) == town_task)

	var choice_beat: Dictionary = story.beats[3]
	var choice: Dictionary = story.choices[0]
	var choice_task := SO.build(story, choice_beat, choice, Vector2i(7, 8))
	var choice_before := _effect_fingerprint(state)
	EventEffects.grant(
		state, choice_task.get("runtime_effects", []), state.floor_number, DetRng.new(812)
	)
	_check("物語の三択は主戦または道へ実際に効く",
		SO.valid(choice_task) and choice_before != _effect_fingerprint(state))

	var view = load("res://src/scenes/event_view.gd").new()
	var opened: bool = view.open_story(choice_beat, story, state.floor_number)
	var rendered_choices: Array = view.event.get("choices", [])
	_check("選択拍は三択とゲーム内効果を同じ画面へ出す",
		opened and rendered_choices.size() == 3
		and not rendered_choices[0].get("runtime_effects", []).is_empty())
	view.free()

	var paper := catalog.duplicate(true)
	paper["arcs"][0]["beats"][0]["operation"]["kind"] = "continue"
	var paper_errors := SAG.validate_catalog(paper)
	_check("会話送り／紙芝居fixtureは落ちる",
		_has_error(paper_errors, "紙芝居なので禁止"), str(paper_errors.slice(0, 4)))
	var inert_choice := catalog.duplicate(true)
	inert_choice["arcs"][0]["choices"][0].erase("runtime_effects")
	var choice_errors := SAG.validate_catalog(inert_choice)
	_check("結末文だけで実効果の無い選択fixtureは落ちる",
		_has_error(choice_errors, "ゲーム内効果が無い"), str(choice_errors.slice(0, 4)))

	var event_view_source := FileAccess.get_file_as_string("res://src/scenes/event_view.gd")
	var main_source := FileAccess.get_file_as_string("res://src/scenes/main.gd")
	var battle_view_source := FileAccess.get_file_as_string("res://src/scenes/battle_view.gd")
	var choice_start := main_source.find("func _on_story_choice")
	var choice_end := main_source.find("func _begin_story_operation", choice_start)
	var complete_start := main_source.find("func _complete_story_task")
	var complete_end := main_source.find("func _show_story_task_objective", complete_start)
	var cross_start := main_source.find("func _show_cross_world_beat")
	var cross_end := main_source.find("func _town_placement", cross_start)
	_check("選択の無い『話を続ける』行を生成しない",
		not event_view_source.contains("EVENT_CONTINUE_CHOICE")
		and event_view_source.contains("phase\", \"\")) != \"choice\""))
	_check("物語の選択時には拍も報酬も進めない",
		choice_start >= 0 and choice_end > choice_start
		and not main_source.substr(choice_start, choice_end - choice_start).contains("advance_story")
		and not main_source.substr(choice_start, choice_end - choice_start).contains("EventEffects.grant"))
	_check("実操作の完了点だけが効果を渡して拍を進める",
		complete_start >= 0 and complete_end > complete_start
		and main_source.substr(complete_start, complete_end - complete_start).contains("EventEffects.grant")
		and main_source.substr(complete_start, complete_end - complete_start).contains("advance_story"))
	_check("またぐ物語の中間拍も文章一枚で入力を止めない",
		cross_start >= 0 and cross_end > cross_start
		and not main_source.substr(cross_start, cross_end - cross_start).contains("open_outcome"))
	_check("決戦の物語は別窓でなく実際の開戦文へ入る",
		main_source.contains("_battle_opening_context.append")
		and main_source.contains("String(task.get(\"cue\", \"\"))")
		and battle_view_source.contains("_opening_lines = context_lines.duplicate()")
		and battle_view_source.contains("append_array(BattleOpeningGate.lines(system))"))


func _effect_state():
	var state = load("res://src/game/game_state.gd").new()
	var roster: Array[PartyMember] = []
	for entry in [
		["アレン", "soldier"],
		["ミナ", "mage"],
		["ルカ", "priest"],
		["トア", "thief"],
	]:
		roster.append(PartyMember.create(String(entry[0]), String(entry[1])))
	state.roster = roster
	state.active_indices.assign([0, 1, 2, 3])
	state.start_new_run(24680)
	state.gold = 999
	state.add_item("herb", 2)
	var gear_pool := Database.gear_ids_for_floor(3)
	if not gear_pool.is_empty():
		state.add_gear(String(gear_pool[0]))
	for member in state.active_party():
		member.hp = maxi(member.max_hp() - 8, 1)
		member.mp = maxi(member.max_mp() - 4, 0)
	# 生物相変化がどちら向きでも実際に変わる中間地点を使う。
	for y in state.world.height:
		for x in state.world.width:
			var index: int = state.world.biome_index_at(x, y)
			if state.world.is_walkable(x, y) and index > 0 and index < WorldMap.BIOMES.size() - 1:
				state.world_pos = Vector2i(x, y)
				return state
	return state


func _effect_fingerprint(state) -> String:
	var party: Array = []
	for member in state.active_party():
		party.append([member.hp, member.mp])
	var known: Array = []
	for seal in state.world.seals:
		known.append(bool(seal.get("known", false)))
	return JSON.stringify({
		"gold": state.gold,
		"earned": state.gold_earned,
		"steps": state.steps,
		"inventory": state.inventory,
		"gear": state.gear_stock,
		"party": party,
		"encounter": state.event_encounter_bias,
		"duration": state.event_bias_steps,
		"shop": state.event_shop_bonus,
		"boons": state.event_boons,
		"boss": [state.event_boss_intel, state.event_boss_weaken],
		"town": [state.event_town_service, state.event_inn_bonus, state.event_service_loss],
		"route": state.event_route_changes,
		"map": state.event_map_reveals,
		"known": known,
		"biome": state.world.biome_index_at(state.world_pos.x, state.world_pos.y),
		"biome_changes": state.event_biome_changes,
	})


func _has_error(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if needle in error:
			return true
	return false


func _test_selection() -> void:
	var first := WEC.select_for_world(DetRng.new(771), {}, 3)
	var second := WEC.select_for_world(DetRng.new(771), {}, 3)
	_check("同じ種から同じ三件を選ぶ", _ids(first) == _ids(second))
	_check("標準三件は道・町・洞を一件ずつ含む",
		_categories(first) == ["road", "town", "cave"], str(_categories(first)))

	var with_faction := WEC.select_for_world(DetRng.new(771), {}, 4)
	_check("四件目は勢力イベント", _categories(with_faction) == [
		"road", "town", "cave", "faction"
	], str(_categories(with_faction)))

	var town_slot := WEC.select_for_world(
		DetRng.new(31), {"site_kind": "town"}, 1
	)
	var cave_slot := WEC.select_for_world(
		DetRng.new(32), {"site_kind": "cave"}, 1
	)
	var road_slot := WEC.select_for_world(
		DetRng.new(33), {"site_kind": "world"}, 1
	)
	_check("町の枠には町イベントだけを置く",
		_categories(town_slot) == ["town"], str(_categories(town_slot)))
	_check("洞の枠には洞イベントだけを置く",
		_categories(cave_slot) == ["cave"], str(_categories(cave_slot)))
	_check("街道の枠には街道イベントを置く",
		_categories(road_slot) == ["road"], str(_categories(road_slot)))

	var seen := {}
	for seed_value in range(1, 320):
		for event_id in _ids(WEC.select_for_world(DetRng.new(seed_value), {}, 4)):
			seen[event_id] = true
	_check("種を変えると64型すべてが抽選対象になる",
		seen.size() == WEC.EXPECTED_TOTAL,
		str(seen.keys()))

	var high_danger := WEC.select_for_world(
		DetRng.new(12), {"danger_min": 9, "danger_max": 10}, 4
	)
	var all_overlap := true
	for event in high_danger:
		all_overlap = all_overlap and int(event.danger[1]) >= 9
	_check("危険度条件と重なる型だけを選ぶ", all_overlap)


func _test_instantiation() -> void:
	var event := WEC.event_by_id("broken_bridge")
	var a := WEC.instantiate(event, DetRng.new(991), {"biome": "grassland"})
	var b := WEC.instantiate(event, DetRng.new(991), {"biome": "grassland"})
	_check("同じ種から同じイベント表層が出る",
		JSON.stringify(a) == JSON.stringify(b))
	_check("イベント骨格は三択を保持する", a.choices.size() == 3)
	_check("四つの表層項目をすべて選ぶ",
		a.skin.size() == 4
		and String(a.skin.title) != ""
		and String(a.skin.actor) != ""
		and String(a.skin.cause) != ""
		and String(a.skin.flavor) != "")

	var variants := {}
	for seed_value in range(1, 40):
		var instance := WEC.instantiate(event, DetRng.new(seed_value))
		variants[JSON.stringify(instance.skin)] = true
	_check("種を変えると同じ骨格にも複数の表層が出る", variants.size() >= 12,
		"variants=%d" % variants.size())


func _test_ai_boundary() -> void:
	var event := WEC.event_by_id("dormant_war_machine")
	var fallback := WEC.instantiate(event, DetRng.new(44), {"biome": "badland"})
	var original_choices = fallback.choices.duplicate(true)
	var candidate := {
		"skin": {
			"title": "灰雨の機兵",
			"actor": "<script>",
			"cause": "第3実験から逃げた",
			"flavor": "ベホマを唱える。",
		},
		"choices": [{"id": "win", "rewards": ["boss_weaken"]}],
		"rewards": ["boss_weaken"],
		"event_id": "broken_bridge",
	}
	var merged := WEC.apply_ai_skin(fallback, candidate)
	_check("正しいAI題名だけ採用する", merged.skin.title == "灰雨の機兵")
	_check("記号入りの担当者名はfallbackへ戻す",
		merged.skin.actor == fallback.skin.actor)
	_check("数字入りの原因はfallbackへ戻す",
		merged.skin.cause == fallback.skin.cause)
	_check("禁止語入りの情景文はfallbackへ戻す",
		merged.skin.flavor == fallback.skin.flavor)
	_check("AIは選択肢と効果を変更できない",
		merged.choices == original_choices
		and merged.event_id == fallback.event_id)
	_check("棄却理由を項目ごとに残す", merged.rejected.size() == 3,
		str(merged.rejected))

	var facts_json := JSON.stringify(WEC.facts_for_ai(fallback))
	var leaks := ["event_id", "choices", "costs", "risks", "rewards"]
	var clean := true
	for key in leaks:
		if "\"%s\":" % key in facts_json:
			clean = false
	_check("AIへID・選択肢・数値効果を渡さない", clean, facts_json)
	_check("AI入力には四つのfallbackと文字数上限がある",
		WEC.facts_for_ai(fallback).slots.size() == 4)

	var awkward := WEC.apply_ai_skin(fallback, {"skin": {
		"title": "水辺の鳥",
		"flavor": "水場で鳴く鳥のさえずりは静かにしている",
	}})
	_check("主語と述語が噛み合わないAI情景だけfallbackへ戻す",
		awkward.skin.title == "水辺の鳥"
		and awkward.skin.flavor == fallback.skin.flavor
		and awkward.rejected.size() == 1
		and String(awkward.rejected[0].get("reason", "")) == "predicate_mismatch")


func _ids(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for event in events:
		out.append(String(event.get("id", "")))
	return out


func _categories(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for event in events:
		out.append(String(event.get("category", "")))
	return out
