class_name BattleSystem
extends RefCounted

## CTB 戦闘のロジック本体。
##
## 描画も入力も持たない。UI は「今だれの手番か」を訊き、「この技をこの相手に」と
## 伝えるだけ。こうしておくと戦闘だけをヘッドレスで何千回も回してバランスを
## 測れる（CTB を選んだ最大の実利がこれ）。

signal finished(victory: bool)

const VARIANCE_LOW := 88
const VARIANCE_HIGH := 112

var scheduler := CtbScheduler.new()
var rng: DetRng = null
var floor_number: int = 1

var allies: Array[Battler] = []
var enemies: Array[Battler] = []

var is_over: bool = false
var stolen_gold: int = 0

## 直近に実行された技。演出側が効果音を選ぶのに使う。
var last_ability_id: String = ""


func start(party: Array[Battler], foes: Array[Battler], run_rng: DetRng, floor_no: int = 1) -> void:
	allies = party
	enemies = foes
	rng = run_rng
	floor_number = floor_no
	is_over = false
	stolen_gold = 0
	scheduler = CtbScheduler.new()
	scheduler.add_all(allies)
	scheduler.add_all(enemies)


# --------------------------------------------------------------------------
# 進行
# --------------------------------------------------------------------------


## 次の手番を開始し、行動者を返す。防御はこの時点で切れる。
func begin_turn() -> Battler:
	var actor := scheduler.next_actor()
	if actor != null:
		actor.guarding = false
	return actor


func turn_order(count: int = 8) -> Array[Battler]:
	return scheduler.preview(count)


## その者が今使える技（MP 不足のものは除く）。
func usable_abilities(actor: Battler) -> Array[String]:
	var result: Array[String] = []
	for id in actor.abilities:
		if actor.can_pay(Database.ability(id)):
			result.append(id)
	return result


func living_allies() -> Array[Battler]:
	return scheduler.living_allies()


func living_enemies() -> Array[Battler]:
	return scheduler.living_enemies()


# --------------------------------------------------------------------------
# 行動の解決
# --------------------------------------------------------------------------


## 行動を実行し、表示用のログ行を返す。
func perform(actor: Battler, ability_id: String, target: Battler = null) -> Array[String]:
	var ab := Database.ability(ability_id)
	if ab.is_empty():
		push_error("未定義のアビリティ: %s" % ability_id)
		return []

	last_ability_id = ability_id
	var lines: Array[String] = []
	actor.mp = maxi(actor.mp - int(ab.get("mp", 0)), 0)
	lines.append("%sの　%s！" % [actor.name, ab.get("name", ability_id)])

	var targets := _resolve_targets(actor, ab, target)
	var kind := String(ab.get("kind", "physical"))
	var power := int(ab.get("power", 0))

	match kind:
		"physical", "magical":
			for t in targets:
				var dmg := _damage(actor, t, power, kind == "magical")
				t.apply_damage(dmg)
				lines.append("%sに　%d の ダメージ！" % [t.name, dmg])
				if not t.is_alive():
					lines.append("%sを　たおした！" % t.name)
		"heal":
			for t in targets:
				if String(ab.get("target", "")) == "one_ally_dead":
					if t.is_alive():
						lines.append("しかし　なにも おこらなかった")
						continue
					t.hp = maxi(t.max_hp * power / 100, 1)
					lines.append("%sは　いきを ふきかえした！" % t.name)
				else:
					var healed := t.heal(power + actor.mag / 2)
					lines.append("%sの　きずが %d かいふくした" % [t.name, healed])
		"buff", "debuff", "special":
			lines.append_array(_apply_effect(actor, ab, targets))

	# 行動コスト x 職業のテンポ倍率のぶんだけ、この者の次の手番が先に進む。
	scheduler.consume(actor, actor.scaled_cost(int(ab.get("cost", CtbScheduler.STANDARD_COST))))

	_check_finished()
	return lines


func _resolve_targets(actor: Battler, ab: Dictionary, chosen: Battler) -> Array[Battler]:
	match String(ab.get("target", "one_enemy")):
		"self":
			return [actor] as Array[Battler]
		"all_enemies":
			return living_enemies() if actor.is_ally else living_allies()
		"all_allies":
			return living_allies() if actor.is_ally else living_enemies()
		_:
			if chosen != null:
				return [chosen] as Array[Battler]
			# 対象が死んでいた等で未指定なら、生存者から選び直す
			var pool := living_enemies() if actor.is_ally else living_allies()
			return ([pool[0]] as Array[Battler]) if not pool.is_empty() else ([] as Array[Battler])


