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
	_test_dungeon_route()
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
