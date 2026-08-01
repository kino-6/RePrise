extends RefCounted

## 宝箱の報酬抽選。
##
## 宝箱から得るものはすべてラン終了時に失うため、出店より大胆に配る。
## ただし抽選は DetRng だけを使い、同じシードなら同じ中身になる。

const MAX_GEAR_CHANCE := 60
## 装備抽選を外した箱のうち、戦具になる割合。全箱ではおよそ 7〜12%。
## 通常物資へ混ぜると深層の「直近品」が戦具だけになりやすいため、別枠にする。
const REUSABLE_CHANCE := 20


static func roll(rng: DetRng, floor_number: int, base_gold: int) -> Dictionary:
	var floor_no := maxi(floor_number, 1)
	var reward := {
		"gold": maxi(base_gold, 1),
		"gear": "",
		"item": "",
		"item_count": 0,
	}

	# 1 階で 33%、10 階で上限の 60%。残りは必ず物資束になる。
	if rng.chance(mini(30 + floor_no * 3, MAX_GEAR_CHANCE)):
		var gear_pool := _recent_gear(floor_no)
		if not gear_pool.is_empty():
			reward.gear = String(rng.pick(gear_pool))
			return reward

	var reusable_pool := _recent_reusables(floor_no)
	if not reusable_pool.is_empty() and rng.chance(REUSABLE_CHANCE):
		reward.item = String(rng.pick(reusable_pool))
		reward.item_count = 1
		return reward

	var item_pool := _recent_items(floor_no)
	if item_pool.is_empty():
		return reward
	var item_id := String(rng.pick(item_pool))
	var price := int(Database.item(item_id).get("price", 0))
	var count := 1
	if price <= 40:
		count = 2 + floor_no / 5
	elif price <= 100:
		count = 2
	reward.item = item_id
	reward.item_count = count
	return reward


## 深層の箱から序盤装備ばかり出ないよう、解禁済みの上位 2 段を候補にする。
static func _recent_gear(floor_number: int) -> Array:
	var unlocked := Database.gear_ids_for_floor(floor_number)
	var highest := 1
	for gear_id in unlocked:
		highest = maxi(highest, int(Database.gear(gear_id).get("floor_min", 1)))
	var result: Array = []
	for gear_id in unlocked:
		if int(Database.gear(gear_id).get("floor_min", 1)) >= highest - 1:
			result.append(gear_id)
	result.sort()
	return result


## 道具も直近 3 段から選ぶ。安い基礎物資は個数で、希少品は質で派手にする。
static func _recent_items(floor_number: int) -> Array:
	var unlocked := Database.item_ids_for_floor(floor_number)
	var highest := 1
	for item_id in unlocked:
		if bool(Database.item(String(item_id)).get("reusable", false)):
			continue
		highest = maxi(highest, int(Database.item(item_id).get("floor_min", 1)))
	var result: Array = []
	for item_id in unlocked:
		if bool(Database.item(String(item_id)).get("reusable", false)):
			continue
		if int(Database.item(item_id).get("floor_min", 1)) >= highest - 2:
			result.append(item_id)
	result.sort()
	return result


## 戦具は一度に1個だけ。直近2段から選び、浅い品だけが続くのを避ける。
static func _recent_reusables(floor_number: int) -> Array:
	var unlocked := Database.reusable_item_ids_for_floor(floor_number)
	var highest := 1
	for item_id in unlocked:
		highest = maxi(highest, int(Database.item(String(item_id)).get("floor_min", 1)))
	var result: Array = []
	for item_id in unlocked:
		if int(Database.item(String(item_id)).get("floor_min", 1)) >= highest - 1:
			result.append(item_id)
	result.sort()
	return result
