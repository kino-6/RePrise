class_name CrossWorldArcCatalog
extends RefCounted

## ランをまたぐ物語（十二型）の読込と検算。
##
## 設計は `docs/cross_world_story_design.md`、原本は `data/cross_world_arcs.json`。
##
## **ここは読込と検算だけを持つ。** 選出・進行・表示は後の段（A-2 以降）で足す。
## 設計文書の言うとおり、最初から十二型を本体へ繋がない ―― 永続セーブを使う
## 物語なので、一型で旧セーブ・全滅・途中終了・再開・決着の全経路を通してから
## カタログを広げる。
##
## 検算するのは設計文書の 5 点。**壊れたカタログを黙って通さない**のが役目で、
## 通ったものだけが物語になる。

const PATH := "res://data/cross_world_arcs.json"

## 四段階。この順でしか進まない。
const PHASE_COUNT := 4

## 型の数。
const ARC_COUNT := 12

## 選択と結末の数（1 型あたり）。
const CHOICE_COUNT := 3

static var _cache: Dictionary = {}
static var _loaded := false


static func load_catalog() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(PATH):
		push_warning("%s が無い。またぐ物語は出ない。" % PATH)
		return _cache
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("%s が読めない。" % PATH)
		return _cache
	_cache = parsed
	return _cache


static func reload() -> Dictionary:
	_loaded = false
	return load_catalog()


static func arcs(catalog: Dictionary = {}) -> Array:
	var source := load_catalog() if catalog.is_empty() else catalog
	return source.get("arcs", [])


static func arc_by_id(arc_id: String, catalog: Dictionary = {}) -> Dictionary:
	for arc in arcs(catalog):
		if String(arc.get("id", "")) == arc_id:
			return arc
	return {}


## カタログ全体の検算。問題の一覧を返す（空なら健全）。
##
## 設計文書の 5 点:
##   1. 型が十二件で ID が重複しない
##   2. 四段階が `phase_order` どおりである
##   3. `placement` が許可語彙に含まれる
##   4. 選択と結末が三件ずつ一対一である
##   5. `fallback_choice` が実在する
##
## **落ちる側もテストする。** 通す側だけ試すと、何でも通す検算でも緑になる。
static func validate(catalog: Dictionary = {}) -> Array[String]:
	var source := load_catalog() if catalog.is_empty() else catalog
	var problems: Array[String] = []
	if source.is_empty():
		return ["カタログが読めない"]

	var order: Array = source.get("phase_order", [])
	var places: Array = source.get("placements", [])
	var failures: Array = source.get("failure_events", [])
	if order.size() != PHASE_COUNT:
		problems.append("phase_order が %d 件（%d 件であるべき）" % [order.size(), PHASE_COUNT])
	if places.is_empty():
		problems.append("placements が空")

	var list := arcs(source)
	if list.size() != ARC_COUNT:
		problems.append("型が %d 件（%d 件であるべき）" % [list.size(), ARC_COUNT])

	var seen := {}
	for raw in list:
		var arc: Dictionary = raw
		var id := String(arc.get("id", ""))
		if id == "":
			problems.append("id の無い型がある")
			continue
		if seen.has(id):
			problems.append("id が重複: %s" % id)
		seen[id] = true
		_check_arc(arc, id, order, places, failures, problems)
	return problems


