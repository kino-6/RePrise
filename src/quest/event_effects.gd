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
## しかもそれが画面上は成功に見える。だから全トークンをここに列挙し、
## まだ効果を作っていないものは `INFORMATIONAL` に**明示的に**置く。
## テスト（`_test_event_effects`）が JSON 側の全トークンとここを突き合わせる。

## 危険度 1 あたりの目安。深いところで起きたイベントほど、得も損も大きい。
const HP_PER_DANGER := 4
const GOLD_PER_DANGER := 14
const STEPS_PER_DANGER := 6

## 一時的な効果が続く歩数。
const TEMPORARY_STEPS := 40


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

## まだ数値の効果を作っていないトークン。**文だけ出して、効果は無い。**
##
## 無視しているのではなく「まだ作っていない」と分かる場所に置く。
## ここを空にするのが次の仕事で、空になったらこの定数ごと消す。
const INFORMATIONAL := [
	"biome_shift",     # 土地の塗り替えは世界の再生成に触るので後回し
	"boss_intel", "boss_weaken",   # 主戦の下準備。BattleSystem 側に受け皿が要る
	"temporary_ally",  # 5 人目を戦闘へ入れる仕組みがまだ無い
	"inn_bonus", "town_service", "service_loss",  # 宿は無料なので差が出ない
	"route_loss", "route_safe", "shortcut", "map_reveal",  # 世界地図への書き込み
]


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


## いま効果を持っているか（`INFORMATIONAL` に無いもの）。
static func has_effect(token: String) -> bool:
	return token not in INFORMATIONAL


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
				var id := String(state.inventory.keys()[0])
				state.remove_item(id)
				log_lines.append("%s を 渡した" % Database.item(id).get("name", id))
			"equipment":
				var gear := String(state.gear_stock[0])
				state.gear_stock.remove_at(0)
				log_lines.append("%s を 渡した" % Database.gear(gear).get("name", gear))
			"steps":
				state.steps += STEPS_PER_DANGER * danger
				log_lines.append("時間を 使った")
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
				log_lines.append("みせの 品が 増えた")
			"encounter_down":
				state.event_encounter_bias = -1
				state.event_bias_steps = TEMPORARY_STEPS
				log_lines.append("しばらく 敵が 減る")
			"encounter_up":
				state.event_encounter_bias = 1
				state.event_bias_steps = TEMPORARY_STEPS
				log_lines.append("しばらく 敵が 増える")
			"temporary_attack", "temporary_guard", "temporary_resist", "temporary_speed":
				state.event_boon = token
				state.event_bias_steps = TEMPORARY_STEPS
				log_lines.append("%s を 得た" % label(token, "reward"))
	return log_lines


## まだ解けていない封の在り処を 1 つ教える。
static func _reveal_seal(state: GameState) -> String:
	if state.world == null:
		return ""
	for s in state.world.seals:
		if bool(s.get("broken", false)):
			continue
		var at: Vector2i = s.get("pos", Vector2i.ZERO)
		return "%s は %s の 洞に ある" % [
			String(s.get("name", "封")), state.world.biome_name_at(at.x, at.y)
		]
	return "封は すべて やぶれている"
