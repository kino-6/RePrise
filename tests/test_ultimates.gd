extends SceneTree

## ★7・8 奥義 30 種の契約 fixture（F-6b）。
##
## 各技について、成功・資源/状態不足・1戦制限・選択対象の消滅・
## 解決途中の決着・同一 seed の再現を同じ表から回す。

var passed := 0
var failed := 0
var ultimate_ids: Array[String] = []


func _initialize() -> void:
	Database.reload()
	for job_id in Database.job_ids():
		var mastery: Array = Database.job(String(job_id)).get("mastery", [])
		for entry in mastery:
			if int(entry.get("rank", 0)) not in [7, 8]:
				continue
			var ability_id := String(entry.get("ability", ""))
			if ability_id != "":
				ultimate_ids.append(ability_id)

	_check("15職×2奥義", ultimate_ids.size() == 30)
	for ability_id in ultimate_ids:
		_test_contract(ability_id)
	_test_auto_roles()

	print("---")
	print("奥義fixture 成功 %d / 失敗 %d" % [passed, failed])
	quit(1 if failed else 0)


func _make(
	id: int, name: String, ally: bool, hp: int = 700, mp: int = 999
) -> Battler:
	var b := Battler.new()
	b.id = id
	b.name = name
	b.is_ally = ally
	b.source_id = "gel"
	b.max_hp = hp
	b.hp = hp
	b.max_mp = mp
	b.mp = mp
	b.atk = 88
	b.mag = 82
	b.defense = 24
	b.agi = 20 + id
	b.abilities = ["attack"]
	return b


func _fixture(ability_id: String, seed_value: int, target_gone: bool = false) -> Dictionary:
	var actor := _make(1, "使い手", true)
	actor.abilities = [ability_id, "fire", "blast"]
	var friend := _make(2, "仲間", true, 620, 120)
	friend.hp = 210
	friend.poison_turns = 2
	var fallen := _make(3, "倒れた仲間", true, 540, 80)
	var foe := _make(11, "標的", false, 900, 80)
	var spare := _make(12, "次の標的", false, 900, 80)
	foe.weak = ["fire"]
	foe.resist = ["ice"]
	spare.weak = ["bolt"]
	spare.resist = ["dark"]
	foe.abilities = ["attack"]
	spare.abilities = ["attack"]
	var system := BattleSystem.new()
	system.start(
		[actor, friend, fallen] as Array[Battler],
		[foe, spare] as Array[Battler],
		DetRng.new(seed_value),
		8
	)

	# 条件付き奥義が成立する戦場を作る。
	match ability_id:
		"returning_bell":
			fallen.hp = 0
		"lockbreaker_round":
			foe.planned_ability = "attack"
			spare.planned_ability = "attack"
		"pacify":
			foe.hp = 400
			spare.hp = 400
		"formula_reprise":
			system.perform(actor, "fire", foe)
			actor.mp = actor.max_mp
		"wise_furnace":
			actor.mp = actor.max_mp

	if target_gone:
		foe.hp = 0
		if ability_id == "lockbreaker_round":
			spare.planned_ability = "attack"
		if ability_id == "pacify":
			spare.hp = 400

	return {
		"system": system,
		"actor": actor,
		"friend": friend,
		"fallen": fallen,
		"foe": foe,
		"spare": spare,
	}


func _snapshot(fixture: Dictionary, lines: Array[String]) -> String:
	var battlers: Array = []
	for b in [
		fixture.actor, fixture.friend, fixture.fallen, fixture.foe, fixture.spare
	]:
		battlers.append([
			b.id, b.hp, b.mp, b.next_at, b.sleep_turns, b.poison_turns,
			b.endure_hits, b.decoy_hits, b.exposed_hits, b.pierce_casts,
			b.reload_turns, b.tamed, b.planned_ability,
		])
	return JSON.stringify([
		lines,
		battlers,
		fixture.system.stolen_gold,
		fixture.system.stolen_items,
		fixture.system.is_over,
	])


