extends SceneTree

## バランス測定 — ランを最後まで自動で回して、どこで死ぬかを数える。
##
##   godot --headless --script res://tests/balance.gd
##
## 戦闘が描画も入力も持たない設計にしてある最大の実利がこれ。数値をいじる
## たびに何千回でも回せるので、勘で調整せずに済む。
##
## 前提（変えるとここを直す）
##   * 1 階につき 4 戦。実際の遭遇率は歩数依存なので、平均的な回数を置いている
##   * 味方の判断は素朴な自動操縦。人が操作すればこれより強くなるので、
##     ここで出る勝率は「下限」として読む
##   * 道具は使わない。出店の効果は測っていない

const RUNS := 200
const ENCOUNTERS_PER_FLOOR := 4
const MAX_TURNS := 400

const PARTY := [
	{ "name": "アレン", "job": "soldier" },
	{ "name": "セラ", "job": "priest" },
	{ "name": "ノア", "job": "mage" },
	{ "name": "キリ", "job": "thief" },
]


func _initialize() -> void:
	Database.reload()
	var final_floor: int = load("res://src/game/game_state.gd").get_script_constant_map()["FINAL_FLOOR"]

	print("=== バランス測定 ===")
	print("%d ラン / 1 階あたり %d 戦 / 最終階 %d" % [RUNS, ENCOUNTERS_PER_FLOOR, final_floor])

	var died_on := {}
	var wins := 0
	var boss_attempts := 0
	var level_sum := 0
	# 稼ぎも測る。出店で何が買えるかはここで決まるのに、測っていなかった
	# （「3 階まで来たのに何も買えない」という指摘で気づいた）。
	var gold_at := {3: 0, 5: 0, 10: 0}
	var gold_runs := {3: 0, 5: 0, 10: 0}

	for i in RUNS:
		var result := _simulate_run(i * 7919 + 13, final_floor)
		level_sum += int(result["level"])
		for milestone in [3, 5, 10]:
			if int(result["gold_at_%d" % milestone]) >= 0 and int(result["floor"]) >= milestone:
				gold_at[milestone] += int(result["gold_at_%d" % milestone])
				gold_runs[milestone] += 1
		if bool(result["victory"]):
			wins += 1
		var reached := int(result["floor"])
		died_on[reached] = int(died_on.get(reached, 0)) + 1
		if bool(result["reached_boss"]):
			boss_attempts += 1

	print("---")
	print("到達階の分布（そこで終わったラン数）")
	for f in range(1, final_floor + 1):
		var count := int(died_on.get(f, 0))
		var bar := "#".repeat(count * 40 / maxi(RUNS, 1))
		print("  地下 %2d 階  %3d  %s" % [f, count, bar])

	print("---")
	print("主に挑めた   : %d / %d (%d%%)" % [boss_attempts, RUNS, boss_attempts * 100 / RUNS])
	print("主を倒した   : %d / %d (%d%%)" % [wins, RUNS, wins * 100 / RUNS])
	print("平均レベル   : %.1f" % (float(level_sum) / float(RUNS)))
	print("---")
	print("その階までの稼ぎ（累計・出店に使える額）")
	for milestone in [3, 5, 10]:
		var runs := int(gold_runs[milestone])
		if runs == 0:
			continue
		print("  地下 %2d 階まで  %4d ゴールド（%d ラン）" % [
			milestone, int(gold_at[milestone]) / runs, runs
		])
	print("---")
	print(_verdict(wins * 100 / RUNS, boss_attempts * 100 / RUNS))
	quit(0)


## 測定結果の読みかた。数字だけ出しても判断が要るので、目安を添える。
func _verdict(win_rate: int, boss_rate: int) -> String:
	if boss_rate < 15:
		return "所見: 道中が重い。主にすら届かないランが多すぎる。"
	if win_rate > 60:
		return "所見: 易しい。自動操縦でこれだけ勝てるなら人が操作すると素通りになる。"
	if win_rate < 5:
		return "所見: 主が硬い。届いても勝てないので、最後の壁として機能していない。"
	return "所見: 妥当。自動操縦での勝率がこの帯なら、人が操作して手応えのある難度になる。"


# --------------------------------------------------------------------------


