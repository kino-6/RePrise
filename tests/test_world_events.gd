extends SceneTree

## 任意イベント64型と AI 表層差し替えの境界を検査する。
##
##   godot --headless --script res://tests/test_world_events.gd

const WEC = preload("res://src/quest/world_event_catalog.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	if _run_invalid_fixture():
		return
	print("=== 世界イベント生成テスト ===")
	_test_catalog()
	_test_effect_gate()
	_test_selection()
	_test_instantiation()
	_test_ai_boundary()
	print("---")
	print("成功 %d / 失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## 完了Gateの偽陰性確認用。意図的に壊した入力なら終了コード1にする。
##   godot --headless --script res://tests/test_world_events.gd -- --fixture=inert
func _run_invalid_fixture() -> bool:
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
