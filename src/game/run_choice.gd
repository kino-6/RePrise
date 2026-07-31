class_name RunChoice
extends RefCounted

## 出撃時に決めること（E-1）。**数値ではなく選択を増やす。**
##
## それまでのアップグレードは「ゴールド +40」「やくそう +1」のように
## **数値を足すだけ**だった。段を上げても手強さが下がるだけで、
## **遊ぶ側の判断は 1 つも増えない**。上げた人が楽になるだけの報酬になる。
##
## ここは「その段で新しく選べるようになったもの」を持つ。
## `GameState` はオートロードで `--headless --script` から触れないので、
## 判断は静的クラスへ置く（`InheritSign` と同じ形）。
##
## 設計は `docs/progression_reward_design.md`。

## 支給品の型（旅支度）。**段が上がるほど選べる型が増える。**
##
## 型ごとに「何に寄せるか」が違う ―― 買い物で凌ぐか、道中で回復するか、
## 引き際に備えるか。**どれも総量はほぼ同じ**で、寄せ方だけが違う。
const SUPPLY_SETS: Array[Dictionary] = [
	{
		"id": "coin", "name": "かねだのみ",
		"desc": "ゴールドに寄せる。店で組み立てる。",
		"gold": 120, "herb": 0, "water": 0,
	},
	{
		"id": "salve", "name": "そなえ",
		"desc": "やくそうに寄せる。道中で保たせる。",
		"gold": 40, "herb": 3, "water": 0,
	},
	{
		"id": "spring", "name": "みずがめ",
		"desc": "まほうの水に寄せる。魔法で押す。",
		"gold": 40, "herb": 1, "water": 2,
	},
	{
		"id": "even", "name": "みつぞろえ",
		"desc": "三つに分ける。どの世界にも噛み合う。",
		"gold": 70, "herb": 2, "water": 1,
	},
]

## 店の重点（商いの伝手）。**どの棚を厚くするか。**
const SHOP_FOCUS: Array[Dictionary] = [
	{"id": "item", "name": "どうぐ", "desc": "消耗品が多く並ぶ。"},
	{"id": "weapon", "name": "ぶき", "desc": "武器が多く並ぶ。"},
	{"id": "armor", "name": "ぼうぐ", "desc": "防具が多く並ぶ。"},
	{"id": "accessory", "name": "かざり", "desc": "装飾が多く並ぶ。"},
]


## その段で選べる支給品の型。**1 段で 2 つ、以降 1 段ごとに 1 つ増える。**
##
## 0 段でも 1 つは選べる（＝選択そのものは常にある）。
static func supply_sets(level: int) -> Array[Dictionary]:
	return SUPPLY_SETS.slice(0, clampi(level + 1, 1, SUPPLY_SETS.size()))


## その段で選べる店の重点。0 段なら「指定しない」だけ。
static func shop_focus(level: int) -> Array[Dictionary]:
	if level <= 0:
		return []
	return SHOP_FOCUS.slice(0, clampi(level + 1, 1, SHOP_FOCUS.size()))


## 選べる選択肢の総数。**関門はここを見る。**
##
## 段を上げたのに増えなければ、その段は「数値が増えただけ」ということ。
static func count_at(level_of: Callable) -> int:
	var total := 0
	total += supply_sets(int(level_of.call("provisions"))).size()
	total += shop_focus(int(level_of.call("connections"))).size()
	# 封の言い伝えは段ごとに 1 つずつ開示が増える（位置 → 番人 → 代償）。
	total += clampi(int(level_of.call("seal_lore")), 0, 3)
	# 命の綱は「使うか、そこで終えるか」を選べるようになる。
	total += 1 if int(level_of.call("lifeline")) > 0 else 0
	# 継承印の枠（E-2）。
	total += InheritSign.slots(int(level_of.call("handmemory"))) - 1
	return total


## 支給品の型 1 つぶん（見つからなければ既定の先頭）。
static func supply_set(id: String) -> Dictionary:
	for row in SUPPLY_SETS:
		if String(row["id"]) == id:
			return row
	return SUPPLY_SETS[0]