func _simulate_run(seed_value: int, final_floor: int) -> Dictionary:
	var members: Array[PartyMember] = []
	for entry in PARTY:
		var m := PartyMember.create(String(entry["name"]), String(entry["job"]))
		# 実際のランと同じく初期装備を着せる。着せずに測ると、
		# ここで出る数字が遊んでいる状態と食い違う。
		for gear_id in Database.job(m.job_id).get("starting_gear", []):
			m.equip(String(gear_id))
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		members.append(m)

	var floor_number := 1
	var gold_total := 0
	var gold_marks := {3: -1, 5: -1, 10: -1}
	while floor_number <= final_floor:
		var rng := DetRng.new(seed_value).fork("battle:%d" % floor_number)

		for _e in ENCOUNTERS_PER_FLOOR:
			var foes := Encounter.build(rng, floor_number)
			if foes.is_empty():
				continue
			var earned := _fight_gold(members, foes, rng, floor_number)
			if earned < 0:
				return _result(members, floor_number, false, false, gold_marks)
			gold_total += earned

		if gold_marks.has(floor_number):
			gold_marks[floor_number] = gold_total

		if floor_number == final_floor:
			var boss := Encounter.build_boss(rng, floor_number)
			if boss.is_empty():
				return _result(members, floor_number, false, false, gold_marks)
			var won := _fight(members, boss, rng, floor_number)
			return _result(members, floor_number, won, true, gold_marks)

		floor_number += 1

	return _result(members, final_floor, false, false, gold_marks)


func _result(
	members: Array[PartyMember], floor_number: int, victory: bool, reached_boss: bool,
	gold_marks: Dictionary = {}
) -> Dictionary:
	var level := 0
	for m in members:
		level = maxi(level, m.level)
	return {
		"floor": floor_number,
		"victory": victory,
		"reached_boss": reached_boss,
		"level": level,
		"gold_at_3": int(gold_marks.get(3, -1)),
		"gold_at_5": int(gold_marks.get(5, -1)),
		"gold_at_10": int(gold_marks.get(10, -1)),
	}


## 1 戦ぶん回して、稼いだゴールドを返す。負けたら -1。
func _fight_gold(
	members: Array[PartyMember], foes: Array[Battler], rng: DetRng, floor_number: int
) -> int:
	# GDScript のラムダは値で捕まえるので、int を代入しても外へ返らない。
	# 参照型（辞書）に入れて受け取る。
	var box := {"gold": 0}
	var won := _fight(members, foes, rng, floor_number, func(reward: Dictionary) -> void:
		box["gold"] = int(reward["gold"])
	)
	return int(box["gold"]) if won else -1


## 1 戦ぶん回して、勝ったかどうかを返す。勝てば経験と熟練が入る。
func _fight(
	members: Array[PartyMember], foes: Array[Battler], rng: DetRng, floor_number: int,
	on_reward: Callable = Callable()
) -> bool:
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))

	var system := BattleSystem.new()
	system.start(party, foes, rng, floor_number)

	var turns := 0
	while not system.is_over and turns < MAX_TURNS:
		turns += 1
		var actor := system.begin_turn()
		if actor == null:
			break
		# 毒と眠りの解決。眠っていればこの手番は飛ぶ。
		var head: Dictionary = system.begin_turn_effects(actor)
		if bool(head["skipped"]):
			continue
		if actor.is_ally:
			var plan := _plan(system, actor)
			system.perform(actor, String(plan["ability"]), plan["target"])
		else:
			system.perform_enemy(actor)

	for i in members.size():
		if i < party.size():
			members[i].sync_from_battler(party[i])

	if not system.victory():
		return false

	var reward := system.rewards()
	if on_reward.is_valid():
		on_reward.call(reward)
	for m in members:
		if m.hp <= 0:
			continue
		m.gain_exp(int(reward["exp"]))
		m.gain_mastery(int(reward["mastery"]))
	return true


## 味方の自動操縦。素朴だが、人がやることの下限にはなっている。
##
##   1. 誰かが半分を切っていて、回復手段があるなら回復する
##   2. そうでなければ、撃てるうちで最も威力の高い技を、
##      いちばん削れている敵へ撃つ
func _plan(system: BattleSystem, actor: Battler) -> Dictionary:
	var usable := system.usable_abilities(actor)
	var allies := system.living_allies()
	var enemies := system.living_enemies()

	# --- 回復 ---
	var weakest: Battler = null
	for b in allies:
		if weakest == null or b.hp * weakest.max_hp < weakest.hp * b.max_hp:
			weakest = b
	if weakest != null and weakest.hp * 2 < weakest.max_hp:
		for id in usable:
			var ab := Database.ability(id)
			if String(ab.get("kind", "")) == "heal" and String(ab.get("target", "")) == "one_ally":
				return { "ability": id, "target": weakest }

	# --- 攻撃 ---
	var best := "attack"
	var best_power := -1
	for id in usable:
		var ab := Database.ability(id)
		var kind := String(ab.get("kind", ""))
		if kind != "physical" and kind != "magical":
			continue
		# 範囲技は敵が複数いるときだけ価値がある、と素朴に見積もる
		var power := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
		var scope := String(ab.get("target", ""))
		if scope == "all_enemies":
			power = power * enemies.size()
		elif scope == "group_enemy" and not enemies.is_empty():
			power = power * maxi(system.group_of(enemies[0]).size(), 1)
		if power > best_power:
			best_power = power
			best = id

	var target: Battler = null
	for b in enemies:
		if target == null or b.hp < target.hp:
			target = b
	return { "ability": best, "target": target }
