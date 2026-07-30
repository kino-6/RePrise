class_name EventEffects
extends RefCounted

## イベントの効果トークンを、実際の数値・状態へ変換する 1 か所。
##
## Codex のカタログは `data/world_events.json` に HP 量や金額を書かず、
## `hp` `gold` `shortcut` のようなトークンだけを置いている。
## バランス調整と世界生成を分けるための作りなので、**数値はここにしか置かない。**
## JSON 側へ数を書き戻さないこと。
##
## いちばん大事な決めごと:
##
## > **知らないトークンを黙って無視しない。**
##
## 未対応のものを素通りさせると、選択肢が「押しても何も起きない」になり、
## しかもそれが画面上は成功に見える。そこで既知かどうかだけでなく、
## **全トークンが状態変化か戦闘予約を起こすこと**を Gate で検査する。

## 危険度 1 あたりの目安。深いところで起きたイベントほど、得も損も大きい。
const HP_PER_DANGER := 4
const GOLD_PER_DANGER := 14
const STEPS_PER_DANGER := 6

## 一時的な効果が続く歩数。
const TEMPORARY_STEPS := 40
const ROUTE_SAFE_STEPS := 56
const SHORTCUT_STEPS := 28
const ROUTE_LOSS_STEPS := 36
const BOSS_EFFECT_CAP := 3


## 支払い（costs）。払えなければ false を返し、選択そのものを断る。
##
## **払えないものを選ばせない。** 先に払えるかを見て、駄目なら理由を出す。
## 途中まで払って失敗するのが最悪で、何が減ったのか分からなくなる。
const COSTS := {
	"none": "なし",
	"hp": "からだ",
	"mp": "ちから",
	"gold": "ゴールド",
	"item": "どうぐ 1 つ",
	"equipment": "そうび 1 つ",
	"steps": "時間",
	"encounter_up": "しばらく 敵が 増える",
	"normal_fight": "たたかい",
	"elite_fight": "手強い たたかい",
	"route_loss": "この道が 使えなくなる",
	"service_loss": "町の 世話が 受けられなくなる",
}

## 危険（risks）。costs と同じ語彙で、確率で起きる側。
const RISKS := {
	"hp": "けが",
	"mp": "ちからの 消耗",
	"equipment": "そうびを 失う",
	"encounter_up": "敵が 増える",
	"normal_fight": "たたかいになる",
	"elite_fight": "手強い たたかいになる",
	"route_loss": "道を 失う",
	"service_loss": "町の 世話を 失う",
	"biome_shift": "土地の ようすが 変わる",
}

## 見返り（rewards）。
const REWARDS := {
	"none": "なし",
	"gold": "ゴールド",
	"item": "どうぐ",
	"equipment": "そうび",
	"heal": "手あて",
	"rest": "休息",
	"elite_loot": "よい 分けまえ",
	"encounter_down": "しばらく 敵が 減る",
	"route_safe": "この道が 安全になる",
	"shortcut": "近道",
	"map_reveal": "この先の ようすが 分かる",
	"biome_shift": "土地の ようすが 変わる",
	"boss_intel": "あるじの 手が 読める",
	"boss_weaken": "あるじが 弱る",
	"quest_reveal": "封の ありかが 分かる",
	"shop_bonus": "みせの 品が 増える",
	"inn_bonus": "やどが よくなる",
	"town_service": "町の 世話",
	"temporary_ally": "ひとときの 助け",
	"temporary_attack": "ひとときの 力",
	"temporary_guard": "ひとときの 守り",
	"temporary_resist": "ひとときの 耐性",
	"temporary_speed": "ひとときの 速さ",
}

## トークンの日本語。画面に出すのはこれ。
static func label(token: String, kind: String) -> String:
	match kind:
		"cost":
			return String(COSTS.get(token, token))
		"risk":
			return String(RISKS.get(token, token))
		_:
			return String(REWARDS.get(token, token))


## そのトークンが既知か。テストがこれで全数を突き合わせる。
static func known(token: String, kind: String) -> bool:
	match kind:
		"cost":
			return COSTS.has(token)
		"risk":
			return RISKS.has(token)
		_:
			return REWARDS.has(token)


## いま効果を持っているか。
## `none` だけは「何も受け取らない」という表示用トークン。
## 戦闘は main.gd が結果窓を閉じた直後に実行するため、ここでも効果ありと数える。
static func has_effect(token: String) -> bool:
	return token != "none" and (
		COSTS.has(token) or RISKS.has(token) or REWARDS.has(token)
	)