@warning_ignore("integer_division")
func _damage(actor: Battler, target: Battler, power: int, magical: bool) -> int:
	# 物理は防御力をまともに受け、魔法は半分しか受けない。
	var base := (actor.mag if magical else actor.atk) * power / 100
	var reduction := target.defense / 4 if magical else target.defense / 2
	var dmg := base - reduction
	dmg = dmg * rng.range_i(VARIANCE_LOW, VARIANCE_HIGH) / 100
	if target.guarding:
		dmg = dmg / 2
	return maxi(dmg, 1)


func _apply_effect(actor: Battler, ab: Dictionary, targets: Array[Battler]) -> Array[String]:
	var lines: Array[String] = []
	var effect := String(ab.get("effect", ""))

	# ぼうぎょ（effect 指定なしの self 技）
	if effect == "" and String(ab.get("target", "")) == "self":
		actor.guarding = true
		lines.append("%sは　みをまもっている" % actor.name)
		return lines

	for t in targets:
		match effect:
			"haste":
				t.agi_scale = 150
				lines.append("%sの　すばやさが あがった！" % t.name)
			"slow":
				t.agi_scale = 70
				# 素早さが落ちた効果を行動順にも即座に反映させる
				t.next_at += CtbScheduler.wait_for(t.effective_agi(), 40)
				lines.append("%sの　すばやさが さがった！" % t.name)
			"defend_up":
				t.guarding = true
				lines.append("%sを　かばう たいせいに はいった" % t.name)
			"steal":
				var loot := rng.range_i(2, 6 + floor_number * 2)
				stolen_gold += loot
				lines.append("%sから　%d ゴールドを ぬすんだ！" % [t.name, loot])
			_:
				lines.append("しかし　なにも おこらなかった")
	return lines


# --------------------------------------------------------------------------
# 道具
# --------------------------------------------------------------------------


## 道具を使う。技と同じく手番を消費するので、
## 「回復に 1 手番を割く」という CTB 上の判断がそのまま成立する。
##
## 在庫の増減は呼び出し側（GameState）の責任にして、ここは効果の解決だけを持つ。
## 戦闘ロジックがランの持ち物を書き換え始めると、戦闘だけを切り出して
## 何千回も回すことができなくなる。
func use_item(actor: Battler, item_id: String, target: Battler) -> Array[String]:
	var it := Database.item(item_id)
	if it.is_empty():
		push_error("未定義の道具: %s" % item_id)
		return []

	var lines: Array[String] = []
	var who := target if target != null else actor
	lines.append("%sは %s を つかった！" % [actor.name, it.get("name", item_id)])

	var power := int(it.get("power", 0))
	match String(it.get("effect", "")):
		"heal_hp":
			if not who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				lines.append("%sの きずが %d かいふくした" % [who.name, who.heal(power)])
		"heal_mp":
			var before := who.mp
			who.mp = mini(who.mp + power, who.max_mp)
			lines.append("%sの まりょくが %d もどった" % [who.name, who.mp - before])
		"revive":
			if who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				who.hp = maxi(who.max_hp * power / 100, 1)
				lines.append("%sは いきを ふきかえした！" % who.name)
		_:
			lines.append("しかし　なにも おこらなかった")

	scheduler.consume(actor, actor.scaled_cost(int(it.get("cost", CtbScheduler.STANDARD_COST))))
	_check_finished()
	return lines


# --------------------------------------------------------------------------
# 敵の行動（決定的な単純 AI）
# --------------------------------------------------------------------------


## 敵の行動を決めて実行する。LLM は一切関与させない。
## 行動決定は決定的でなければリプレイもバランス測定も成立しないため。
func perform_enemy(actor: Battler) -> Array[String]:
	var usable := usable_abilities(actor)
	if usable.is_empty():
		usable = ["attack"]

	# 手負いの相手を狙いやすくする程度の、素朴だが読める AI。
	var ability_id: String = rng.pick(usable)
	var ab := Database.ability(ability_id)
	var target: Battler = null
	if String(ab.get("target", "one_enemy")).begins_with("one_enemy"):
		var pool := living_allies()
		if pool.is_empty():
			return []
		target = pool[0]
		for candidate in pool:
			if candidate.hp < target.hp and rng.chance(60):
				target = candidate
	return perform(actor, ability_id, target)


# --------------------------------------------------------------------------


func _check_finished() -> void:
	if is_over:
		return
	if scheduler.is_over():
		is_over = true
		finished.emit(scheduler.allies_won())


func victory() -> bool:
	return scheduler.allies_won()


## 勝利報酬。熟練度は戦闘 1 回ごとに入るので、
## 「深く潜るほど職業が育つ」が自然に成立する。
func rewards() -> Dictionary:
	return {
		"exp": Encounter.total_exp(enemies),
		"gold": Encounter.total_gold(enemies) + stolen_gold,
		"mastery": 4 + floor_number,
	}
