class_name Encounter
extends RefCounted

## 敵編成の組み立て。すべて渡された RNG からしか引かないので、
## 同じシード・同じ階層・同じ歩数からは必ず同じ敵が出る。

const MAX_ENEMIES := 3

## 同名が並ぶときの識別子。DQ の「スライムA / スライムB」と同じ作法。
const SUFFIX := ["Ａ", "Ｂ", "Ｃ"]


static func build(rng: DetRng, floor_number: int, first_id: int = 100) -> Array[Battler]:
	var pool := Database.monster_ids_for_floor(floor_number)
	var result: Array[Battler] = []
	if pool.is_empty():
		return result

	var count := rng.range_i(1, mini(MAX_ENEMIES, 1 + floor_number / 2))
	var chosen: Array = []
	for _i in count:
		chosen.append(rng.pick(pool))

	# 同名が複数いる場合だけ接尾辞を付ける
	var tally := {}
	for id in chosen:
		tally[id] = int(tally.get(id, 0)) + 1
	var seen := {}

	for i in chosen.size():
		var id: String = chosen[i]
		var index := int(seen.get(id, 0))
		seen[id] = index + 1
		var b := _to_battler(id, floor_number, first_id + i)
		if tally[id] > 1 and index < SUFFIX.size():
			b.name += SUFFIX[index]
		result.append(b)
	return result


@warning_ignore("integer_division")
static func _to_battler(monster_id: String, floor_number: int, battler_id: int) -> Battler:
	var m := Database.monster(monster_id)
	var b := Battler.new()
	b.id = battler_id
	b.name = String(m.get("name", monster_id))
	b.sprite = String(m.get("sprite", "gel"))
	b.source_id = monster_id
	b.is_ally = false

	# 深い階ほど強くする。10% ずつの単純な線形強化で、まずは調整しやすさを優先。
	var scale := 100 + (floor_number - 1) * 10
	b.max_hp = maxi(int(m.get("hp", 10)) * scale / 100, 1)
	b.hp = b.max_hp
	b.max_mp = int(m.get("mp", 0))
	b.mp = b.max_mp
	b.atk = maxi(int(m.get("atk", 1)) * scale / 100, 1)
	b.mag = b.atk
	b.defense = maxi(int(m.get("def", 1)) * scale / 100, 1)
	b.agi = int(m.get("agi", 10))
	b.cost_scale = int(m.get("cost_scale", 100))

	var raw: Array = m.get("abilities", ["attack"])
	b.abilities.assign(raw)
	return b


static func total_exp(enemies: Array[Battler]) -> int:
	return _sum_field(enemies, "exp")


static func total_gold(enemies: Array[Battler]) -> int:
	return _sum_field(enemies, "gold")


static func _sum_field(enemies: Array[Battler], field: String) -> int:
	var total := 0
	for b in enemies:
		total += int(Database.monster(b.source_id).get(field, 0))
	return total
