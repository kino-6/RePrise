class_name RunRules
extends RefCounted

## 出撃ごとの「難しさ / 周回速度 / 誓約」を一つの計算へ集約する。
##
## これは乱数ではなく、世界を作る前にプレイヤーが決める入力。同じシードと
## 同じ規律なら敵能力・成長・報酬は必ず一致する。表示文と数値は
## data/run_rules.json に置き、ここには組み合わせ方だけを置く。

const DEFAULT_DIFFICULTY := "standard"
const DEFAULT_PACE := "steady"
const BASE_CONTRACT_SLOTS := 1


static func default_config() -> Dictionary:
	return {
		"difficulty": DEFAULT_DIFFICULTY,
		"pace": DEFAULT_PACE,
		"contracts": [],
	}


static func _ordered_ids(order_key: String, group_key: String) -> Array[String]:
	var result: Array[String] = []
	var group: Dictionary = Database.run_rule_group(group_key)
	for raw_id in Database.run_rules.get(order_key, []):
		var id := String(raw_id)
		if group.has(id):
			result.append(id)
	return result


static func difficulty_ids(unlock_level: int = 99) -> Array[String]:
	var result: Array[String] = []
	var group := Database.run_rule_group("difficulties")
	for id in _ordered_ids("difficulty_order", "difficulties"):
		if int(group[id].get("unlock", 0)) <= unlock_level:
			result.append(id)
	return result


static func pace_ids(unlock_level: int = 99) -> Array[String]:
	var result: Array[String] = []
	var group := Database.run_rule_group("paces")
	for id in _ordered_ids("pace_order", "paces"):
		if int(group[id].get("unlock", 0)) <= unlock_level:
			result.append(id)
	return result


static func contract_ids() -> Array[String]:
	return _ordered_ids("contract_order", "contracts")


## 古いセーブや、強化を失った開発データからも必ず有効な構成へ落とす。
static func normalize(
	config: Dictionary, difficulty_unlock: int, pace_unlock: int, contract_slots: int
) -> Dictionary:
	var result := default_config()
	var difficulties := difficulty_ids(difficulty_unlock)
	var paces := pace_ids(pace_unlock)
	var selected_difficulty := String(config.get("difficulty", DEFAULT_DIFFICULTY))
	var selected_pace := String(config.get("pace", DEFAULT_PACE))
	if selected_difficulty in difficulties:
		result["difficulty"] = selected_difficulty
	elif DEFAULT_DIFFICULTY in difficulties:
		result["difficulty"] = DEFAULT_DIFFICULTY
	elif not difficulties.is_empty():
		result["difficulty"] = difficulties[0]
	if selected_pace in paces:
		result["pace"] = selected_pace
	elif not paces.is_empty():
		result["pace"] = paces[0]

	var known_contracts := contract_ids()
	var selected: Array[String] = []
	for raw_id in config.get("contracts", []):
		var id := String(raw_id)
		if id in known_contracts and id not in selected and selected.size() < contract_slots:
			selected.append(id)
	result["contracts"] = selected
	return result


static func definition(group: String, id: String) -> Dictionary:
	return Database.run_rule_group(group).get(id, {})


@warning_ignore("integer_division")
static func reward_percent(config: Dictionary) -> int:
	var difficulty := definition("difficulties", String(config.get(
		"difficulty", DEFAULT_DIFFICULTY)))
	var pace := definition("paces", String(config.get("pace", DEFAULT_PACE)))
	var percent := int(difficulty.get("reward_pct", 100))
	percent = percent * int(pace.get("reward_pct", 100)) / 100
	var contracts := Database.run_rule_group("contracts")
	for raw_id in config.get("contracts", []):
		percent += int(contracts.get(String(raw_id), {}).get("reward_bonus", 0))
	return maxi(percent, 10)


static func growth_percent(config: Dictionary, kind: String) -> int:
	var pace := definition("paces", String(config.get("pace", DEFAULT_PACE)))
	return int(pace.get("%s_pct" % kind, 100))


static func has_contract(config: Dictionary, id: String) -> bool:
	return id in config.get("contracts", [])


@warning_ignore("integer_division")
static func scaled_value(value: int, percent: int) -> int:
	if value <= 0:
		return 0
	return maxi(value * percent / 100, 1)


## 編成後、戦闘開始前に一度だけ掛ける。行動速度は触らない。
##
## 素早さまで倍率を掛けると CTB の手番数が非線形に増え、表示された 8% の差より
## はるかに難しくなる。生命と一撃の重さだけを別軸で動かす。
static func apply_enemy_scaling(foes: Array[Battler], config: Dictionary) -> void:
	var difficulty := definition("difficulties", String(config.get(
		"difficulty", DEFAULT_DIFFICULTY)))
	var hp_percent := int(difficulty.get("enemy_hp_pct", 100))
	var power_percent := int(difficulty.get("enemy_power_pct", 100))
	for foe in foes:
		foe.max_hp = scaled_value(foe.max_hp, hp_percent)
		foe.hp = foe.max_hp
		foe.atk = scaled_value(foe.atk, power_percent)
		foe.mag = scaled_value(foe.mag, power_percent)
		foe.defense = scaled_value(foe.defense, power_percent)
