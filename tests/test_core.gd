extends SceneTree

## 決定性の検証。
##
##   godot --headless --script res://tests/test_core.gd
##
## ローグライクは「同じシードなら同じ結果」が崩れた瞬間に、リプレイも
## 不具合の再現もバランスの自動調整も全部できなくなる。ここは常に緑に保つ。

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 決定性テスト ===")
	_test_rng_determinism()
	_test_rng_range()
	_test_rng_fork_independence()
	_test_scheduler_order()
	_test_scheduler_preview_matches_reality()
	_test_scheduler_tiebreak()
	_test_action_cost_matters()
	_test_cover_and_buff_expiry()
	_test_dungeon_determinism()
	_test_dungeon_reachable()
	_test_docs_hygiene()
	_test_data_integrity()
	_test_save_migration()
	_test_save_to_disk()
	_test_suspend()
	_test_guardian_and_escape()
	_test_roster()
	_test_field_poison()
	_test_settings()
	_test_dungeon_route()
	_test_world_generation()
	_test_town_generation()
	_test_quest_text()
	_test_vocabulary()
	_test_event_effects()
	_test_text_wrap()
	_test_database_loaded()
	_test_final_floor()
	_test_boss_encounter()
	_test_every_floor_populated()
	_test_shop()
	_test_echo_and_upgrades()
	_test_mastery_persists()
	_test_job_change()
	_test_advanced_jobs()

	print("---")
	print("成功 %d / 失敗 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --------------------------------------------------------------------------


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  OK   %s" % label)
	else:
		_failed += 1
		print("  FAIL %s %s" % [label, detail])


func _equal(label: String, actual: Variant, expected: Variant) -> void:
	_check(label, actual == expected, "(実際: %s / 期待: %s)" % [actual, expected])


# --------------------------------------------------------------------------


func _sequence(seed_value: int, count: int) -> Array:
	var rng := DetRng.new(seed_value)
	var out := []
	for _i in count:
		out.append(rng.next_u32())
	return out


func _test_rng_determinism() -> void:
	var a := _sequence(12345, 64)
	var b := _sequence(12345, 64)
	_check("同一シードは同一数列", a == b)
	var c := _sequence(12346, 64)
	_check("異なるシードは異なる数列", a != c)
	_check("0 が並び続けない", a.count(0) < 4)


func _test_rng_range() -> void:
	var rng := DetRng.new(99)
	var ok := true
	var seen := {}
	for _i in 3000:
		var v := rng.range_i(3, 9)
		seen[v] = true
		if v < 3 or v > 9:
			ok = false
	_check("range_i が範囲内", ok)
	_equal("range_i が全値を出す", seen.size(), 7)


func _test_rng_fork_independence() -> void:
	# 片方の系統で乱数を余分に引いても、もう片方の結果が動かないこと。
	var base_a := DetRng.new(777)
	var terrain_a := base_a.fork("terrain")
	var first := []
	for _i in 8:
		first.append(terrain_a.next_u32())

	var base_b := DetRng.new(777)
	var terrain_b := base_b.fork("terrain")
	var second := []
	for _i in 8:
		second.append(terrain_b.next_u32())

	_check("fork が再現する", first == second)

	var loot := DetRng.new(777).fork("loot")
	var loot_values := []
	for _i in 8:
		loot_values.append(loot.next_u32())
	_check("系統が違えば数列も違う", first != loot_values)


# --------------------------------------------------------------------------


func _make_battler(id: int, name: String, agi: int, ally: bool = true) -> Battler:
	var b := Battler.new()
	b.id = id
	b.name = name
	b.agi = agi
	b.is_ally = ally
	b.max_hp = 100
	b.hp = 100
	return b


func _test_scheduler_order() -> void:
	var s := CtbScheduler.new()
	var slow := _make_battler(1, "おそい", 8)
	var fast := _make_battler(2, "はやい", 24)
	s.add(slow)
	s.add(fast)
	s.add(_make_battler(3, "てき", 12, false))
	_equal("素早い者が先に動く", s.next_actor().name, "はやい")


func _test_scheduler_preview_matches_reality() -> void:
	# 先読みと実際の進行が一致しなければ、行動順バーが嘘をつくことになる。
	var build := func() -> CtbScheduler:
		var sch := CtbScheduler.new()
		sch.add(_make_battler(1, "A", 10))
		sch.add(_make_battler(2, "B", 17))
		sch.add(_make_battler(3, "C", 13, false))
		return sch

	var previewed: Array[Battler] = build.call().preview(12)
	var predicted := previewed.map(func(b: Battler) -> String: return b.name)

	var actual := []
	var live: CtbScheduler = build.call()
	for _i in 12:
		var who := live.next_actor()
		actual.append(who.name)
		live.consume(who, CtbScheduler.STANDARD_COST)

	_equal("先読みが実際の行動順と一致", predicted, actual)


func _test_scheduler_tiebreak() -> void:
	# 素早さが同じ = next_at が同値。id で決めないと配列順という偶然に依存する。
	var order := []
	for _trial in 5:
		var s := CtbScheduler.new()
		s.add(_make_battler(7, "G", 12))
		s.add(_make_battler(3, "C", 12))
		s.add(_make_battler(5, "E", 12))
		order.append(s.next_actor().id)
	_equal("同時刻は id 昇順で確定", order, [3, 3, 3, 3, 3])


func _test_action_cost_matters() -> void:
	var s := CtbScheduler.new()
	var heavy := _make_battler(1, "重い技", 12)
	var light := _make_battler(2, "軽い技", 12)
	s.add(heavy)
	s.add(light)
	s.consume(heavy, 200)
	s.consume(light, 60)
	_check("コストが安いほど手番が早く回る", light.next_at < heavy.next_at)
	# 素早さが同じなら待ち時間の比はコストの比になる
	var heavy_wait := CtbScheduler.wait_for(12, 200)
	var light_wait := CtbScheduler.wait_for(12, 60)
	_check("待ち時間はコストに比例", heavy_wait > light_wait * 3)


## かばうと素早さ変化の寿命。
##
## かばうが「守り手が代わりに受ける」になっていないと技の名前が嘘になり、
## 素早さ変化が切れないと一度かけたら勝ちの永続バフになる。どちらも
## 静かに壊れるので、ロジックだけを直接まわして確かめる。
func _test_cover_and_buff_expiry() -> void:
	Database.reload()
	var system := BattleSystem.new()
	var tank := _make_battler(1, "たて", 10)
	var frail := _make_battler(2, "よわい", 12)
	var foe := _make_battler(3, "てき", 8, false)
	foe.atk = 40
	var party: Array[Battler] = [tank, frail]
	var foes: Array[Battler] = [foe]
	system.start(party, foes, DetRng.new(7), 1)

	# たてが よわい をかばう
	system.perform(tank, "guard_stance", frail)
	_check("かばわれた側に守り手が付く", frail.protected_by == tank)

	var frail_hp := frail.hp
	var tank_hp := tank.hp
	system.perform(foe, "attack", frail)
	_equal("かばわれた側は傷つかない", frail.hp, frail_hp)
	_check("守り手が代わりに受ける", tank.hp < tank_hp)

	# 守り手が動いたら、かばいは解ける
	system.begin_turn()
	while system.scheduler.next_actor() != tank:
		system.scheduler.consume(system.scheduler.next_actor(), CtbScheduler.STANDARD_COST)
	system.begin_turn()
	_check("守り手が動くとかばいが解ける", frail.protected_by == null)

	# 素早さ変化は BUFF_TURNS 手番で切れる
	var runner := _make_battler(4, "はしる", 12)
	var other := _make_battler(5, "ほか", 12, false)
	var s2 := BattleSystem.new()
	s2.start([runner] as Array[Battler], [other] as Array[Battler], DetRng.new(7), 1)
	s2.perform(runner, "haste", runner)
	_check("素早さが上がる", runner.agi_scale > 100)
	_equal("残り手番が積まれる", runner.agi_scale_turns, BattleSystem.BUFF_TURNS)

	# 相手を遠くへ押しやって、runner の手番だけを BUFF_TURNS 回まわす
	for _i in BattleSystem.BUFF_TURNS:
		s2.scheduler.consume(other, CtbScheduler.STANDARD_COST * 10)
		s2.begin_turn()
	_equal("いずれ素早さが元に戻る", runner.agi_scale, 100)
	_equal("残り手番も 0 になる", runner.agi_scale_turns, 0)


# --------------------------------------------------------------------------


func _test_dungeon_determinism() -> void:
	var a := DungeonGenerator.generate(DetRng.new(4242), 3).to_ascii()
	var b := DungeonGenerator.generate(DetRng.new(4242), 3).to_ascii()
	_check("同一シードで同一フロア", a == b)
	var c := DungeonGenerator.generate(DetRng.new(4243), 3).to_ascii()
	_check("異なるシードで異なるフロア", a != c)


func _test_dungeon_reachable() -> void:
	# 到達不能な階段を作ると、そのランはそこで詰む。全シードで通ることを確認する。
	var all_ok := true
	var checked := 0
	for seed_value in range(1, 40):
		var map := DungeonGenerator.generate(DetRng.new(seed_value * 977), 2)
		checked += 1
		if not _reachable(map, map.start_pos, map.stairs_pos):
			all_ok = false
			print("    シード %d で階段に到達できない" % seed_value)
	_check("%d 個のシードすべてで階段に到達できる" % checked, all_ok)


## 積んだ「やること」が読める量に収まっているか。
##
## 長い一覧は読まれない。読まれない一覧は棚卸しされず、
## 終わった項目と生きている項目が混ざって、結局どれも進まなくなる。
## 超えたら済んだものを docs/tasks_archive.md へ移す。
const TASKS_LIMIT := 200


func _test_docs_hygiene() -> void:
	var text := FileAccess.get_file_as_string("res://tasks.md")
	_check("tasks.md がある", text != "")
	var count := text.split("
").size()
	if count > TASKS_LIMIT:
		print("    tasks.md が %d 行。済んだものを docs/tasks_archive.md へ移すこと" % count)
	_check("tasks.md が %d 行以内（いま %d 行）" % [TASKS_LIMIT, count], count <= TASKS_LIMIT)

	# 控えのほうは伸びてよいが、存在は要る（移す先が無いと棚卸しできない）
	_check(
		"docs/tasks_archive.md がある",
		FileAccess.get_file_as_string("res://docs/tasks_archive.md") != ""
	)


## データの整合。職業が 15 まで増えたので、手で並べた JSON の取りこぼしを機械で見る。
## 「熟練で覚える技が存在しない」「解放条件が存在しない職業を指している」は
## 遊んでいて初めて気づくと原因が遠い。
func _test_data_integrity() -> void:
	var missing_ability: Array[String] = []
	var missing_unlock: Array[String] = []
	var no_mastery: Array[String] = []
	for job_id in Database.job_ids():
		var job := Database.job(String(job_id))
		var mastery: Array = job.get("mastery", [])
		if mastery.is_empty():
			no_mastery.append(String(job_id))
		for entry in mastery:
			var ability_id := String(entry.get("ability", ""))
			if Database.ability(ability_id).is_empty():
				missing_ability.append("%s -> %s" % [job_id, ability_id])
		for required in job.get("unlock", {}).keys():
			if Database.job(String(required)).is_empty():
				missing_unlock.append("%s -> %s" % [job_id, required])

	if not missing_ability.is_empty():
		print("    存在しない技: " + ", ".join(missing_ability))
	if not missing_unlock.is_empty():
		print("    存在しない解放条件: " + ", ".join(missing_unlock))
	_check("すべての熟練が実在する技を指す", missing_ability.is_empty())
	_check("すべての解放条件が実在する職業を指す", missing_unlock.is_empty())
	_check("すべての職業に熟練表がある", no_mastery.is_empty())

	# 解放条件が循環していないか（互いを条件にすると永久に就けない）
	var cyclic: Array[String] = []
	for job_id in Database.job_ids():
		for required in Database.job(String(job_id)).get("unlock", {}).keys():
			if Database.job(String(required)).get("unlock", {}).has(job_id):
				cyclic.append("%s <-> %s" % [job_id, required])
	_check("解放条件が循環していない", cyclic.is_empty())

	# 技の対象と系統が語彙の中にあるか
	var bad_target: Array[String] = []
	const TARGETS := [
		"one_enemy", "group_enemy", "all_enemies",
		"one_ally", "all_allies", "one_ally_dead", "self",
	]
	const KINDS := ["physical", "magical", "heal", "buff", "debuff", "special"]
	for id in Database.all_abilities().keys():
		var ab := Database.ability(String(id))
		if String(ab.get("target", "one_enemy")) not in TARGETS:
			bad_target.append("%s target=%s" % [id, ab.get("target", "")])
		if String(ab.get("kind", "physical")) not in KINDS:
			bad_target.append("%s kind=%s" % [id, ab.get("kind", "")])
	if not bad_target.is_empty():
		print("    語彙の外: " + ", ".join(bad_target))
	_check("技の対象と系統が語彙の中にある", bad_target.is_empty())

	# 敵の絵がある（敵を足して絵を忘れると、戦闘で別の敵が出たまま気づかない）
	var no_enemy_sprite: Array[String] = []
	for monster_id in Database.all_monsters().keys():
		var sprite := String(Database.monster(String(monster_id)).get("sprite", ""))
		if not ResourceLoader.exists("res://assets/sprites/%s.png" % sprite):
			no_enemy_sprite.append("%s -> %s" % [monster_id, sprite])
	if not no_enemy_sprite.is_empty():
		print("    敵の絵が無い: " + ", ".join(no_enemy_sprite))
	_check("すべての敵に絵がある", no_enemy_sprite.is_empty())

	# 敵の技も実在するか
	var bad_monster_ability: Array[String] = []
	for monster_id in Database.all_monsters().keys():
		for ability_id in Database.monster(String(monster_id)).get("abilities", []):
			if Database.ability(String(ability_id)).is_empty():
				bad_monster_ability.append("%s -> %s" % [monster_id, ability_id])
	if not bad_monster_ability.is_empty():
		print("    存在しない敵の技: " + ", ".join(bad_monster_ability))
	_check("敵の技がすべて実在する", bad_monster_ability.is_empty())

	# 立ち絵がある（職業を足して絵を忘れると、拠点で欠けたまま気づかない）
	var no_sprite: Array[String] = []
	for job_id in Database.job_ids():
		if not ResourceLoader.exists("res://assets/sprites/hero_%s.png" % job_id):
			no_sprite.append(String(job_id))
	if not no_sprite.is_empty():
		print("    立ち絵が無い職業: " + ", ".join(no_sprite))
	_check("すべての職業に立ち絵がある", no_sprite.is_empty())


## 設定。ゲームの進み具合とは別のファイルに置くので、往復で壊れないことだけ見る。
func _test_settings() -> void:
	var volume_before: int = Settings.volume
	var speed_before: int = Settings.text_speed

	Settings.volume = 3
	Settings.text_speed = 2
	Settings.bindings = {"confirm": KEY_SPACE}
	Settings.save_config()

	Settings.volume = 10
	Settings.text_speed = 0
	Settings.bindings = {}
	Settings.load_config()
	_check("音量が戻る", Settings.volume == 3)
	_check("文字の速さが戻る", Settings.text_speed == 2)
	_check("キーの割り当てが戻る", int(Settings.bindings.get("confirm", 0)) == KEY_SPACE)
	_check("速い設定のほうが待ち時間が短い", Settings.line_delay() < Settings.TEXT_SPEEDS[0])

	# 元へ戻して後始末（テストが遊ぶ人の設定を書き換えたままにしない）
	Settings.volume = volume_before
	Settings.text_speed = speed_before
	Settings.bindings = {}
	Settings.save_config()


## 毒の持ち越し。戦闘の外へ出ても効き続けるが、毒だけでは死なない。
func _test_field_poison() -> void:
	var m := PartyMember.create("どく", "soldier")
	m.hp = m.max_hp()
	_check("はじめは毒でない", m.poison_steps == 0)
	_check("毒でなければ歩いても減らない", m.step_poison() == 0)

	# 戦闘から毒を持ち帰る
	var b := m.to_battler(0)
	b.poison_turns = 3
	b.hp = m.max_hp()
	m.sync_from_battler(b)
	_check("戦闘の毒を持ち帰る", m.poison_steps > 0)

	var before: int = m.hp
	_check("歩くと減る", m.step_poison() > 0)
	_check("HP が実際に減っている", m.hp < before)

	# 毒では死なない（歩いているだけで全滅すると打つ手が無い）
	for _i in 500:
		m.step_poison()
	_check("毒では倒れない", m.hp >= 1)

	_check("毒を消せる", m.cure_poison())
	_check("消したら進まない", m.step_poison() == 0)

	# 毒を持ったまま戦闘へ入ると、戦闘側でも毒のまま
	m.poison_steps = 10
	var carried := m.to_battler(0)
	_check("毒は戦闘へも持ち込む", carried.poison_turns > 0)

	# ランが終われば抜ける
	m.reset_for_run()
	_check("ランが終われば毒は消える", m.poison_steps == 0)


## 控えと編成。名簿が伸びても「連れて行くのは 4 人」が崩れないことを見る。
func _test_roster() -> void:
	var state: Node = load("res://src/game/game_state.gd").new()
	state.load_from_dict({
		"version": 2,
		"echo": 200,
		"roster": [
			{"name": "あ", "job_id": "soldier"}, {"name": "い", "job_id": "priest"},
			{"name": "う", "job_id": "mage"}, {"name": "え", "job_id": "thief"},
		],
	})
	_check("指定が無ければ先頭 4 人が出撃する", state.active_party().size() == 4)

	var before: int = state.roster.size()
	var echo_before: int = state.echo
	var joined: Variant = state.recruit()
	_check("仲間を迎えられる", joined != null and state.roster.size() == before + 1)
	_check("恒久通貨を払う", state.echo < echo_before)
	_check("迎えても出撃は 4 人のまま", state.active_party().size() == 4)

	# 迎えた 5 人目を入れるには、誰かを外さないといけない
	_check("5 人目はそのままでは入らない", not state.toggle_active(4))
	_check("外せる", state.toggle_active(0))
	_check("空いたので入る", state.toggle_active(4))
	_check("入れ替えても 4 人", state.active_party().size() == 4)
	_check("外した者は出撃しない", not state.is_active(0))

	# 全員外すことはできない（誰も居ないランは始められない）
	for i in [1, 2, 3]:
		state.toggle_active(i)
	_check("最後の 1 人は外せない", state.active_party().size() >= 1)

	# 書いて読み直しても編成が残る
	var again: Node = load("res://src/game/game_state.gd").new()
	again.load_from_dict(state.to_dict())
	_check("編成がセーブに残る", again.active_indices == state.active_indices)

	# 上限まで迎えたら止まる
	while again.can_recruit():
		again.echo = 999
		again.recruit()
	_check("名簿には上限がある", not again.can_recruit())

	state.free()
	again.free()


## セーブの移行。version を上げたときに古いセーブが読めるかは、
## 遊んでいる人のデータが消えるかどうかの話なので、必ず機械で見る。
func _test_save_migration() -> void:
	var state: Node = load("res://src/game/game_state.gd").new()

	# version 1 のセーブ（残響もアップグレードも無い）を読ませる
	var old_save := {
		"version": 1,
		"roster": [{
			"name": "ふるいひと", "job_id": "soldier",
			"job_exp": {"soldier": 40}, "learned": ["power_slash"],
		}],
		"deepest_floor": 5,
		"runs_attempted": 3,
	}
	state.load_from_dict(old_save)
	_check("version 1 のセーブから名簿が読める", state.roster.size() == 1)
	_check("熟練度が残る", state.roster[0].mastery_points("soldier") == 40)
	_check("覚えた技が残る", "power_slash" in state.roster[0].learned)
	_check("最深階が残る", state.deepest_floor == 5)
	_check("無い項目は既定値になる", state.echo == 0 and state.upgrades.is_empty())

	# 書いて読み直しても同じ（往復で壊れない）
	state.echo = 42
	state.upgrades = {"shop_stock": 2}
	var round_trip: Node = load("res://src/game/game_state.gd").new()
	round_trip.load_from_dict(state.to_dict())
	_check("書いて読み直しても資源が残る", round_trip.echo == 42)
	_check("書いて読み直してもアップグレードが残る", int(round_trip.upgrades.get("shop_stock", 0)) == 2)
	_check("書いて読み直しても名簿が残る", round_trip.roster.size() == state.roster.size())

	state.free()
	round_trip.free()


## 実際にディスクへ書くところ。
##
## 起動のたびに「控えから復帰した」が出る状態になっていたのを直したときに足した。
## 原因は本体が消えていたことで、`FileAccess.open(WRITE)` が**開いた瞬間に
## 中身を捨てる**以上、書いている最中に落ちればセーブは消える。
##
## **必ず `use_save_paths()` で別名へ寄せてから触ること。** 既定のままだと
## テストが実データを潰す（過去に名簿を 1 人に減らした。テストは全部緑だった）。
func _test_save_to_disk() -> void:
	const PREFIX := "user://test_save"
	var dir := DirAccess.open("user://")
	for suffix in [".json", ".bak.json", ".tmp.json"]:
		if dir.file_exists(PREFIX + suffix):
			dir.remove(PREFIX + suffix)

	var state: Node = load("res://src/game/game_state.gd").new()
	state.use_save_paths(PREFIX)
	_check("実データの側を向いていない", state.save_path != state.SAVE_PATH)

	# roster は Array[PartyMember]。素の Array を代入すると型で弾かれる。
	var members: Array[PartyMember] = [PartyMember.create("ためし", "soldier")]
	state.roster = members
	state.echo = 7
	state.save_game()
	_check("セーブが書けている", FileAccess.file_exists(PREFIX + ".json"))
	_check("書きかけが残っていない", not FileAccess.file_exists(PREFIX + ".tmp.json"))
	_check("初回は控えを作らない", not FileAccess.file_exists(PREFIX + ".bak.json"))

	# 2 回目で 1 つ前が控えへ寄る
	state.echo = 99
	state.save_game()
	_check("2 回目で控えができる", FileAccess.file_exists(PREFIX + ".bak.json"))
	var backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREFIX + ".bak.json"))
	_check("控えは 1 つ前の状態", int((backup as Dictionary).get("echo", 0)) == 7)

	var reloaded: Node = load("res://src/game/game_state.gd").new()
	reloaded.use_save_paths(PREFIX)
	_check("書いたセーブを読み直せる", reloaded.load_game())
	_check("読み直した値が合う", reloaded.echo == 99)

	# 本体を壊す。控えから戻り、そのうえで**本体を作り直す**のが肝。
	# 書き戻さないと次の起動でも同じ警告が出て、鳴りっぱなしの警告は本物を隠す。
	var broken := FileAccess.open(PREFIX + ".json", FileAccess.WRITE)
	broken.store_string("{ こわれている")
	broken.close()
	var healed: Node = load("res://src/game/game_state.gd").new()
	healed.use_save_paths(PREFIX)
	_check("壊れていても控えから復帰する", healed.load_game())
	_check("控えの値で戻る", healed.echo == 7)
	var repaired: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREFIX + ".json"))
	_check("復帰したら本体を書き直す", typeof(repaired) == TYPE_DICTIONARY)

	for suffix in [".json", ".bak.json", ".tmp.json"]:
		if dir.file_exists(PREFIX + suffix):
			dir.remove(PREFIX + suffix)
	state.free()
	reloaded.free()
	healed.free()


