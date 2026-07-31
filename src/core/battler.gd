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

## 敵が次に使うと決めている技。行動順バーに出して「予告」にする。
##
## 相手の手が見えていないと、こちらが手を変える理由が生まれない。
## 技だけを先に決め、対象は実行時に選ぶ（先に決めると対象が死んでいることがある）。
var planned_ability: String = ""

## 防御中は次の行動まで被ダメージが減る。
var guarding: bool = false
## 素早さ倍率を 100 分率で持つ（ヘイスト 150 / スロウ 50）。整数のまま扱う。
var agi_scale: int = 100
## 素早さ倍率の残り手番。0 になったら 100 に戻る。
## これが無いと、一度かけたピオラが戦闘終了まで効き続ける永続バフになる。
var agi_scale_turns: int = 0

## この者をかばっている者。攻撃はそちらが肩代わりする。
## かばい手が動いたら解除されるので、守り続けるには毎回かばい直す必要がある。
var protected_by: Battler = null

## 属性の耐性。weak なら 2 倍、resist なら半減。
## 「敵ごとに効く手が変わる」ための装置で、これが無いと最強の 1 手を覚えた時点で
## 考えるのをやめてしまう（docs/battle_design.md）。
var weak: Array[String] = []
var resist: Array[String] = []

## 通常攻撃に乗る属性（炎の武器など）。
var attack_element: String = ""

## ★5 の象徴技が置いていく状態（F-6a）。**どれも数手番で切れる。**
##
##   counter_turns  受けた傷を返す（せんし「むかえうち」）
##   charged        次の一撃が守りを抜いて重くなる（じゅうし「そうてん」）
##   rune_turns     刃に移した属性の残り（まけんし「るんのやいば」）
##   tamed          倒さずに戦いから降りた（まじゅうつかい「てなずけ」）
var counter_turns: int = 0
var charged: bool = false
var rune_turns: int = 0
var tamed: bool = false

## 状態異常。CTB では時間に触る効果がいちばん強く効くので、そこに絞る。
## ねむり: 手番が来ても動けず、そのぶん後ろへ回る
## どく  : 手番が来るたびに削れる（速い者ほど早く減る）
var sleep_turns: int = 0
var poison_turns: int = 0


## 装備由来の特殊効果（"steal_up" など）。
var effects: Array[String] = []


func has_effect(id: String) -> bool:
	return id in effects


func has_status() -> bool:
	return sleep_turns > 0 or poison_turns > 0


func clear_status() -> void:
	sleep_turns = 0
	poison_turns = 0


## 状態異常の短い表示（HUD 用）。無ければ空文字。
func status_tag() -> String:
	if sleep_turns > 0:
		return "ねむり"
	if poison_turns > 0:
		return "どく"
	return ""


func is_alive() -> bool:
	# **手懐けた相手は「生きているが戦っていない」。** 倒したのではないので
	# 経験値も戦利品も出ないが、場からは降りる（まじゅうつかい「てなずけ」）。
	return hp > 0 and not tamed


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
