class_name WorldEventCatalog
extends RefCounted

## 世界に置く任意イベントのカタログを読み、決定的に抽選する。
##
## choices 以下のコスト・危険・報酬は Script が所有する。AI に渡すのは
## skin の四項目だけで、AI が不在・失敗・不正でも fallback がそのまま使える。

const DATA_PATH := "res://data/world_events.json"
const CATEGORY_ORDER := ["road", "town", "cave", "faction"]
const SKIN_KEYS := ["title", "actor", "cause", "flavor"]
const SITE_KINDS := ["world", "town", "cave"]
const EXPECTED_TOTAL := 64
const EXPECTED_PER_CATEGORY := 16
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
			"events": [],
			"load_error": "open_failed:%s" % FileAccess.get_open_error(),
		}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"version": 0, "events": [], "load_error": "invalid_json"}
	_cache = parsed
	return _cache


static func event_by_id(event_id: String, catalog: Dictionary = {}) -> Dictionary:
	var source := load_catalog() if catalog.is_empty() else catalog
	for event in source.get("events", []):
		if String(event.get("id", "")) == event_id:
			return event
	return {}


## 通常は road / town / cave を一つずつ、count=4 なら faction も一つ選ぶ。
## それ以上は重複なしで全カテゴリから補充する。
static func select_for_world(
	rng: DetRng, context: Dictionary = {}, count: int = 3, catalog: Dictionary = {}
) -> Array[Dictionary]:
	var source := load_catalog() if catalog.is_empty() else catalog
	var events: Array = source.get("events", [])
	var selected: Array[Dictionary] = []
	var selected_ids := {}
	var wanted := clampi(count, 0, events.size())
	var category_order: Array = CATEGORY_ORDER
	match String(context.get("site_kind", "")):
		"town":
			category_order = ["town"]
		"cave":
			category_order = ["cave"]
		"world":
			category_order = ["road", "faction"]
	var broad_context := {}
	if context.has("site_kind"):
		broad_context["site_kind"] = context["site_kind"]

	for category in category_order:
		if selected.size() >= wanted:
			break
		var pool := _eligible(events, category, context, selected_ids)
		if pool.is_empty():
			pool = _eligible(events, category, broad_context, selected_ids)
		if not pool.is_empty():
			var picked: Dictionary = rng.pick(pool)
			selected.append(picked)
			selected_ids[String(picked.get("id", ""))] = true

	if selected.size() < wanted:
		var remainder := _eligible(events, "", context, selected_ids)
		if remainder.size() < wanted - selected.size():
			remainder = _eligible(events, "", broad_context, selected_ids)
		rng.shuffle(remainder)
		for event in remainder:
			if selected.size() >= wanted:
				break
			var event_id := String(event.get("id", ""))
			if selected_ids.has(event_id):
				continue
			selected.append(event)
			selected_ids[event_id] = true
	return selected


## 骨格を変えず、fallback の四項目だけを seed から選んだ一件へする。
static func instantiate(
	event_def: Dictionary, rng: DetRng, context: Dictionary = {}
) -> Dictionary:
	var selected_skin := {}
	var skin: Dictionary = event_def.get("skin", {})
	for key in SKIN_KEYS:
		var pool: Array = skin.get(key, [])
		selected_skin[key] = String(rng.pick(pool)) if not pool.is_empty() else ""
	return {
		"event_id": String(event_def.get("id", "")),
		"category": String(event_def.get("category", "")),
		"site_kind": String(event_def.get("site_kind", "")),
		"danger": event_def.get("danger", []).duplicate(true),
		"tags": event_def.get("tags", []).duplicate(true),
		"premise": String(event_def.get("premise", "")),
		"trigger": String(event_def.get("trigger", "")),
		"choices": event_def.get("choices", []).duplicate(true),
		"skin": selected_skin,
		"ai_slots": event_def.get("ai_slots", {}).duplicate(true),
		"context": context.duplicate(true),
		"rejected": [],
	}


