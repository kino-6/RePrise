extends SceneTree

## 感情的な連続シナリオの骨格・決定性・AI境界・失敗継続を検査する。
##
##   godot --headless --script res://tests/test_story_arcs.gd

const SAG = preload("res://src/quest/story_arc_generator.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 連続シナリオ生成テスト ===")
	_test_catalog()
	_test_all_arcs()
	_test_determinism_and_variety()
	_test_world_binding()
	_test_fail_forward()
	_test_ai_boundary()
	print("---")
	print("成功 %d / 失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  OK   %s" % label)
	else:
		_failed += 1
		print("  FAIL %s %s" % [label, detail])


func _sample_facts() -> Dictionary:
	return {
		"world_id": "sample",
		"towns": [
			{"id": "town:0", "danger": 2, "biome": "grassland", "place": "草原"},
			{"id": "town:1", "danger": 5, "biome": "wetland", "place": "湿地"},
			{"id": "town:2", "danger": 7, "biome": "badland", "place": "荒地"},
			{"id": "town:3", "danger": 9, "biome": "snowfield", "place": "雪原"},
		],
		"caves": [
			{"id": "cave:0", "danger": 3, "biome": "grassland", "place": "草原"},
			{"id": "cave:1", "danger": 4, "biome": "forest", "place": "森林"},
			{"id": "cave:2", "danger": 6, "biome": "wetland", "place": "湿地"},
			{"id": "cave:3", "danger": 8, "biome": "badland", "place": "荒地"},
			{"id": "cave:4", "danger": 9, "biome": "volcano", "place": "火山"},
		],
		"castle": {
			"id": "castle:0", "danger": 10, "biome": "volcano", "place": "火山",
		},
	}


func _test_catalog() -> void:
	var catalog := SAG.load_catalog()
	var errors := SAG.validate_catalog(catalog)
	_check("物語カタログは感情構造の検算を通る", errors.is_empty(), str(errors))
	var arcs: Array = catalog.get("arcs", [])
	_check("六つの中核シナリオを持つ", arcs.size() == 6)
	var fallback_combinations_ok := true
	for arc in arcs:
		var combinations := 1
		for key in SAG.SKIN_KEYS:
			combinations *= arc.get("skin", {}).get(key, []).size()
		fallback_combinations_ok = fallback_combinations_ok and combinations >= 81
	_check("各骨格がAIなしでも81通り以上の表層を持つ",
		fallback_combinations_ok)


func _test_all_arcs() -> void:
	for raw_arc in SAG.load_catalog().get("arcs", []):
		var arc_id := String(raw_arc.get("id", ""))
		var story := SAG.generate(_sample_facts(), DetRng.new(100 + _passed), arc_id)
		_check("%s は六拍の物語として成立" % arc_id,
			bool(story.get("valid", false)), str(story.get("errors", [])))
		_check("%s は導入から後日談まで順番を守る" % arc_id,
			_phases(story) == SAG.PHASES, str(_phases(story)))
		_check("%s は三つの代償つき結末を持つ" % arc_id,
			story.choices.size() == 3 and story.endings.size() == 3)
		_check("%s は三種類の失敗を終盤へ持ち越す" % arc_id,
			story.fail_forward.size() == SAG.FAILURE_IDS.size())


func _test_determinism_and_variety() -> void:
	var a := SAG.generate(_sample_facts(), DetRng.new(4242))
	var b := SAG.generate(_sample_facts(), DetRng.new(4242))
	_check("同じ種から同じ物語・配置・表層が出る",
		JSON.stringify(a) == JSON.stringify(b))

	var seen := {}
	for seed_value in range(1, 100):
		var story := SAG.generate(_sample_facts(), DetRng.new(seed_value))
		seen[String(story.get("arc_id", ""))] = true
	_check("種を変えると六つの骨格がすべて出る", seen.size() == 6,
		str(seen.keys()))

	var surfaces := {}
	for seed_value in range(1, 50):
		var story := SAG.generate(
			_sample_facts(), DetRng.new(seed_value), "nameless_machine"
		)
		surfaces[JSON.stringify(story.skin)] = true
	_check("同じ骨格にも十分な表層差が出る", surfaces.size() >= 20,
		"surfaces=%d" % surfaces.size())


