class_name StoryOperation
extends RefCounted

## 一世界物語の一拍を「読む画面」ではなく、実際のプレイ工程へ変換する。
##
## 文章は工程の目的と完了結果にだけ使う。町の仕事場、洞の探索、主戦の
## いずれかをプレイヤーが操作しなければ拍は進まない。

const VERSION := 1

const TOWN_ACTION := "town_action"
const CAVE_SEARCH := "cave_search"
const BOSS := "boss"
const CHRONICLE := "chronicle"

const KINDS := [TOWN_ACTION, CAVE_SEARCH, BOSS, CHRONICLE]
const FORBIDDEN_KINDS := ["dialogue", "cutscene", "continue", "story"]
## 操作そのものが残す共通効果。既に使った町の仕事場へ物語が後から来ても、
## 再操作が空振りにならない。町の調査は地図情報、洞の踏査は安全な道を残す。
const KIND_EFFECTS := {
	TOWN_ACTION: ["map_reveal"],
	CAVE_SEARCH: ["route_safe"],
	BOSS: [],
	CHRONICLE: [],
}


static func definition_errors(beat: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var beat_id := String(beat.get("id", "<no-id>"))
	var phase := String(beat.get("phase", ""))
	var site_role := String(beat.get("site_role", ""))
	var operation = beat.get("operation", null)
	if not operation is Dictionary:
		return ["%s: operation が無い（文章だけの拍は禁止）" % beat_id]
	var kind := String(operation.get("kind", ""))
	if kind in FORBIDDEN_KINDS:
		errors.append("%s: %s は会話送り／紙芝居なので禁止" % [beat_id, kind])
	elif kind not in KINDS:
		errors.append("%s: operation.kind が不正" % beat_id)
	if phase == "finale" and kind != BOSS:
		errors.append("%s: finale は主戦で決着する" % beat_id)
	elif phase == "epilogue" and kind != CHRONICLE:
		errors.append("%s: epilogue は戦記で回収する" % beat_id)
	elif phase not in ["finale", "epilogue"]:
		if site_role.begins_with("town_") and kind != TOWN_ACTION:
			errors.append("%s: 町の拍は仕事場の実操作にする" % beat_id)
		elif site_role.begins_with("cave_") and kind != CAVE_SEARCH:
			errors.append("%s: 洞の拍は探索の実操作にする" % beat_id)
	if kind in [TOWN_ACTION, CAVE_SEARCH]:
		if String(operation.get("objective", "")).strip_edges() == "":
			errors.append("%s: 操作前に読める目的が無い" % beat_id)
		if String(operation.get("result", "")).strip_edges() == "":
			errors.append("%s: 操作後に確認できる変化が無い" % beat_id)
		for token in KIND_EFFECTS.get(kind, []):
			if EventEffects.resolution_kind(String(token)) != "state":
				errors.append("%s: 操作効果 %s が未実装" % [beat_id, token])
	elif kind == BOSS and String(operation.get("cue", "")).strip_edges() == "":
		errors.append("%s: 物語を主戦へ渡す短い開戦文が無い" % beat_id)
	return errors


static func choice_errors(choice: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var choice_id := String(choice.get("id", "<no-id>"))
	var effects = choice.get("runtime_effects", null)
	if not effects is Array or effects.is_empty():
		return ["%s: 選択後のゲーム内効果が無い" % choice_id]
	for raw_token in effects:
		var token := String(raw_token)
		if EventEffects.resolution_kind(token) != "state":
			errors.append("%s: %s は実装済みの状態変化ではない" % [choice_id, token])
	return errors


static func build(
	story: Dictionary, beat: Dictionary, choice: Dictionary, at: Vector2i
) -> Dictionary:
	var operation: Dictionary = beat.get("operation", {})
	var kind := String(operation.get("kind", ""))
	var choice_effects: Array = choice.get("runtime_effects", [])
	# 選択拍はその選択固有の効き目自体が状態変化になる。共通効果を重ねて
	# 主戦準備の意味を薄めず、非選択拍だけ操作種別の共通効果を使う。
	var effects: Array = (
		choice_effects.duplicate()
		if not choice_effects.is_empty()
		else KIND_EFFECTS.get(kind, []).duplicate()
	)
	return {
		"version": VERSION,
		"story_id": String(story.get("story_id", "")),
		"beat_id": String(beat.get("id", "")),
		"phase": String(beat.get("phase", "")),
		"kind": kind,
		"at": [at.x, at.y],
		"objective": String(operation.get("objective", "")),
		"result": String(operation.get("result", "")),
		"cue": String(operation.get("cue", "")),
		"choice_id": String(choice.get("id", "")),
		"runtime_effects": effects,
	}


static func valid(task: Dictionary) -> bool:
	if int(task.get("version", 0)) != VERSION:
		return false
	if String(task.get("story_id", "")) == "" or String(task.get("beat_id", "")) == "":
		return false
	var kind := String(task.get("kind", ""))
	if kind not in KINDS:
		return false
	var raw_at = task.get("at", null)
	if not raw_at is Array or raw_at.size() != 2:
		return false
	if kind in [TOWN_ACTION, CAVE_SEARCH]:
		return objective(task) != "" and String(task.get("result", "")) != ""
	if kind == BOSS:
		return String(task.get("cue", "")).strip_edges() != ""
	return true


static func position(task: Dictionary) -> Vector2i:
	var raw: Array = task.get("at", [-1, -1])
	return Vector2i(int(raw[0]), int(raw[1])) if raw.size() == 2 else Vector2i(-1, -1)


static func is_at(task: Dictionary, at: Vector2i) -> bool:
	return valid(task) and position(task) == at


static func objective(task: Dictionary) -> String:
	return String(task.get("objective", "")).strip_edges()
