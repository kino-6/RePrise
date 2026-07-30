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
	Mode.OFF: Vocabulary.word("auto", "off_desc", "自分で えらぶ"),
	Mode.SAFE: Vocabulary.word("auto", "safe_desc", "回復を さきに、MP を のこして 攻める"),
	Mode.AGGRESSIVE: Vocabulary.word("auto", "aggressive_desc", "弱点と 範囲を ねらって 攻める"),
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


## この手番に取る行動。{"ability": String, "target": Battler} を返す。
static func decide(system: BattleSystem, actor: Battler, mode: Mode) -> Dictionary:
	if mode == Mode.SAFE:
		var safe := _safe_plan(system, actor)
		if not safe.is_empty():
			return safe
	elif mode == Mode.AGGRESSIVE:
		var strike := _weakness_plan(system, actor)
		if not strike.is_empty():
			return strike

	var attack_id := _best_attack(system, actor, mode)
	var scope := String(Database.ability(attack_id).get("target", "one_enemy"))
	if scope in ["self", "all_enemies", "all_allies"]:
		return {"ability": attack_id, "target": null}

	# 手負いの敵から片付ける。数を減らすほうが受ける被害が減る。
	var target: Battler = null
	for b in system.living_enemies():
		if target == null or b.hp < target.hp:
			target = b
	return {"ability": attack_id, "target": target}


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
			var power := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
			if power > best_power:
				best_power = power
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
	for id in system.usable_abilities(actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) not in ["physical", "magical"]:
			continue
		if mode == Mode.SAFE and int(ab.get("mp", 0)) > 0:
			continue
		var score := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		if String(ab.get("target", "")) in ["group_enemy", "all_enemies"]:
			# 範囲は敵が多いときだけ得。1 体に撃っても減衰で損をする。
			score = score * mini(foes, 3) / 2
		score = score * 100 / maxi(int(ab.get("cost", 100)), 1)
		if score > best_score:
			best_score = score
			best = id
	return best
