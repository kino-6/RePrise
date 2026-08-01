class_name AutoTactic
extends RefCounted

## オート戦闘の指針（SFC 期の「さくせん」に当たるもの）。
##
## **何を基準に動いているかが読めること**が最優先。
## 「通常攻撃を連打しているだけに見える」と言われたら、それは指針が悪いのではなく
## 指針が見えていない。ここに書いた優先順位が、そのまま画面の説明文になる。
##
## いのちだいじに（SAFE）
##   1. 倒れた仲間がいて、起こす手があるなら起こす
##   2. 誰かが半分を切っていたら回復する
##   3. 状態異常を受けている者がいて、解く手があるなら解く
##   4. あとは MP を使わない攻撃で削る（回復ぶんの MP を残す）
##
## ガンガンいこうぜ（AGGRESSIVE）
##   1. 弱点を突ける属性の技があればそれを撃つ
##   2. 敵が 2 体以上なら範囲技（1 体には減衰で損をするので撃たない）
##   3. あとは時間あたりの効率が最大の技（MP は惜しまない）
##
## 判断だけを持ち、実行は戦闘画面に任せる。balance.gd の自動操縦と方針を
## 揃えたいときも、ここだけ見ればよい。

enum Mode { OFF, SAFE, AGGRESSIVE }

## 画面に出す呼び名。**短く、何をするかがそのまま分かる語にする。**
## 「いのちだいじに」「ガンガンいこうぜ」は他社の言い方でもあるし、
## 括弧書きが増えて読みにくかった。
static var LABELS := {
	Mode.OFF: Vocabulary.word("auto", "off", "オート"),
	Mode.SAFE: Vocabulary.word("auto", "safe", "守備重視"),
	Mode.AGGRESSIVE: Vocabulary.word("auto", "aggressive", "攻撃重視"),
}

## 画面に出す基準。選ぶ前に何をするか分かるようにする。
## 選ぶ前の説明。**画面の隅には出さない。**
## 戦闘中の隅に長い説明を置くと、読まないのに場所を取るだけになる
## （「わけのわからない文言」と言われた）。呼び名で足りる。
static var DESCRIPTIONS := {
	Mode.OFF: Vocabulary.word("auto", "off_desc", "自分で選ぶ"),
	Mode.SAFE: Vocabulary.word("auto", "safe_desc", "回復を優先し、MPを残して攻める"),
	Mode.AGGRESSIVE: Vocabulary.word("auto", "aggressive_desc", "弱点と範囲を狙って攻める"),
}

## この割合を下回った味方がいれば回復に回る（いのちだいじに）。
const HURT_RATIO := 45


static func label(mode: Mode) -> String:
	return String(LABELS[mode])


static func description(mode: Mode) -> String:
	return String(DESCRIPTIONS[mode])


## 最後に選んだ作戦。**戦闘をまたいで覚える。**
## 毎回 OFF から入れ直すのは、連戦のたびに同じ操作を繰り返させることになる。
static var last_mode: Mode = Mode.OFF


static func remember(mode: Mode) -> void:
	last_mode = mode


static func next_mode(mode: Mode) -> Mode:
	match mode:
		Mode.OFF:
			return Mode.SAFE
		Mode.SAFE:
			return Mode.AGGRESSIVE
		_:
			return Mode.OFF


## この手番に取る行動。技なら `ability`、救命用の消耗品なら `item` を返す。
## `items` を空で渡せば従来どおり道具を一切考えない。
static func decide(
	system: BattleSystem, actor: Battler, mode: Mode, items: Dictionary = {}
) -> Dictionary:
	var ultimate := _ultimate_plan(system, actor, mode)
	if not ultimate.is_empty():
		return ultimate
	if mode == Mode.SAFE:
		var safe := _safe_plan(system, actor)
		if not safe.is_empty():
			return safe
		var rescue := _item_plan(system, mode, items)
		if not rescue.is_empty():
			return rescue
	elif mode == Mode.AGGRESSIVE:
		# 攻撃重視でも、倒れた仲間と瀕死は放置しない。許可された道具だけを使う。
		var rescue := _item_plan(system, mode, items)
		if not rescue.is_empty():
			return rescue
		var strike := _weakness_plan(system, actor)
		if not strike.is_empty():
			return strike

	var attack_id := _best_attack(system, actor, mode)
	var scope := String(Database.ability(attack_id).get("target", "one_enemy"))
	if scope in ["self", "all_enemies", "all_allies"]:
		return {"ability": attack_id, "target": null}

	var target := _best_target(system, actor, attack_id)
	return {"ability": attack_id, "target": target}


