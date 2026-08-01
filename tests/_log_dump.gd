extends SceneTree

## S-6a の安全網（一時）。決定的な戦闘を回して、出た行をすべて並べる。
##
##     godot --headless --script tests/_log_dump.gd
##
## 外へ出す前と出した後で出力を突き合わせ、**1 文字も変わっていない**ことを見る。
## 文言の移動は「動くけれど言い回しが変わった」が起きても誰も気づけないので、
## 実際に出る行そのものを比べる。

const PARTY := [
	{"name": "アレン", "job": "soldier"},
	{"name": "セラ", "job": "priest"},
	{"name": "ノア", "job": "mage"},
	{"name": "キリ", "job": "thief"},
]

const MAX_TURNS := 120


func _initialize() -> void:
	Database.reload()
	for seed_value in [11, 97, 313, 1021, 4242, 8675, 20260801]:
		for danger in [1, 5, 10]:
			_run(seed_value, danger)
	_dump_tools()
	quit()


func _members(level: int) -> Array[PartyMember]:
	var out: Array[PartyMember] = []
	for entry in PARTY:
		var m := PartyMember.create(String(entry["name"]), String(entry["job"]))
		while m.level < level:
			m.gain_exp(m.exp_to_next())
		for gear_id in Database.job(m.job_id).get("starting_gear", []):
			m.equip(String(gear_id))
		m.hp = m.max_hp()
		m.mp = m.max_mp()
		out.append(m)
	return out


func _run(seed_value: int, danger: int) -> void:
	var rng := DetRng.new(seed_value).fork("dump:%d" % danger)
	var members := _members(maxi(danger * 2, 3))
	var party: Array[Battler] = []
	for i in members.size():
		party.append(members[i].to_battler(i))
	var foes := Encounter.build(rng, danger, 100, "")
	if foes.is_empty():
		return
	var system := BattleSystem.new()
	system.start(party, foes, rng, danger)
	print("=== seed=%d danger=%d" % [seed_value, danger])
	var turns := 0
	while not system.is_over and turns < MAX_TURNS:
		turns += 1
		var actor := system.begin_turn()
		if actor == null:
			break
		var head: Dictionary = system.begin_turn_effects(actor)
		for line in head.get("lines", []):
			print(line)
		if bool(head.get("skipped", false)):
			continue
		var said: Array[String]
		if actor.is_ally:
			var plan := AutoTactic.decide(system, actor, AutoTactic.Mode.AGGRESSIVE)
			said = system.perform(actor, String(plan["ability"]), plan["target"])
		else:
			said = system.perform_enemy(actor)
		for line in said:
			print(line)


## 技・道具・装備は自動戦闘ではまず出ない。**全部を名指しで 1 回ずつ通す。**
func _dump_tools() -> void:
	var ability_ids: Array = Database.abilities.keys()
	ability_ids.sort()
	for raw_id in ability_ids:
		var id := String(raw_id)
		var rng := DetRng.new(7777).fork("ability:%s" % id)
		var members := _members(20)
		var party: Array[Battler] = []
		for i in members.size():
			party.append(members[i].to_battler(i))
		var foes := Encounter.build(rng, 8, 100, "")
		if foes.is_empty():
			continue
		var system := BattleSystem.new()
		system.start(party, foes, rng, 8)
		var actor: Battler = party[0]
		actor.mp = 999
		actor.abilities.append(id)
		print("=== ability=%s" % id)
		for line in system.perform(actor, id, foes[0]):
			print(line)

	var item_ids: Array = Database.items.keys()
	item_ids.sort()
	for raw_id in item_ids:
		var id := String(raw_id)
		var rng := DetRng.new(5555).fork("item:%s" % id)
		var members := _members(20)
		var party: Array[Battler] = []
		for i in members.size():
			party.append(members[i].to_battler(i))
		var foes := Encounter.build(rng, 8, 100, "")
		if foes.is_empty():
			continue
		var system := BattleSystem.new()
		system.start(party, foes, rng, 8)
		var actor: Battler = party[0]
		party[1].hp = 1
		print("=== item=%s" % id)
		for line in system.use_item(actor, id, party[1]):
			print(line)
		print("--- item on foe")
		for line in system.use_item(actor, id, foes[0]):
			print(line)
