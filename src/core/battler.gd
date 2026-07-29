class_name Battler
extends RefCounted

## 戦闘に参加する 1 体分の状態。味方も敵もこれで表す。
##
## 恒久データ（職業熟練度など）はここに置かない。Battler は「そのランの、その
## 戦闘での姿」であり、使い捨て。持ち帰るものは PartyMember 側が持つ。

var id: int = 0
var name: String = ""
var is_ally: bool = false
var sprite: String = ""

## 元になったデータの ID（モンスターなら monsters.json のキー）。
## 報酬などを引き直すのに使う。表示名から逆引きすると "ゲルＡ" のような
## 装飾で簡単に壊れるので、ID を持たせておく。
var source_id: String = ""

var max_hp: int = 1
var hp: int = 1
var max_mp: int = 0
var mp: int = 0
var atk: int = 1
var mag: int = 1
var defense: int = 1
var agi: int = 10

## 行動コストの倍率（100 が標準）。職業や種族ごとの「テンポの個性」。
## とうぞくは 70 で手数型、まほうつかいは 145 で重量型。
var cost_scale: int = 100

var job_id: String = ""
var abilities: Array[String] = []

## CTB の仮想時間軸上で、次に行動できる時刻。
var next_at: int = 0

## 防御中は次の行動まで被ダメージが減る。
var guarding: bool = false
## 素早さ倍率を 100 分率で持つ（ヘイスト 150 / スロウ 50）。整数のまま扱う。
var agi_scale: int = 100


func is_alive() -> bool:
	return hp > 0


@warning_ignore("integer_division")
func effective_agi() -> int:
	return maxi(agi * agi_scale / 100, 1)


## この者がコスト cost の技を使ったときの実コスト。
@warning_ignore("integer_division")
func scaled_cost(cost: int) -> int:
	return maxi(cost * cost_scale / 100, 1)


func can_pay(ability: Dictionary) -> bool:
	return mp >= int(ability.get("mp", 0))


## 与えられたダメージを適用し、実際に減った量を返す。
func apply_damage(amount: int) -> int:
	var before := hp
	hp = clampi(hp - maxi(amount, 0), 0, max_hp)
	return before - hp


func heal(amount: int) -> int:
	var before := hp
	hp = clampi(hp + maxi(amount, 0), 0, max_hp)
	return hp - before


func describe() -> String:
	return "%s HP %d/%d" % [name, hp, max_hp]