func _test_world_binding() -> void:
	var valid := true
	var failures: Array = []
	for seed_value in range(1, 32):
		var world := WorldGenerator.generate(DetRng.new(seed_value * 977))
		var story := SAG.generate_for_world(world, DetRng.new(seed_value * 131))
		if not bool(story.get("valid", false)):
			valid = false
			failures.append({"seed": seed_value, "errors": story.get("errors", [])})
	_check("現行の三十一世界すべてへ六拍を割り当てられる", valid,
		str(failures))

	var sample := SAG.generate(
		_sample_facts(), DetRng.new(55), "last_message"
	)
	var site_ids := {}
	var ordered_danger: Array[int] = []
	for beat in sample.beats:
		if String(beat.phase) != "epilogue":
			site_ids[String(beat.site_id)] = true
		ordered_danger.append(int(beat.danger))
	_check("複数の土地を巡って城へ到達する", site_ids.size() >= 5,
		str(site_ids.keys()))
	_check("最終決戦は危険度十の城", int(sample.beats[4].danger) == 10)


func _test_fail_forward() -> void:
	var all_reach := true
	var all_have_changed_context := true
	for raw_arc in SAG.load_catalog().get("arcs", []):
		var story := SAG.generate(
			_sample_facts(), DetRng.new(700), String(raw_arc.get("id", ""))
		)
		for choice in story.choices:
			var ending := SAG.resolve_ending(
				story, String(choice.id), SAG.FAILURE_IDS
			)
			all_reach = (
				all_reach
				and bool(ending.reaches_epilogue)
				and String(ending.line) != ""
				and String(ending.promise_state) in SAG.PROMISE_STATES
			)
			all_have_changed_context = (
				all_have_changed_context
				and ending.setback_changes.size() == SAG.FAILURE_IDS.size()
			)
		var fallback := SAG.resolve_ending(story, "unknown_choice", [])
		all_reach = (
			all_reach
			and bool(fallback.reaches_epilogue)
			and String(fallback.choice_id) == String(story.fallback_choice)
		)
	_check("全骨格・全選択・未知入力が必ず後日談へ到達する", all_reach)
	_check("三つの失敗は脱落でなく結末の文脈へ変換される",
		all_have_changed_context)


func _test_ai_boundary() -> void:
	var fallback := SAG.generate(
		_sample_facts(), DetRng.new(87), "nameless_machine"
	)
	var original_choices = fallback.choices.duplicate(true)
	var original_endings = fallback.endings.duplicate(true)
	var candidate := {
		"skin": {
			"title": "名を得た機兵",
			"anchor_name": "機兵7",
			"motif": "<命令>",
			"home_name": "ベホマの町",
		},
		"choices": [{"id": "win", "ending_id": "perfect"}],
		"endings": {"perfect": {"tone": "happy"}},
		"fail_forward": [],
	}
	var merged := SAG.apply_ai_skin(fallback, candidate)
	_check("正しいAI題名だけを採用する", merged.skin.title == "名を得た機兵")
	_check("数字入りの人物名はfallbackへ戻す",
		merged.skin.anchor_name == fallback.skin.anchor_name)
	_check("記号入りのモチーフはfallbackへ戻す",
		merged.skin.motif == fallback.skin.motif)
	_check("禁止語入りの故郷名はfallbackへ戻す",
		merged.skin.home_name == fallback.skin.home_name)
	_check("AI変更後は採用した題名以外の物語構造を保つ",
		merged.choices == original_choices and merged.endings.keys() == original_endings.keys())
	_check("人物名の変更が全ビートの同一人物へ反映される",
		String(merged.skin.anchor_name) in String(merged.beats[0].line)
		and String(merged.skin.anchor_name) in String(merged.beats[4].line))
	_check("棄却理由を項目ごとに残す", merged.rejected.size() == 3,
		str(merged.rejected))

	var facts_json := JSON.stringify(SAG.facts_for_ai(fallback))
	var leaks := [
		"story_id", "arc_id", "site_id", "choices", "endings",
		"fail_forward", "fallback_choice", "ending_id",
	]
	var clean := true
	for key in leaks:
		if "\"%s\":" % key in facts_json:
			clean = false
	_check("AIへ選択・結末・失敗条件・内部IDを渡さない", clean, facts_json)
	_check("AI入力は四つのfallbackと上限を持つ",
		SAG.facts_for_ai(fallback).slots.size() == SAG.SKIN_KEYS.size())


func _phases(story: Dictionary) -> Array:
	var out: Array = []
	for beat in story.get("beats", []):
		out.append(String(beat.get("phase", "")))
	return out