## 世界の生成。**詰む世界を出さないこと**が最優先の不変条件。
##
## 城まで歩けない世界を 1 つ出すだけで、そのランは丸ごと無駄になる。
## 生成物の到達性は目で見て確かめられないので、必ずここで測る。
func _test_world_generation() -> void:
	var seeds := [1, 7, 42, 4242, 99991, 123456]
	var all_reachable := true
	var gates_on_land := true
	var danger_spans := true
	var has_sites := true
	for seed_value in seeds:
		var w := WorldGenerator.generate(DetRng.new(seed_value))
		if w.get_tile(w.start_pos.x, w.start_pos.y) != WorldMap.T_GATE:
			gates_on_land = false
		if w.get_tile(w.castle_pos.x, w.castle_pos.y) != WorldMap.T_CASTLE:
			gates_on_land = false
		# 城まで陸路で届くか
		var dist := w.distance_field(w.start_pos)
		if dist[w.castle_pos.y * w.width + w.castle_pos.x] < 0:
			all_reachable = false
		# 門は 1、城は上限。難度の軸がここで決まるので、端が合っていないと
		# data/*.json の floor_min の目盛りと噛み合わなくなる。
		if w.danger_at(w.start_pos.x, w.start_pos.y) != 1:
			danger_spans = false
		if w.danger_at(w.castle_pos.x, w.castle_pos.y) != WorldMap.MAX_DANGER:
			danger_spans = false
		var towns := 0
		var caves := 0
		for pos in w.sites:
			match String(w.sites[pos].get("kind", "")):
				"town":
					towns += 1
				"cave":
					caves += 1
		# 町が 1 つも無いと、道中で買い物ができないまま城へ着く
		if towns < 2 or caves < 2:
			has_sites = false

	_check("どの世界でも城まで歩ける", all_reachable)
	_check("門と城がその地形として置かれている", gates_on_land)
	_check("危険度が門 1 から城 %d まで伸びる" % WorldMap.MAX_DANGER, danger_spans)
	_check("町と洞が最低 2 つずつ置かれる", has_sites)

	# 同じ種から同じ世界（決定性）。地形も拠点地の場所も揃うこと。
	var a := WorldGenerator.generate(DetRng.new(555))
	var b := WorldGenerator.generate(DetRng.new(555))
	_check("同じ種から同じ世界が出る", a.to_ascii() == b.to_ascii())
	_check("同じ種なら拠点地も同じ", a.sites.keys() == b.sites.keys())
	_check("違う種なら違う世界", a.to_ascii() != WorldGenerator.generate(DetRng.new(556)).to_ascii())

	# 通れない地形（海・山）の上には拠点地を置かない
	var on_walkable := true
	for pos in a.sites:
		var at: Vector2i = pos
		if not a.is_walkable(at.x, at.y):
			on_walkable = false
	_check("拠点地は必ず歩ける場所にある", on_walkable)

	# 生成器の自己検算。**ここが本体。**
	# 世界は毎回違うので、目で見て確かめられるのはごく一部でしかない。
	# 生成器に自分の出力を疑わせて、通ったものだけを世界にする。
	var bad := []
	for seed_value in range(1, 60):
		var w := WorldGenerator.generate(DetRng.new(seed_value * 5171))
		var problems := WorldGenerator.verify(w)
		if not problems.is_empty():
			bad.append("種%d: %s" % [seed_value, "/".join(problems)])
	_check(
		"59 個の世界すべてが生成器の検算を通る", bad.is_empty(),
		"(落ちた: %s)" % str(bad.slice(0, 3))
	)

	# 検算が壊れた世界を見逃さないこと。**検算そのものを試す。**
	# 通す側だけ試すと、いつも空を返す検算でもテストは緑になる。
	var broken := WorldGenerator.generate(DetRng.new(31337))
	broken.seals.clear()
	_check("封が無い世界は検算に落ちる", not WorldGenerator.verify(broken).is_empty())
	var shifted := WorldGenerator.generate(DetRng.new(31337))
	for s in shifted.seals:
		s["band"] = "low"
	_check("帯が偏った世界は検算に落ちる", not WorldGenerator.verify(shifted).is_empty())

	# 封の中身
	var w2 := WorldGenerator.generate(DetRng.new(2024))
	_check("封が 3 つ置かれる", w2.seals.size() == 3)
	_check("封はすべて洞にある", w2.seals.all(func(s: Dictionary) -> bool:
		return String(w2.sites.get(s["pos"], {}).get("kind", "")) == "cave"))
	_check("最初はどれも解けていない", w2.seals_remaining() == 3)
	_check("封に名と由来が付く", w2.seals.all(func(s: Dictionary) -> bool:
		return String(s.get("name", "")) != "" and String(s.get("why", "")) != ""))
	var names := {}
	for s in w2.seals:
		names[String(s["name"])] = true
	_check("封の名が重複しない", names.size() == w2.seals.size())


