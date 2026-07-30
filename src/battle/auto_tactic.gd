class_name AutoTactic
extends RefCounted

## オート戦闘の指針（SFC 期の「さくせん」に当たるもの）。
##
## 賢さより**読めること**を優先する。何をするか分からない自動戦闘は使われない。
## DQ4 の作戦が優秀なのは、プレイヤーの意図を 1 語で渡せるところ。
##
##   いのちだいじに … 傷が深い者がいれば回復を最優先
##   ガンガンいこうぜ … 回復しない。時間あたりの効率が最大の攻撃だけを打つ
##
## 戦闘画面から切り出してあるのは、ここが「判断」で、あちらが「表示と入力」だから。
## balance.gd の自動操縦と方針を揃えたいときも、ここだけ見ればよい。

enum Mode { OFF, SAFE, AGGRESSIVE }

const LABELS := {
	Mode.OFF: "オート",
	Mode.SAFE: "オート（いのち）",
	Mode.AGGRESSIVE: "オート（ガンガン）",
}

## この割合を下回った味方がいれば回復に回る（いのちだいじに）。
const HURT_RATIO := 45


static func label(mode: Mode) -> String:
	return String(LABELS[mode])


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
		var hurt := _most_hurt(system)
		if hurt != null:
			var heal_id := _best_heal(system, actor)
			if heal_id != "":
				return {"ability": heal_id, "target": hurt}

	var attack_id := _best_attack(system, actor)
	var scope := String(Database.ability(attack_id).get("target", "one_enemy"))
	if scope in ["self", "all_enemies", "all_allies"]:
		return {"ability": attack_id, "target": null}

	# 手負いの敵から片付ける。数を減らすほうが受ける被害が減る。
	var target: Battler = null
	for b in system.living_enemies():
		if target == null or b.hp < target.hp:
			target = b
	return {"ability": attack_id, "target": target}


static func _most_hurt(system: BattleSystem) -> Battler:
	var worst: Battler = null
	for b in system.living_allies():
		if b.hp * 100 / maxi(b.max_hp, 1) > HURT_RATIO:
			continue
		if worst == null or b.hp * worst.max_hp < worst.hp * b.max_hp:
			worst = b
	return worst


static func _best_heal(system: BattleSystem, actor: Battler) -> String:
	for id in system.usable_abilities(actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) == "heal" and String(ab.get("target", "")) == "one_ally":
			return id
	return ""


## いちばん効率の高い攻撃。属性の相性までは見ない（見ると読めなくなる）。
## CTB では「1 手あたり」ではなく「時間あたり」が効率なので、コストで割る。
static func _best_attack(system: BattleSystem, actor: Battler) -> String:
	var best := "attack"
	var best_score := 0
	var foes := system.living_enemies().size()
	for id in system.usable_abilities(actor):
		var ab := Database.ability(id)
		if String(ab.get("kind", "")) not in ["physical", "magical"]:
			continue
		var score := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		if String(ab.get("target", "")) in ["group_enemy", "all_enemies"]:
			score = score * mini(foes, 3) / 2
		score = score * 100 / maxi(int(ab.get("cost", 100)), 1)
		if score > best_score:
			best_score = score
			best = id
	return best
