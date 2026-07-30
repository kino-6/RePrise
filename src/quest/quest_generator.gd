class_name QuestGenerator
extends RefCounted

## 1 つの世界に 1 本のクエスト骨格を与える。
##
## AI はここへ入れない。構造・配置・正解・城の解放条件は DetRng だけで決める。
## AI に渡してよいのは facts_for_ai() が返す表示用の事実だけ。

const SCHEMA_VERSION := 1

const LOW := "low"
const MID := "mid"
const HIGH := "high"
const BANDS := [LOW, MID, HIGH]
const BAND_CENTER := {LOW: 3, MID: 6, HIGH: 9}

const THREE_SEALS := "three_seals"
const RELAY_FLAME := "relay_flame"
const TWO_PACTS := "two_pacts"
const TRUE_RELIC := "true_relic"
const ARCHETYPE_IDS := [THREE_SEALS, RELAY_FLAME, TWO_PACTS, TRUE_RELIC]


## WorldMap から、クエストが必要とする事実だけを抜く。
## 位置そのものではなく安定した site id を持たせるので、表示文とロジックが混ざらない。
static func facts_from_world(world: WorldMap, boss_kind: String = "sovereign") -> Dictionary:
	var towns: Array = []
	var caves: Array = []
	var castle: Dictionary = {}
	for raw_pos in world.sites:
		var pos: Vector2i = raw_pos
		var site: Dictionary = world.sites[pos]
		var kind := String(site.get("kind", ""))
		var entry := {
			"id": "%s:%d" % [kind, int(site.get("index", 0))],
			"kind": kind,
			"index": int(site.get("index", 0)),
			"danger": int(site.get("danger", world.danger_at(pos.x, pos.y))),
			"biome": String(site.get("biome", world.biome_id_at(pos.x, pos.y))),
			"place": String(site.get("place", world.biome_name_at(pos.x, pos.y))),
		}
		match kind:
			"town":
				towns.append(entry)
			"cave":
				caves.append(entry)
			"castle":
				castle = entry
	_sort_sites(towns)
	_sort_sites(caves)
	var preplaced_seals: Array = []
	for seal in world.seals:
		var pos: Vector2i = seal.get("pos", Vector2i(-1, -1))
		var site: Dictionary = world.site_at(pos)
		if String(site.get("kind", "")) != "cave":
			continue
		preplaced_seals.append({
			"id": "cave:%d" % int(site.get("index", 0)),
			"kind": "cave",
			"index": int(site.get("index", 0)),
			"danger": int(seal.get("danger", site.get("danger", 1))),
			"band": String(seal.get("band", "")),
			"biome": String(site.get("biome", world.biome_id_at(pos.x, pos.y))),
			"place": String(site.get("place", world.biome_name_at(pos.x, pos.y))),
			"fixed_name": String(seal.get("name", "")),
			"fixed_reason": String(seal.get("why", "")),
		})
	return {
		"world_id": "world",
		"towns": towns,
		"caves": caves,
		"castle": castle,
		"boss_kind": boss_kind,
		"preplaced_seals": preplaced_seals,
	}


static func generate_for_world(
	world: WorldMap, rng: DetRng, forced_archetype: String = ""
) -> Dictionary:
	return generate(facts_from_world(world), rng, forced_archetype)


## world_facts の形:
## {
##   "world_id": String,
##   "towns": [{"id", "danger", "biome", "place"}, ...],
##   "caves": [{"id", "danger", "biome", "place"}, ...],
##   "castle": {"id", "danger", "biome", "place"},
##   "boss_kind": String,
## }
static func generate(
	world_facts: Dictionary, rng: DetRng, forced_archetype: String = ""
) -> Dictionary:
	var fact_errors := validate_world_facts(world_facts)
	if not fact_errors.is_empty():
		return {
			"schema": SCHEMA_VERSION,
			"valid": false,
			"errors": fact_errors,
			"nodes": [],
		}

	var archetype := forced_archetype
	if archetype == "":
		archetype = String(ARCHETYPE_IDS[rng.range_i(0, ARCHETYPE_IDS.size() - 1)])
	if archetype not in ARCHETYPE_IDS:
		return {
			"schema": SCHEMA_VERSION,
			"valid": false,
			"errors": ["unknown archetype: %s" % archetype],
			"nodes": [],
		}

	var binding := _bind_sites(world_facts, rng, archetype)
	var quest := _base_quest(world_facts, archetype)
	match archetype:
		THREE_SEALS:
			_build_three_seals(quest, binding)
		RELAY_FLAME:
			_build_relay_flame(quest, binding)
		TWO_PACTS:
			_build_two_pacts(quest, binding, rng)
		TRUE_RELIC:
			_build_true_relic(quest, binding, rng)

	var errors := validate_quest(quest)
	quest["valid"] = errors.is_empty()
	quest["errors"] = errors
	return quest