## 町の生成。**迷わせないこと**と**用が足せること**を守る。
##
## 町は目的地であって迷路ではない。宿にも店にも出口にも辿り着けない町を
## 1 つ出すと、そこに寄った時間が丸ごと無駄になる。
func _test_town_generation() -> void:
	var reachable := true
	var has_folk := true
	var named := true
	var folk_blocked := true
	for seed_value in [1, 9, 77, 4242, 31337]:
		var town := TownGenerator.generate(DetRng.new(seed_value), 3, "dungeon")
		var dist := town.distance_field(town.start_pos)
		for goal in [town.inn_pos, town.shop_pos, town.exit_pos]:
			# 入口そのものは通行可なので、そこへ届くかを直接見る
			if dist[goal.y * town.width + goal.x] < 0:
				reachable = false
		if town.folk.size() < 2:
			has_folk = false
		if town.town_name == "":
			named = false
		# 人は押し当てて話すので、通れてはいけない（すり抜けると話せない）
		for pos in town.folk:
			var at: Vector2i = pos
			if town.is_walkable(at.x, at.y):
				folk_blocked = false

	_check("町の宿・店・出口に必ず辿り着ける", reachable)
	_check("町に人が居る", has_folk)
	_check("町に名前が付く", named)
	_check("町の人は通り抜けられない", folk_blocked)

	# **町ごとに形が違うこと。** 固定座標で作っていたころは、名前と人の位置
	# 以外がすべて同じで「街ぜんぶ一緒」になっていた。
	var shapes := {}
	for seed_value in range(1, 13):
		var m := TownGenerator.generate(DetRng.new(seed_value * 977), 3, "dungeon")
		shapes["%dx%d:%s" % [m.width, m.height, str(m.exit_pos)]] = true
	_check("12 個の町が 10 通り以上の形になる（%d 通り）" % shapes.size(), shapes.size() >= 10)

	var a := TownGenerator.generate(DetRng.new(555), 3, "dungeon")
	var b := TownGenerator.generate(DetRng.new(555), 3, "dungeon")
	_check("同じ種から同じ町が出る", a.to_ascii() == b.to_ascii())
	_check("同じ種なら名前も同じ", a.town_name == b.town_name)


