class_name TownInteraction
extends RefCounted

const TownDialogue := preload("res://src/world/town_dialogue.gd")

## 町を「回復と買い物の背景」で終わらせないための接続層。
##
## NPCの文章・仕事場の名前は差し替え可能なデータに置き、ここでは実際の状態を
## 読む／変える部分だけを扱う。同じ町で報酬だけを繰り返せないよう、利用済みの印は
## GameStateのラン中データへ残す。

const FACILITY_REWARDS := {
	"mining": ["temporary_guard"],
	"trade": ["shop_bonus"],
	"workshop": ["temporary_attack"],
	"pilgrimage": ["temporary_resist"],
	"beast_ranch": ["temporary_speed"],
	"ferry": ["route_safe"],
	"imperial_supply": ["boss_intel"],
}

const ROUTE_ROLES := ["scout", "guard", "ferryman", "pilgrim", "beastkeeper", "scribe"]
const STATUS_ROLES := ["innkeeper", "healer"]
const GEAR_ROLES := ["blacksmith", "mechanic"]


static func facility_key(town_index: int, town: TownMap) -> String:
	return "facility:%d:%s" % [town_index, town.profile.signature()]


static func guide_key(town_index: int, town: TownMap) -> String:
	return "guide:%d:%s" % [town_index, town.profile.signature()]


static func supply_chest_key(town_index: int, town: TownMap) -> String:
	return "supply_chest:%d:%s" % [town_index, town.profile.signature()]


static func talk(
	state: Node, town: TownMap, town_index: int, person: Dictionary
) -> Dictionary:
	var role := String(person.get("kind", ""))
	var lines: Array[String] = [String(person.get("line", ""))]
	var advice := ""
	if role == "elder":
		advice = _guide_advice(state, town, town_index)
	elif role in STATUS_ROLES:
		advice = _status_advice(state)
	elif role == "merchant":
		advice = _supply_advice(state)
	elif role in GEAR_ROLES:
		advice = _gear_advice(state)
	elif role in ROUTE_ROLES:
		advice = _route_advice(state)
	else:
		advice = String(TownDialogue.facility(town.profile.industry_id).get("hint", ""))
	if advice != "" and advice not in lines:
		lines.append(advice)
	return {
		"speaker": TownDialogue.role_name(role),
		"lines": lines,
		"role": role,
	}


## 中央の仕事場を一度だけ利用する。効果は既存EventEffectsへ寄せ、
## 町だけに似たバフ計算を増やさない。農園の固定物資だけは抽選させない。
static func use_facility(
	state: Node, town: TownMap, town_index: int, rng: DetRng
) -> Dictionary:
	var industry := town.profile.industry_id
	var copy := TownDialogue.facility(industry)
	var key := facility_key(town_index, town)
	if state.town_actions_done.has(key):
		return {
			"speaker": String(copy.get("name", Terms.TOWN_WORKPLACE)),
			"lines": [String(copy.get("repeat", Terms.TOWN_FACILITY_REPEAT_FALLBACK))],
			"changed": false,
		}

	var results: Array[String] = []
	if industry == "farming":
		state.add_item("herb", 2)
		state.add_item("water", 1)
		results.append(Terms.TOWN_FARM_SUPPLY)
	else:
		var tokens: Array = FACILITY_REWARDS.get(industry, ["route_safe"])
		results.append_array(EventEffects.grant(state, tokens, town.profile.danger, rng))
	if results.is_empty():
		# 効果が無いものを利用済みにしない。表示だけ成功する施設を作らないため。
		return {
			"speaker": String(copy.get("name", Terms.TOWN_WORKPLACE)),
			"lines": [String(copy.get("hint", Terms.TOWN_FACILITY_HINT_FALLBACK))],
			"changed": false,
		}

	state.town_actions_done[key] = true
	results.push_front(Terms.TOWN_FACILITY_USED % String(copy.get("name", Terms.TOWN_WORKPLACE)))
	return {
		"speaker": String(copy.get("name", Terms.TOWN_WORKPLACE)),
		"lines": results,
		"changed": true,
	}