func _test_contract(ability_id: String) -> void:
	var label := String(Database.ability(ability_id).get("name", ability_id))

	# 発動成功 + 1戦制限。
	var fixture := _fixture(ability_id, 771)
	var system: BattleSystem = fixture.system
	var actor: Battler = fixture.actor
	var target: Battler = fixture.foe
	var before := system.ultimate_uses_left(actor, ability_id)
	var lines := system.perform(actor, ability_id, target)
	_check("%s 発動成功" % label, not lines.is_empty() and before == 1)
	_check("%s 使用済み" % label, system.ultimate_uses_left(actor, ability_id) == 0)
	var second := system.perform(actor, ability_id, target)
	_check("%s 1戦制限" % label, not second.is_empty() and system.ultimate_uses_left(
		actor, ability_id) == 0)

	# 全技に共通する不足経路。MP 0 技は「全弾後で通常行動しかできない」を使う。
	var lacking := _fixture(ability_id, 772)
	var lacking_actor: Battler = lacking.actor
	if int(Database.ability(ability_id).get("mp", 0)) > 0:
		lacking_actor.mp = 0
	else:
		lacking_actor.reload_turns = 1
	var lacking_system: BattleSystem = lacking.system
	var reason: String = lacking_system.ability_unavailable_reason(
		lacking_actor, ability_id, lacking.foe)
	_check("%s 条件不足" % label, reason != "")
	lacking_system.perform(lacking_actor, ability_id, lacking.foe)
	_check("%s 不成立では回数を失わない" % label, lacking_system.ultimate_uses_left(
		lacking_actor, ability_id) == 1 and not lacking_system.last_action_consumed)

	# 選んだ相手が直前に消えても、生存する次の対象へ解決を続ける。
	var gone := _fixture(ability_id, 773, true)
	var gone_system: BattleSystem = gone.system
	var gone_lines: Array[String] = gone_system.perform(gone.actor, ability_id, gone.foe)
	_check("%s 対象消滅" % label, not gone_lines.is_empty())

	# 解決途中で敵が尽きても、残りの多段や後続効果が不正な対象を触らない。
	var ending := _fixture(ability_id, 774)
	ending.foe.hp = 1
	ending.spare.hp = 1
	if ability_id == "pacify":
		ending.foe.hp = 1
		ending.spare.hp = 1
	var ending_system: BattleSystem = ending.system
	var ending_lines: Array[String] = ending_system.perform(
		ending.actor, ability_id, ending.foe)
	_check("%s 途中決着" % label, not ending_lines.is_empty())

	# 同じ seed・同じ対象選択なら、出目・標的・行動順を含む状態が一致する。
	var left := _fixture(ability_id, 775)
	var right := _fixture(ability_id, 775)
	var left_system: BattleSystem = left.system
	var right_system: BattleSystem = right.system
	var left_lines: Array[String] = left_system.perform(left.actor, ability_id, left.foe)
	var right_lines: Array[String] = right_system.perform(right.actor, ability_id, right.foe)
	_check("%s 決定性" % label, _snapshot(left, left_lines) == _snapshot(
		right, right_lines))


func _test_auto_roles() -> void:
	var revival := _fixture("returning_bell", 881)
	revival.actor.abilities.assign(["returning_bell"])
	revival.fallen.hp = 0
	var plan := AutoTactic.decide(
		revival.system, revival.actor, AutoTactic.Mode.SAFE)
	_check("オート守備は全体蘇生を選ぶ", String(plan.get("ability", "")) == "returning_bell")

	var recovery := _fixture("sanctuary", 882)
	recovery.actor.abilities.assign(["sanctuary"])
	recovery.actor.hp = 150
	recovery.friend.hp = 150
	plan = AutoTactic.decide(recovery.system, recovery.actor, AutoTactic.Mode.SAFE)
	_check("オート守備は複数の傷を治す", String(plan.get("ability", "")) == "sanctuary")

	var shelter := _fixture("vow_of_life", 883)
	shelter.actor.abilities.assign(["vow_of_life"])
	shelter.friend.hp = 150
	shelter.foe.planned_ability = "attack"
	plan = AutoTactic.decide(shelter.system, shelter.actor, AutoTactic.Mode.SAFE)
	_check("オート守備は敵予告へ致死防護", String(plan.get("ability", "")) == "vow_of_life")

	var interrupt := _fixture("lockbreaker_round", 884)
	interrupt.actor.abilities.assign(["lockbreaker_round"])
	interrupt.foe.planned_ability = "attack"
	interrupt.foe.source_id = "warden"
	plan = AutoTactic.decide(
		interrupt.system, interrupt.actor, AutoTactic.Mode.AGGRESSIVE)
	_check("オート攻撃は主の予告を中断", String(plan.get("ability", "")) == "lockbreaker_round")

	var setup := _fixture("hunter_mark", 885)
	setup.actor.abilities.assign(["hunter_mark"])
	setup.foe.planned_ability = ""
	setup.spare.planned_ability = ""
	setup.foe.source_id = "warden"
	setup.actor.hp = setup.actor.max_hp / 3
	setup.fallen.hp = setup.fallen.max_hp / 3
	plan = AutoTactic.decide(setup.system, setup.actor, AutoTactic.Mode.AGGRESSIVE)
	_check("オート攻撃は劣勢の主へ狩標", String(plan.get("ability", "")) == "hunter_mark")

	var damage := _fixture("veteran_barrage", 886)
	damage.actor.abilities.assign(["veteran_barrage"])
	damage.foe.planned_ability = ""
	damage.spare.planned_ability = ""
	damage.actor.hp = damage.actor.max_hp / 3
	damage.fallen.hp = damage.fallen.max_hp / 3
	damage.system.start(
		[damage.actor, damage.friend, damage.fallen] as Array[Battler],
		[
			damage.foe, damage.spare,
			_make(13, "増援A", false, 700, 80),
			_make(14, "増援B", false, 700, 80),
		] as Array[Battler],
		DetRng.new(886),
		8
	)
	plan = AutoTactic.decide(damage.system, damage.actor, AutoTactic.Mode.AGGRESSIVE)
	_check("オート攻撃は多勢の劣勢で再配分連撃を選ぶ", String(
		plan.get("ability", "")) == "veteran_barrage")


func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("  OK   %s" % label)
	else:
		failed += 1
		print("  FAIL %s" % label)