static func _check_arc(
	arc: Dictionary, id: String, order: Array, places: Array, failures: Array,
	problems: Array[String]
) -> void:
	# 2. 四段階が phase_order どおり
	var beats: Array = arc.get("beats", [])
	if beats.size() != order.size():
		problems.append("%s: 段階が %d 件（%d 件であるべき）" % [id, beats.size(), order.size()])
	else:
		for i in beats.size():
			var phase := String(beats[i].get("phase", ""))
			if phase != String(order[i]):
				problems.append("%s: %d 番目の段階が %s（%s であるべき）" % [
					id, i + 1, phase, String(order[i])
				])

	# 3. placement が許可語彙に含まれる
	for beat in beats:
		var placement := String(beat.get("placement", ""))
		if placement == "" or placement not in places:
			problems.append("%s: 置き場が語彙に無い（%s）" % [id, placement])
		if String(beat.get("line", "")) == "":
			problems.append("%s: %s の文が空" % [id, String(beat.get("phase", "?"))])

	# 4. 選択と結末が三件ずつ一対一
	var choices: Array = arc.get("choices", [])
	var endings: Dictionary = arc.get("endings", {})
	if choices.size() != CHOICE_COUNT:
		problems.append("%s: 選択が %d 件（%d 件であるべき）" % [id, choices.size(), CHOICE_COUNT])
	if endings.size() != CHOICE_COUNT:
		problems.append("%s: 結末が %d 件（%d 件であるべき）" % [id, endings.size(), CHOICE_COUNT])
	var used_endings := {}
	for choice in choices:
		var ending_id := String(choice.get("ending_id", ""))
		if not endings.has(ending_id):
			problems.append("%s: 選択 %s の結末 %s が無い" % [
				id, String(choice.get("id", "?")), ending_id
			])
		elif used_endings.has(ending_id):
			# 一対一。2 つの選択が同じ結末に落ちると、選んだ意味が消える。
			problems.append("%s: 結末 %s が 2 つの選択から使われている" % [id, ending_id])
		used_endings[ending_id] = true
		if String(choice.get("label", "")) == "":
			problems.append("%s: 選択 %s に文が無い" % [id, String(choice.get("id", "?"))])

	# 5. fallback_choice が実在する
	var fallback := String(arc.get("fallback_choice", ""))
	var has_fallback := false
	for choice in choices:
		if String(choice.get("id", "")) == fallback:
			has_fallback = true
			break
	if not has_fallback:
		problems.append("%s: fallback_choice %s が選択に無い" % [id, fallback])

	# 失敗継続の宛先が語彙にあること（設計の 5 点の外だが、
	# ここが外れると全滅したときに何も起きない静かな穴になる）。
	for rule in arc.get("fail_forward", []):
		var when := String(rule.get("when", ""))
		if when == "" or (not failures.is_empty() and when not in failures):
			problems.append("%s: 失敗継続の宛先が語彙に無い（%s）" % [id, when])


## AI へ渡してよい表示用の情報だけへ縮める。
##
## **ID・選択・結末・失敗条件は渡さない**（構造はゲームが決める）。
## `WorldEventCatalog.facts_for_ai()` と同じ作り。
static func facts_for_ai(arc: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var source := load_catalog() if catalog.is_empty() else catalog
	var keys: Array = source.get("skin_keys", [])
	var skin: Dictionary = arc.get("skin", {})
	var slots: Array[Dictionary] = []
	for raw_key in keys:
		var key := String(raw_key)
		# 各枠は候補の配列（AI を使わないときは DetRng がここから選ぶ）。
		# **AI へ渡すのは既定値 1 つだけ**で、候補の全部は見せない
		# （選択肢を見せると、そこから選び直そうとして構造に手が伸びる）。
		var pool: Array = skin.get(key, [])
		slots.append({
			"key": key,
			"fallback": String(pool[0]) if not pool.is_empty() else "",
		})
	return {
		"theme": String(arc.get("theme", "")),
		"promise": String(arc.get("promise", "")),
		"slots": slots,
	}


## 表示語を 1 組決める（AI を使わないときの土台）。
##
## 候補から `DetRng` で選ぶだけ。**同じ種からは同じ語**になる。
static func pick_skin(arc: Dictionary, rng: DetRng, catalog: Dictionary = {}) -> Dictionary:
	var source := load_catalog() if catalog.is_empty() else catalog
	var skin: Dictionary = arc.get("skin", {})
	var picked := {}
	for raw_key in source.get("skin_keys", []):
		var key := String(raw_key)
		var pool: Array = skin.get(key, [])
		picked[key] = String(rng.pick(pool)) if not pool.is_empty() else ""
	return picked