## 町の案内札と見分けられる、本当に開けられる物資箱。
## 洞の宝箱より控えめだが、寄り道が無意味にならないだけのラン中資源を渡す。
static func open_supply_chest(
	state: Node, town: TownMap, town_index: int, rng: DetRng
) -> Dictionary:
	var key := supply_chest_key(town_index, town)
	if state.town_actions_done.has(key):
		return {
			"speaker": Terms.TOWN_SUPPLY_CHEST,
			"lines": [Terms.TOWN_CHEST_EMPTY],
			"changed": false,
		}

	var reward := supply_chest_reward(town.profile.danger, rng)
	var item_id := String(reward.get("item", "herb"))
	var count := int(reward.get("count", 1))
	var gold := int(reward.get("gold", 0))
	state.add_item(item_id, count)
	state.earn_gold(gold)
	state.town_actions_done[key] = true
	return {
		"speaker": Terms.TOWN_SUPPLY_CHEST,
		"lines": [
			Terms.TOWN_CHEST_OPENED,
			Terms.TOWN_CHEST_REWARD % [
				String(Database.item(item_id).get("name", item_id)), count, gold,
			],
		],
		"changed": true,
		"item": item_id,
		"count": count,
		"gold": gold,
	}


## 実プレイとbalanceが共有する町箱の抽選。状態変更は呼び出し側だけで行う。
static func supply_chest_reward(danger: int, rng: DetRng) -> Dictionary:
	var item_pool: Array = Database.item_ids_for_floor(maxi(danger, 1))
	item_pool.sort()
	var item_id := "herb" if item_pool.is_empty() else String(rng.pick(item_pool))
	var price := int(Database.item(item_id).get("price", 0))
	return {
		"item": item_id,
		"count": 2 if price <= 40 else 1,
		"gold": 8 + maxi(danger, 1) * 2 + rng.range_i(0, 8),
	}


## 物知りは一町につき未知の封を一つだけ地図へ記す。
## 同じ人へ連打して全情報を得る作業にはせず、別の町へ寄る理由を残す。
static func _guide_advice(state: Node, town: TownMap, town_index: int) -> String:
	if state.world == null:
		return Terms.TOWN_ROUTE_UNKNOWN
	var key := guide_key(town_index, town)
	if not state.town_actions_done.has(key):
		state.town_actions_done[key] = true
		for seal in state.world.seals:
			if bool(seal.get("broken", false)) or bool(seal.get("known", false)):
				continue
			seal["known"] = true
			return Terms.TOWN_GUIDE_REVEAL % String(seal.get("name", Terms.SEAL))
	return _route_advice(state)


static func _status_advice(state: Node) -> String:
	var poisoned := 0
	var hurt := 0
	for member in state.active_party():
		if member.poison_steps > 0:
			poisoned += 1
		if member.hp < member.max_hp() or member.mp < member.max_mp():
			hurt += 1
	if poisoned > 0:
		return Terms.TOWN_STATUS_POISON % poisoned
	if hurt > 0:
		return Terms.TOWN_STATUS_HURT % hurt
	return Terms.TOWN_STATUS_READY


static func _supply_advice(state: Node) -> String:
	var recovery := 0
	for raw_id in state.inventory:
		var id := String(raw_id)
		var effect := String(Database.item(id).get("effect", ""))
		if effect in ["heal_hp", "heal_mp", "revive", "cleanse", "heal_cleanse"]:
			recovery += int(state.inventory.get(id, 0))
	return (
		Terms.TOWN_SUPPLY_LOW % recovery
		if recovery < 3
		else Terms.TOWN_SUPPLY_READY % recovery
	)


static func _gear_advice(state: Node) -> String:
	var count: int = state.gear_stock.size()
	return Terms.TOWN_GEAR_EMPTY if count == 0 else Terms.TOWN_GEAR_READY % count


static func _route_advice(state: Node) -> String:
	if state.world == null:
		return Terms.TOWN_ROUTE_UNKNOWN
	var all_broken := true
	for seal in state.world.seals:
		if not bool(seal.get("broken", false)):
			all_broken = false
			if not bool(seal.get("known", false)):
				continue
			var at: Vector2i = seal.get("pos", Vector2i.ZERO)
			var origin: Vector2i = state.site.get("pos", state.world_pos)
			return Terms.TOWN_ROUTE_KNOWN % [
				_direction(origin, at), int(seal.get("danger", 1)),
				state.world.biome_name_at(at.x, at.y),
			]
	return Terms.TOWN_GUIDE_DONE if all_broken else Terms.TOWN_ROUTE_UNKNOWN


static func _direction(from: Vector2i, to: Vector2i) -> String:
	var delta := to - from
	if absi(delta.x) + absi(delta.y) <= 2:
		return Terms.TOWN_NEAR
	if absi(delta.x) >= absi(delta.y):
		return Terms.EAST if delta.x > 0 else Terms.WEST
	return Terms.SOUTH if delta.y > 0 else Terms.NORTH
