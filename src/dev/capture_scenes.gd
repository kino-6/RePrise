class_name CaptureScenes
extends RefCounted

## 開発用。決まった画面へ直行して 1 枚撮る／そのまま操作する（S-1）。
##
##     godot --path . -- --shot=explore     撮って終了
##     godot --path . -- --inspect=cave     撮らずにその状態で操作する
##
## **`main.gd` から出したのは大きさではなく、触る頻度のため。**
## 画面を足すタスクは必ずここへ 1 節足すので、本編のすぐ隣に置いておくと
## 別の作業と同じファイルの同じ場所を奪い合う。
##
## ここは**本編を呼ぶだけ**にする。撮るために状態を作る近道を書くと、
## 「撮影では通るが遊ぶと通らない」経路が育つ（実際、踏み込む経路だと
## 重なった出来事の窓が先に出て、撮りたい階が写らなかった）。


static func run(main: Main, which: String, keep_open: bool = false) -> void:
	match which:
		"title":
			pass  # 起動直後がタイトル
		"prologue":
			main._enter_prologue()
		"prologue_shatter":
			main._enter_prologue()
			main.prologue.debug_open_beat(3)
		"prologue_worlds":
			main._enter_prologue()
			main.prologue.debug_open_beat(6)
		"prologue_oath":
			main._enter_prologue()
			main.prologue.debug_open_beat(7)
		"stronghold":
			main._enter_stronghold()
		"job":
			main._enter_stronghold()
			main.stronghold.debug_open_job_menu(0)
		"inherit":
			main._enter_stronghold()
			var member := GameState.active_party()[0]
			for job_id in Database.job_ids():
				member.job_exp[job_id] = 9999
				for entry in Database.job(job_id).get("mastery", []):
					var ability_id := String(entry.get("ability", ""))
					if ability_id != "" and ability_id not in member.learned:
						member.learned.append(ability_id)
			var candidates := member.inheritable_abilities()
			if not candidates.is_empty():
				member.inherited[0] = candidates[0]
			GameState.inherit_signs = ["soldier"]
			main.stronghold.debug_open_loadout(0)
		"depart":
			# 潜る理由と、4つの出撃選択が重なっていないかを見るため。
			main._enter_stronghold()
			GameState.upgrades["relic_satchel"] = 3
			GameState.reusable_loadout_id = "pilgrim_chalice"
			main.stronghold.debug_open_depart()
		"upgrade":
			main._enter_stronghold()
			main.stronghold.debug_open_upgrades()
		"rules":
			main._enter_stronghold()
			# 最長の名前・最大枠・高い倍率で収まりを見る。
			GameState.upgrades["world_lens"] = 2
			GameState.upgrades["marching_score"] = 2
			GameState.upgrades["oath_tablet"] = 2
			GameState.upgrades["provisions"] = 1
			GameState.upgrades["lifeline"] = 1
			GameState.run_rule_choices = {
				"difficulty": "ruin",
				"pace": "sprint",
				"contracts": ["closed_market", "empty_pack", "no_escape"],
			}
			main.stronghold.debug_open_rules()
		"explore":
			main._start_run()
		"items":
			main._start_run()
			GameState.add_item("herb", 3)
			GameState.add_item("water", 2)
			GameState.add_item("ember_talon")
			GameState.add_item("mending_stone")
			GameState.add_item("pilgrim_chalice")
			# 装備使用も同じ一覧へ出ることを見る撮影用の装備。
			for member in GameState.active_party():
				member.equipment["weapon"] = "prayer_staff"
			main._on_encounter()
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
			main.battle.debug_open_item_menu(true)
		"shop":
			# 町の武器売り場を撮る。物語や重なったイベントを経由すると
			# 品書きではない画面になるので、撮影時だけ町へ直に入る。
			main._start_run()
			GameState.gold = 300
			var town := DevProbe.first_site("town")
			if town.x >= 0:
				GameState.enter_site(town)
				main._open_town()
				main._on_shop_entered()
				main.shop.debug_set_category("weapon")
		"world":
			# 世界の全景。歩ける地形と拠点地の見分けを確かめる。
			main._start_run()
		"elite":
			# 赤い印が街道の脇に見え、主人公が踏まずに通れる構図を撮る。
			main._start_run()
			for raw_pos in GameState.world.events:
				var elite_pos: Vector2i = raw_pos
				if not bool(GameState.world.events[elite_pos].get("visible_elite", false)):
					continue
				for road in GameState.world.main_road:
					if absi(elite_pos.x - road.x) + absi(elite_pos.y - road.y) == 2:
						GameState.stand_on_world(road)
						main._enter_world()
						break
				break
		"elite_event":
			# 挑戦前に型のルールと「戻れば避けられる」が読めるかを見る。
			main._start_run()
			for raw_pos in GameState.world.events:
				var elite_pos: Vector2i = raw_pos
				if bool(GameState.world.events[elite_pos].get("visible_elite", false)):
					main._on_event_reached(elite_pos)
					break
		"elite_reward":
			# 勝利後の三択が、数値報酬だけでなく役割の違いとして読めるかを見る。
			main._start_run()
			main._open_elite_reward()
		"map":
			# 地図イベント後に封と安全路が増えた状態を撮る。
			main._start_run()
			GameState.event_map_reveals = 1
			for seal in GameState.world.seals:
				seal["known"] = true
			main._open_world_chart()
		"acrosschoice":
			# またぐ物語の最後の段階（三択）。
			main._enter_stronghold()
			GameState.cross_world = CrossWorldArc.empty_state()
			CrossWorldArc.select(GameState.cross_world, 9, 4242, {})
			var arc: Dictionary = CrossWorldArc.active(GameState.cross_world, {})
			GameState.cross_world["phase_index"] = (arc["beats"] as Array).size() - 1
			GameState.runs_attempted = 99
			var last: Dictionary = (arc["beats"] as Array).back()
			main._open_cross_world_choice(last)
		"hitfx":
			# 技の絵が敵の上に出るところを撮る。
			main._start_run()
			GameState.world.story_beat = 99
			main._on_encounter()
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
			await main.get_tree().create_timer(0.4).timeout
			# 描画そのものを確かめる（技→絵の対応は単体テストで見る）。
			main.effect.play("fx_fire", Vector2(256, 120))
		"effect":
			# 演出の見え方を撮る。演出は 0.4 秒で終わるので、
			# **世界を立ててから最後に流す**（下の待ちも短くしてある）。
			main._start_run()
			GameState.world.story_beat = 99
			await main.get_tree().create_timer(0.5).timeout
			main.effect.play("seal_break", Vector2(256, 120))
		"story":
			# 物語の 1 拍目。語りが窓に収まっているかを見る。
			main._start_run()
			var b0: Dictionary = GameState.world.story.get("beats", [])[0]
			var at0 := GameState.world.pos_of_site_id(String(b0.get("site_id", "")))
			GameState.world_pos = at0
			main._open_story(b0)
		"choicebeat":
			# 「代償の選択」の拍。守るもの・手ばなすものが読めるかを見る。
			main._start_run()
			var beats: Array = GameState.world.story.get("beats", [])
			for i in beats.size():
				if String(beats[i].get("phase", "")) == "choice":
					GameState.world.story_beat = i
					GameState.world_pos = GameState.world.pos_of_site_id(
						String(beats[i].get("site_id", "")))
					main._open_story(beats[i])
					break
		"event":
			# イベントの選択画面。払うものが選ぶ前に見えているかを確かめる。
			main._start_run()
			for pos in GameState.world.events:
				main._open_event(pos)
				break
		"event_outcome":
			# 選択後に代償と利益が読めるか。表示だけで終わる回帰もここで見る。
			main._start_run()
			var definition := WorldEventCatalog.event_by_id("signal_tower")
			var instance := WorldEventCatalog.instantiate(
				definition, DetRng.new(771), {"biome": GameState.biome_here()}
			)
			main._event_pos = GameState.world.start_pos
			GameState.world.events[main._event_pos] = instance
			main._on_event_choice(instance.get("choices", [])[1])
		"event_task":
			# 選択後、報酬前の実行工程が探索画面へ残るかを見る。
			main._start_run()
			var definition := WorldEventCatalog.event_by_id("broken_bridge")
			var instance := WorldEventCatalog.instantiate(
				definition, DetRng.new(771), {"biome": GameState.biome_here()}
			)
			main._event_pos = GameState.world.start_pos
			GameState.world.events[main._event_pos] = instance
			GameState.event_task = main.EventOperationScript.build(
				instance, instance.get("choices", [])[0], [],
				main._event_pos, GameState.floor_number
			)
			main._refresh_hud()
		"town", "town_dungeon", "town_grassland", "town_wetland", \
		"town_snowfield", "town_volcano":
			# 町の中の見え方（宿・店・人）を確かめる。
			# 物語や重なった出来事は町より先に出るので、撮影では直に入る。
			main._start_run()
			# キャラ美術の実画面基準は、ユーザー指定のまほうつかい。
			# NPCとの頭身・明暗・接地を毎回同じ基準で比較できるよう撮影時だけ替える。
			var leader := GameState.active_party()[0]
			leader.change_job("mage")
			var town_at := DevProbe.first_site("town")
			if town_at.x >= 0:
				GameState.enter_site(town_at)
				if which.begins_with("town_"):
					# 5生物相の町床Gate。構造とNPCを同じに保ち、床だけ比較する。
					GameState.site["tileset"] = which.trim_prefix("town_")
				main._open_town()
		"town_talk", "town_facility", "town_facility_repeat", \
		"town_chest", "town_chest_opened":
			# 会話が流れて消えず、話者・町の状況・実用情報を原寸で読めるかを見る。
			main._start_run()
			var talk_leader := GameState.active_party()[0]
			talk_leader.change_job("mage")
			var talk_town_at := DevProbe.first_site("town")
			if talk_town_at.x >= 0:
				GameState.enter_site(talk_town_at)
				main._open_town()
				if which == "town_chest" or which == "town_chest_opened":
					for step in FieldMap.NEIGHBORS:
						var near := main._town.supply_chest_pos + step
						if main._town.is_walkable(near.x, near.y):
							main.explore.setup(main._town, main._encounter_rng, main._leader_job(), near)
							break
					if which == "town_chest_opened":
						main._town.clear_supply_chest()
						main._on_town_chest()
				elif which == "town_facility" or which == "town_facility_repeat":
					main._on_town_facility()
					if which == "town_facility_repeat":
						# 初回の状態変化と再利用防止を、同じ実表示経路で再現する。
						main._close_town_talk()
						main._on_town_facility()
				else:
					for raw_pos in main._town.folk:
						var person: Dictionary = main._town.folk[raw_pos]
						if String(person.get("kind", "")) == "elder":
							main._on_talked(person)
							break
		"cave":
			main._start_run()
			var cave := DevProbe.first_site("cave")
			if cave.x >= 0:
				main._on_site_entered(cave)
		"greed":
			# 1 つ目を開けたあとの洞。**残りの箱に赤い印**が出て、
			# 「これ以上は呼ぶ」が踏む前に読めるかを確かめる（R-3）。
			# 洞へ直に入る。踏み込む経路だと、重なった出来事の窓が先に出て
			# 撮りたい階が写らない（実際そうなった）。
			main._start_run()
			var greed_cave := DevProbe.first_site("cave")
			if greed_cave.x >= 0:
				GameState.enter_site(greed_cave)
				main._enter_floor()
			if main._map != null and not main._map.chests.is_empty():
				main._map.chests_taken = GreedWatch.FREE_TAKES
				# 印が付いた箱の前に立たせる。遠くの箱を撮っても読めない。
				# **隣に立てる箱を選ぶ**（壁で囲まれた箱の前には行けない）。
				# **箱の真上には立たない。** 主人公の絵は印より後に描くので、
				# 隣に立つと自分の体で印を隠してしまう（撮って初めて分かった）。
				for raw_chest in main._map.chests:
					var mark_at: Vector2i = raw_chest
					var placed := false
					for step in FieldMap.NEIGHBORS:
						var far: Vector2i = mark_at + step * 2
						var near: Vector2i = mark_at + step
						if not main._map.is_walkable(near.x, near.y):
							continue
						var stand := far if main._map.is_walkable(far.x, far.y) else near
						main.explore.setup(main._map, main._encounter_rng, main._leader_job(), stand)
						placed = true
						break
					if placed:
						break
				main.hud.toast(Terms.GREED_WARNING)
		"cave_return":
			# 下り→上りを実入力で短く試せるよう、1階の下り階段前から始める。
			main.dev.prepare_cave_return(main, true)
		"cave_exit":
			# 1階の上り階段から世界へ戻る経路。
			main.dev.prepare_cave_return(main, false)
		"deep":
			# 終点近くの敵の見え方を確認する。
			main._start_run()
			GameState.floor_number = GameState.FINAL_FLOOR - 1
			main._enter_floor()
			for _i in 40:
				main._on_encounter()
				if main.battle.visible:
					break
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
		"boss":
			main._start_run()
			# 主の絵を撮るのが目的なので、開幕で壊滅しない程度に育てておく。
			# 敵 AI が範囲攻撃を選ぶようになってから、レベル 1 では 1 手で全滅する。
			for m in GameState.active_party():
				while m.level < 20:
					m.gain_exp(m.exp_to_next())
				m.hp = m.max_hp()
				m.mp = m.max_mp()
			# **世界へ入り直さない。** `_enter_world()` の暗転と主戦の閃光が
			# かち合って、撮影が世界のままになる。戦闘だけを立てる。
			# 実プレイと同じく「城の中」にしてから立てる（背景が城の絵になる）。
			GameState.floor_number = GameState.FINAL_FLOOR
			GameState.enter_site(GameState.world.castle_pos)
			main._battle_rng = GameState.rng_for("battle")
			main._on_boss_reached()
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
		"menu":
			main._start_run()
			GameState.add_item("herb", 3)
			GameState.add_gear("short_sword")
			GameState.add_gear("leather_vest")
			main._open_menu()
		"jobmenu":
			# てんしょくの一覧の見え方を確かめる
			main._start_run()
			# 熟練を積んだ状態で撮る。★ が最大まで並ぶのはこのときだけ。
			for m in GameState.active_party():
				while m.level < 7:
					m.gain_exp(m.exp_to_next())
				# 全職の熟練を積む（★ が最大まで並ぶ状態を作る）。
				for job_id in Database.job_ids():
					m.job_exp[job_id] = 9999
			main._open_menu()
			main.menu.debug_open_jobs()
		"status":
			# つよさ の重なりを見る
			main._start_run()
			for m in GameState.active_party():
				while m.level < 12:
					m.gain_exp(m.exp_to_next())
			main._open_menu()
			main.menu.debug_open_status()
		"equip":
			main._start_run()
			GameState.add_gear("war_axe")
			GameState.add_gear("flame_dagger")
			main._open_menu()
			main.menu.debug_open_equip()
		"party":
			main._enter_stronghold()
			GameState.echo = 90
			main.stronghold.debug_open_party()
		"settings":
			main.settings.open()
			main._set_mode(Main.Mode.SETTINGS)
		"save_erase":
			main.settings.open(true, true)
			main.settings.debug_open_save_erase()
			main._set_mode(Main.Mode.SETTINGS)
		"run_abandon":
			# 実際には終わらせず、最終確認だけを撮る。
			main._start_run()
			main._open_menu()
			main._open_settings()
			main.settings.debug_open_run_abandon()
		"upgrade":
			main._enter_stronghold()
			GameState.echo = 42
			main.stronghold.debug_open_upgrades()
		"win":
			main._start_run()
			# 記録の見え方を確かめたいので、それらしい戦績を入れておく
			GameState.kills = 24
			GameState.gold_earned = 380
			GameState.floor_number = GameState.FINAL_FLOOR
			GameState.deepest_floor = GameState.FINAL_FLOOR
			# 物語を通した状態で戦記を見る（終幕が回収されているか）。
			GameState.world.story_beat = 6
			var cs: Array = GameState.world.story.get("choices", [])
			if not cs.is_empty():
				GameState.world.story_choice = String(cs[0].get("id", ""))
			main.result.show_summary(GameState.end_run(true))
			main._set_mode(Main.Mode.RESULT)
		"commands":
			# 技が 1 ページに収まらないときの見え方を確認する。
			# 保存を挟まないので、この改変が名簿に残ることはない。
			main._start_run()
			for m in GameState.active_party():
				for job_id in Database.job_ids():
					for entry in Database.job(job_id).get("mastery", []):
						var ability_id := String(entry.get("ability", ""))
						if ability_id != "" and ability_id not in m.learned:
							m.learned.append(ability_id)
			main._on_encounter()
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
			# 技が増えたときのサブウィンドウの見え方を確かめる。
			main.battle.debug_open_ultimate_menu()
		"cover":
			# 場面転換の覆い（B-3）。**覆いきる途中**を撮る。
			# 実際の切り替えに任せると、どの覆いがいつ鳴るかが撮影と噛み合わない
			# （世界地図の門を「覆いが出ている」と見間違えた）。直に鳴らす。
			main._start_run()
			await main.get_tree().create_timer(0.9).timeout
			main._transition.play_cover("iris_gate", func() -> void: pass)
		"gearoffer":
			# 拾った装備を着けるか聞く窓（C-9）。
			main._start_run()
			await main.get_tree().create_timer(0.5).timeout
			GameState.add_gear("war_axe")
		"transition":
			# 遭遇の演出そのものを撮る。待ちは下の `wait` で調整する
			# （ここで待つと、そのあとの固定待ちが足されて撮り逃す）。
			main._start_run()
			main._on_encounter()
		"transition_lock":
			# 覆いが開いている中点で移動入力を押し、座標が変わらないことを実測する。
			main._start_run()
			await main.get_tree().create_timer(0.8).timeout
			var before := main.explore.player_pos
			var action := main.dev.step_to_exit(main)
			main._fade_to(Main.Mode.EXPLORE)
			await main.get_tree().create_timer(
				ScreenTransition.IN_TIME + ScreenTransition.MOSAIC_SWAP_HOLD * 0.75
			).timeout
			if action != "":
				Input.action_press(action)
				await main.get_tree().create_timer(ExploreView.MOVE_DELAY + 0.04).timeout
				Input.action_release(action)
			if main.explore.player_pos != before:
				push_error("遷移入力Gate: NG %s -> %s" % [before, main.explore.player_pos])
				main.get_tree().quit(1)
				return
			print("遷移入力Gate: OK（覆いの途中では移動しない）")
		"defeat_transition":
			# 戦場が崩れずに沈んでいく、全滅専用の暗転途中を撮る。
			main._start_run()
			main._on_encounter()
			await main.get_tree().create_timer(
				ScreenTransition.IN_TIME + ScreenTransition.OUT_TIME + 0.08
			).timeout
			Sound.stop_bgm()
			# セーブを書き換える end_run() は通さず、実際と同じ遷移経路だけを鳴らす。
			main._transition_to_result(true)
		"battle_opening":
			# 敵が先に動く開戦文を、実際の遭遇遷移経路で原寸確認する。
			main._start_run()
			var opening_foes := Encounter.build(
				main._battle_rng, GameState.floor_number, 100, GameState.biome_here())
			for foe in opening_foes:
				foe.agi = 999
			main._begin_battle(opening_foes, false)
			if not keep_open:
				main.battle.debug_hold_opening()
		"story_boss":
			# 一世界物語の決戦を別窓にせず、主戦の開戦文へ載せた実画面。
			main._start_run()
			GameState.cross_world = CrossWorldArc.empty_state()
			GameState.floor_number = GameState.FINAL_FLOOR
			GameState.enter_site(GameState.world.castle_pos)
			main._battle_rng = GameState.rng_for("battle")
			var story_beats: Array = GameState.world.story.get("beats", [])
			var finale: Dictionary = story_beats[4]
			main._battle_opening_context.append(
				String(finale.get("operation", {}).get("cue", "")))
			main._on_boss_reached()
			if not keep_open:
				main.battle.debug_hold_opening()
		"battle":
			main._start_run()
			main._on_encounter()
			# 味方のコマンド選択が出るまで待つ（見せたいのはその画面なので）
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
		"auto_items":
			main._start_run()
			GameState.add_item("medicine", 1)
			main._on_encounter()
			for _i in 60:
				await main.get_tree().create_timer(0.1).timeout
				if main.battle.is_awaiting_command():
					break
			main.battle.debug_show_auto_item()
		"result":
			main._start_run()
			main.result.show_summary(GameState.end_run(false))
			main._set_mode(Main.Mode.RESULT)
		"chronicle":
			# ローカル AI が書いた戦記を確かめる（届かなければテンプレートのまま）。
			main._start_run()
			GameState.kills = 18
			GameState.gold_earned = 240
			GameState.floor_number = 7
			GameState.deepest_floor = 7
			main.result.show_summary(GameState.end_run(false))
			main._set_mode(Main.Mode.RESULT)
	# 戦記の撮影だけは、ローカル AI の文章が届くのを少し待つ。
	# 戦記だけは AI の文章を待つ。演出は 0.4 秒で終わるので短く撮る。
	# 最長の頁遷移（0.88秒）と入力解放待ちを越えてから、静止画面を撮る。
	var wait := 1.05
	if which == "chronicle":
		wait = 9.0
	elif which == "effect" or which == "hitfx":
		wait = 0.15
	elif which == "cover":
		wait = ScreenTransition.COVER_IN_TIME * 0.65
	elif which == "transition":
		# **崩れている途中**を撮る。入りきると戦闘画面になってしまうので、
		# 入りの時間の 6 割で切る。
		wait = ScreenTransition.IN_TIME * 0.6
	elif which == "defeat_transition":
		wait = ScreenTransition.DEFEAT_DIM_TIME * 0.65
	await main.get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	if keep_open:
		main.get_window().title = "%s — inspect:%s" % [GameVersion.window_title(), which]
		print("検査画面: %s（実ゲーム入力で操作可能。終了はウィンドウを閉じる）" % which)
		return
	var image := main.get_viewport().get_texture().get_image()
	var path := "res://docs/preview/screen_%s.png" % which
	DirAccess.make_dir_recursive_absolute("res://docs/preview")
	image.save_png(path)
	print("撮影: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	# はみ出しの検出結果。--ui-check を付けたときだけ出る。
	if PixelUI.ui_check_enabled():
		var bad := PixelUI.ui_violations()
		if bad.is_empty():
			print("  はみ出し: なし")
		else:
			for note in bad:
				print("  はみ出し: %s" % note)
		# **詰めた文字も見せる。** 横のはみ出しは draw_text が自動で `…` に
		# するので遊ぶ側には見えないが、詰まっていること自体が割り付けの誤り。
		for note in PixelUI.clipped():
			print("  詰めた: %s" % note)
		# 安全のため描画しなかった行も失敗にする。空の窓を正常扱いしない。
		for note in PixelUI.dropped_lines():
			print("  行落ち: %s" % note)
		# **12px の漢字は潰れて読めない**（D-5）。かなと数字だけにする。
		for note in PixelUI.small_kanji():
			print("  小さすぎる漢字: %s" % note)
	main.get_tree().quit()