## Gate と実行側で共有する解決種別。unknown を allowed に足しただけでは通らない。
static func resolution_kind(token: String) -> String:
	if token == "none":
		return "none"
	if token in ["normal_fight", "elite_fight"]:
		return "fight"
	if has_effect(token):
		return "state"
	return "unknown"


static func fight_grade(tokens: Array) -> int:
	var grade := 0
	for raw in tokens:
		var token := String(raw)
		if token == "elite_fight":
			grade = 2
		elif token == "normal_fight":
			grade = maxi(grade, 1)
	return grade


## 選択しただけで済み扱いにしてよいか。
## 効果ゼロの撤退手は `defer: true` を必須にし、踏み直せば再び選べる。
static func choice_has_consequence(choice: Dictionary) -> bool:
	for field in ["costs", "risks", "rewards"]:
		for raw in choice.get(field, []):
			if has_effect(String(raw)):
				return true
	return bool(choice.get("defer", false))


static func choice_completes_event(choice: Dictionary) -> bool:
	return not bool(choice.get("defer", false))


## 支払えるか。足りないものの名前を返す（空なら払える）。
static func unpayable(state: GameState, tokens: Array, danger: int) -> Array[String]:
	var missing: Array[String] = []
	for raw in tokens:
		var token := String(raw)
		match token:
			"gold":
				if state.gold < GOLD_PER_DANGER * danger:
					missing.append("ゴールドが %d" % (GOLD_PER_DANGER * danger))
			"item":
				if state.inventory.is_empty():
					missing.append("どうぐ")
			"equipment":
				if state.gear_stock.is_empty():
					missing.append("あまった そうび")
			"hp":
				# 倒れるほどは払わせない（払った結果の全滅は理不尽）
				var lowest := 999
				for m in state.active_party():
					lowest = mini(lowest, m.hp)
				if lowest <= HP_PER_DANGER * danger:
					missing.append("からだの ゆとり")
	return missing


## 実際に払う。`unpayable()` が空のときだけ呼ぶこと。
## 戻り値は起きたことの説明（画面に出す）。
static func pay(state: GameState, tokens: Array, danger: int) -> Array[String]:
	var log_lines: Array[String] = []
	for raw in tokens:
		var token := String(raw)
		match token:
			"gold":
				var amount := GOLD_PER_DANGER * danger
				state.gold = maxi(state.gold - amount, 0)
				log_lines.append("%d ゴールドを 払った" % amount)
			"hp":
				var hurt := HP_PER_DANGER * danger
				for m in state.active_party():
					m.hp = maxi(m.hp - hurt, 1)
				log_lines.append("みんな %d 傷ついた" % hurt)
			"mp":
				var spent := HP_PER_DANGER * danger
				for m in state.active_party():
					m.mp = maxi(m.mp - spent, 0)
				log_lines.append("ちからを %d 使った" % spent)
			"item":
				var ids := state.inventory_ids()
				if ids.is_empty():
					_hurt_party(state, maxi(HP_PER_DANGER * danger / 2, 1))
					log_lines.append(Terms.EVENT_ITEM_MISSING)
				else:
					var id := String(ids[0])
					state.consume_item(id)
					log_lines.append("%s を 渡した" % Database.item(id).get("name", id))
			"equipment":
				if state.gear_stock.is_empty():
					_hurt_party(state, maxi(HP_PER_DANGER * danger / 2, 1))
					log_lines.append(Terms.EVENT_GEAR_MISSING)
				else:
					var gear := String(state.gear_stock[0])
					state.gear_stock.remove_at(0)
					log_lines.append("%s を 渡した" % Database.gear(gear).get("name", gear))
			"steps":
				state.steps += STEPS_PER_DANGER * danger
				log_lines.append("時間を 使った")
			"encounter_up":
				_change_route(state, 1, TEMPORARY_STEPS)
				log_lines.append(Terms.EVENT_ENCOUNTER_UP % TEMPORARY_STEPS)
			"route_loss":
				state.steps += STEPS_PER_DANGER * danger
				state.event_route_changes += 1
				_change_route(state, 2, ROUTE_LOSS_STEPS)
				log_lines.append(Terms.EVENT_ROUTE_LOST % ROUTE_LOSS_STEPS)
			"service_loss":
				state.event_service_loss += 1
				log_lines.append(Terms.EVENT_SERVICE_LOST)
			"biome_shift":
				var place := _shift_biome(state, 1)
				log_lines.append(Terms.EVENT_BIOME_DAMAGED % place)
	return log_lines


