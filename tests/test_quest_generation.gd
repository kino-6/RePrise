extends SceneTree

## クエスト骨格と AI 文言の境界を検査する。
##
##   godot --headless --script res://tests/test_quest_generation.gd

const QG = preload("res://src/quest/quest_generator.gd")
const QT = preload("res://src/quest/quest_text.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== クエスト生成テスト ===")
	_test_all_archetypes()
	_test_determinism_and_variety()
	_test_current_worlds_can_bind()
	_test_ai_boundary()
	_test_invalid_world_is_rejected()
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
		"boss_kind": "war_engine",
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


func _test_all_archetypes() -> void:
	for archetype in QG.ARCHETYPE_IDS:
		var quest: Dictionary = QG.generate(
			_sample_facts(), DetRng.new(700 + _passed), String(archetype)
		)
		_check("%s は検算を通る" % archetype, bool(quest.get("valid", false)),
			str(quest.get("errors", [])))
		_check("%s は低・中・高の目的を持つ" % archetype,
			_has_all_bands(quest))
		_check("%s は判断を持つ" % archetype,
			String(quest.get("decision", "")) != "")

	var seals: Dictionary = QG.generate(
		_sample_facts(), DetRng.new(1), QG.THREE_SEALS
	)
	_check("三つの封は全 3 目的で城が開く",
		String(seals.gate.get("mode", "")) == "all"
		and int(seals.gate.get("count", 0)) == 3)

	var relay: Dictionary = QG.generate(
		_sample_facts(), DetRng.new(2), QG.RELAY_FLAME
	)
	var beacon := _node(relay, "light_beacon")
	_check("継火は安全路か危険路のどちらでも終盤へ進める",
		beacon.get("requires_any", []).size() == 2)

	var pacts: Dictionary = QG.generate(
		_sample_facts(), DetRng.new(3), QG.TWO_PACTS
	)
	var aspects := {}
	for node in pacts.nodes:
		if String(node.get("role", "")) == "objective":
			aspects[String(node.get("boss_aspect", ""))] = true
	_check("盟約は三つから二つを選ぶ",
		String(pacts.gate.get("mode", "")) == "count"
		and int(pacts.gate.get("count", 0)) == 2)
	_check("残すボス特性は三つとも異なる", aspects.size() == 3)

	var relic: Dictionary = QG.generate(
		_sample_facts(), DetRng.new(4), QG.TRUE_RELIC
	)
	var truths := 0
	var false_clues := 0
	for node in relic.nodes:
		if bool(node.get("is_true", false)):
			truths += 1
		if String(node.get("clue_kind", "")) == "false_candidate":
			false_clues += 1
	_check("遺物の正解は一つ", truths == 1)
	_check("二つの証言で偽物を二つ落とせる", false_clues == 2)


func _test_determinism_and_variety() -> void:
	var a := QG.generate(_sample_facts(), DetRng.new(4242))
	var b := QG.generate(_sample_facts(), DetRng.new(4242))
	_check("同じ種から同じクエスト骨格が出る",
		JSON.stringify(a) == JSON.stringify(b))

	var seen := {}
	for seed_value in range(1, 80):
		var quest := QG.generate(_sample_facts(), DetRng.new(seed_value))
		seen[String(quest.get("archetype", ""))] = true
	_check("種を変えると四つの型がすべて出る",
		seen.size() == QG.ARCHETYPE_IDS.size(), str(seen.keys()))

	var text_a := QT.fallback(a, DetRng.new(99))
	var text_b := QT.fallback(b, DetRng.new(99))
	_check("同じ種から同じ代替文が出る", text_a == text_b)


