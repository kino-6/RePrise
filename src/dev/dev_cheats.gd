class_name DevCheats
extends RefCounted

## 開発用の状態指定。**ゲームのロジックからは呼ばない。**
##
## 深い階や高レベルの手触りを確かめたいときに、そこまで遊んで到達するのは無駄。
## コマンドラインからランの初期状態を指定できるようにしてある。
##
##   godot --path . -- --play=120 --dev-level=8 --dev-floor=7 --dev-gear
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
				var gear_id := String(ids[i % ids.size()])
				state.add_gear(gear_id)
				state.equip_gear(party[i], gear_id)
		applied.append("装備一式")

	if has_flag("--dev-stock"):
		# 手持ちに入れるが着せない。装備の付け替えの道筋を確かめるため
		# （--dev-gear は着せてしまうので、UI を通ったかが分からない）。
		for slot in ["weapon", "armor", "accessory"]:
			for id in Database.gear_ids_in_slot(String(slot)):
				state.add_gear(String(id))
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
		state.floor_number = mini(floor_number, state.FINAL_FLOOR)
		state.deepest_floor = maxi(state.deepest_floor, state.floor_number)
		applied.append("地下 %d 階" % state.floor_number)

	return applied
