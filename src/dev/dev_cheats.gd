class_name DevCheats
extends RefCounted

## 開発用の状態指定。**ゲームのロジックからは呼ばない。**
##
## 深い階や高レベルの手触りを確かめたいときに、そこまで遊んで到達するのは無駄。
## コマンドラインからランの初期状態を指定できるようにしてある。
##
##   godot --path . -- --play=120 --dev-level=8 --dev-floor=7 --dev-gear
##
## 狙って通すときの組み合わせ（P-3）:
##
##   深層        --dev-level=8 --dev-floor=7
##   主戦        --dev-level=12 --dev-seals --dev-castle
##   拾ったら装備 --dev-drop=war_axe
##
## | 引数 | すること |
## |---|---|
## | `--dev-level=N` | 全員をレベル N にする（能力値も上がる） |
## | `--dev-floor=N` | 地下 N 階から始める |
## | `--dev-gear` | 手持ちに装備を一式入れて、全員に着せる |
## | `--dev-stock` | 手持ちに装備を入れるが着せない（付け替えの道筋を試す） |
## | `--dev-items` | 道具を一式入れる |
## | `--dev-echo=N` | 恒久通貨を N 持たせる（拠点の強化を試すため） |
## | `--dev-master` | 全職業の技を全部覚えた状態にする |
##
## 決定性は壊さない。ここが触るのは「ランの初期状態」だけで、
## 以後の乱数の引き方は通常どおり。


static func has_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


## `--dev-level=8` のような引数から値を取り出す。無ければ fallback。
static func value(flag: String, fallback: int = 0) -> int:
	var prefix := flag + "="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback


## `--dev-drop=short_sword` のような引数から文字を取り出す。
static func text(flag: String, fallback: String = "") -> String:
	var prefix := flag + "="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


static func any() -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--dev-"):
			return true
	return false


## ラン開始直後に呼ぶ。指定が無ければ何もしない。
static func apply_to_run(state: Node) -> Array[String]:
	var applied: Array[String] = []
	if not any():
		return applied

	var level := value("--dev-level", 0)
	if level > 1:
		for m in state.active_party():
			# gain_exp を回して上げる。レベルだけ書き換えると HP が伸びない。
			while m.level < level:
				m.gain_exp(m.exp_to_next())
			m.hp = m.max_hp()
			m.mp = m.max_mp()
		applied.append("レベル %d" % level)

	if has_flag("--dev-master"):
		for m in state.active_party():
			for job_id in Database.job_ids():
				for entry in Database.job(job_id).get("mastery", []):
					var ability_id := String(entry.get("ability", ""))
					if ability_id != "" and ability_id not in m.learned:
						m.learned.append(ability_id)
		applied.append("全技習得")

	if has_flag("--dev-gear"):
		var party: Array = state.active_party()
		for slot in ["weapon", "armor", "accessory"]:
			var ids := Database.gear_ids_in_slot(String(slot))
			if ids.is_empty():
				continue
			for i in party.size():
				# 適性導入後も開発用装備が空振りしないよう、その者が着けられる
				# 候補の中から決定的に 1 つ選ぶ。
				var usable: Array[String] = []
				for id in ids:
					if party[i].can_equip(String(id)):
						usable.append(String(id))
				if usable.is_empty():
					continue
				var gear_id := usable[i % usable.size()]
				state.add_gear(gear_id, false)
				state.equip_gear(party[i], gear_id)
		applied.append("装備一式")

	if has_flag("--dev-stock"):
		# 手持ちに入れるが着せない。装備の付け替えの道筋を確かめるため
		# （--dev-gear は着せてしまうので、UI を通ったかが分からない）。
		for slot in ["weapon", "armor", "accessory"]:
			for id in Database.gear_ids_in_slot(String(slot)):
				state.add_gear(String(id), false)
		applied.append("装備を手持ちへ")

	if has_flag("--dev-items"):
		for id in Database.all_items().keys():
			state.add_item(String(id), 5)
		applied.append("道具一式")

	var echo := value("--dev-echo", 0)
	if echo > 0:
		state.echo = echo
		applied.append("%s %d" % [Terms.ECHO, echo])

	var floor_number := value("--dev-floor", 0)
	if floor_number > 1:
		# **数字を書くだけでは深層にならない**（P-3）。
		#
		# 以前は `floor_number` を代入するだけで、party は門（危険度 1）に
		# 立ったままだった。世界の上では危険度は**立っている場所**で決まるので、
		# 次の `stand_on_world()` がすぐ 1 へ書き戻す。
		# 起動ログだけが「地下 7 階」と言う、という状態になっていた。
		#
		# 実際にその危険度の土地へ立たせる。**歩いて行ける場所**から選ぶので、
		# 「そこから先へ進める」ことも同時に保証される。
		var want := mini(floor_number, state.FINAL_FLOOR)
		var at := _tile_with_danger(state.world, want)
		if at.x >= 0:
			state.stand_on_world(at)
			applied.append("危険度 %d の地（%d, %d）" % [state.floor_number, at.x, at.y])
		else:
			state.floor_number = want
			state.deepest_floor = maxi(state.deepest_floor, state.floor_number)
			applied.append("危険度 %d（立てる土地が無く数値のみ）" % want)

	if has_flag("--dev-seals"):
		# **封を解いておく**（P-3）。城の扉は封が 3 つ解けるまで開かないので、
		# ここを開けないと「主戦を実入力で確かめる」に永遠に届かない。
		if state.world != null:
			for s in state.world.seals:
				(s as Dictionary)["broken"] = true
			applied.append("封を解いた")

	if has_flag("--dev-castle"):
		# 城の前に立たせる。封と併せて使うと、歩いて主戦へ入れる。
		if state.world != null:
			var gate := _tile_beside(state.world, state.world.castle_pos)
			if gate.x >= 0:
				state.stand_on_world(gate)
				applied.append("城の前")

	var drop := text("--dev-drop", "")
	if drop != "" and not Database.gear(drop).is_empty():
		# 拾った装備の通知（C-9）を実入力で踏むため、1 つ落としておく。
		state.add_gear(drop)
		applied.append("拾い物 %s" % drop)

	return applied


## その場所の隣で、歩いて行ける空きマスを 1 つ返す（無ければ x < 0）。
static func _tile_beside(world, at: Vector2i) -> Vector2i:
	var reach: PackedInt32Array = world.distance_field(world.start_pos)
	for step in FieldMap.NEIGHBORS:
		var side: Vector2i = at + step
		if not world.in_bounds(side.x, side.y):
			continue
		if reach[side.y * world.width + side.x] < 0:
			continue
		if world.sites.has(side):
			continue
		return side
	return Vector2i(-1, -1)


## その危険度の土地を 1 つ返す（無ければ x < 0）。
##
## **門から歩いて行ける場所だけ**を候補にする。孤島に置くと、
## そこから先へ進めず「深層を入力で確かめる」にならない。
## 走査は左上から順で、乱数を引かない（同じ世界からは同じ場所）。
static func _tile_with_danger(world, want: int) -> Vector2i:
	if world == null:
		return Vector2i(-1, -1)
	var reach: PackedInt32Array = world.distance_field(world.start_pos)
	var best := Vector2i(-1, -1)
	for y in world.height:
		for x in world.width:
			if reach[y * world.width + x] < 0:
				continue
			if world.sites.has(Vector2i(x, y)):
				continue   # 拠点地の上に立たせると、入るか出るかの判断が混ざる
			if world.danger_at(x, y) != want:
				continue
			best = Vector2i(x, y)
			return best
	return best