## AI が書いた文字列の検算。**繋ぐ前にここを固める。**
##
## 通す側だけ試すと、何でも通す検算でもテストは緑になる。だから
## **落ちるべきものが落ちること**を主に確かめる。
func _test_quest_text() -> void:
	# 通ってほしいもの
	_equal("ふつうの名は通る", QuestText.accept_name("しずまりの錠"), "しずまりの錠")
	_equal("前後の飾りは落ちる", QuestText.accept_name("「うつろな楔」"), "うつろな楔")
	_equal(
		"ふつうの一文は通る", QuestText.accept_line("これが ある かぎり 主は 傷つかない。"),
		"これが ある かぎり 主は 傷つかない。"
	)

	# 落ちてほしいもの
	_equal("長すぎる名は落ちる", QuestText.accept_name("とてもとてもながいふうじのなまえ"), "")
	_equal("空は落ちる", QuestText.accept_name("   "), "")
	_equal("数字の混入は落ちる", QuestText.accept_name("だい3の封"), "")
	_equal("英字の混入は落ちる", QuestText.accept_name("Seal の錠"), "")
	_equal("記号の混入は落ちる", QuestText.accept_line("{\"name\": \"ほげ\"}"), "")
	_equal("他社の固有名詞は落ちる", QuestText.accept_name("ホイミの錠"), "")
	_equal("他社の固有名詞は一文でも落ちる", QuestText.accept_line("ザオラルで よみがえる。"), "")
	_equal(
		"長すぎる一文は落ちる",
		QuestText.accept_line("あ".repeat(QuestText.MAX_LINE + 1)), ""
	)

	# 世界へ当てる。**構造には触らないこと**を確かめる。
	var w := WorldGenerator.generate(DetRng.new(4242))
	var before_pos := []
	var before_band := []
	for s in w.seals:
		before_pos.append(s["pos"])
		before_band.append(s["band"])

	var reply := {"seals": [
		{"name": "とこしえの枷", "why": "この地の ちからが とびらを 閉ざす。"},
		{"name": "ホイミの錠", "why": "だめな 例。"},          # 名だけ落ちる
		{"name": "こごえた戒め", "why": "HP300 の ぬしが まもる。"},  # 由来だけ落ちる
	]}
	var report := QuestText.apply_to_world(w, reply)

	_equal("採れたぶんだけ入る", int(report["taken"]), 4)
	_check("落ちた理由が残る", report["rejected"].size() == 2)
	_equal("通った名が入る", String(w.seals[0]["name"]), "とこしえの枷")
	_check("落ちた名はテンプレートのまま", String(w.seals[1]["name"]) != "ホイミの錠")
	_check("落ちた由来はテンプレートのまま", "HP300" not in String(w.seals[2]["why"]))
	_equal("通った由来が入る", String(w.seals[0]["why"]), "この地の ちからが とびらを 閉ざす。")

	var pos_kept := true
	var band_kept := true
	for i in w.seals.size():
		if w.seals[i]["pos"] != before_pos[i]:
			pos_kept = false
		if w.seals[i]["band"] != before_band[i]:
			band_kept = false
	_check("AI は封の位置を動かさない", pos_kept)
	_check("AI は封の帯を動かさない", band_kept)
	_check("当てたあとも検算を通る", WorldGenerator.verify(w).is_empty())

	# 同じ名前を並べさせない
	var w2 := WorldGenerator.generate(DetRng.new(99))
	var same := {"seals": [
		{"name": "おなじ錠", "why": "ひとつめ。"},
		{"name": "おなじ錠", "why": "ふたつめ。"},
		{"name": "おなじ錠", "why": "みっつめ。"},
	]}
	QuestText.apply_to_world(w2, same)
	var names := {}
	for s in w2.seals:
		names[String(s["name"])] = true
	_equal("同じ名前は 1 つしか採らない", names.size(), 3)


