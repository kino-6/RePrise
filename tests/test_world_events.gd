extends SceneTree

## 任意イベント32型と AI 表層差し替えの境界を検査する。
##
##   godot --headless --script res://tests/test_world_events.gd

const WEC = preload("res://src/quest/world_event_catalog.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 世界イベント生成テスト ===")
	_test_catalog()
	_test_selection()
	_test_instantiation()
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


func _test_catalog() -> void:
	var catalog := WEC.load_catalog()
	var errors := WEC.validate_catalog(catalog)
	_check("カタログは検算を通る", errors.is_empty(), str(errors))
	var events: Array = catalog.get("events", [])
	_check("任意イベントを32型持つ", events.size() == 32)

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
		_check("%s は8型" % category, int(counts.get(category, 0)) == 8)
	_check("全型がAIなしでも81通り以上の表層を持つ", minimum_combinations_ok)
	_check("全選択肢にコスト・危険・報酬が明示される", every_choice_has_tradeoff)


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

	var seen := {}
	for seed_value in range(1, 80):
		for event_id in _ids(WEC.select_for_world(DetRng.new(seed_value), {}, 4)):
			seen[event_id] = true
	_check("種を変えると32型すべてが抽選対象になる", seen.size() == 32,
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