## 見返りを渡す。戻り値は説明と、戦闘が要るかどうか。
static func grant(state: GameState, tokens: Array, danger: int, rng: DetRng) -> Array[String]:
	var log_lines: Array[String] = []
	for raw in tokens:
		var token := String(raw)
		match token:
			"gold", "elite_loot":
				var amount := GOLD_PER_DANGER * danger * (2 if token == "elite_loot" else 1)
				state.gold += amount
				state.gold_earned += amount
				log_lines.append("%d ゴールドを 得た" % amount)
			"item":
				var pool := Database.item_ids_for_floor(danger)
				if not pool.is_empty():
					var id := String(rng.pick(pool))
					state.add_item(id)
					log_lines.append("%s を 得た" % Database.item(id).get("name", id))
			"equipment":
				var gear_pool := Database.gear_ids_for_floor(danger)
				if not gear_pool.is_empty():
					var id := String(rng.pick(gear_pool))
					state.add_gear(id)
					log_lines.append("%s を 得た" % Database.gear(id).get("name", id))
			"heal", "rest":
				for m in state.active_party():
					m.hp = m.max_hp()
					if token == "rest":
						m.mp = m.max_mp()
					m.cure_poison()
				log_lines.append("みんな 元気に なった")
			"quest_reveal":
				log_lines.append(_reveal_seal(state))
			"shop_bonus":
				state.event_shop_bonus += 1
				log_lines.append(Terms.EVENT_SHOP_STOCK)
			"encounter_down":
				_change_route(state, -1, TEMPORARY_STEPS)
				log_lines.append(Terms.EVENT_ENCOUNTER_DOWN % TEMPORARY_STEPS)
			"encounter_up":
				_change_route(state, 1, TEMPORARY_STEPS)
				log_lines.append(Terms.EVENT_ENCOUNTER_UP % TEMPORARY_STEPS)
			"route_safe":
				state.event_route_changes += 1
				_change_route(state, -1, ROUTE_SAFE_STEPS)
				log_lines.append(Terms.EVENT_ROUTE_SAFE % ROUTE_SAFE_STEPS)
			"shortcut":
				state.event_route_changes += 1
				_change_route(state, -2, SHORTCUT_STEPS)
				log_lines.append(Terms.EVENT_SHORTCUT % SHORTCUT_STEPS)
			"map_reveal":
				log_lines.append(_reveal_map(state))
			"biome_shift":
				var place := _shift_biome(state, -1)
				_change_route(state, -1, TEMPORARY_STEPS)
				log_lines.append(Terms.EVENT_BIOME_CALMED % place)
			"boss_intel":
				state.event_boss_intel = mini(state.event_boss_intel + 1, BOSS_EFFECT_CAP)
				log_lines.append(Terms.EVENT_BOSS_INTEL % state.event_boss_intel)
			"boss_weaken":
				state.event_boss_weaken = mini(state.event_boss_weaken + 1, BOSS_EFFECT_CAP)
				log_lines.append(Terms.EVENT_BOSS_WEAKEN % state.event_boss_weaken)
			"inn_bonus":
				state.event_inn_bonus += 1
				log_lines.append(Terms.EVENT_INN_BONUS)
			"town_service":
				state.event_town_service += 1
				log_lines.append(Terms.EVENT_TOWN_SERVICE)
			"temporary_ally", "temporary_attack", "temporary_guard", "temporary_resist", "temporary_speed":
				_add_boon(state, token)
				log_lines.append(Terms.EVENT_BOON % [label(token, "reward"), TEMPORARY_STEPS])
	return log_lines


## イベントで得た準備を戦闘へ反映する。表示だけの buff を作らないため、
## Battler の実数値を変えたあと BattleSystem へ渡す。
static func prepare_battle(
	state: GameState, allies: Array[Battler], enemies: Array[Battler], is_boss: bool
) -> Array[String]:
	var lines: Array[String] = []
	for boon in state.event_boons:
		for b in allies:
			match boon:
				"temporary_attack":
					b.atk = maxi(b.atk * 125 / 100, 1)
					b.mag = maxi(b.mag * 125 / 100, 1)
				"temporary_guard":
					b.defense = maxi(b.defense * 130 / 100, 1)
				"temporary_speed":
					b.agi = maxi(b.agi * 125 / 100, 1)
				"temporary_resist":
					for element in ["fire", "ice", "bolt"]:
						if element not in b.resist:
							b.resist.append(element)
				"temporary_ally":
					b.atk = maxi(b.atk * 112 / 100, 1)
					b.mag = maxi(b.mag * 112 / 100, 1)
					b.defense = maxi(b.defense * 112 / 100, 1)
					b.agi = maxi(b.agi * 112 / 100, 1)
	if not state.event_boons.is_empty():
		lines.append(Terms.EVENT_BATTLE_BOON)

	if is_boss and state.event_boss_intel > 0:
		var intel_scale := maxi(100 - state.event_boss_intel * 15, 55)
		for foe in enemies:
			foe.agi = maxi(foe.agi * intel_scale / 100, 1)
		lines.append(Terms.EVENT_BOSS_INTEL_ACTIVE)
	if is_boss and state.event_boss_weaken > 0:
		var weaken_scale := maxi(100 - state.event_boss_weaken * 12, 60)
		for foe in enemies:
			foe.max_hp = maxi(foe.max_hp * weaken_scale / 100, 1)
			foe.hp = mini(foe.hp, foe.max_hp)
			foe.atk = maxi(foe.atk * weaken_scale / 100, 1)
			foe.mag = maxi(foe.mag * weaken_scale / 100, 1)
			foe.defense = maxi(foe.defense * weaken_scale / 100, 1)
		lines.append(Terms.EVENT_BOSS_WEAKEN_ACTIVE)
	return lines