## 語彙の差し替え。
##
## **コードを触らずに語を変えられること**が目的なので、
## 「JSON にある語が実際に画面へ出る」ことと「無くても既定に落ちる」ことを見る。
func _test_vocabulary() -> void:
	Vocabulary.reload()
	_check("語彙ファイルが読める", Vocabulary.word("terms", "echo", "×") != "×")
	_equal("無い節は既定に落ちる", Vocabulary.word("nope", "nope", "既定"), "既定")
	_equal("無い語は既定に落ちる", Vocabulary.word("terms", "nope", "既定"), "既定")
	_check("語彙表が読める", Vocabulary.nested("seal_names", "", "tail", []).size() > 0)
	_equal("無い語彙表は既定に落ちる", Vocabulary.nested("x", "", "y", ["既定"]), ["既定"])

	# 画面に出る側が JSON を通っていること（定数直書きに戻ったら落ちる）
	_equal("Terms が語彙ファイルを通る", Terms.ECHO, Vocabulary.word("terms", "echo", "×"))
	_equal(
		"生物相の名が語彙ファイルを通る",
		String(WorldMap.BIOMES[0]["name"]), Vocabulary.word("biomes", "grassland", "×")
	)
	_check("Lore の前提が組み立てられる", Lore.WORLD.contains("世界の前提"))
	_equal("Lore の 3 行がそろう", Lore.DEPART_LINES.size(), 3)


## イベントの効果トークン。
##
## **知らないトークンを黙って無視しないこと**が唯一の不変条件。
## 素通りさせると、選択肢が「押しても何も起きない」になり、しかも画面上は
## 成功に見える。カタログ側の全トークンが解決表にあることを機械で突き合わせる。
func _test_event_effects() -> void:
	var catalog := WorldEventCatalog.load_catalog()
	_check("カタログが読める", not catalog.is_empty())

	var unknown: Array[String] = []
	var counted := 0
	for event in catalog.get("events", []):
		for choice in event.get("choices", []):
			for pair in [["costs", "cost"], ["risks", "risk"], ["rewards", "reward"]]:
				for token in choice.get(String(pair[0]), []):
					counted += 1
					if not EventEffects.known(String(token), String(pair[1])):
						var note := "%s/%s" % [String(pair[1]), String(token)]
						if note not in unknown:
							unknown.append(note)
	_check(
		"全 %d 件のトークンが解決表にある" % counted, unknown.is_empty(),
		"(未登録: %s)" % str(unknown)
	)

	# 未実装のものは INFORMATIONAL に明示されていること（黙って無視でないこと）
	_check("未実装のトークンは明示されている", EventEffects.INFORMATIONAL.size() > 0)
	_check("効果があるトークンは INFORMATIONAL に無い", EventEffects.has_effect("gold"))
	_check("未実装のトークンは has_effect が false", not EventEffects.has_effect("boss_intel"))

	# 世界に置かれ、歩いて行けること
	var placed := 0
	var bad := []
	for seed_value in range(1, 25):
		var w := WorldGenerator.generate(DetRng.new(seed_value * 811))
		placed += w.events.size()
		var problems := WorldGenerator.verify(w)
		if not problems.is_empty():
			bad.append("種%d: %s" % [seed_value, "/".join(problems)])
		for pos in w.events:
			var inst: Dictionary = w.events[pos]
			# 表層の 4 項目が埋まっていること（AI 無しでも成立する）
			for key in ["title", "actor", "cause", "flavor"]:
				if String(inst.get("skin", {}).get(key, "")) == "":
					bad.append("種%d: skin の %s が空" % [seed_value, key])
			if inst.get("choices", []).is_empty():
				bad.append("種%d: 選択肢が無い" % seed_value)
	_check("24 個の世界すべてが検算を通る（イベント込み）", bad.is_empty(), "(%s)" % str(bad.slice(0, 3)))
	_check("イベントが世界に置かれる（%d 件）" % placed, placed >= 24 * 2)

	# 同じ種からは同じイベント（決定性）
	var a := WorldGenerator.generate(DetRng.new(606))
	var b := WorldGenerator.generate(DetRng.new(606))
	_check("同じ種から同じイベントが出る", a.events.keys() == b.events.keys())
	var same_skin := true
	for pos in a.events:
		if a.events[pos]["skin"] != b.events[pos]["skin"]:
			same_skin = false
	_check("同じ種から同じ表層が出る", same_skin)


