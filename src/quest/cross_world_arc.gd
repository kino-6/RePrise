class_name CrossWorldArc
extends RefCounted

## ランをまたぐ物語の選出と進行（A-3）。
##
## カタログの読込と検算は `CrossWorldArcCatalog`、永続状態は
## `GameState.cross_world`。ここが持つのは**選ぶ・進める・終える**の 3 つだけ。
##
## 設計は `docs/cross_world_story_design.md`。守っている決めごと:
##
##   * **乱数系列を分ける。** 地形・敵編成・世界内六拍の乱数を消費しない。
##     ここが混ざると、物語が始まっただけで世界の中身が変わってしまう。
##   * **`phase_index` は表示または失敗継続が確定してから進める。**
##     表示前に進めると、落ちたときに段階だけ飛ぶ。
##   * **`setbacks` は結末の文脈に使い、打ち切る条件にはしない。**
##     全滅しても物語は続く（続かないと、失敗したランが無かったことになる）。

## 乱数系列。用途ごとに分ける（設計文書の指定どおり）。
const SEQ_SELECT := "meta_arc_select"
const SEQ_SKIN := "meta_arc_skin"
const SEQ_SCHEDULE := "meta_arc_schedule"


## 何も始まっていない状態。**形はここ 1 か所に置く。**
##
## `GameState` はオートロードで `--headless --script` から触れないので、
## 形も進行もこちら（静的クラス）に置く。セーブ側はこれを呼ぶだけ。
static func empty_state() -> Dictionary:
	return {
		"schema": 1,
		"active_id": "",
		"phase_index": 0,
		"skin": {},
		"started_run": 0,
		"next_due_run": 0,
		"setbacks": [],
		"history": [],
		"completed": {},
		"recent_ids": [],
	}