## 宿に着いたときの貸し借り。戻り値の blocked が true なら回復も起こさない。
static func consume_inn(state: GameState, rng: DetRng) -> Dictionary:
	var result := {"blocked": false, "lines": []}
	var lines: Array[String] = []
	if state.event_service_loss > 0:
		state.event_service_loss -= 1
		result["blocked"] = true
		lines.append(Terms.EVENT_INN_DENIED)
		result["lines"] = lines
		return result
	if state.event_town_service > 0:
		state.event_town_service -= 1
		var pool := Database.item_ids_for_floor(state.floor_number)
		if not pool.is_empty():
			var id := String(rng.pick(pool))
			state.add_item(id)
			lines.append(Terms.EVENT_INN_SUPPLY % Database.item(id).get("name", id))
	if state.event_inn_bonus > 0:
		state.event_inn_bonus -= 1
		_add_boon(state, "temporary_guard")
		lines.append(Terms.EVENT_INN_RESTED)
	result["lines"] = lines
	return result


static func _add_boon(state: GameState, token: String) -> void:
	state.event_boon = token
	if token not in state.event_boons:
		state.event_boons.append(token)
	state.event_bias_steps = maxi(state.event_bias_steps, TEMPORARY_STEPS)


static func _hurt_party(state: GameState, amount: int) -> void:
	for member in state.active_party():
		member.hp = maxi(member.hp - amount, 1)


static func _change_route(state: GameState, amount: int, duration: int) -> void:
	state.event_encounter_bias = clampi(state.event_encounter_bias + amount, -3, 3)
	state.event_bias_steps = maxi(state.event_bias_steps, duration)


## direction > 0 は危険側、< 0 は穏やかな側へ一段ずらす。
## 端でも必ず隣へ動かし、結果文だけ出て地形が同じ、を許さない。
static func _shift_biome(state: GameState, direction: int) -> String:
	if state.world == null:
		return "この辺り"
	var at := state.world_pos
	var current := state.world.biome_index_at(at.x, at.y)
	var last := WorldMap.BIOMES.size() - 1
	var target := clampi(current + signi(direction), 0, last)
	if target == current and last > 0:
		target = current - 1 if current == last else current + 1
	state.world.set_biome(at.x, at.y, target)
	state.event_biome_changes["%d,%d" % [at.x, at.y]] = target
	return String(WorldMap.BIOMES[target].get("name", "この辺り"))


## まだ解けていない封の在り処を 1 つ教える。
static func _reveal_seal(state: GameState) -> String:
	if state.world == null:
		return ""
	for s in state.world.seals:
		if bool(s.get("broken", false)):
			continue
		if bool(s.get("known", false)):
			continue
		s["known"] = true
		var at: Vector2i = s.get("pos", Vector2i.ZERO)
		return "%s は %s の 洞に ある" % [
			String(s.get("name", "封")), state.world.biome_name_at(at.x, at.y)
		]
	for s in state.world.seals:
		if not bool(s.get("broken", false)):
			return Terms.EVENT_SEALS_KNOWN
	return "封は すべて やぶれている"


## 地図は残る全ての封を既知にし、その情報で当面の遭遇も抑える。
## 画面に地図窓が無い現状でも、位置の情報とゲーム上の利益が両方残る。
static func _reveal_map(state: GameState) -> String:
	if state.world == null:
		return "地図を 読み解いた"
	var found := 0
	for s in state.world.seals:
		if bool(s.get("broken", false)) or bool(s.get("known", false)):
			continue
		s["known"] = true
		found += 1
	state.event_map_reveals += 1
	_change_route(state, -1, ROUTE_SAFE_STEPS)
	return Terms.EVENT_MAP_SEALS % found if found > 0 else Terms.EVENT_MAP_ROUTE