## 中断と再開。
##
## **世界を書き出さず、種から作り直す**作りなので、復元が本当に一致するかを
## ここで見る。目で見て気づけるのは「同じ場所に立っている」だけで、
## 封やイベントの進みが落ちていても画面では分からない。
func _test_suspend() -> void:
	var state: Node = load("res://src/game/game_state.gd").new()
	state.use_save_paths("user://test_suspend_save")
	state.roster = _fresh_roster()
	state.start_new_run(4242)

	# 進めた状態を作る（場所・封・イベント・物語・持ち物）
	state.world_pos = state.world.seals[0]["pos"]
	state.floor_number = 6
	state.gold = 321
	state.kills = 12
	state.add_item("herb", 2)
	state.world.seals[0]["broken"] = true
	state.world.story_beat = 3
	state.world.story_choice = "test_choice"
	state.event_done[Vector2i(9, 9)] = true
	state.event_tags["rescue"] = 2
	state.lifeline_left = 1
	state.active_party()[0].hp = 7

	var suspended: Dictionary = state.to_suspend()
	_check("中断に世界の地形を書かない（種だけ）", not suspended.has("tiles"))
	_equal("種を書く", int(suspended["seed"]), 4242)

	# 別の GameState で読み直す（保存ファイルは共有なので同じ経路を通る）
	_check("中断を書き出せる", state.save_suspend())
	_check("中断があると分かる", state.has_suspend())

	var back: Node = load("res://src/game/game_state.gd").new()
	back.use_save_paths("user://test_suspend_save")
	back.roster = _fresh_roster()
	_check("中断から再開できる", back.resume())

	_equal("居た場所が戻る", back.world_pos, state.world_pos)
	_equal("危険度が戻る", back.floor_number, 6)
	_equal("ゴールドが戻る", back.gold, 321)
	_equal("撃破数が戻る", back.kills, 12)
	_equal("持ち物が戻る", int(back.inventory.get("herb", 0)), 2)
	_check("解いた封が戻る", bool(back.world.seals[0].get("broken", false)))
	_equal("物語の進みが戻る", back.world.story_beat, 3)
	_equal("選んだ手が戻る", back.world.story_choice, "test_choice")
	_check("済んだイベントが戻る", back.event_done.has(Vector2i(9, 9)))
	_equal("えらび方の記憶が戻る", int(back.event_tags.get("rescue", 0)), 2)
	_equal("命の綱が戻る", back.lifeline_left, 1)
	_equal("HP が戻る", back.active_party()[0].hp, 7)

	# **同じ世界であること。** 種から作り直すので、ここが崩れたら全部が嘘になる。
	_equal("同じ世界が出る", back.world.to_ascii(), state.world.to_ascii())
	_equal("封の場所も同じ", back.world.seals[1]["pos"], state.world.seals[1]["pos"])

	# 読んだら消える（同じ中断を二度使えない）
	_check("読んだら中断は消える", not back.has_suspend())

	state.free()
	back.free()


func _fresh_roster() -> Array[PartyMember]:
	var members: Array[PartyMember] = []
	for entry in [["ア", "soldier"], ["イ", "priest"], ["ウ", "mage"], ["エ", "thief"]]:
		members.append(PartyMember.create(String(entry[0]), String(entry[1])))
	return members


## 封の番人と、洞からの脱出。
##
## **番人は城の主とは別格**でなければならない（同格にすると寄り道が本筋と
## 同じ重さになる）。脱出は**用が済んだときだけ**（残っていると番人を避ける
## 近道になる）。どちらも条件を外すと静かに壊れるので、ここで固定する。
func _test_guardian_and_escape() -> void:
	Database.reload()
	var keeper := Encounter.build_guardian(DetRng.new(7), 5, "")
	_equal("番人は 1 体だけ", keeper.size(), 1)
	_check("番人に名が付く", keeper.is_empty() or keeper[0].name.contains("番人"))

	# 同じ危険度の通常の敵より強いこと（別格である、の中身）
	var plain := Encounter.build(DetRng.new(7), 5, 200, "")
	var plain_hp := 0
	for b in plain:
		plain_hp = maxi(plain_hp, b.max_hp)
	_check(
		"番人は同じ危険度の通常の敵より硬い",
		keeper.is_empty() or plain.is_empty() or keeper[0].max_hp > plain_hp
	)

	# 城の主より弱いこと（別格だが上ではない）
	var boss := Encounter.build_boss(DetRng.new(7), WorldMap.MAX_DANGER)
	_check(
		"番人は城の主より弱い",
		keeper.is_empty() or boss.is_empty() or keeper[0].max_hp < boss[0].max_hp
	)

	# 脱出の条件
	var state: Node = load("res://src/game/game_state.gd").new()
	state.use_save_paths("user://test_escape_save")
	state.roster = _fresh_roster()
	state.start_new_run(2024)
	_check("世界の上では脱出できない", not state.can_escape_site())

	var seal_pos: Vector2i = state.world.seals[0]["pos"]
	state.enter_site(seal_pos)
	_check("封が残る洞からは脱出できない", not state.can_escape_site())
	state.world.seals[0]["broken"] = true
	_check("封を解いた洞からは脱出できる", state.can_escape_site())

	# 封の無い洞（寄り道）はいつでも出られる
	var plain_cave := Vector2i(-1, -1)
	for pos in state.world.sites:
		if String(state.world.sites[pos].get("kind", "")) == "cave" 				and state.world.seal_at(pos).is_empty():
			plain_cave = pos
			break
	if plain_cave.x >= 0:
		state.enter_site(plain_cave)
		_check("封の無い洞はいつでも出られる", state.can_escape_site())
	state.free()


## 経路探索。オート移動と自動プレイの土台なので、決定性の側に入れて守る。
func _test_dungeon_route() -> void:
	var map := DungeonGenerator.generate(DetRng.new(4242), 3)
	var a := map.route(map.start_pos, map.stairs_pos)
	var b := map.route(map.start_pos, map.stairs_pos)
	_check("階段までの経路が見つかる", not a.is_empty())
	_check("同じ地形からは同じ経路が出る", a == b)
	_check("経路の終点が階段", a.is_empty() or a[a.size() - 1] == map.stairs_pos)

	var contiguous := true
	var cursor := map.start_pos
	for step in a:
		if (step - cursor).length() != 1.0:
			contiguous = false
		cursor = step
	_check("経路が 1 マスずつ繋がっている", contiguous)
	_check("届かない場所には空の経路", map.route(map.start_pos, Vector2i(-5, -5)).is_empty())


## 折り返しは戦記（将来 LLM の文章が流れる場所）が溢れないための保証。
func _test_text_wrap() -> void:
	var long_line := "だが おおぶり, かばう, つむじぎり, リアン, ハステ, リザン の技は 残った。"
	var wrapped := PixelUI.wrap(long_line, 200.0)
	_check("長い行は折り返される", wrapped.size() > 1)
	var fits := true
	for line in wrapped:
		if PixelUI.text_width(line) > 200.0 + 1.0:
			fits = false
	_check("折り返した各行が幅に収まる", fits)
	_check("文字が落ちていない", "".join(wrapped) == long_line)
	var head_ok := true
	for i in range(1, wrapped.size()):
		if PixelUI.NO_LINE_HEAD.contains(wrapped[i][0]):
			head_ok = false
	_check("句読点が行頭に来ない", head_ok)