## AI へ渡してよい表示用情報だけへ縮める。
## event_id、choices、costs、risks、rewards は意図的に含めない。
static func facts_for_ai(instance: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	var skin: Dictionary = instance.get("skin", {})
	var limits: Dictionary = instance.get("ai_slots", {})
	for key in SKIN_KEYS:
		slots.append({
			"key": key,
			"max_length": int(limits.get(key, 0)),
			"fallback": String(skin.get(key, "")),
		})
	var context: Dictionary = instance.get("context", {})
	return {
		"category": String(instance.get("category", "")),
		"site_kind": String(instance.get("site_kind", "")),
		"premise": String(instance.get("premise", "")),
		"trigger": String(instance.get("trigger", "")),
		"danger_band": instance.get("danger", []).duplicate(true),
		"biome": String(context.get("biome", "")),
		"slots": slots,
	}


## AI 候補を項目単位で検査して上書きする。
## candidate 内の choices や rewards は読みもしない。
static func apply_ai_skin(instance: Dictionary, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = instance.duplicate(true)
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
	return result


## データ追加時に骨格と AI 境界の破損をまとめて報告する。
static func validate_catalog(catalog: Dictionary = {}) -> Array[String]:
	var source := load_catalog() if catalog.is_empty() else catalog
	var errors: Array[String] = []
	if int(source.get("version", 0)) != 1:
		errors.append("version は 1 であること")
	var events = source.get("events", null)
	if not events is Array:
		errors.append("events が配列ではない")
		return errors
	if events.size() != EXPECTED_TOTAL:
		errors.append("events は %d 件であること: %d" % [
			EXPECTED_TOTAL, events.size()
		])

	var allowed_costs := _as_set(source.get("allowed_costs", []))
	var allowed_risks := _as_set(source.get("allowed_risks", []))
	var allowed_rewards := _as_set(source.get("allowed_rewards", []))
	var ids := {}
	var category_counts := {}
	for category in CATEGORY_ORDER:
		category_counts[category] = 0

	for raw_event in events:
		if not raw_event is Dictionary:
			errors.append("event が辞書ではない")
			continue
		var event: Dictionary = raw_event
		var event_id := String(event.get("id", ""))
		var prefix := event_id if event_id != "" else "<no-id>"
		if event_id == "":
			errors.append("%s: id が空" % prefix)
		elif ids.has(event_id):
			errors.append("%s: id が重複" % prefix)
		ids[event_id] = true

		var category := String(event.get("category", ""))
		if not category in CATEGORY_ORDER:
			errors.append("%s: category が不正" % prefix)
		else:
			category_counts[category] = int(category_counts[category]) + 1
		if not String(event.get("site_kind", "")) in SITE_KINDS:
			errors.append("%s: site_kind が不正" % prefix)
		if String(event.get("premise", "")).strip_edges() == "":
			errors.append("%s: premise が空" % prefix)
		if String(event.get("trigger", "")).strip_edges() == "":
			errors.append("%s: trigger が空" % prefix)

		var danger = event.get("danger", null)
		if (
			not danger is Array
			or danger.size() != 2
			or int(danger[0]) < 1
			or int(danger[1]) > 10
			or int(danger[0]) > int(danger[1])
		):
			errors.append("%s: danger は 1..10 の昇順二要素" % prefix)

		_validate_choices(
			prefix, event.get("choices", null),
			allowed_costs, allowed_risks, allowed_rewards, errors
		)
		_validate_skin(
			prefix, event.get("skin", null), event.get("ai_slots", null), errors
		)

	for category in CATEGORY_ORDER:
		if int(category_counts.get(category, 0)) != EXPECTED_PER_CATEGORY:
			errors.append("%s は %d 件であること: %d" % [
				category, EXPECTED_PER_CATEGORY, int(category_counts.get(category, 0))
			])
	return errors


static func _eligible(
	events: Array, category: String, context: Dictionary, excluded: Dictionary
) -> Array:
	var out: Array = []
	var danger_min := int(context.get("danger_min", 1))
	var danger_max := int(context.get("danger_max", 10))
	var wanted_tags: Array = context.get("tags", [])
	var site_kind := String(context.get("site_kind", ""))
	for raw_event in events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		if category != "" and String(event.get("category", "")) != category:
			continue
		if site_kind != "" and String(event.get("site_kind", "")) != site_kind:
			continue
		if excluded.has(String(event.get("id", ""))):
			continue
		var danger: Array = event.get("danger", [1, 10])
		if int(danger[1]) < danger_min or int(danger[0]) > danger_max:
			continue
		if not wanted_tags.is_empty() and not _overlaps(event.get("tags", []), wanted_tags):
			continue
		out.append(event)
	return out


static func _overlaps(left: Array, right: Array) -> bool:
	for value in left:
		if value in right:
			return true
	return false


static func _as_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[String(value)] = true
	return result


static func _validate_choices(
	prefix: String,
	choices,
	allowed_costs: Dictionary,
	allowed_risks: Dictionary,
	allowed_rewards: Dictionary,
	errors: Array[String]
) -> void:
	if not choices is Array:
		errors.append("%s: choices が配列ではない" % prefix)
		return
	if choices.size() < 2 or choices.size() > 3:
		errors.append("%s: choices は 2..3 件" % prefix)
	var choice_ids := {}
	for raw_choice in choices:
		if not raw_choice is Dictionary:
			errors.append("%s: choice が辞書ではない" % prefix)
			continue
		var choice: Dictionary = raw_choice
		var choice_id := String(choice.get("id", ""))
		var choice_prefix := "%s/%s" % [prefix, choice_id]
		if choice_id == "" or choice_ids.has(choice_id):
			errors.append("%s: choice id が空か重複" % choice_prefix)
		choice_ids[choice_id] = true
		if String(choice.get("label", "")).strip_edges() == "":
			errors.append("%s: label が空" % choice_prefix)
		_validate_tokens(
			choice_prefix, "costs", choice.get("costs", null), allowed_costs, errors
		)
		_validate_tokens(
			choice_prefix, "risks", choice.get("risks", null), allowed_risks, errors
		)
		_validate_tokens(
			choice_prefix, "rewards", choice.get("rewards", null), allowed_rewards, errors
		)


static func _validate_tokens(
	prefix: String, field: String, values, allowed: Dictionary, errors: Array[String]
) -> void:
	if not values is Array:
		errors.append("%s: %s が配列ではない" % [prefix, field])
		return
	if field != "risks" and values.is_empty():
		errors.append("%s: %s が空" % [prefix, field])
	for value in values:
		var token := String(value)
		if not allowed.has(token):
			errors.append("%s: %s の未知トークン %s" % [prefix, field, token])
	if "none" in values and values.size() != 1:
		errors.append("%s: none は単独指定" % prefix)


static func _validate_skin(
	prefix: String, skin, ai_slots, errors: Array[String]
) -> void:
	if not skin is Dictionary or not ai_slots is Dictionary:
		errors.append("%s: skin と ai_slots は辞書" % prefix)
		return
	if skin.size() != SKIN_KEYS.size() or ai_slots.size() != SKIN_KEYS.size():
		errors.append("%s: skin と ai_slots は四項目のみ" % prefix)
	for key in SKIN_KEYS:
		var pool = skin.get(key, null)
		var limit := int(ai_slots.get(key, 0))
		if not pool is Array or pool.size() < 3:
			errors.append("%s: skin.%s は三候補以上" % [prefix, key])
			continue
		if limit < 1 or limit > 34:
			errors.append("%s: ai_slots.%s は 1..34" % [prefix, key])
		for value in pool:
			var reason := _invalid_reason(String(value), limit)
			if reason != "":
				errors.append("%s: skin.%s が不正(%s)" % [prefix, key, reason])


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
