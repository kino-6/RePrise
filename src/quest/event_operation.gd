class_name EventOperation
extends RefCounted

## 任意イベントを「選んで即終了」させないための、選択後の行動契約。
##
## 64型の文章や報酬は data 側に残し、ここでは場所と戦闘の有無から
## **実際に何を終えたら報酬を渡すか**だけを決める。同じ選択なら同じ契約になり、
## AI の表層文やフレーム時間には左右されない。

const VERSION := 1
const TRAVEL_STEPS := 3

const FIGHT := "fight"
const TRAVEL := "travel"
const TOWN_CONTACT := "town_contact"
const CAVE_SEARCH := "cave_search"
const KINDS := [FIGHT, TRAVEL, TOWN_CONTACT, CAVE_SEARCH]


static func kind_for(instance: Dictionary, choice: Dictionary, fired: Array = []) -> String:
	var tokens: Array = []
	tokens.append_array(choice.get("costs", []))
	tokens.append_array(fired)
	if _fight_grade(tokens) > 0:
		return FIGHT
	match String(instance.get("site_kind", "world")):
		"town":
			return TOWN_CONTACT
		"cave":
			return CAVE_SEARCH
	return TRAVEL


static func build(
	instance: Dictionary, choice: Dictionary, fired: Array,
	pos: Vector2i, danger: int
) -> Dictionary:
	var kind := kind_for(instance, choice, fired)
	return {
		"version": VERSION,
		"event_id": String(instance.get("event_id", instance.get("id", ""))),
		"choice_id": String(choice.get("id", "")),
		"choice_label": String(choice.get("label", "")),
		"event_title": _display_text(instance.get("skin", {}).get("title", "")),
		"category": String(instance.get("category", "")),
		"site_kind": String(instance.get("site_kind", "world")),
		"kind": kind,
		"position": [pos.x, pos.y],
		"danger": danger,
		"progress": 0,
		"goal": TRAVEL_STEPS if kind == TRAVEL else 1,
		"ready": false,
		"fight_grade": _fight_grade(choice.get("costs", []) + fired),
		"rewards": choice.get("rewards", []).duplicate(),
		"tags": instance.get("tags", []).duplicate(),
	}


static func valid(task: Dictionary) -> bool:
	var pos = task.get("position", null)
	return (
		int(task.get("version", 0)) == VERSION
		and String(task.get("event_id", "")) != ""
		and String(task.get("choice_id", "")) != ""
		and String(task.get("kind", "")) in KINDS
		and pos is Array and pos.size() == 2
		and int(task.get("goal", 0)) > 0
	)


static func position(task: Dictionary) -> Vector2i:
	var pair: Array = task.get("position", [-1, -1])
	if pair.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(pair[0]), int(pair[1]))


static func is_at(task: Dictionary, pos: Vector2i) -> bool:
	return valid(task) and position(task) == pos


static func preview(instance: Dictionary, choice: Dictionary) -> String:
	match kind_for(instance, choice):
		FIGHT:
			return Terms.EVENT_TASK_PREVIEW_FIGHT
		TOWN_CONTACT:
			return Terms.EVENT_TASK_PREVIEW_TOWN
		CAVE_SEARCH:
			return Terms.EVENT_TASK_PREVIEW_CAVE
	return Terms.EVENT_TASK_PREVIEW_TRAVEL % TRAVEL_STEPS


static func objective(task: Dictionary) -> String:
	match String(task.get("kind", "")):
		FIGHT:
			return Terms.EVENT_TASK_OBJECTIVE_FIGHT
		TOWN_CONTACT:
			return Terms.EVENT_TASK_OBJECTIVE_TOWN
		CAVE_SEARCH:
			return Terms.EVENT_TASK_OBJECTIVE_CAVE
		TRAVEL:
			return Terms.EVENT_TASK_OBJECTIVE_TRAVEL % [
				int(task.get("progress", 0)), int(task.get("goal", TRAVEL_STEPS))
			]
	return ""


static func completion_line(kind: String) -> String:
	match kind:
		FIGHT:
			return Terms.EVENT_TASK_DONE_FIGHT
		TOWN_CONTACT:
			return Terms.EVENT_TASK_DONE_TOWN
		CAVE_SEARCH:
			return Terms.EVENT_TASK_DONE_CAVE
	return Terms.EVENT_TASK_DONE_TRAVEL


static func _fight_grade(tokens: Array) -> int:
	var grade := 0
	for raw in tokens:
		match String(raw):
			"normal_fight":
				grade = maxi(grade, 1)
			"elite_fight":
				grade = maxi(grade, 2)
	return grade


static func _display_text(value: Variant) -> String:
	if value is Array:
		return "" if value.is_empty() else String(value[0])
	return String(value)
