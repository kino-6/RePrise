class_name StoryArcGenerator
extends RefCounted

## 一世界で完結する、感情的な連続シナリオを決定的に生成する。
##
## 「誰を守るか」「何を約束したか」「どの代償を選ぶか」は Script が固定する。
## AI が触れるのは題名・人物名・反復モチーフ・故郷名だけ。途中の失敗は
## fail_forward により別の文脈へ変換され、終幕そのものを消さない。

const DATA_PATH := "res://data/story_arcs.json"
const SCHEMA_VERSION := 1
const PHASES := ["hook", "bond", "reversal", "choice", "finale", "epilogue"]
const SKIN_KEYS := ["title", "anchor_name", "motif", "home_name"]
const SITE_ROLES := [
	"town_low", "town_mid", "town_high",
	"cave_low", "cave_mid", "cave_high", "castle",
]
const FAILURE_IDS := ["bond_missed", "motif_lost", "anchor_falls"]
const ENDING_TONES := ["hopeful", "bittersweet", "grave"]
const PROMISE_STATES := ["kept", "transformed", "broken_honestly"]
const BAND_CENTER := {"low": 3, "mid": 6, "high": 9}
const BAND_RANGE := {
	"low": [1, 4],
	"mid": [4, 7],
	"high": [7, 10],
}
const BANNED := [
	"ドラゴンクエスト", "ファイナルファンタジー", "クロノトリガー",
	"メラゾーマ", "ベホマ", "ホイミ", "ケアル", "ファイガ",
	"プロンプト", "思考過程", "システムメッセージ", "JSON",
]

static var _cache: Dictionary = {}


static func load_catalog() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return {
			"version": 0,
			"arcs": [],
			"load_error": "open_failed:%s" % FileAccess.get_open_error(),
		}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"version": 0, "arcs": [], "load_error": "invalid_json"}
	_cache = parsed
	return _cache


static func generate_for_world(
	world: WorldMap, rng: DetRng, forced_arc: String = ""
) -> Dictionary:
	return generate(QuestGenerator.facts_from_world(world), rng, forced_arc)


static func generate(
	world_facts: Dictionary, rng: DetRng, forced_arc: String = "",
	catalog: Dictionary = {}
) -> Dictionary:
	var source := load_catalog() if catalog.is_empty() else catalog
	var fact_errors := _validate_world_facts(world_facts)
	if not fact_errors.is_empty():
		return {
			"schema": SCHEMA_VERSION,
			"valid": false,
			"errors": fact_errors,
			"beats": [],
		}

	var arcs: Array = source.get("arcs", [])
	var blueprint: Dictionary = {}
	if forced_arc == "":
		if not arcs.is_empty():
			blueprint = rng.pick(arcs)
	else:
		for raw_arc in arcs:
			if String(raw_arc.get("id", "")) == forced_arc:
				blueprint = raw_arc
				break
	if blueprint.is_empty():
		return {
			"schema": SCHEMA_VERSION,
			"valid": false,
			"errors": ["unknown story arc: %s" % forced_arc],
			"beats": [],
		}

	var skin := {}
	for key in SKIN_KEYS:
		var pool: Array = blueprint.get("skin", {}).get(key, [])
		skin[key] = String(rng.pick(pool)) if not pool.is_empty() else ""
	var bindings := _bind_sites(world_facts, rng)
	var story := {
		"schema": SCHEMA_VERSION,
		"story_id": "%s:%s" % [
			String(world_facts.get("world_id", "world")),
			String(blueprint.get("id", "")),
		],
		"arc_id": String(blueprint.get("id", "")),
		"theme": String(blueprint.get("theme", "")),
		"anchor_role": String(blueprint.get("anchor_role", "")),
		"promise": String(blueprint.get("promise", "")),
		"conflict": String(blueprint.get("conflict", "")),
		"skin": skin,
		"ai_slots": blueprint.get("ai_slots", {}).duplicate(true),
		"beats": [],
		"choices": blueprint.get("choices", []).duplicate(true),
		"endings": blueprint.get("endings", {}).duplicate(true),
		"fallback_choice": String(blueprint.get("fallback_choice", "")),
		"fail_forward": blueprint.get("fail_forward", []).duplicate(true),
		"rejected": [],
	}
	for raw_beat in blueprint.get("beats", []):
		var beat: Dictionary = raw_beat.duplicate(true)
		var site_role := String(beat.get("site_role", ""))
		var site: Dictionary = bindings.get(site_role, {})
		beat["site_id"] = String(site.get("id", ""))
		beat["danger"] = int(site.get("danger", 10 if site_role == "castle" else 1))
		beat["biome"] = String(site.get("biome", ""))
		beat["place"] = String(site.get("place", ""))
		beat["line_template"] = String(beat.get("line", ""))
		story.beats.append(beat)
	for ending_id in story.endings:
		var ending: Dictionary = story.endings[ending_id]
		ending["line_template"] = String(ending.get("line", ""))
		story.endings[ending_id] = ending
	_render(story)
	var errors := validate_story(story)
	story["valid"] = errors.is_empty()
	story["errors"] = errors
	return story


