class_name BattleOpening
extends RefCounted

## 戦闘開始時に見せる文と、その一拍の Gate。
##
## BattleView の表示状態から切り離してあるので、ヘッドレステストも本番画面も
## 同じ判定を使う。乱数や実時間には触れず、すでに確定した CTB 順を読むだけ。

## 文字速度が「はやい」でも、戦場が見えてから最低限ここまでは攻撃を始めない。
const MIN_HOLD := 0.85


## 敵名と、最初に動く側を戦闘開始前に伝える。
## 「素早い敵」を乱数の不意打ちと偽らず、実際の CTB 順をそのまま文にする。
static func lines(battle: BattleSystem) -> Array[String]:
	var result: Array[String] = []
	if battle == null or battle.enemies.is_empty():
		return result
	var first_enemy: Battler = battle.enemies[0]
	var enemy_name := String(
		Database.monster(first_enemy.source_id).get("name", first_enemy.name)
	)
	result.append(
		Terms.BATTLE_ENEMY_APPEARED % enemy_name
		if battle.enemies.size() == 1
		else Terms.BATTLE_ENEMIES_APPEARED % enemy_name
	)
	var order := battle.turn_order(1)
	if not order.is_empty() and not order[0].is_ally:
		result.append(
			Terms.BATTLE_VANGUARD_FIRST
			if String(order[0].elite_rule) == "vanguard"
			else Terms.BATTLE_ENEMY_FIRST
		)
	return result


static func hold(lines_to_show: Array[String], line_delay: float) -> float:
	return maxf(MIN_HOLD, line_delay * float(maxi(lines_to_show.size(), 1)))


## トランジション完了前は、残り時間が負でも絶対に先へ渡さない。
static func can_advance(revealed: bool, remaining: float) -> bool:
	return revealed and remaining <= 0.0