static func _base_quest(world_facts: Dictionary, archetype: String) -> Dictionary:
	var castle: Dictionary = world_facts.get("castle", {})
	return {
		"schema": SCHEMA_VERSION,
		"quest_id": "%s:%s" % [String(world_facts.get("world_id", "world")), archetype],
		"archetype": archetype,
		"boss_kind": String(world_facts.get("boss_kind", "sovereign")),
		"castle_site_id": String(castle.get("id", "castle:0")),
		"nodes": [],
		"gate": {},
		"decision": "",
	}


static func _build_three_seals(quest: Dictionary, binding: Dictionary) -> void:
	var objective_ids: Array[String] = []
	for band in BANDS:
		var objective_id := "seal_%s" % band
		objective_ids.append(objective_id)
		quest.nodes.append(_node(
			objective_id, "break_seal", binding["cave_%s" % band], band,
			"seal_%s" % band
		))
		quest.nodes.append(_rumor(
			"rumor_%s" % band, binding["town_%s" % band], band,
			objective_id, "location"
		))
	quest.gate = {"mode": "all", "nodes": objective_ids, "count": objective_ids.size()}
	quest.decision = "free_order"


static func _build_relay_flame(quest: Dictionary, binding: Dictionary) -> void:
	var source := _node(
		"recover_source", "recover", binding.cave_low, LOW, "relay_source"
	)
	var safe := _node(
		"temper_safe", "attune", binding.town_mid, MID, "relay_safe"
	)
	safe.requires = ["recover_source"]
	safe["path_group"] = "temper"
	safe["mechanic"] = "long_route"

	var risky := _node(
		"temper_risky", "trial", binding.cave_mid, MID, "relay_risky"
	)
	risky.requires = ["recover_source"]
	risky["path_group"] = "temper"
	risky["mechanic"] = "elite_fight"

	var beacon := _node(
		"light_beacon", "activate", binding.cave_high, HIGH, "relay_beacon"
	)
	beacon.requires_any = ["temper_safe", "temper_risky"]

	quest.nodes.append_array([source, safe, risky, beacon])
	quest.nodes.append(_rumor(
		"rumor_source", binding.town_low, LOW, "recover_source", "location"
	))
	quest.nodes.append(_rumor(
		"rumor_choice", binding.town_high, HIGH, "temper_safe", "choice"
	))
	quest.gate = {"mode": "all", "nodes": ["light_beacon"], "count": 1}
	quest.decision = "safe_or_risky_route"


static func _build_two_pacts(
	quest: Dictionary, binding: Dictionary, rng: DetRng
) -> void:
	var aspects := ["venom", "haste", "armor"]
	rng.shuffle(aspects)
	var objective_ids: Array[String] = []
	for i in BANDS.size():
		var band: String = BANDS[i]
		var objective_id := "pact_%s" % band
		objective_ids.append(objective_id)
		var node := _node(
			objective_id, "defeat_guardian", binding["cave_%s" % band], band,
			"pact_%s" % band
		)
		# 倒さなかった守護者の性質が城の主に残る。対応は Script が決める。
		node["boss_aspect"] = aspects[i]
		quest.nodes.append(node)
		quest.nodes.append(_rumor(
			"rumor_%s" % band, binding["town_%s" % band], band,
			objective_id, "boss_aspect"
		))
	quest.gate = {"mode": "count", "nodes": objective_ids, "count": 2}
	quest.decision = "choose_two_boss_aspects"


