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
	_test_dungeon_determinism()
	_test_dungeon_reachable()
	_test_database_loaded()
	_test_mastery_persists()

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