func _reachable(map: DungeonMap, from: Vector2i, to: Vector2i) -> bool:
	var seen := {}
	var queue: Array[Vector2i] = [from]
	seen[from] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			return true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nxt: Vector2i = cur + d
			if seen.has(nxt):
				continue
			# 宝箱は乗れないが、その先へ進めるかの判定には通す
			var t := map.get_tile(nxt.x, nxt.y)
			if map.is_walkable(nxt.x, nxt.y) or t == DungeonMap.T_CHEST:
				seen[nxt] = true
				queue.append(nxt)
	return false


## 最終階だけは出口の意味が変わる。ここが壊れるとランに終わりが無くなり、
## 「生還」という結果が永久に出せなくなる。
func _test_final_floor() -> void:
	var open_map := DungeonGenerator.generate(DetRng.new(555), 10, false)
	var final_map := DungeonGenerator.generate(DetRng.new(555), 10, true)

	# 最終階でも地形の作り方は同じ。別生成にすると到達性の検査から外れてしまう。
	_equal("最終階でも開始位置は変わらない", final_map.start_pos, open_map.start_pos)
	_equal("最終階でも出口の位置は変わらない", final_map.stairs_pos, open_map.stairs_pos)

	var open_exit := open_map.get_tile(open_map.stairs_pos.x, open_map.stairs_pos.y)
	var final_exit := final_map.get_tile(final_map.stairs_pos.x, final_map.stairs_pos.y)
	_equal("通常階の出口は下り階段", open_exit, DungeonMap.T_STAIRS)
	_equal("最終階の出口は主の間の扉", final_exit, DungeonMap.T_DOOR)
	_check("扉は通行できる", final_map.is_walkable(final_map.stairs_pos.x, final_map.stairs_pos.y))

	# 扉に辿り着けない最終階を出すと、そのランは勝ちようが無くなる。
	var all_ok := true
	var checked := 0
	for seed_value in range(1, 40):
		var map := DungeonGenerator.generate(DetRng.new(seed_value * 977), 10, true)
		checked += 1
		if not _reachable(map, map.start_pos, map.stairs_pos):
			all_ok = false
			print("    シード %d で主の間に到達できない" % seed_value)
	_check("%d 個のシードすべてで主の間に到達できる" % checked, all_ok)


## 出現表に穴があると、その階だけ遭遇判定が空振りして無傷で歩ける。
## 静かに壊れる種類の不具合なので、階層を全部なめて確認する。
func _test_every_floor_populated() -> void:
	Database.reload()
	# 最終階の値は GameState が持つ。ここで数字を書き写すと二重管理になるので、
	# スクリプトの定数を直接読む（オートロードは headless では起動しない）。
	var game_state: GDScript = load("res://src/game/game_state.gd")
	var final_floor: int = game_state.get_script_constant_map()["FINAL_FLOOR"]
	_check("最終階が 2 階以上に設定されている", final_floor >= 2, str(final_floor))

	var empty := []
	for floor_no in range(1, final_floor + 1):
		if Database.monster_ids_for_floor(floor_no).is_empty():
			empty.append(floor_no)
	_check("1〜%d 階すべてに敵がいる" % final_floor, empty.is_empty(), "敵のいない階: %s" % str(empty))

	# 絵が無いと battle_view が既定の姿で代用し、別の敵として静かに表示される。
	var missing := []
	for id in Database.all_monsters().keys():
		var path := "res://assets/sprites/%s.png" % String(Database.monster(id).get("sprite", ""))
		if not ResourceLoader.exists(path):
			missing.append("%s -> %s" % [id, path])
	_check("敵の絵がすべて存在する", missing.is_empty(), str(missing))


## 出店。ゴールドの唯一の使い道なので、出なさすぎても詰まらせても成立しない。
func _test_shop() -> void:
	Database.reload()
	_check("道具が読める", Database.all_items().size() >= 2)

	# 深い階ほど品揃えが増える（浅い階に高級品が並ばない）
	var shallow := Database.item_ids_for_floor(1)
	var deep := Database.item_ids_for_floor(9)
	_check("浅い階の品揃えは狭い", shallow.size() < deep.size(), "%s / %s" % [shallow, deep])
	for id in shallow:
		_check("浅い階の品は深い階にも並ぶ (%s)" % id, id in deep)

	# 主の間の前には必ず店がある（最後の支度をさせる）
	var final_map := DungeonGenerator.generate(DetRng.new(31337), 10, true)
	_check("最終階には必ず出店がある", final_map.shop_pos.x >= 0)

	# 出店が通路を塞ぐと、その階の階段に届かなくなる
	var blocked := []
	var found := 0
	for seed_value in range(1, 40):
		var map := DungeonGenerator.generate(DetRng.new(seed_value * 977), 5)
		if map.shop_pos.x < 0:
			continue
		found += 1
		if not map.is_walkable(map.shop_pos.x, map.shop_pos.y):
			blocked.append(seed_value)
		if map.shop_pos == map.start_pos or map.shop_pos == map.stairs_pos:
			blocked.append(seed_value)
		if not _reachable(map, map.start_pos, map.stairs_pos):
			blocked.append(seed_value)
	_check("出店は 39 シード中の一部にだけ出る", found > 0 and found < 39, str(found))
	_check("出店が階を詰ませない", blocked.is_empty(), str(blocked))


## 恒久通貨「残響」。毎ランのスコアに対して必ず払われることが要点で、
## 一度きりの達成報酬にすると達成後に周回する理由が消える。
##
## GameState はオートロードなので headless では起動しない。スクリプトを
## 直接 new() して使う（_ready() は走らないのでセーブも読まない）。
## 保存を伴う buy_upgrade は呼ばない——テストで user://save.json を
## 壊してはいけない。判定は can_buy_upgrade に切り出してある。
func _test_echo_and_upgrades() -> void:
	Database.reload()
	var gs: Node = load("res://src/game/game_state.gd").new()

	# --- スコア ---
	gs.floor_number = 5
	gs.kills = 10
	gs.gold_earned = 200
	var lost: int = gs.run_score(false)
	_equal("スコアは階と撃破と稼ぎから決まる", lost, 5 * 100 + 10 * 12 + 200 / 4)

	var won: int = gs.run_score(true)
	_check("生還はスコアが上乗せされる", won > lost)

	# 使ったぶんスコアが減るなら、出店で買わないのが最適解になってしまう
	gs.gold = 0
	_equal("所持金を使ってもスコアは減らない", gs.run_score(false), lost)

	_check("全滅でも残響が入る", gs.echo_for_score(lost) > 0)
	gs.floor_number = 1
	gs.kills = 0
	gs.gold_earned = 0
	_check("何もできなかったランでも 0 以上", gs.echo_for_score(gs.run_score(false)) >= 0)

	# --- アップグレード ---
	var ids := Database.upgrade_ids()
	_check("アップグレードが読める", ids.size() >= 2, str(ids))
	var id := String(ids[0])

	gs.echo = 0
	_check("残響が足りなければ買えない", not gs.can_buy_upgrade(id))
	gs.echo = 9999
	_check("足りていれば買える", gs.can_buy_upgrade(id))

	gs.run_active = true
	_check("ラン中は買えない", not gs.can_buy_upgrade(id))
	gs.run_active = false

	# 段が上がるほど高くなる
	var first_price: int = gs.upgrade_price(id)
	gs.upgrades[id] = 1
	_check("2 段目は 1 段目より高い", gs.upgrade_price(id) > first_price)

	# 上限まで伸ばしたら買えない
	gs.upgrades[id] = int(Database.upgrade(id).get("levels", 0))
	_check("上限まで伸ばしたら買えない", not gs.can_buy_upgrade(id))
	_check("上限判定が効いている", gs.upgrade_maxed(id))

	# 効果値は段数に比例する
	var effect := String(Database.upgrade(id).get("effect", ""))
	var per_level := int(Database.upgrade(id).get("value", 0))
	var levels := int(Database.upgrade(id).get("levels", 0))
	_equal("効果は段数に比例する", gs.upgrade_value(effect), per_level * levels)
	gs.upgrades.clear()
	_equal("買っていなければ効果は 0", gs.upgrade_value(effect), 0)

	gs.free()