static func _build_true_relic(
	quest: Dictionary, binding: Dictionary, rng: DetRng
) -> void:
	var objective_ids: Array[String] = []
	for band in BANDS:
		var objective_id := "candidate_%s" % band
		objective_ids.append(objective_id)
		var node := _node(
			objective_id, "search_relic", binding["cave_%s" % band], band,
			"relic_%s" % band
		)
		node["is_true"] = false
		node["mandatory"] = false
		quest.nodes.append(node)

	var truth_index := rng.range_i(0, objective_ids.size() - 1)
	var truth_id: String = objective_ids[truth_index]
	for node in quest.nodes:
		if String(node.get("id", "")) == truth_id:
			node["is_true"] = true
			node["mandatory"] = true

	var false_ids := objective_ids.duplicate()
	false_ids.erase(truth_id)
	quest.nodes.append(_rumor(
		"rumor_false_a", binding.town_low, LOW, String(false_ids[0]), "false_candidate"
	))
	quest.nodes.append(_rumor(
		"rumor_false_b", binding.town_mid, MID, String(false_ids[1]), "false_candidate"
	))
	quest.gate = {"mode": "all", "nodes": [truth_id], "count": 1}
	quest["truth_node"] = truth_id
	quest.decision = "investigate_or_bruteforce"


static func _node(
	id: String, kind: String, site: Dictionary, band: String, text_key: String
) -> Dictionary:
	return {
		"id": id,
		"role": "objective",
		"kind": kind,
		"site_id": String(site.get("id", "")),
		"danger": int(site.get("danger", 1)),
		"band": band,
		"biome": String(site.get("biome", "")),
		"place": String(site.get("place", "")),
		"text_key": text_key,
		"fixed_name": String(site.get("fixed_name", "")),
		"fixed_reason": String(site.get("fixed_reason", "")),
		"requires": [],
		"requires_any": [],
		"mandatory": true,
	}


static func _rumor(
	id: String, site: Dictionary, band: String, reveals: String, clue_kind: String
) -> Dictionary:
	return {
		"id": id,
		"role": "rumor",
		"kind": "talk",
		"site_id": String(site.get("id", "")),
		"danger": int(site.get("danger", 1)),
		"band": band,
		"biome": String(site.get("biome", "")),
		"place": String(site.get("place", "")),
		"text_key": id,
		"reveals": reveals,
		"clue_kind": clue_kind,
		"requires": [],
		"requires_any": [],
		"mandatory": false,
	}


## AI へ渡す表示用の事実。site_id・正解・依存関係・ボス効果は渡さない。
## AI が返す配列はこの順番に対応するが、構造の ID を返させない。
static func facts_for_ai(quest: Dictionary) -> Dictionary:
	var objectives: Array = []
	var rumor_count := 0
	for node in quest.get("nodes", []):
		if String(node.get("role", "")) == "objective":
			objectives.append({
				"kind": String(node.get("kind", "")),
				"band": String(node.get("band", "")),
				"biome": String(node.get("biome", "")),
				"place": String(node.get("place", "")),
			})
		elif String(node.get("role", "")) == "rumor":
			rumor_count += 1
	return {
		"archetype": String(quest.get("archetype", "")),
		"decision": String(quest.get("decision", "")),
		"boss_kind": String(quest.get("boss_kind", "")),
		"objectives": objectives,
		"rumor_flavor_count": rumor_count,
	}