## 進行中の型（無ければ空）。
static func active(state: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var id := String(state.get("active_id", ""))
	return {} if id == "" else CrossWorldArcCatalog.arc_by_id(id, catalog)


## いま出すべき段階（無ければ空）。
static func current_beat(state: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var arc := active(state, catalog)
	if arc.is_empty():
		return {}
	var beats: Array = arc.get("beats", [])
	var index := int(state.get("phase_index", 0))
	return beats[index] if index >= 0 and index < beats.size() else {}


## その置き場で、いま段階が起きるか。
##
## `due` を満たしていないランでは起きない（毎ラン出すと、またぐ物語ではなく
## 毎回の出来事になる）。
static func beat_due_at(
	state: Dictionary, placement: String, runs_attempted: int, catalog: Dictionary = {}
) -> Dictionary:
	var beat := current_beat(state, catalog)
	if beat.is_empty() or String(beat.get("placement", "")) != placement:
		return {}
	if runs_attempted < int(state.get("next_due_run", 0)):
		return {}
	return beat


## 進行中でなければ 1 つ選ぶ。選べたら true。
##
## 選出は決定的（`run_seed` と回数から引く）なので、同じ状況からは同じ型が出る。
static func select(
	state: Dictionary, runs_attempted: int, seed_value: int, catalog: Dictionary = {}
) -> bool:
	if String(state.get("active_id", "")) != "":
		return false
	# 1 つ終えた直後は間を置く（`cooldown_runs`）。
	if runs_attempted < int(state.get("next_due_run", 0)):
		return false

	var completed: Dictionary = state.get("completed", {})
	var recent: Array = state.get("recent_ids", [])
	var pool: Array = []
	var weights: Array = []
	for raw in CrossWorldArcCatalog.arcs(catalog):
		var arc: Dictionary = raw
		var id := String(arc.get("id", ""))
		if completed.has(id) or id in recent:
			continue   # 同じ型を続けない
		var rule: Dictionary = arc.get("selection", {})
		if runs_attempted < int(rule.get("min_runs_attempted", 0)):
			continue
		if completed.size() < int(rule.get("min_completed_arcs", 0)):
			continue
		pool.append(arc)
		weights.append(maxi(int(rule.get("weight", 1)), 1))
	if pool.is_empty():
		return false

	var pick_rng := DetRng.new(seed_value).fork("%s:%d" % [SEQ_SELECT, runs_attempted])
	var total := 0
	for w in weights:
		total += int(w)
	var roll := pick_rng.range_i(1, total)
	var chosen: Dictionary = pool[0]
	for i in pool.size():
		roll -= int(weights[i])
		if roll <= 0:
			chosen = pool[i]
			break

	var skin_rng := DetRng.new(seed_value).fork("%s:%d" % [SEQ_SKIN, runs_attempted])
	var span: Dictionary = chosen.get("span", {})
	var due_rng := DetRng.new(seed_value).fork("%s:%d" % [SEQ_SCHEDULE, runs_attempted])

	state["active_id"] = String(chosen.get("id", ""))
	state["skin"] = CrossWorldArcCatalog.pick_skin(chosen, skin_rng, catalog)
	state["phase_index"] = 0
	state["started_run"] = runs_attempted
	state["next_due_run"] = runs_attempted + due_rng.range_i(
		maxi(int(span.get("min_runs", 1)), 1), maxi(int(span.get("max_runs", 2)), 1)
	)
	state["setbacks"] = []
	state["history"] = []
	return true


## 段階を 1 つ進める。**表示または失敗継続が確定してから呼ぶ。**
##
## 四段階目まで進んだら、選んだ手の結末を `completed` に残して型を閉じる。
## `choice_id` は最後の段階でだけ使う（それ以外では空でよい）。
static func advance(
	state: Dictionary, runs_attempted: int, choice_id: String = "", catalog: Dictionary = {}
) -> Dictionary:
	var arc := active(state, catalog)
	if arc.is_empty():
		return {}
	var beats: Array = arc.get("beats", [])
	var index := int(state.get("phase_index", 0))
	if index >= beats.size():
		return {}

	var history: Array = state.get("history", [])
	history.append({
		"phase": String(beats[index].get("phase", "")),
		"run": runs_attempted,
		"result": "seen",
	})
	state["history"] = history
	state["phase_index"] = index + 1

	if index + 1 < beats.size():
		return {}   # まだ続く

	# 最後の段階。結末を決めて閉じる。
	var ending := _resolve(arc, choice_id)
	var completed: Dictionary = state.get("completed", {})
	completed[String(arc.get("id", ""))] = String(ending.get("ending_id", ""))
	state["completed"] = completed
	var recent: Array = state.get("recent_ids", [])
	recent.append(String(arc.get("id", "")))
	while recent.size() > 3:
		recent.pop_front()
	state["recent_ids"] = recent
	state["active_id"] = ""
	state["phase_index"] = 0
	state["skin"] = {}
	# 次の連作までは間を置く。
	var span: Dictionary = arc.get("span", {})
	state["next_due_run"] = runs_attempted + maxi(int(span.get("cooldown_runs", 1)), 1)
	return ending


## 失敗を書き留める。**打ち切らない**（続かないと失敗したランが無かったことになる）。
static func note_setback(state: Dictionary, failure_id: String) -> void:
	if String(state.get("active_id", "")) == "":
		return
	var setbacks: Array = state.get("setbacks", [])
	if failure_id not in setbacks:
		setbacks.append(failure_id)
	state["setbacks"] = setbacks


## 段階の文。`skin` を差し込んで返す。失敗を挟んでいれば `loss_line` を優先する。
static func line_of(state: Dictionary, beat: Dictionary) -> String:
	var setbacks: Array = state.get("setbacks", [])
	var text := String(beat.get("line", ""))
	if not setbacks.is_empty() and String(beat.get("loss_line", "")) != "":
		text = String(beat.get("loss_line", ""))
	var skin: Dictionary = state.get("skin", {})
	for key in skin:
		text = text.replace("{%s}" % String(key), String(skin[key]))
	return text


static func _resolve(arc: Dictionary, choice_id: String) -> Dictionary:
	var choices: Array = arc.get("choices", [])
	var picked: Dictionary = {}
	for choice in choices:
		if String(choice.get("id", "")) == choice_id:
			picked = choice
			break
	if picked.is_empty():
		# 選ばずに終わった（画面を見ずに閉じたなど）。**必ず既定へ落ちる。**
		for choice in choices:
			if String(choice.get("id", "")) == String(arc.get("fallback_choice", "")):
				picked = choice
				break
	if picked.is_empty() and not choices.is_empty():
		picked = choices[0]
	var endings: Dictionary = arc.get("endings", {})
	var ending_id := String(picked.get("ending_id", ""))
	var ending: Dictionary = endings.get(ending_id, {})
	return {
		"arc_id": String(arc.get("id", "")),
		"choice_id": String(picked.get("id", "")),
		"ending_id": ending_id,
		"line": String(ending.get("line", "")),
	}