## 許可されたときだけ使う、救命用の消耗品。
##
## 攻撃びん・加速薬・MP回復は、いつ切るかがラン全体の判断になるので自動消費しない。
## 蘇生、瀕死回復、守備重視の状態回復に絞り、「許可したら在庫を使い切る」を防ぐ。
static func _item_plan(system: BattleSystem, mode: Mode, items: Dictionary) -> Dictionary:
	if items.is_empty():
		return {}

	for friend in system.allies:
		if friend.is_alive():
			continue
		var revive := _first_item_with_effect(items, ["revive"])
		if revive != "":
			return {"item": revive, "target": friend}
		break

	var emergency_ratio := 30 if mode == Mode.SAFE else 20
	var hurt := _most_hurt_below(system, emergency_ratio)
	if hurt != null:
		var healing := _best_healing_item(items, hurt.max_hp - hurt.hp)
		if healing != "":
			return {"item": healing, "target": hurt}

	if mode == Mode.SAFE:
		for friend in system.living_allies():
			if not friend.has_status():
				continue
			var cure := _first_item_with_effect(items, ["cleanse", "heal_cleanse"])
			if cure != "":
				return {"item": cure, "target": friend}
			break
	return {}


static func _owned_item_ids(items: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id in items:
		var id := String(raw_id)
		if int(items.get(raw_id, 0)) > 0 and not Database.item(id).is_empty():
			ids.append(id)
	ids.sort()
	return ids


## 同じ役割なら安い品を先に使う。価格も同じなら id 順で決定的にする。
static func _first_item_with_effect(items: Dictionary, effects: Array[String]) -> String:
	var best := ""
	var best_price := 1 << 30
	for id in _owned_item_ids(items):
		var item := Database.item(id)
		if String(item.get("effect", "")) not in effects:
			continue
		var price := int(item.get("price", 0))
		if price < best_price or (price == best_price and (best == "" or id < best)):
			best = id
			best_price = price
	return best


## 必要量を満たす最小の回復品を選ぶ。不足する品を連打したり、軽傷へ全快薬を切らない。
static func _best_healing_item(items: Dictionary, missing_hp: int) -> String:
	var best := ""
	var best_score := 1 << 60
	for id in _owned_item_ids(items):
		var item := Database.item(id)
		var effect := String(item.get("effect", ""))
		if effect not in ["heal_hp", "heal_cleanse"]:
			continue
		var power := maxi(int(item.get("power", 0)), 0)
		if power <= 0:
			continue
		var shortfall := maxi(missing_hp - power, 0)
		var waste := maxi(power - missing_hp, 0)
		# まず回復不足を避け、次に過剰回復と複合薬の温存、最後に価格を見る。
		var score := (
			shortfall * 100000
			+ waste * 100
			+ (10000 if effect == "heal_cleanse" else 0)
			+ int(item.get("price", 0))
		)
		if score < best_score or (score == best_score and (best == "" or id < best)):
			best = id
			best_score = score
	return best


static func _most_hurt_below(system: BattleSystem, ratio: int) -> Battler:
	var worst: Battler = null
	for friend in system.living_allies():
		if friend.hp * 100 / maxi(friend.max_hp, 1) > ratio:
			continue
		if worst == null or friend.hp * worst.max_hp < worst.hp * friend.max_hp:
			worst = friend
	return worst


## 1戦1回の奥義は、単純な「威力÷CTB」へ混ぜない。
##
## 守備重視は倒れた人数・傷・状態・敵予告を、攻撃重視は中断・弱点看破・
## 敵数・総打撃量を見る。これで治療や手番操作の奥義も実際に選択肢へ入る（F-7）。
static func _ultimate_plan(
	system: BattleSystem, actor: Battler, mode: Mode
) -> Dictionary:
	var ultimates: Array[String] = []
	for id in system.usable_abilities(actor):
		if String(Database.ability(id).get("ultimate_rule", "")) != "":
			ultimates.append(id)
	if ultimates.is_empty():
		return {}

	var fallen := 0
	var hurt := 0
	var troubled := 0
	for friend in system.allies:
		if not friend.is_alive():
			fallen += 1
		elif friend.hp * 100 / maxi(friend.max_hp, 1) <= HURT_RATIO:
			hurt += 1
		if friend.has_status():
			troubled += 1

	if mode == Mode.SAFE:
		if fallen > 0:
			var revival := _ultimate_with_rule(ultimates, ["returning_bell", "curtain_return"])
			if revival != "":
				return {"ability": revival, "target": null}
		if hurt >= 2 or troubled >= 2:
			var recovery := _ultimate_with_rule(
				ultimates, ["sanctuary", "guardian_pact", "curtain_return", "chain_compound"])
			if recovery != "":
				return {"ability": recovery, "target": null}
		if hurt > 0 and _planned_enemy(system) != null:
			var shelter := _ultimate_with_rule(
				ultimates, ["vow_of_life", "unyielding_line", "counter_phalanx"])
			if shelter != "":
				return {"ability": shelter, "target": null}
		return {}

	# 攻撃重視。奥義は毎戦の初手ではなく、主戦か劣勢を返す札として使う。
	# 3人が半分を切る／誰かが倒れる、のどちらかを危機とする。
	var crisis := fallen > 0 or hurt >= 3
	var toughest := _toughest_enemy(system)
	var boss_fight := (
		toughest != null
		and bool(Database.monster(toughest.source_id).get("boss", false))
	)

	# 予告を止められるなら、総威力より先に止める。ただの通常戦の予告へ
	# 1戦1回札を毎回切らず、主戦か危機にだけ使う。
	var casting := _planned_enemy(system)
	if casting != null and (boss_fight or crisis):
		var interrupt := _ultimate_with_rule(
			ultimates, ["lockbreaker_round", "time_exchange", "time_pilfer"])
		if interrupt != "":
			return {"ability": interrupt, "target": casting}

	# 強敵には、先に後続の三撃を伸ばすか耐性を抜く。
	#
	# HP が少し高い通常敵まで「強敵」にすると、1 戦ごとに回復する奥義を
	# 道中で毎回開幕使用し、温存する判断が消える。看破・標は主戦だけ先行する。
	if boss_fight and crisis:
		var setup := _ultimate_with_rule(ultimates, ["hunter_mark", "phase_reveal"])
		if setup != "":
			return {"ability": setup, "target": toughest}

	# その場で最も大きく戦況を動かす攻撃奥義。power 0 の複合奥義にも
	# 固有の評価を与え、単なる数値技だけが選ばれ続けないようにする。
	# ただし通常戦で無傷なら使わない。1 戦制限は「毎戦ただ押すボタン」ではなく、
	# 主戦か、多数の敵に押し込まれた時の切り返しとして選ぶ。
	if not crisis or (not boss_fight and system.living_enemies().size() < 4):
		return {}
	var best := ""
	var best_score := -1
	for id in ultimates:
		var ab := Database.ability(id)
		var rule := String(ab.get("ultimate_rule", ""))
		var score := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		if String(ab.get("target", "")) == "all_enemies":
			score = score * mini(system.living_enemies().size(), 3)
		match rule:
			"fourfold_collapse", "fourfold_edge":
				score = int(ab.get("power", 0)) * 4
			"astral_beast_array", "beast_procession":
				score += 180
			"wise_furnace":
				score = 90 + actor.mp * 2
			"twin_ring_cast":
				score = 260
			"fate_cards", "curtain_return":
				score = 190
			"time_pilfer", "time_exchange", "zero_time_field":
				score = 120
		if score > best_score or (score == best_score and id < best):
			best_score = score
			best = id
	if best == "":
		return {}
	return {"ability": best, "target": _ultimate_target(system, best)}


static func _ultimate_with_rule(ids: Array[String], ordered_rules: Array[String]) -> String:
	for rule in ordered_rules:
		for id in ids:
			if String(Database.ability(id).get("ultimate_rule", "")) == rule:
				return id
	return ""


static func _planned_enemy(system: BattleSystem) -> Battler:
	for foe in system.living_enemies():
		if foe.planned_ability != "":
			return foe
	return null


static func _toughest_enemy(system: BattleSystem) -> Battler:
	var toughest: Battler = null
	for foe in system.living_enemies():
		if (
			toughest == null
			or foe.hp > toughest.hp
			or (foe.hp == toughest.hp and foe.id < toughest.id)
		):
			toughest = foe
	return toughest


static func _ultimate_target(system: BattleSystem, ability_id: String) -> Battler:
	var ab := Database.ability(ability_id)
	var scope := String(ab.get("target", "one_enemy"))
	if scope in ["self", "all_enemies", "all_allies"]:
		return null
	var rule := String(ab.get("ultimate_rule", ""))
	if rule == "pacify":
		for foe in system.living_enemies():
			if (
				not bool(Database.monster(foe.source_id).get("boss", false))
				and foe.hp * 100 / maxi(foe.max_hp, 1) <= 50
			):
				return foe
	if rule in ["hunter_mark", "phase_reveal"]:
		return _toughest_enemy(system)
	var target: Battler = null
	for foe in system.living_enemies():
		if target == null or foe.hp < target.hp or (foe.hp == target.hp and foe.id < target.id):
			target = foe
	return target


## いのちだいじに の前半（起こす・癒す・治す）。やることが無ければ空。
static func _safe_plan(system: BattleSystem, actor: Battler) -> Dictionary:
	var fallen: Battler = null
	for b in system.allies:
		if not b.is_alive():
			fallen = b
			break
	if fallen != null:
		var revive := _find(system, actor, func(ab: Dictionary) -> bool:
			return String(ab.get("target", "")) == "one_ally_dead")
		if revive != "":
			return {"ability": revive, "target": fallen}

	var hurt := _most_hurt(system)
	if hurt != null:
		var heal_id := _find(system, actor, func(ab: Dictionary) -> bool:
			return (
				String(ab.get("kind", "")) == "heal"
				and String(ab.get("target", "")) == "one_ally"
				and String(ab.get("effect", "")) != "cleanse"
			))
		if heal_id != "":
			return {"ability": heal_id, "target": hurt}

	for b in system.living_allies():
		if not b.has_status():
			continue
		var cure := _find(system, actor, func(ab: Dictionary) -> bool:
			return String(ab.get("effect", "")) == "cleanse")
		if cure != "":
			return {"ability": cure, "target": b}
		break
	return {}


## ガンガン の前半（弱点を突く）。突ける相手がいなければ空。
static func _weakness_plan(system: BattleSystem, actor: Battler) -> Dictionary:
	var best_id := ""
	var best_power := 0
	var best_target: Battler = null
	for id in system.usable_abilities(actor):
		var ab := Database.ability(id)
		var element := String(ab.get("element", ""))
		if element == "" or String(ab.get("kind", "")) not in ["physical", "magical"]:
			continue
		for foe in system.living_enemies():
			if element not in foe.weak:
				continue
			var score := _attack_score(system, actor, id, foe)
			if score > best_power:
				best_power = score
				best_id = id
				best_target = foe
	if best_id == "":
		return {}
	return {"ability": best_id, "target": best_target}


static func _find(system: BattleSystem, actor: Battler, matches: Callable) -> String:
	for id in system.usable_abilities(actor):
		if matches.call(Database.ability(id)):
			return id
	return ""


static func _most_hurt(system: BattleSystem) -> Battler:
	var worst: Battler = null
	for b in system.living_allies():
		if b.hp * 100 / maxi(b.max_hp, 1) > HURT_RATIO:
			continue
		if worst == null or b.hp * worst.max_hp < worst.hp * b.max_hp:
			worst = b
	return worst


## いちばん効率の高い攻撃。
##
## CTB では「1 手あたり」ではなく「時間あたり」が効率なので、コストで割る。
## いのちだいじに のときは MP を使う技を避ける（回復ぶんを残すため）。
static func _best_attack(system: BattleSystem, actor: Battler, mode: Mode) -> String:
	var best := "attack"
	var best_score := 0
	var foes := system.living_enemies().size()
	var target := _best_target(system, actor, "attack")
	for id in system.usable_abilities(actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) not in ["physical", "magical"]:
			continue
		if mode == Mode.SAFE and int(ab.get("mp", 0)) > 0:
			continue
		# 技どうしの比較は、実ダメージを完全に先読みしない。そこまで最適化すると
		# オートだけが毎手番の最善解を知り、同じ500 seedで難度帯を壊した。
		# 威力/CTBを土台にしつつ、防御・耐性・予告・状態・副次目的を補正に使う。
		var score := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		if target != null:
			var magical := String(ab.get("kind", "")) == "magical"
			score = maxi(score - target.defense / (8 if magical else 4), 1)
			var element := String(ab.get("element", ""))
			if element in target.weak:
				score = score * 2
			elif element in target.resist:
				score = score / 2
		if String(ab.get("target", "")) in ["group_enemy", "all_enemies"]:
			# 総ダメージを全部足すと範囲だけが常時最適になる。人数は見るが、
			# 各個撃破の価値を残すため3体までを半分の重みで数える。
			score = score * mini(foes, 3) / 2
		match String(ab.get("effect", "")):
			"poison":
				if target != null and target.poison_turns <= 0:
					score += 8
			"stillness":
				if target != null and target.planned_ability != "":
					score += 24
			"mend":
				if _most_hurt(system) != null:
					score += 18
			"steal_and_haste":
				if target != null and not system.stolen_targets.has(target.id):
					score += 12
		score = score * 100 / maxi(int(ab.get("cost", 100)), 1)
		if score > best_score:
			best_score = score
			best = id
	return best


## 防御・弱点・予告・状態・人数・副次効果を含む、乱数を使わない見積もり。
## 実ダメージの乱数は BattleSystem だけが引く。オートが先に乱数を消費してはならない。
static func _attack_score(
	system: BattleSystem, actor: Battler, ability_id: String, target: Battler
) -> int:
	var ab := Database.ability(ability_id)
	var magical := String(ab.get("kind", "")) == "magical"
	var power := int(ab.get("power", 0))
	var hits := maxi(int(ab.get("hits", 1)), 1)
	var base := (actor.mag if magical else actor.atk) * power / 100
	var reduction := target.defense / 4 if magical else target.defense / 2
	if bool(ab.get("pierce", false)):
		reduction = 0
	var per_hit := maxi(base - reduction, 1)
	var element := String(ab.get("element", ""))
	if element in target.weak:
		per_hit = per_hit * BattleSystem.ELEMENT_WEAK / 100
	elif element in target.resist:
		per_hit = per_hit * BattleSystem.ELEMENT_RESIST / 100
	var score := per_hit * hits
	var scope := String(ab.get("target", "one_enemy"))
	if scope in ["group_enemy", "all_enemies"]:
		var count := system.living_enemies().size()
		# 総ダメージをそのまま足すと、敵を倒さず薄く削る範囲技を過大評価する。
		# 撃破による被害軽減も半分の価値として残し、人数は見るが常時最適にしない。
		score = score * BattleSystem.spread_bonus(count) * mini(count, 3) / 200

	# 同じ威力なら、今の戦況をもう一つ解く技を優先する。
	match String(ab.get("effect", "")):
		"poison":
			if target.poison_turns <= 0 and target.hp > score:
				score += target.max_hp / 12
		"afterimage", "execute":
			if target.hp <= score:
				score += 90
		"mend":
			for friend in system.living_allies():
				if friend.hp * 100 / maxi(friend.max_hp, 1) <= HURT_RATIO:
					score += 70
					break
		"stillness":
			if target.planned_ability != "":
				score += 120
		"steal_and_haste":
			if not system.stolen_targets.has(target.id):
				score += 75
	return score * 100 / maxi(int(ab.get("cost", 100)), 1)


static func _best_target(
	system: BattleSystem, actor: Battler, ability_id: String
) -> Battler:
	var best: Battler = null
	for foe in system.living_enemies():
		# 敵を1体減らす価値は、防御差による数点の効率より大きい。
		# 弱点は前段の _weakness_plan が拾うので、通常時は手負いを集中して落とす。
		if (
			best == null
			or foe.hp < best.hp
			or (foe.hp == best.hp and foe.id < best.id)
		):
			best = foe
	return best