## AI に渡してよい表示用の事実。選択肢・結末・失敗条件・IDは含めない。
static func facts_for_ai(story: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	var skin: Dictionary = story.get("skin", {})
	var limits: Dictionary = story.get("ai_slots", {})
	for key in SKIN_KEYS:
		slots.append({
			"key": key,
			"max_length": int(limits.get(key, 0)),
			"fallback": String(skin.get(key, "")),
		})
	var biomes: Array[String] = []
	for beat in story.get("beats", []):
		var biome := String(beat.get("biome", ""))
		if biome != "" and biome not in biomes:
			biomes.append(biome)
	return {
		"theme": String(story.get("theme", "")),
		"anchor_role": String(story.get("anchor_role", "")),
		"promise": String(story.get("promise", "")),
		"conflict": String(story.get("conflict", "")),
		"biomes": biomes,
		"slots": slots,
	}


## AI 候補を四つの表示項目だけへ適用し、全ビートと結末を再描画する。
static func apply_ai_skin(story: Dictionary, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = story.duplicate(true)
	var current: Dictionary = result.get("skin", {}).duplicate(true)
	var limits: Dictionary = result.get("ai_slots", {})
	var rejected: Array = []
	var proposed: Dictionary = candidate.get("skin", candidate)
	for key in SKIN_KEYS:
		if not proposed.has(key):
			continue
		var value := String(proposed.get(key, "")).strip_edges()
		var reason := _invalid_reason(value, int(limits.get(key, 0)))
		if reason == "":
			current[key] = value
		else:
			rejected.append({"field": key, "reason": reason})
	result["skin"] = current
	result["rejected"] = rejected
	_render(result)
	return result


## 選んだ結末と途中の失敗を一つの終幕へまとめる。
##
## 未知の選択肢でも fallback_choice へ落ちるため、物語は必ず終幕へ到達する。
static func resolve_ending(
	story: Dictionary, choice_id: String, setbacks: Array = []
) -> Dictionary:
	var actual_choice := choice_id
	var choices: Array = story.get("choices", [])
	var choice: Dictionary = _choice_by_id(choices, actual_choice)
	if choice.is_empty():
		actual_choice = String(story.get("fallback_choice", ""))
		choice = _choice_by_id(choices, actual_choice)
	var ending_id := String(choice.get("ending_id", ""))
	var ending: Dictionary = story.get("endings", {}).get(ending_id, {}).duplicate(true)
	var changes: Array[String] = []
	for failure_id in setbacks:
		for rule in story.get("fail_forward", []):
			if String(rule.get("when", "")) == String(failure_id):
				changes.append(String(rule.get("change", "")))
				break
	return {
		"choice_id": actual_choice,
		"ending_id": ending_id,
		"tone": String(ending.get("tone", "")),
		"promise_state": String(ending.get("promise_state", "")),
		"line": String(ending.get("line", "")),
		"setback_changes": changes,
		"reaches_epilogue": not ending.is_empty(),
	}


static func validate_catalog(catalog: Dictionary = {}) -> Array[String]:
	var source := load_catalog() if catalog.is_empty() else catalog
	var errors: Array[String] = []
	if int(source.get("version", 0)) != SCHEMA_VERSION:
		errors.append("version は %d" % SCHEMA_VERSION)
	var arcs = source.get("arcs", null)
	if not arcs is Array:
		return errors + ["arcs が配列ではない"]
	if arcs.size() < 6:
		errors.append("物語骨格は六型以上")
	var ids := {}
	for raw_arc in arcs:
		if not raw_arc is Dictionary:
			errors.append("arc が辞書ではない")
			continue
		var arc: Dictionary = raw_arc
		var arc_id := String(arc.get("id", ""))
		var prefix := arc_id if arc_id != "" else "<no-id>"
		if arc_id == "" or ids.has(arc_id):
			errors.append("%s: id が空か重複" % prefix)
		ids[arc_id] = true
		for key in ["theme", "anchor_role", "promise", "conflict"]:
			if String(arc.get(key, "")).strip_edges() == "":
				errors.append("%s: %s が空" % [prefix, key])
		_validate_skin(prefix, arc, errors)
		_validate_beats(prefix, arc.get("beats", null), errors)
		_validate_choices_and_endings(prefix, arc, errors)
		_validate_fail_forward(prefix, arc.get("fail_forward", null), errors)
	return errors


static func validate_story(story: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(story.get("schema", 0)) != SCHEMA_VERSION:
		errors.append("unsupported story schema")
	if String(story.get("arc_id", "")) == "":
		errors.append("story has no arc")
	var beats: Array = story.get("beats", [])
	if beats.size() != PHASES.size():
		errors.append("story needs six beats")
	for i in mini(beats.size(), PHASES.size()):
		var beat: Dictionary = beats[i]
		if String(beat.get("phase", "")) != PHASES[i]:
			errors.append("story phase order is broken")
		if String(beat.get("site_id", "")) == "":
			errors.append("%s has no site" % String(beat.get("id", "")))
		var rendered_line := String(beat.get("line", ""))
		if rendered_line == "":
			errors.append("%s has no rendered line" % String(beat.get("id", "")))
		elif "{" in rendered_line or "}" in rendered_line:
			errors.append("%s has unresolved placeholder" % String(beat.get("id", "")))
	for ending_id in story.get("endings", {}):
		var ending_line := String(story.endings[ending_id].get("line", ""))
		if ending_line == "" or "{" in ending_line or "}" in ending_line:
			errors.append("%s has invalid ending line" % ending_id)
	var resolved := resolve_ending(story, "", FAILURE_IDS)
	if not bool(resolved.get("reaches_epilogue", false)):
		errors.append("fallback choice does not reach epilogue")
	return errors


static func _bind_sites(world_facts: Dictionary, rng: DetRng) -> Dictionary:
	var bindings := {}
	for kind in ["town", "cave"]:
		var sites: Array = world_facts.get("%ss" % kind, [])
		var used := {}
		for band in ["low", "mid", "high"]:
			var site := _pick_site(sites, band, used, rng)
			bindings["%s_%s" % [kind, band]] = site
			used[String(site.get("id", ""))] = true
	bindings["castle"] = world_facts.get("castle", {}).duplicate(true)
	return bindings


static func _pick_site(
	sites: Array, band: String, used: Dictionary, rng: DetRng
) -> Dictionary:
	var bounds: Array = BAND_RANGE[band]
	var matching: Array = []
	for raw_site in sites:
		var site: Dictionary = raw_site
		var site_id := String(site.get("id", ""))
		var danger := int(site.get("danger", 1))
		if used.has(site_id):
			continue
		if danger >= int(bounds[0]) and danger <= int(bounds[1]):
			matching.append(site)
	if not matching.is_empty():
		return rng.pick(matching).duplicate(true)

	var remaining: Array = []
	for raw_site in sites:
		var site: Dictionary = raw_site
		if not used.has(String(site.get("id", ""))):
			remaining.append(site)
	if remaining.is_empty():
		remaining = sites.duplicate()
	remaining.sort_custom(func(a, b):
		var da := absi(int(a.get("danger", 1)) - int(BAND_CENTER[band]))
		var db := absi(int(b.get("danger", 1)) - int(BAND_CENTER[band]))
		if da == db:
			return String(a.get("id", "")) < String(b.get("id", ""))
		return da < db
	)
	return remaining[0].duplicate(true) if not remaining.is_empty() else {}


static func _render(story: Dictionary) -> void:
	var values: Dictionary = story.get("skin", {}).duplicate(true)
	for beat in story.get("beats", []):
		values["place"] = String(beat.get("place", "その地"))
		beat["line"] = String(beat.get("line_template", beat.get("line", ""))).format(values)
	for ending_id in story.get("endings", {}):
		var ending: Dictionary = story.endings[ending_id]
		ending["line"] = String(
			ending.get("line_template", ending.get("line", ""))
		).format(values)
		story.endings[ending_id] = ending


static func _choice_by_id(choices: Array, choice_id: String) -> Dictionary:
	for raw_choice in choices:
		if String(raw_choice.get("id", "")) == choice_id:
			return raw_choice
	return {}


static func _validate_world_facts(world_facts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if world_facts.get("towns", []).size() < 3:
		errors.append("story needs at least three towns")
	if world_facts.get("caves", []).size() < 3:
		errors.append("story needs at least three caves")
	if String(world_facts.get("castle", {}).get("id", "")) == "":
		errors.append("story needs one castle")
	return errors


static func _validate_skin(
	prefix: String, arc: Dictionary, errors: Array[String]
) -> void:
	var skin = arc.get("skin", null)
	var limits = arc.get("ai_slots", null)
	if not skin is Dictionary or not limits is Dictionary:
		errors.append("%s: skin と ai_slots は辞書" % prefix)
		return
	if skin.size() != SKIN_KEYS.size() or limits.size() != SKIN_KEYS.size():
		errors.append("%s: skin は四項目のみ" % prefix)
	for key in SKIN_KEYS:
		var pool = skin.get(key, null)
		var limit := int(limits.get(key, 0))
		if not pool is Array or pool.size() < 3:
			errors.append("%s: skin.%s は三候補以上" % [prefix, key])
			continue
		for value in pool:
			var reason := _invalid_reason(String(value), limit)
			if reason != "":
				errors.append("%s: skin.%s が不正(%s)" % [prefix, key, reason])


static func _validate_beats(
	prefix: String, beats, errors: Array[String]
) -> void:
	if not beats is Array or beats.size() != PHASES.size():
		errors.append("%s: beats は六拍" % prefix)
		return
	var anchor_count := 0
	var motif_states := {}
	var ids := {}
	for i in beats.size():
		var beat: Dictionary = beats[i]
		var beat_id := String(beat.get("id", ""))
		if beat_id == "" or ids.has(beat_id):
			errors.append("%s: beat id が空か重複" % prefix)
		ids[beat_id] = true
		if String(beat.get("phase", "")) != PHASES[i]:
			errors.append("%s: phase 順が不正" % prefix)
		if String(beat.get("site_role", "")) not in SITE_ROLES:
			errors.append("%s/%s: site_role が不正" % [prefix, beat_id])
		if bool(beat.get("anchor_present", false)):
			anchor_count += 1
		var motif_state := String(beat.get("motif_state", ""))
		if motif_state != "":
			motif_states[motif_state] = true
		var line := String(beat.get("line", ""))
		if line == "":
			errors.append("%s/%s: line が空" % [prefix, beat_id])
	for required_index in [0, 2, 4]:
		var line := String(beats[required_index].get("line", ""))
		if "{anchor_name}" not in line or "{motif}" not in line:
			errors.append("%s: 導入・反転・決戦で人物とモチーフを回収する" % prefix)
	if anchor_count < 4:
		errors.append("%s: 人物が四拍以上に登場する" % prefix)
	if motif_states.size() < 4:
		errors.append("%s: モチーフが四段階以上変化する" % prefix)


static func _validate_choices_and_endings(
	prefix: String, arc: Dictionary, errors: Array[String]
) -> void:
	var choices = arc.get("choices", null)
	var endings = arc.get("endings", null)
	if not choices is Array or choices.size() != 3:
		errors.append("%s: choices は三件" % prefix)
		return
	if not endings is Dictionary or endings.size() != 3:
		errors.append("%s: endings は三件" % prefix)
		return
	var choice_ids := {}
	var ending_ids := {}
	for raw_choice in choices:
		var choice: Dictionary = raw_choice
		var choice_id := String(choice.get("id", ""))
		if choice_id == "" or choice_ids.has(choice_id):
			errors.append("%s: choice id が空か重複" % prefix)
		choice_ids[choice_id] = true
		for key in ["label", "immediate_cost", "preserves", "sacrifices", "ending_id"]:
			if String(choice.get(key, "")).strip_edges() == "":
				errors.append("%s/%s: %s が空" % [prefix, choice_id, key])
		ending_ids[String(choice.get("ending_id", ""))] = true
	for ending_id in endings:
		var ending: Dictionary = endings[ending_id]
		if String(ending.get("tone", "")) not in ENDING_TONES:
			errors.append("%s/%s: tone が不正" % [prefix, ending_id])
		if String(ending.get("promise_state", "")) not in PROMISE_STATES:
			errors.append("%s/%s: promise_state が不正" % [prefix, ending_id])
		if String(ending.get("line", "")).strip_edges() == "":
			errors.append("%s/%s: ending line が空" % [prefix, ending_id])
	if ending_ids.size() != endings.size():
		errors.append("%s: choice と ending が一対一でない" % prefix)
	for ending_id in ending_ids:
		if not endings.has(ending_id):
			errors.append("%s: ending %s が無い" % [prefix, ending_id])
	if not choice_ids.has(String(arc.get("fallback_choice", ""))):
		errors.append("%s: fallback_choice が不正" % prefix)


static func _validate_fail_forward(
	prefix: String, rules, errors: Array[String]
) -> void:
	if not rules is Array or rules.size() != FAILURE_IDS.size():
		errors.append("%s: fail_forward は三件" % prefix)
		return
	var seen := {}
	for raw_rule in rules:
		var rule: Dictionary = raw_rule
		var failure_id := String(rule.get("when", ""))
		if failure_id not in FAILURE_IDS or seen.has(failure_id):
			errors.append("%s: fail_forward id が不正" % prefix)
		seen[failure_id] = true
		var continues_to := String(rule.get("continues_to", ""))
		if continues_to not in ["reversal", "choice", "finale"]:
			errors.append("%s/%s: 継続先が不正" % [prefix, failure_id])
		if String(rule.get("change", "")).strip_edges() == "":
			errors.append("%s/%s: 変化説明が空" % [prefix, failure_id])


static func _invalid_reason(value: String, limit: int) -> String:
	if value == "":
		return "empty"
	if limit < 1 or value.length() > limit:
		return "too_long"
	if "\n" in value or "\r" in value:
		return "line_break"
	for banned in BANNED:
		if banned in value:
			return "banned"
	for i in value.length():
		var code := value.unicode_at(i)
		if code >= 0x30 and code <= 0x39:
			return "number"
		if code >= 0xFF10 and code <= 0xFF19:
			return "number"
		if (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A):
			return "latin"
		if value[i] in ["{", "}", "[", "]", "<", ">"]:
			return "symbol"
	return ""