static func validate_world_facts(world_facts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var towns: Array = world_facts.get("towns", [])
	var caves: Array = world_facts.get("caves", [])
	if towns.size() < 3:
		errors.append("quest needs at least 3 towns")
	if caves.size() < 3:
		errors.append("quest needs at least 3 caves")
	var castle: Dictionary = world_facts.get("castle", {})
	if String(castle.get("id", "")) == "":
		errors.append("quest needs one castle")
	for site in towns + caves:
		if String(site.get("id", "")) == "":
			errors.append("site id is empty")
	return errors


static func validate_quest(quest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(quest.get("schema", 0)) != SCHEMA_VERSION:
		errors.append("unsupported schema")
	if String(quest.get("archetype", "")) not in ARCHETYPE_IDS:
		errors.append("unknown archetype")
	if String(quest.get("decision", "")) == "":
		errors.append("quest has no meaningful decision")

	var nodes: Array = quest.get("nodes", [])
	var by_id := {}
	var bands := {}
	for node in nodes:
		var id := String(node.get("id", ""))
		if id == "":
			errors.append("node id is empty")
			continue
		if by_id.has(id):
			errors.append("duplicate node id: %s" % id)
		by_id[id] = node
		if String(node.get("site_id", "")) == "":
			errors.append("node has no site: %s" % id)
		if String(node.get("role", "")) == "objective":
			bands[String(node.get("band", ""))] = true

	for node in nodes:
		var id := String(node.get("id", ""))
		for dep in node.get("requires", []) + node.get("requires_any", []):
			if not by_id.has(String(dep)):
				errors.append("%s depends on missing %s" % [id, dep])
	if _has_cycle(by_id):
		errors.append("quest graph has a cycle")

	for band in BANDS:
		if not bands.has(band):
			errors.append("quest has no objective in band: %s" % band)

	var gate: Dictionary = quest.get("gate", {})
	var mode := String(gate.get("mode", ""))
	var gate_nodes: Array = gate.get("nodes", [])
	if mode not in ["all", "count"]:
		errors.append("invalid gate mode")
	if gate_nodes.is_empty():
		errors.append("gate has no requirements")
	for id in gate_nodes:
		if not by_id.has(String(id)):
			errors.append("gate depends on missing %s" % id)
	var count := int(gate.get("count", 0))
	if count < 1 or count > gate_nodes.size():
		errors.append("invalid gate count")
	return errors


static func _has_cycle(by_id: Dictionary) -> bool:
	var state := {}
	for id in by_id:
		if _visit(String(id), by_id, state):
			return true
	return false


static func _visit(id: String, by_id: Dictionary, state: Dictionary) -> bool:
	var mark := int(state.get(id, 0))
	if mark == 1:
		return true
	if mark == 2:
		return false
	state[id] = 1
	var node: Dictionary = by_id[id]
	for dep in node.get("requires", []) + node.get("requires_any", []):
		var dep_id := String(dep)
		if by_id.has(dep_id) and _visit(dep_id, by_id, state):
			return true
	state[id] = 2
	return false


static func _bind_sites(
	world_facts: Dictionary, rng: DetRng, archetype: String
) -> Dictionary:
	var towns: Array = world_facts.get("towns", []).duplicate(true)
	var caves: Array = world_facts.get("caves", []).duplicate(true)
	var preplaced: Array = world_facts.get("preplaced_seals", [])
	var out := {}
	for band in BANDS:
		out["town_%s" % band] = _take_nearest(towns, int(BAND_CENTER[band]), rng)
		var bound: Dictionary = {}
		if archetype == THREE_SEALS:
			for seal in preplaced:
				if String(seal.get("band", "")) == band:
					bound = seal
					break
		if bound.is_empty():
			bound = _take_nearest(caves, int(BAND_CENTER[band]), rng)
		else:
			for i in range(caves.size() - 1, -1, -1):
				if String(caves[i].get("id", "")) == String(bound.get("id", "")):
					caves.remove_at(i)
					break
		out["cave_%s" % band] = bound
	return out


static func _take_nearest(sites: Array, target: int, rng: DetRng) -> Dictionary:
	var best_distance := 999
	var candidates: Array[int] = []
	for i in sites.size():
		var distance := absi(int(sites[i].get("danger", 1)) - target)
		if distance < best_distance:
			best_distance = distance
			candidates = [i]
		elif distance == best_distance:
			candidates.append(i)
	var picked_index: int = candidates[rng.range_i(0, candidates.size() - 1)]
	var picked: Dictionary = sites[picked_index]
	sites.remove_at(picked_index)
	return picked


static func _sort_sites(sites: Array) -> void:
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var danger_a := int(a.get("danger", 1))
		var danger_b := int(b.get("danger", 1))
		if danger_a != danger_b:
			return danger_a < danger_b
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