func _test_boss_encounter() -> void:
	Database.reload()
	_check("最終階に主がいる", not Database.boss_ids_for_floor(10).is_empty())

	# 主が通常の遭遇に混ざると、道中でいきなり最終試験が始まってしまう。
	var leaked := []
	for id in Database.boss_ids_for_floor(10):
		if id in Database.monster_ids_for_floor(10):
			leaked.append(id)
	_check("主は通常の出現表に出ない", leaked.is_empty(), str(leaked))

	var foes := Encounter.build_boss(DetRng.new(1), 10)
	_equal("主の編成は 1 体", foes.size(), 1)
	# 階層補正をかけると、調整点がデータと補正式の 2 か所に散る。
	var raw := Database.monster(foes[0].source_id)
	_equal("主に階層補正はかからない", foes[0].max_hp, int(raw.get("hp", 0)))
	_check("主は複数の技を持つ", foes[0].abilities.size() >= 3)


# --------------------------------------------------------------------------


func _test_database_loaded() -> void:
	Database.reload()
	_check("職業が読める", Database.all_jobs().size() >= 4, str(Database.job_ids()))
	_check("アビリティが読める", Database.all_abilities().size() >= 10)
	_check("モンスターが読める", Database.all_monsters().size() >= 3)
	_equal("せんしの名前", Database.job("soldier").get("name", ""), "せんし")
	_check("_comment が除かれている", not Database.jobs.has("_comment"))

	# すべての職業の習得技が実在すること（データの綴り間違いは静かに壊れるので必ず検査）
	var missing := []
	for job_id in Database.job_ids():
		for entry in Database.job(job_id).get("mastery", []):
			var ability_id := String(entry.get("ability", ""))
			if not Database.abilities.has(ability_id):
				missing.append("%s -> %s" % [job_id, ability_id])
	_check("習得技がすべて実在する", missing.is_empty(), str(missing))

	# モンスターの技も同様
	var bad_monster := []
	for id in Database.monsters.keys():
		for ability_id in Database.monster(id).get("abilities", []):
			if not Database.abilities.has(String(ability_id)):
				bad_monster.append("%s -> %s" % [id, ability_id])
	_check("敵の技がすべて実在する", bad_monster.is_empty(), str(bad_monster))


func _test_mastery_persists() -> void:
	var m := PartyMember.create("テスト", "soldier")
	_equal("初期ランクは 0", m.mastery_rank(), 0)
	_check("初期は基本技のみ", m.available_abilities() == ["attack", "guard"])

	var learned := m.gain_mastery(24)
	_equal("ランク 1 で 1 つ覚える", learned, ["power_slash"])
	_equal("ランクが上がる", m.mastery_rank(), 1)

	# 転職しても覚えた技は消えない（DQ6 / FF5 の肝）
	m.job_id = "mage"
	_check("転職後も技が残る", "power_slash" in m.available_abilities())
	_equal("転職先のランクは別勘定", m.mastery_rank(), 0)

	# レベルは失うが熟練度は残る、というランの境界
	m.level = 12
	m.reset_for_run()
	_equal("レベルは 1 に戻る", m.level, 1)
	_check("熟練度は残る", m.mastery_points("soldier") == 24)


## 上級職。熟練を貯める動機をラン単位からゲーム単位へ伸ばすための仕掛けなので、
## 「本人が条件を満たすまで就けない」が崩れると意味が無くなる。
func _test_advanced_jobs() -> void:
	Database.reload()

	var locked := []
	for job_id in Database.job_ids():
		if not Database.job(job_id).get("unlock", {}).is_empty():
			locked.append(job_id)
	_check("解放条件を持つ職業がある", not locked.is_empty(), str(Database.job_ids()))

	var m := PartyMember.create("テスト", "soldier")
	var target := String(locked[0])
	var unlock: Dictionary = Database.job(target).get("unlock", {})

	_check("最初は上級職に就けない", not m.can_take_job(target))
	_check("足りない条件が示される", not m.unmet_requirements(target).is_empty())
	_check("条件を満たす前は転職も拒否される", not m.change_job(target))
	_equal("拒否されたら職業は変わらない", m.job_id, "soldier")

	# 条件の職業をひとつだけ満たしても、まだ足りない
	var required: Array = unlock.keys()
	required.sort()
	_check("条件は 2 つ以上ある", required.size() >= 2, str(required))
	_grant_rank(m, String(required[0]), int(unlock[required[0]]))
	_check("片方だけでは就けない", not m.can_take_job(target))

	_grant_rank(m, String(required[1]), int(unlock[required[1]]))
	_check("両方を満たすと就ける", m.can_take_job(target))
	_check("条件が残っていない", m.unmet_requirements(target).is_empty())
	_check("上級職へ転職できる", m.change_job(target))
	_equal("職業が上級職になる", m.job_id, target)

	# 基本職は誰でも最初から就ける
	_check("基本職に条件は無い", PartyMember.create("素", "thief").can_take_job("soldier"))

	# 別の仲間は自分で条件を満たすまで就けない（誰かが極めれば全員、にはしない）
	_check("他の仲間には解放が波及しない", not PartyMember.create("別", "mage").can_take_job(target))


## 指定した職業の熟練を、目的のランクに届くまで積む。
func _grant_rank(m: PartyMember, job_id: String, rank: int) -> void:
	var before := m.job_id
	m.job_id = job_id
	for entry in Database.job(job_id).get("mastery", []):
		if int(entry.get("rank", 0)) == rank:
			m.gain_mastery(int(entry.get("need", 0)))
			break
	m.job_id = before


## 拠点での転職。GameState はオートロードなので --headless --script からは触れない。
## 転職の実体は PartyMember 側にあるので、そちらを直接検査する。
func _test_job_change() -> void:
	var m := PartyMember.create("テスト", "soldier")
	m.gain_mastery(30)
	var hp_before := m.max_hp()

	_check("同じ職業への転職は拒否", not m.change_job("soldier"))
	_check("存在しない職業への転職は拒否", not m.change_job("dancer"))
	_equal("拒否されたら職業は変わらない", m.job_id, "soldier")

	_check("転職できる", m.change_job("mage"))
	_check("能力値が転職先のものになる", m.max_hp() != hp_before)
	_equal("転職直後は満タン", m.hp, m.max_hp())
	_equal("前職の熟練度は残る", m.mastery_points("soldier"), 30)
	_check("前職で覚えた技も残る", "power_slash" in m.available_abilities())
	_equal("転職先の熟練度は 0 から", m.mastery_points("mage"), 0)

	# 貯めた熟練度は戻ってきたときにそのまま効く（ダーマ神殿の往復）
	m.gain_mastery(24)
	_equal("転職先でも熟練が貯まる", m.mastery_rank("mage"), 1)
	_check("元の職業に戻せる", m.change_job("soldier"))
	_equal("戻ると前職のランクが復活する", m.mastery_rank(), 1)
	_check("両方の技を持ったまま", m.available_abilities().has("fire")
		and m.available_abilities().has("power_slash"))