func _test_current_worlds_can_bind() -> void:
	var valid := true
	var seal_binding_matches := true
	var failures: Array = []
	for seed_value in range(1, 32):
		var world := WorldGenerator.generate(DetRng.new(seed_value * 977))
		var quest := QG.generate_for_world(world, DetRng.new(seed_value * 131))
		if not bool(quest.get("valid", false)):
			valid = false
			failures.append({"seed": seed_value, "errors": quest.get("errors", [])})
		var seal_quest := QG.generate_for_world(
			world, DetRng.new(seed_value * 131), QG.THREE_SEALS
		)
		var expected := {}
		for seal in world.seals:
			var site: Dictionary = world.site_at(seal.get("pos", Vector2i(-1, -1)))
			expected["cave:%d" % int(site.get("index", -1))] = true
		var actual := {}
		for node in seal_quest.get("nodes", []):
			if String(node.get("role", "")) == "objective":
				actual[String(node.get("site_id", ""))] = true
		if actual != expected:
			seal_binding_matches = false
	_check("現行の 31 世界すべてにクエストを結び付けられる", valid, str(failures))
	_check("三つの封型は現行世界に置かれた封と同じ洞を使う", seal_binding_matches)


func _test_ai_boundary() -> void:
	var quest := QG.generate(
		_sample_facts(), DetRng.new(18), QG.TRUE_RELIC
	)
	var fallback := QT.fallback(quest, DetRng.new(77))
	var candidate := {
		"world_name": "灰雨の環",
		"quest_title": "<script>",
		"boss_name": "ベホマの王",
		"objective_names": ["翠の輪", "翠の輪", "第3の印"],
		"objective_reasons": ["旅人の記憶をたどる。"],
		"rumor_flavor": ["古い鐘が鳴ったそうだ。"],
		"gate": {"mode": "all", "count": 0},
		"truth_node": "candidate_low",
	}
	var merged := QT.apply_ai(fallback, candidate)
	_check("正しい AI 項目だけ採用する", merged.world_name == "灰雨の環")
	_check("記号と英字を含む題は代替文へ戻す",
		merged.quest_title == fallback.quest_title)
	_check("禁止語を含む主名は代替文へ戻す",
		merged.boss_name == fallback.boss_name)
	_check("重複した目的名はその項目だけ戻す",
		merged.objective_names[1] == fallback.objective_names[1])
	_check("数字を含む目的名はその項目だけ戻す",
		merged.objective_names[2] == fallback.objective_names[2])
	_check("AI の gate と正解指定は出力へ混ざらない",
		not merged.has("gate") and not merged.has("truth_node"))
	_check("落とした理由が記録される", merged.rejected.size() >= 4)

	var facts_json := JSON.stringify(QG.facts_for_ai(quest))
	var leaks := ["site_id", "truth_node", "is_true", "boss_aspect", "requires", "gate"]
	var clean := true
	for key in leaks:
		if "\"%s\":" % key in facts_json:
			clean = false
	_check("AI へ正解・依存・効果を渡さない", clean, facts_json)

	var lines := QT.critical_lines(quest, merged)
	_check("攻略に必要な証言は Script が二本作る", lines.size() == 2, str(lines))
	_check("証言の事実は AI の自由文に依存しない",
		"まことの遺物ではない" in lines[0]
		and "まことの遺物ではない" in lines[1])


func _test_invalid_world_is_rejected() -> void:
	var facts := _sample_facts()
	facts.towns = [facts.towns[0]]
	facts.caves = [facts.caves[0]]
	var quest := QG.generate(facts, DetRng.new(1))
	_check("拠点地が足りない世界を黙って通さない",
		not bool(quest.get("valid", true))
		and quest.get("errors", []).size() >= 2)


func _has_all_bands(quest: Dictionary) -> bool:
	var found := {}
	for node in quest.get("nodes", []):
		if String(node.get("role", "")) == "objective":
			found[String(node.get("band", ""))] = true
	return found.has(QG.LOW) and found.has(QG.MID) and found.has(QG.HIGH)


func _node(quest: Dictionary, id: String) -> Dictionary:
	for node in quest.get("nodes", []):
		if String(node.get("id", "")) == id:
			return node
	return {}
