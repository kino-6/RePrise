class_name BattleSystem
extends RefCounted

## CTB 戦闘のロジック本体。
##
## 描画も入力も持たない。UI は「今だれの手番か」を訊き、「この技をこの相手に」と
## 伝えるだけ。こうしておくと戦闘だけをヘッドレスで何千回も回してバランスを
## 測れる（CTB を選んだ最大の実利がこれ）。
##
## 設計の根拠は docs/battle_design.md。特に次の 3 つはそこから来ている。
##   * 属性の倍率 — 敵ごとに効く手が変わらないと、最強の 1 手を覚えて考えなくなる
##   * 範囲攻撃の減衰 — 減衰が無いと範囲が常に最適になり、単体を選ぶ理由が消える
##   * 敵の予告 — 相手の手が見えないと、こちらが手を変える理由が生まれない

signal finished(victory: bool)

const VARIANCE_LOW := 88
const VARIANCE_HIGH := 112

## 属性倍率（100 分率）。弱点で 2 倍、耐性で半減。
const ELEMENT_WEAK := 200
const ELEMENT_RESIST := 50

## 範囲攻撃の減衰。対象が少ないほど 1 体あたりが増える DQ 式。
## group は 2 体以下、all は 3 体以下で増える。
## 範囲技の 1 体あたりの威力（百分率）。少ない相手に撃つほど得。
##
## 表で 1〜3 だけ持っていたので、**4 体以上が減衰なしで一番得**になっていた
## （敵の上限を 6 へ上げた時点で、範囲技が常に最適解になる）。式に直す。
const SPREAD_SOLO := 150
const SPREAD_PAIR := 120
## 3 体以上は 1 体増えるごとに 7% 落ちる。下限を置いて無意味にはしない。
const SPREAD_STEP := 7
const SPREAD_FLOOR := 76


static func spread_bonus(count: int) -> int:
	if count <= 1:
		return SPREAD_SOLO
	if count == 2:
		return SPREAD_PAIR
	return maxi(100 - (count - 3) * SPREAD_STEP, SPREAD_FLOOR)

## 敵が候補に入れる素点の下限（最善の何 % か）。
## 小さいほど気まぐれ、100 にすると常に最善を打って理不尽になる。
const ENEMY_PICK_RATIO := 45

## 状態異常の持続手番。
const SLEEP_TURNS := 3
const POISON_TURNS := 5
## 毒の 1 手番あたりの割合（最大 HP 比・%）。
const POISON_RATE := 7

var scheduler := CtbScheduler.new()
var rng: DetRng = null
var floor_number: int = 1

var allies: Array[Battler] = []
var enemies: Array[Battler] = []

var is_over: bool = false
var stolen_gold: int = 0
## ぬすんだ道具の ID。戦闘後に GameState が持ち物へ入れる。
var stolen_items: Array[String] = []
## 一度中身を取った敵。id で持ち、同じ敵からの反復稼ぎを防ぐ。
var stolen_targets: Dictionary = {}

## 直近に実行された技。演出側が効果音を選ぶのに使う。
var last_ability_id: String = ""
## 直前の `perform()` が手番を進めたか。不成立理由を見せたあと同じ手番へ戻すための印。
var last_action_consumed := false

## 直近の行動でダメージを受けた者の id と量。演出（点滅と数字）に使う。
## 表示側がログの文字列を読んで判断すると、文言を変えた瞬間に演出が消える。
var last_hit_ids: Array[int] = []
var last_hit_amount: Dictionary = {}


## 持ち込んでいる継承印（E-2b）。**職の id で持つ。**
##
## `GameState` を直に見ない ―― Sim（`tests/balance.gd`）も同じ `BattleSystem` を
## 回すので、ここがオートロードに依存すると測れなくなる。呼ぶ側が渡す。
var signs: Array[String] = []

## 印を 1 戦に 1 度だけ使うための控え。`start()` で作り直す。
var _sign_used: Dictionary = {}


## 開戦時に分かること（E-2b）。**画面がそのまま読む行。**
##
## 印の多くは「情報が増える」報酬なので、数値ではなく**文**で返す。
## 数値の加算にすると、設計文書が禁じている「上げた人が強い」形になる。
var sign_notes: Array[String] = []


## その印を持っていて、この戦いでまだ使っていないか。
func sign_ready(job_id: String) -> bool:
	return job_id in signs and not _sign_used.has(job_id)


## 使ったことにする。**使えたときだけ呼ぶ**（空振りで消費しない）。
func spend_sign(job_id: String) -> void:
	_sign_used[job_id] = true


func start(
	party: Array[Battler], foes: Array[Battler], run_rng: DetRng,
	floor_no: int = 1, active_signs: Array[String] = []
) -> void:
	signs = active_signs
	_sign_used.clear()
	sign_notes.clear()
	allies = party
	enemies = foes
	rng = run_rng
	floor_number = floor_no
	is_over = false
	stolen_gold = 0
	stolen_items.clear()
	stolen_targets.clear()
	# 前の戦闘の残りかす（かばい・素早さ変化・状態異常）を持ち越さない。
	for b in party + foes:
		b.protected_by = null
		b.agi_scale = 100
		b.agi_scale_turns = 0
		b.guarding = false
		b.clear_status()
		b.planned_ability = ""
		b.endure_hits = 0
		b.decoy_hits = 0
		b.exposed_hits = 0
		b.pierce_casts = 0
		b.reload_turns = 0
	scheduler = CtbScheduler.new()
	_ultimate_uses.clear()
	_last_magic.clear()
	_in_ultimate = false
	_open_battle_signs()
	scheduler.add_all(allies)
	scheduler.add_all(enemies)
	# 敵の初手を先に決めておく。行動順バーに予告として出すため。
	for b in enemies:
		b.planned_ability = _choose_enemy_ability(b)


# --------------------------------------------------------------------------
# 進行
# --------------------------------------------------------------------------


## 素早さ変化が続く手番数。長すぎると一度かければ勝ちになり、
## 短すぎると重いコストを払う意味が無くなる。
const BUFF_TURNS := 4


## 次の手番を開始し、行動者を返す。
## 防御・かばい・素早さ変化の寿命は、すべてこの 1 か所で切る。
## 効果ごとに解除場所が散ると、必ずどれかが解除され忘れて永続化する。
func begin_turn() -> Battler:
	var actor := scheduler.next_actor()
	if actor == null:
		return null

	actor.guarding = false

	# 自分がかばっていた相手を解放する。守り続けるにはかばい直す。
	for b in scheduler.all():
		if b.protected_by == actor:
			b.protected_by = null

	if actor.agi_scale_turns > 0:
		actor.agi_scale_turns -= 1
		if actor.agi_scale_turns == 0:
			actor.agi_scale = 100
	return actor


## 手番の頭で起きること（毒の進行・眠りの判定）を解決する。
## 眠っていて動けないときは true を返す。UI はそのまま次の手番へ送る。
func begin_turn_effects(actor: Battler) -> Dictionary:
	var lines: Array[String] = []
	var skipped := false

	if actor.poison_turns > 0:
		actor.poison_turns -= 1
		var dmg := maxi(actor.max_hp * POISON_RATE / 100, 1)
		actor.apply_damage(dmg)
		lines.append("%sは　どくで %d の ダメージ！" % [actor.name, dmg])
		if not actor.is_alive():
			lines.append("%sは　たおれた…" % actor.name)
			_check_finished()
			return {"lines": lines, "skipped": true}

	# ★5 の状態の寿命（F-6a）。**数手番で切れる**ので、掛け直す判断が生まれる。
	if actor.counter_turns > 0:
		actor.counter_turns -= 1
	if actor.rune_turns > 0:
		actor.rune_turns -= 1
		if actor.rune_turns <= 0:
			actor.attack_element = ""
			lines.append("%sの　刃から 色が 抜けた" % actor.name)

	if actor.sleep_turns > 0:
		actor.sleep_turns -= 1
		lines.append("%sは　ねむっている…" % actor.name)
		skipped = true
		# 眠っているぶん、次の手番も後ろへ回る。
		scheduler.consume(actor, CtbScheduler.STANDARD_COST)

	# 全弾解放の反動。値 3 で置き、次の 2 手だけ通常攻撃か防御に絞る。
	# ここで減らすので、3→2（1手目）、2→1（2手目）、1→0（解除）となる。
	if actor.reload_turns > 0:
		actor.reload_turns -= 1
		if actor.reload_turns == 0:
			lines.append("%sは　装填を おえた" % actor.name)

	return {"lines": lines, "skipped": skipped}


## 開戦時に効く印（E-2b）。**情報を開くだけで、数値は動かさない。**
func _open_battle_signs() -> void:
	if "mage" in signs:
		# みとおしの印。いちばん通る属性が分かる。
		var weakest := ""
		for foe in enemies:
			for element in foe.weak:
				weakest = String(element)
				break
			if weakest != "":
				break
		sign_notes.append(
			"みとおしの印: %s が 通る" % weakest if weakest != ""
			else "みとおしの印: 目立った弱点は 無い"
		)
	if "ranger" in signs and not enemies.is_empty():
		# えものの印。狙う 1 体の残りと次の手が読める。
		var prey := enemies[0]
		for foe in enemies:
			if foe.hp > prey.hp:
				prey = foe
		sign_notes.append("えものの印: %s は 残り %d／次は %s" % [
			prey.name, prey.hp,
			Database.ability(prey.planned_ability).get("name", "まだ 読めない"),
		])
	if "gunner" in signs:
		# しょだんの印。初弾に性質が乗る（装填と同じ扱い）。
		for ally in allies:
			if ally.is_alive():
				ally.charged = true
				break
		sign_notes.append("しょだんの印: 初弾に 弾を こめた")


## 瀕死の獣をなだめる（E-2b / まじゅうつかい「なだめの印」）。
##
## **撃破とは違う決着。** 経験値は出ないが、戦いがそこで終わる。
## `てなずけ`（★5）より条件が厳しい代わりに、手番を使わない ――
## 印は「持ち込んだ判断」であって、押す技ではない。
func soothe_sign(target: Battler) -> bool:
	if not sign_ready("beastmaster") or _is_boss(target):
		return false
	if target.hp * 100 / maxi(target.max_hp, 1) > SOOTHE_HP:
		return false
	spend_sign("beastmaster")
	target.tamed = true
	_check_finished()
	return true


## なだめられる残り体力（百分率）。
const SOOTHE_HP := 25

## 記録した獣（E-2b / しょうかんし「けいやくの印」）。**1 ランに 1 体。**
var recorded_beast := ""


## 倒した相手を記録する。**すでに記録していれば上書きしない**
## （1 ランに 1 体、という約束を戦闘側で守る）。
func record_beast_sign(source_id: String) -> bool:
	if not sign_ready("summoner") or recorded_beast != "":
		return false
	spend_sign("summoner")
	recorded_beast = source_id
	return true


## 味方 2 人の次の手番を入れ替える（E-2b / じじゅつし「いれかえの印」）。
##
## **1 戦に 1 度。** 誰と誰を入れ替えるかは呼ぶ側（画面 / オート）が決める。
## 効いたときだけ true を返し、空振りでは消費しない。
func swap_turns_sign(a: Battler, b: Battler) -> bool:
	if a == b or not sign_ready("chronomancer"):
		return false
	if not (a.is_alive() and b.is_alive() and a.is_ally and b.is_ally):
		return false
	spend_sign("chronomancer")
	var keep := a.next_at
	a.next_at = b.next_at
	b.next_at = keep
	return true


## 直前に味方が使った技を、重い代価で再演する（E-2b / けんじゃ「さいえんの印」）。
##
## **奥義は再演できない**（`uses_per_battle` を持つ技）。許すと 1 戦制限が
## 抜け道になり、共通契約の意味が消える。
func echo_ability_sign(actor: Battler, target: Battler = null) -> Array[String]:
	if not sign_ready("sage") or last_ally_ability == "":
		return []
	if int(Database.ability(last_ally_ability).get("uses_per_battle", 0)) > 0:
		return ["%sは　奥義を 再演できない" % actor.name]
	spend_sign("sage")
	var cost := int(Database.ability(last_ally_ability).get("mp", 0)) * ECHO_MP_RATE / 100
	actor.mp = maxi(actor.mp - cost, 0)
	var lines: Array[String] = ["%sの さいえんの印！" % actor.name]
	lines.append_array(perform(actor, last_ally_ability, target))
	return lines


## さいえんの代価（もとの MP の百分率）。**重くする** ―― 軽いと毎回押すだけになる。
const ECHO_MP_RATE := 180

## 直前に味方が使った技（再演のもと）。
var last_ally_ability := ""


func turn_order(count: int = 8) -> Array[Battler]:
	return scheduler.preview(count)


## その者が今使える技（MP 不足のものは除く）。
func usable_abilities(actor: Battler) -> Array[String]:
	var result: Array[String] = []
	for id in actor.abilities:
		if ability_unavailable_reason(actor, id) == "":
			result.append(id)
	return result


## 技を押せない理由。手動・オート・テストが同じ判定を使う（F-7）。
##
## `target == null` は一覧を開いている段階。対象依存の条件は「候補が 1 体でも
## いるか」を見て、対象決定後は選んだ 1 体を厳密に見る。
func ability_unavailable_reason(
	actor: Battler, ability_id: String, target: Battler = null
) -> String:
	var ab := Database.ability(ability_id)
	if ab.is_empty():
		return Terms.REASON_NO_ABILITY
	# 直接 fixture は abilities を空にして個々の技だけを解く。実プレイでは
	# PartyMember が必ず所持技を渡すので、その経路だけ資源不足を拒否する。
	if ability_id in actor.abilities and actor.mp < int(ab.get("mp", 0)):
		return Terms.REASON_MP
	if actor.reload_turns > 0 and ability_id not in ["attack", "guard"]:
		return Terms.REASON_RELOADING

	var limit := int(ab.get("uses_per_battle", 0))
	if limit > 0 and ultimate_uses_left(actor, ability_id) <= 0:
		return Terms.REASON_USED

	var scope := String(ab.get("target", "one_enemy"))
	var friendly := living_allies() if actor.is_ally else living_enemies()
	var hostile := living_enemies() if actor.is_ally else living_allies()
	if scope == "one_ally_dead":
		var has_fallen := false
		for b in (allies if actor.is_ally else enemies):
			if not b.is_alive():
				has_fallen = true
				break
		if not has_fallen:
			return Terms.REASON_NO_FALLEN
	elif scope in ["one_enemy", "group_enemy", "all_enemies"] and hostile.is_empty():
		return Terms.REASON_NO_TARGET
	elif scope in ["one_ally", "all_allies"] and friendly.is_empty():
		return Terms.REASON_NO_TARGET

	match String(ab.get("condition", "")):
		"fallen_ally":
			var party := allies if actor.is_ally else enemies
			var fallen := false
			for b in party:
				if not b.is_alive():
					fallen = true
					break
			if not fallen:
				return Terms.REASON_NO_FALLEN
		"enemy_casting":
			if target != null:
				if target.planned_ability == "":
					return Terms.REASON_PICK_CASTING
			else:
				var casting := false
				for b in hostile:
					if b.planned_ability != "":
						casting = true
						break
				if not casting:
					return Terms.REASON_NO_CASTING
		"full_mp":
			if actor.mp < actor.max_mp:
				return Terms.REASON_FULL_MP
		"replayable_magic":
			if String(_last_magic.get(actor.is_ally, "")) == "":
				return Terms.REASON_NO_REPLAY
		"two_attack_spells":
			if _attack_spells(actor).size() < 2:
				return Terms.REASON_TWO_SPELLS
		"pacifiable_enemy":
			if target != null:
				if _is_boss(target):
					return Terms.REASON_BOSS
				if target.hp * 100 / maxi(target.max_hp, 1) > 50:
					return Terms.REASON_ALERT
			else:
				var found := false
				for b in hostile:
					if not _is_boss(b) and b.hp * 100 / maxi(b.max_hp, 1) <= 50:
						found = true
						break
				if not found:
					return Terms.REASON_NO_PACIFY
	return ""


func ultimate_uses_left(actor: Battler, ability_id: String) -> int:
	var limit := int(Database.ability(ability_id).get("uses_per_battle", 0))
	if limit <= 0:
		return 0
	return maxi(limit - int(_ultimate_uses.get([actor.id, ability_id], 0)), 0)


func living_allies() -> Array[Battler]:
	return scheduler.living_allies()


func living_enemies() -> Array[Battler]:
	return scheduler.living_enemies()


## chosen と同じ種族で生きている敵（＝1 グループ）。
## DQ と同じく、並んでいる同名の一団をひとまとめに扱う。
func group_of(chosen: Battler) -> Array[Battler]:
	var result: Array[Battler] = []
	if chosen == null:
		return result
	var pool := living_enemies() if not chosen.is_ally else living_allies()
	for b in pool:
		if b.source_id == chosen.source_id:
			result.append(b)
	return result


# --------------------------------------------------------------------------
# 行動の解決
# --------------------------------------------------------------------------


## 行動を実行し、表示用のログ行を返す。
func perform(actor: Battler, ability_id: String, target: Battler = null) -> Array[String]:
	last_action_consumed = false
	var ab := Database.ability(ability_id)
	if ab.is_empty():
		push_error("未定義のアビリティ: %s" % ability_id)
		return []
	var unavailable := ability_unavailable_reason(actor, ability_id, target)
	if unavailable != "":
		return ["%sは　%sを 使えない（%s）" % [
			actor.name, ab.get("name", ability_id), unavailable
		]]

	# **奥義の共通契約**（F-6b）。30 個ぶん個別に書くと必ず食い違うので、
	# 入口で 1 度だけ見る。
	#
	#   * 1 戦につき使える回数（`uses_per_battle`）
	#   * **奥義から奥義を再演できない** ―― 再演を許すと、行動回数を増やす
	#     奥義どうしで無限に回る（`_in_ultimate` が印）
	var limit := int(ab.get("uses_per_battle", 0))
	if limit > 0:
		if _in_ultimate:
			return ["%sは　続けて 奥義を 出せない" % actor.name]
		var used := int(_ultimate_uses.get([actor.id, ability_id], 0))
		if used >= limit:
			return ["%sは　もう %s を 出せない" % [actor.name, ab.get("name", ability_id)]]
		_ultimate_uses[[actor.id, ability_id]] = used + 1
		_in_ultimate = true

	last_ability_id = ability_id
	if actor.is_ally and int(ab.get("uses_per_battle", 0)) == 0:
		last_ally_ability = ability_id   # さいえんの印のもと（奥義は除く）
	last_hit_ids.clear()
	last_hit_amount.clear()
	var lines: Array[String] = []
	actor.mp = maxi(actor.mp - int(ab.get("mp", 0)), 0)
	lines.append("%sの　%s！" % [actor.name, ab.get("name", ability_id)])

	var targets := _resolve_targets(actor, ab, target)
	var kind := String(ab.get("kind", "physical"))
	var power := int(ab.get("power", 0))
	var ultimate_rule := String(ab.get("ultimate_rule", ""))
	var consume_pierce := (
		actor.pierce_casts > 0
		and (
			kind == "magical"
			or ultimate_rule in [
				"fourfold_collapse", "astral_beast_array", "chain_compound",
				"wise_furnace", "formula_reprise", "twin_ring_cast", "curtain_return",
			]
		)
	)

	if ultimate_rule != "":
		lines.append_array(_perform_ultimate(actor, ab, target))
	else:
		match kind:
			"physical", "magical":
				# **成立条件を持つ一撃は別経路**（F-2）。`ひっさつ` は残り体力で
				# 効き目が変わるので、素の打撃と同じ式では作れない。
				if String(ab.get("effect", "")) == "execute" and not targets.is_empty():
					lines.append_array(_execute_blow(actor, targets[0], ab))
				else:
					lines.append_array(_strike(actor, ab, targets, power, kind == "magical"))
			"heal":
				for t in targets:
					if String(ab.get("target", "")) == "one_ally_dead":
						if t.is_alive():
							lines.append("しかし　なにも おこらなかった")
							continue
						t.hp = maxi(t.max_hp * power / 100, 1)
						lines.append("%sは　いきを ふきかえした！" % t.name)
					elif String(ab.get("effect", "")) == "cleanse":
						if t.has_status():
							t.clear_status()
							lines.append("%sの　ぐあいが よくなった" % t.name)
						else:
							lines.append("しかし　なにも おこらなかった")
					else:
						var healed := t.heal(power + actor.mag / 2)
						lines.append("%sの　きずが %d かいふくした" % [t.name, healed])
			"buff", "debuff", "special":
				lines.append_array(_apply_effect(actor, ab, targets))

	if limit > 0:
		_in_ultimate = false
	if consume_pierce:
		actor.pierce_casts = maxi(actor.pierce_casts - 1, 0)
	if ultimate_rule == "" and kind == "magical":
		_last_magic[actor.is_ally] = ability_id

	# 行動コスト x 職業のテンポ倍率のぶんだけ、この者の次の手番が先に進む。
	scheduler.consume(actor, actor.scaled_cost(int(ab.get("cost", CtbScheduler.STANDARD_COST))))
	last_action_consumed = true

	_check_finished()
	return lines


## 打撃・魔法の解決。多段攻撃と範囲の減衰をここで面倒みる。
func _strike(
	actor: Battler, ab: Dictionary, targets: Array[Battler], power: int, magical: bool
) -> Array[String]:
	var lines: Array[String] = []
	var hits := maxi(int(ab.get("hits", 1)), 1)
	var element := String(ab.get("element", ""))
	# 武器の属性は通常攻撃にだけ乗せる（技は自前の属性を持つ）。
	if element == "" and not magical:
		element = actor.attack_element
	var spread := _spread_scale(String(ab.get("target", "one_enemy")), targets.size())
	# **呼び声**（しょうかんし「よびごえ」）。数が多いほど応えるものが増える。
	# 群れの割り引き（`_spread_scale`）を打ち消す方向なので、
	# 「多い相手ほど効く」という、ほかに無い形になる。
	if String(ab.get("effect", "")) == "swarm":
		spread = spread * (100 + targets.size() * SWARM_PER_FOE) / 100

	for t in targets:
		if not t.is_alive():
			continue
		# かばわれていれば、守り手が代わりに受ける。
		var receiver := t
		if t.protected_by != null and t.protected_by.is_alive() and t.protected_by != actor:
			receiver = t.protected_by
			lines.append("%sが　%sを かばった！" % [receiver.name, t.name])

		var total := 0
		var tag := ""
		# **装填**（じゅうし「そうてん」）。次の一撃だけ守りを抜いて重くなる。
		var shot_power := power
		var shot_pierce := bool(ab.get("pierce", false))
		if actor.charged:
			shot_power = shot_power * CHARGED_POWER / 100
			shot_pierce = true
		var redistribute := String(ab.get("effect", "")) == "redistribute"
		for _i in hits:
			if not receiver.is_alive():
				# **対象が消えたら、残りの打撃を回す**（型 2）。
				# ここが無いと「1 発目で倒れたら残りが宙に消える」になり、
				# 多段の奥義が相手の残り体力で強さが変わってしまう。
				if not redistribute:
					break
				var alive := living_enemies() if actor.is_ally else living_allies()
				if alive.is_empty():
					break
				receiver = alive[0]
				lines.append("%sへ 打ち直す" % receiver.name)
			var dmg := _damage(
				actor, receiver, shot_power * spread / 100, magical, element, shot_pierce)
			# **みきりの印**（E-2b / にんじゃ）。予告された単体攻撃を 1 度だけ避ける。
			# 予告が出ている相手にしか効かないので、**予告を見る目**が要る。
			if (
				receiver.is_ally and hits == 1 and not actor.is_ally
				and actor.planned_ability != "" and sign_ready("ninja")
			):
				spend_sign("ninja")
				lines.append("%sは　みきりの印で かわした！" % receiver.name)
				continue
			# **みがわりの印**（E-2b / せいきし）。致死傷を 1 度だけ 1 で耐える。
			var endured := _endure_sign(receiver, dmg)
			if endured != dmg:
				dmg = endured
				lines.append("%sは　みがわりの印で こらえた！" % receiver.name)
			var decoys_before := receiver.decoy_hits
			var dealt := receiver.apply_damage(dmg)
			total += dealt
			if decoys_before > receiver.decoy_hits:
				lines.append("%sの　影が 攻撃を 受けた" % receiver.name)
			elif dealt > 0:
				if receiver.id not in last_hit_ids:
					last_hit_ids.append(receiver.id)
				last_hit_amount[receiver.id] = int(
					last_hit_amount.get(receiver.id, 0)) + dealt
			# **反撃**（せんし「むかえうち」）。受けた傷をそのまま返す。
			if receiver.counter_turns > 0 and receiver.is_alive() and actor.is_alive():
				var back := dealt * COUNTER_RATE / 100
				if back > 0:
					actor.apply_damage(back)
					lines.append("%sが　むかえうった！ %s に %d" % [
						receiver.name, actor.name, back])
		actor.charged = false
		tag = _element_tag(receiver, element)
		if hits > 1:
			lines.append("%sに　%d の ダメージ！（%d 回）%s" % [receiver.name, total, hits, tag])
		else:
			lines.append("%sに　%d の ダメージ！%s" % [receiver.name, total, tag])

		# 眠りは物理で起きる（FF の作法。眠らせて殴るだけの解にしない）。
		if receiver.sleep_turns > 0 and not magical:
			receiver.sleep_turns = 0
			lines.append("%sは　目をさました！" % receiver.name)

		if String(ab.get("effect", "")) == "poison" and receiver.is_alive():
			if receiver.poison_turns <= 0 and rng.chance(60):
				receiver.poison_turns = POISON_TURNS
				lines.append("%sは　どくに おかされた！" % receiver.name)

		# **三つの理**（まほうつかい「みつのことわり」）。炎・氷・雷を同時に通す。
		if receiver.is_alive() and total > 0 				and String(ab.get("effect", "")) == "triune":
			for one in ["fire", "ice", "bolt"]:
				lines.append_array(_element_effect(actor, receiver, one, total))

		# **属性の効き目**（F-5）。弱点倍率だけで終わらせない ――
		# 倍率しか無いと、弱点を持たない相手には炎も氷も雷も同じ技になる。
		if receiver.is_alive() and total > 0:
			lines.append_array(_element_effect(actor, receiver, element, total))

		if not receiver.is_alive():
			lines.append("%sを　たおした！" % receiver.name)
			# **残影**（にんじゃ「ざんえい」）。倒しきればすぐ次が動ける。
			# 倒せなかったときは何も起きない ―― 決めきる技であって、
			# 押すだけで速くなる技ではない。
			if String(ab.get("effect", "")) == "afterimage":
				actor.next_at = maxi(actor.next_at - AFTERIMAGE_GAIN, 0)
				lines.append("%sは　影を のこして next へ" % actor.name)

	# 攻めながら味方も癒す技（賢者の一撃）。攻撃と回復を 1 手で兼ねるので、
	# 手番の価値がいちばん高い。そのぶんコストと MP は重くしてある。
	if String(ab.get("effect", "")) == "mend":
		var mend := actor.mag / 2 + 12
		for friend in (living_allies() if actor.is_ally else living_enemies()):
			var healed := friend.heal(mend)
			if healed > 0:
				lines.append("%sの　きずが %d かいふくした" % [friend.name, healed])
	return lines


## 属性が残していくもの（F-5）。**弱点を持たない相手にも効く。**
##
## 倍率だけだと、弱点表を持たない相手に対して炎も氷も雷も同じ技になり、
## 「属性を切り替える」判断が消える。1 手ごとに違うものが残るようにする。
##
##   炎 … **波及**。ほかの敵へも延焼する（群れに強い）
##   氷 … **足止め**。次の手番が遅れる（CTB を直に触る）
##   雷 … **中断**。溜めていた行動を打ち消す（予告技への答え）
##   闇 … **交換**。与えた傷の一部を自分の MP へ移す（続ける力に変える）
##
## どれも**「いつ押すか」が変わる**ように選んである。数字の色違いにしない。
func _element_effect(
	actor: Battler, target: Battler, element: String, dealt: int
) -> Array[String]:
	var lines: Array[String] = []
	match element:
		"fire":
			var others := living_enemies() if actor.is_ally else living_allies()
			var splash := dealt * FIRE_SPLASH / 100
			if splash <= 0:
				return lines
			for other in others:
				if other == target:
					continue
				other.apply_damage(splash)
				lines.append("%sにも 火が うつった（%d）" % [other.name, splash])
				if not other.is_alive():
					lines.append("%sを　たおした！" % other.name)
		"ice":
			# 次の手番を遅らせる。**倒しきれない相手に対する答え**になる。
			target.next_at += CtbScheduler.wait_for(target.effective_agi(), ICE_DELAY)
			lines.append("%sの　動きが にぶった" % target.name)
		"bolt":
			# 溜めている行動を打ち消す。予告技を見てから当てる技。
			if target.planned_ability != "":
				target.planned_ability = ""
				lines.append("%sの　構えが くずれた！" % target.name)
		"dark":
			# 傷を自分の力へ移す。**削るだけでなく、続ける力に変える。**
			var drained := dealt * DARK_DRAIN / 100
			if drained > 0 and actor.mp < actor.max_mp:
				actor.mp = mini(actor.mp + drained, actor.max_mp)
				lines.append("%sは 力を すいとった（MP+%d）" % [actor.name, drained])
	return lines


## 属性の効き目の量。**実測で決める**（`balance.gd -- --runs=500` が帯を見る）。
const FIRE_SPLASH := 25
const ICE_DELAY := 45
const DARK_DRAIN := 20


func _element_tag(target: Battler, element: String) -> String:
	if element == "":
		return ""
	if element in target.weak:
		return "　弱点！"
	if element in target.resist:
		return "　効きが わるい"
	return ""


## 範囲攻撃の減衰。対象が少ないほど 1 体あたりが増える。
## これが無いと範囲攻撃が常に最適になり、単体攻撃を選ぶ理由が消える。
func _spread_scale(scope: String, count: int) -> int:
	if scope == "group_enemy":
		return spread_bonus(count)
	if scope == "all_enemies":
		return spread_bonus(count)
	return 100


func _resolve_targets(actor: Battler, ab: Dictionary, chosen: Battler) -> Array[Battler]:
	match String(ab.get("target", "one_enemy")):
		"self":
			return [actor] as Array[Battler]
		"all_enemies":
			return living_enemies() if actor.is_ally else living_allies()
		"all_allies":
			return living_allies() if actor.is_ally else living_enemies()
		"group_enemy":
			if chosen != null:
				return group_of(chosen)
			var pool := living_enemies() if actor.is_ally else living_allies()
			return group_of(pool[0]) if not pool.is_empty() else ([] as Array[Battler])
		_:
			if chosen != null and chosen.is_alive():
				return [chosen] as Array[Battler]
			# 対象が死んでいた等で未指定なら、生存者から選び直す
			var pool := living_enemies() if actor.is_ally else living_allies()
			return ([pool[0]] as Array[Battler]) if not pool.is_empty() else ([] as Array[Battler])


## 致死傷を 1 度だけ肩代わりする（E-2b / せいきし「みがわりの印」）。
##
## **倒れる直前にだけ効く。** 常時発動にすると「硬くなる」だけになり、
## 設計文書が禁じている形（解放するほど強い）になる。
func _endure_sign(target: Battler, damage: int) -> int:
	if not target.is_ally or damage < target.hp:
		return damage
	if not sign_ready("paladin"):
		return damage
	spend_sign("paladin")
	return maxi(target.hp - 1, 0)


@warning_ignore("integer_division")
func _damage(
	actor: Battler, target: Battler, power: int, magical: bool, element: String,
	pierce: bool = false
) -> int:
	# 物理は防御力をまともに受け、魔法は半分しか受けない。
	var base := (actor.mag if magical else actor.atk) * power / 100
	var reduction := target.defense / 4 if magical else target.defense / 2
	# 守りを抜く技は防御力を無視する。硬い相手に対する答えになる。
	if pierce:
		reduction = 0
	var dmg := base - reduction
	if element != "":
		if element in target.weak:
			dmg = dmg * ELEMENT_WEAK / 100
		elif element in target.resist and not (magical and actor.pierce_casts > 0):
			dmg = dmg * ELEMENT_RESIST / 100
	if target.exposed_hits > 0:
		target.exposed_hits -= 1
		dmg = dmg * EXPOSED_RATE / 100
	dmg = dmg * rng.range_i(VARIANCE_LOW, VARIANCE_HIGH) / 100
	if target.guarding:
		dmg = dmg / 2
	return maxi(dmg, 1)


func _apply_effect(actor: Battler, ab: Dictionary, targets: Array[Battler]) -> Array[String]:
	var lines: Array[String] = []
	var effect := String(ab.get("effect", ""))

	# ぼうぎょ（effect 指定なしの self 技）
	if effect == "" and String(ab.get("target", "")) == "self":
		actor.guarding = true
		lines.append("%sは　みをまもっている" % actor.name)
		return lines

	# **「鈍らせる」に何が付いてくるか**（F-2）。相手への効果は下の輪で、
	# 使い手の側に起きることはここで 1 回だけ。
	if effect == "slow_and_haste_self":
		actor.agi_scale = 150
		actor.agi_scale_turns = BUFF_TURNS
		# 止めた時間のぶん、自分が先に動く。説明どおりの効き目にする。
		actor.next_at -= CtbScheduler.wait_for(actor.effective_agi(), TIME_STOP_GAIN)
	elif effect == "slow_and_flee":
		# 煙は逃げるための技。**鈍足の上位互換にしない**（`ときとまれ` と
		# 役割が重なると、強いほうだけ使われて片方が飾りになる）。
		smoke_screen = true

	for t in targets:
		match effect:
			"haste":
				t.agi_scale = 150
				t.agi_scale_turns = BUFF_TURNS
				lines.append("%sの　すばやさが あがった！" % t.name)
			"slow":
				t.agi_scale = 70
				t.agi_scale_turns = BUFF_TURNS
				# 素早さが落ちた効果を行動順にも即座に反映させる
				t.next_at += CtbScheduler.wait_for(t.effective_agi(), 40)
				lines.append("%sの　すばやさが さがった！" % t.name)
			"slow_and_haste_self", "slow_and_flee":
				# **同じ「鈍らせる」でも、付いてくるものが違う**（F-2）。
				# 前は両方とも素の `slow` で、名前と説明だけが違っていた
				# （`ときとまれ` の説明は「自分を速める」と言っていたのに
				# 何も速めていなかった）。数値違いは技の作り分けではない。
				t.agi_scale = 70
				t.agi_scale_turns = BUFF_TURNS
				t.next_at += CtbScheduler.wait_for(t.effective_agi(), 40)
				lines.append("%sの　すばやさが さがった！" % t.name)
			"sleep":
				# ボスには効きにくい。ここが効きすぎると戦闘が「眠らせて殴る」だけになる。
				var odds := 35 if _is_boss(t) else 70
				if rng.chance(odds):
					t.sleep_turns = SLEEP_TURNS
					lines.append("%sは　ねむってしまった！" % t.name)
				else:
					lines.append("%sには きかなかった" % t.name)
			"defend_up":
				# 自分は自分をかばえない。全体版（まもりのかまえ）で自分が
				# 対象に入ったときは、素直に身構えるだけにする。
				if t == actor:
					actor.guarding = true
					lines.append("%sは　みをまもっている" % actor.name)
				else:
					t.protected_by = actor
					lines.append("%sが　%sを かばう たいせいに はいった" % [actor.name, t.name])
			"steal":
				lines.append_array(_steal_from(actor, t))
			"random":
				# **えらびのばくち印**（E-2b / あそびにん）。最初の運まかせだけ、
				# 2 つ引いて ましなほうを採れる。**1 戦に 1 度**なので、
				# ここぞで押すか、軽く流すかが判断になる。
				if sign_ready("jester"):
					spend_sign("jester")
					var first := rng.range_i(0, 5)
					var second := rng.range_i(0, 5)
					var better := (
						first if WHIM_SCORE[first] >= WHIM_SCORE[second] else second)
					lines.append("%sは えらびのばくち印で 目を選んだ" % actor.name)
					lines.append_array(_play_around(actor, t, better))
				else:
					lines.append_array(_play_around(actor, t))
			"extra_turn":
				# **行動回数を変える**（奥義の型 1）。この者がもう一度すぐ動く。
				# 再演は禁じてあるので、奥義から奥義へは繋がらない。
				actor.next_at = maxi(actor.next_at - ULTIMATE_TURN_GAIN, 0)
				lines.append("%sは　もう一度 動ける！" % actor.name)
			"reorder":
				# **行動表を変える**（型 3）。敵の手番を後ろへ、味方を前へ。
				for b in scheduler.living():
					if b.is_ally == actor.is_ally:
						b.next_at = maxi(b.next_at - REORDER_SHIFT, 0)
					else:
						b.next_at += REORDER_SHIFT
				lines.append("%sが　流れを 書き換えた" % actor.name)
			"convert":
				# **資源を変える**（型 4）。体力を削って魔力へ、または逆へ。
				if actor.mp * 100 / maxi(actor.max_mp, 1) < 50:
					var paid := maxi(actor.hp * CONVERT_RATE / 100, 1)
					actor.apply_damage(mini(paid, maxi(actor.hp - 1, 0)))
					actor.mp = mini(actor.mp + paid, actor.max_mp)
					lines.append("%sは　命を 力へ 変えた（MP+%d）" % [actor.name, paid])
				else:
					var spent := maxi(actor.mp * CONVERT_RATE / 100, 1)
					actor.mp = maxi(actor.mp - spent, 0)
					actor.heal(spent * 2)
					lines.append("%sは　力を 命へ 変えた（HP+%d）" % [actor.name, spent * 2])
			"banish":
				# **撃破以外の決着**（型 5）。倒さずに場から外す。
				# `てなずけ` より確実だが、1 戦に 1 度きり。
				if _is_boss(t):
					lines.append("%sには　通じない" % t.name)
				else:
					t.tamed = true
					lines.append("%sは　この場から 消えた" % t.name)
					_check_finished()
			"counter":
				# 構えて待つ。受けた傷をそのまま返す（せんし）。
				actor.guarding = true
				actor.counter_turns = SIGNATURE_TURNS
				lines.append("%sは　むかえうちの かまえ" % actor.name)
			"chain":
				# 全員を癒し、いちばん深い傷の者を速める（そうりょ）。
				var worst: Battler = null
				for friend in (living_allies() if actor.is_ally else living_enemies()):
					if worst == null or friend.hp * 100 / maxi(friend.max_hp, 1) 							< worst.hp * 100 / maxi(worst.max_hp, 1):
						worst = friend
				if worst != null:
					worst.agi_scale = 150
					worst.agi_scale_turns = BUFF_TURNS
					lines.append("%sの　いのりが %s に とどいた" % [actor.name, worst.name])
			"cover_all":
				# 全員を自分の背へ置く（せいきし）。
				for friend in (living_allies() if actor.is_ally else living_enemies()):
					if friend != actor:
						friend.protected_by = actor
				lines.append("%sが　みんなを 背にした" % actor.name)
			"rune_edge":
				# 刃に属性を移す。しばらく通常攻撃に乗る（まけんし）。
				actor.attack_element = RUNE_ELEMENTS[
					rng.range_i(0, RUNE_ELEMENTS.size() - 1)]
				actor.rune_turns = SIGNATURE_TURNS
				lines.append("%sの　刃が 色を おびた" % actor.name)
			"reload":
				# 弾を込める。次の一撃が守りを抜いて重くなる（じゅうし）。
				actor.charged = true
				lines.append("%sは　弾を こめた" % actor.name)
			"stillness":
				# 構えを解かせ、動きを止める（けんじゃ）。
				t.planned_ability = ""
				t.agi_scale = 70
				t.agi_scale_turns = BUFF_TURNS
				t.next_at += CtbScheduler.wait_for(t.effective_agi(), 40)
				lines.append("%sは　動きを 止められた" % t.name)
			"pull_turn":
				# 味方ひとりの手番を今へ引き寄せる（じじゅつし）。
				# **いちばん早い者より前に置く。** 絶対時刻を持たないので、
				# 場でいちばん早い `next_at` を基準にする。
				var soonest := t.next_at
				for b in scheduler.living():
					soonest = mini(soonest, b.next_at)
				t.next_at = maxi(soonest - 1, 0)
				lines.append("%sの　手番が すぐ来る！" % t.name)
			"tame":
				# **倒さずに戦いから降ろす**（まじゅうつかい）。弱った相手ほど応じる。
				# 撃破ではないので経験値も戦利品も出ない ―― 速さと引き換えの決着。
				var ratio := t.hp * 100 / maxi(t.max_hp, 1)
				if _is_boss(t):
					lines.append("%sには　通じない" % t.name)
				elif rng.range_i(0, 99) < TAME_BASE - ratio:
					t.tamed = true
					lines.append("%sは　戦いから おりた" % t.name)
					_check_finished()
				else:
					lines.append("%sは　応じない" % t.name)
			"steal_and_haste":
				lines.append_array(_steal_from(actor, t))
				actor.agi_scale = 150
				actor.agi_scale_turns = BUFF_TURNS
				lines.append("%sは　そのまま 先へ 回った" % actor.name)
			"all_or_nothing":
				# **全部の出目をまとめて通す**（あそびにん）。良いも悪いも全部くる。
				for roll in 6:
					lines.append_array(_play_around(actor, t, roll))
			"random_pick":
				# **同じ乱数表の範囲版にしない**（F-2）。`あそぶ` は出たとこ勝負、
				# `きまぐれ` は**三つ引いて ましなものを選ぶ**。
				# 同じ表を単体／範囲で分けただけだと、操作としては同じ技になる。
				lines.append_array(_pick_best_whim(actor, t))
			_:
				lines.append("しかし　なにも おこらなかった")
	return lines


## きまぐれ。**三つ引いて、いちばんましな出目を採る**（F-2）。
##
## `あそぶ` と同じ表を使うが、引き方が違う。出たとこ勝負ではなく
## 「悪い目を避ける」技なので、押すときの気持ちが別になる。
## 乱数は `DetRng` だけ（同じ種からは同じ出目）。
func _pick_best_whim(actor: Battler, target: Battler) -> Array[String]:
	var best := 0
	var best_score := -1
	for _i in WHIM_DRAWS:
		var roll := rng.range_i(0, 5)
		var score: int = WHIM_SCORE[roll]
		if score > best_score:
			best_score = score
			best = roll
	return _play_around(actor, target, best)


# --------------------------------------------------------------------------
# ★7・8 奥義（F-6b）
# --------------------------------------------------------------------------


func _friends_of(actor: Battler) -> Array[Battler]:
	return living_allies() if actor.is_ally else living_enemies()


func _foes_of(actor: Battler) -> Array[Battler]:
	return living_enemies() if actor.is_ally else living_allies()


func _first_foe(actor: Battler, chosen: Battler = null) -> Battler:
	if chosen != null and chosen.is_alive() and chosen.is_ally != actor.is_ally:
		return chosen
	var foes := _foes_of(actor)
	return foes[0] if not foes.is_empty() else null


func _ultimate_strike(
	actor: Battler,
	chosen: Battler,
	power: int,
	magical: bool = false,
	hits: int = 1,
	element: String = "",
	redistribute: bool = false,
	pierce: bool = false
) -> Array[String]:
	var foe := _first_foe(actor, chosen)
	if foe == null:
		return ["しかし　対象が いない"]
	var strike_data := {
		"target": "one_enemy",
		"power": power,
		"hits": hits,
		"element": element,
		"effect": "redistribute" if redistribute else "",
		"pierce": pierce,
	}
	return _strike(
		actor, strike_data, [foe] as Array[Battler], power, magical
	)


func _ultimate_strike_all(
	actor: Battler, power: int, magical: bool = false, element: String = ""
) -> Array[String]:
	var strike_data := {
		"target": "all_enemies",
		"power": power,
		"element": element,
	}
	return _strike(actor, strike_data, _foes_of(actor), power, magical)


func _most_hurt_friend(actor: Battler) -> Battler:
	var worst: Battler = null
	for friend in _friends_of(actor):
		if worst == null or friend.hp * worst.max_hp < worst.hp * friend.max_hp:
			worst = friend
	return worst


func _slowest_friend(actor: Battler) -> Battler:
	var slowest: Battler = null
	for friend in _friends_of(actor):
		if (
			slowest == null
			or friend.next_at > slowest.next_at
			or (friend.next_at == slowest.next_at and friend.id < slowest.id)
		):
			slowest = friend
	return slowest


func _attack_spells(actor: Battler) -> Array[String]:
	var result: Array[String] = []
	for id in actor.abilities:
		var spell := Database.ability(id)
		if (
			String(spell.get("kind", "")) == "magical"
			and int(spell.get("power", 0)) > 0
			and String(spell.get("ultimate_rule", "")) == ""
		):
			result.append(id)
	result.sort_custom(func(a: String, b: String) -> bool:
		var aa := Database.ability(a)
		var bb := Database.ability(b)
		var score_a := int(aa.get("power", 0)) * maxi(int(aa.get("hits", 1)), 1)
		var score_b := int(bb.get("power", 0)) * maxi(int(bb.get("hits", 1)), 1)
		return score_a > score_b if score_a != score_b else a < b
	)
	return result


func _replay_magic(actor: Battler, ability_id: String, chosen: Battler) -> Array[String]:
	var spell := Database.ability(ability_id)
	if spell.is_empty() or String(spell.get("kind", "")) != "magical":
		return ["再演できる術式が なかった"]
	var targets := _resolve_targets(actor, spell, chosen)
	var lines: Array[String] = ["%sを 再演！" % spell.get("name", ability_id)]
	lines.append_array(_strike(
		actor, spell, targets, int(spell.get("power", 0)), true
	))
	return lines


func _fate_score(actor: Battler, target: Battler, card: int) -> int:
	match card:
		0: # 攻撃
			return 4 if target != null and target.hp * 100 / maxi(target.max_hp, 1) <= 45 else 2
		1: # 回復
			var hurt := _most_hurt_friend(actor)
			return 5 if hurt != null and hurt.hp * 100 / maxi(hurt.max_hp, 1) <= 45 else 1
		2: # 中断
			return 5 if target != null and target.planned_ability != "" else 1
		_: # 加速
			return 3


func _play_fate_card(actor: Battler, target: Battler, card: int) -> Array[String]:
	var lines: Array[String] = []
	match card:
		0:
			lines.append("剣の札を 選んだ")
			lines.append_array(_ultimate_strike(actor, target, 205))
		1:
			var hurt := _most_hurt_friend(actor)
			if hurt != null:
				var healed := hurt.heal(actor.mag + 55)
				lines.append("杯の札！ %sの 傷が %d 回復" % [hurt.name, healed])
		2:
			if target != null:
				target.planned_ability = ""
				target.next_at += CtbScheduler.wait_for(target.effective_agi(), 80)
				lines.append("鎖の札！ %sの 構えが ほどけた" % target.name)
		_:
			actor.next_at = maxi(actor.next_at - ULTIMATE_TURN_GAIN, 0)
			lines.append("翼の札！ %sの 手番が 近づいた" % actor.name)
	return lines


## 30 個の奥義は View へ分岐を散らさず、ここで戦闘規則として解く。
## 共通する打撃・回復・CTB 操作は上の helper を通すので、手動とオートで同じ結果になる。
func _perform_ultimate(actor: Battler, ab: Dictionary, chosen: Battler) -> Array[String]:
	var lines: Array[String] = []
	var target := _first_foe(actor, chosen)
	match String(ab.get("ultimate_rule", "")):
		"counter_phalanx":
			actor.counter_turns = 4
			for friend in _friends_of(actor):
				if friend != actor:
					friend.protected_by = actor
			lines.append("%sは 全員を背に置き、反撃に備えた" % actor.name)
		"veteran_barrage":
			lines.append_array(_ultimate_strike(actor, target, 55, false, 8, "", true))
			actor.next_at = maxi(actor.next_at - 70, 0)
		"sanctuary":
			for friend in _friends_of(actor):
				var healed := friend.heal(52 + actor.mag / 2)
				friend.clear_status()
				lines.append("%sの 傷と異常が癒えた（%d）" % [friend.name, healed])
		"returning_bell":
			var party := allies if actor.is_ally else enemies
			for friend in party:
				if friend.is_alive():
					friend.endure_hits = maxi(friend.endure_hits, 1)
					lines.append("%sは 一度だけ踏みとどまれる" % friend.name)
				else:
					friend.tamed = false
					friend.hp = maxi(friend.max_hp * 35 / 100, 1)
					lines.append("%sは いきを ふきかえした！" % friend.name)
		"phase_reveal":
			if target != null:
				var weak_text := "なし" if target.weak.is_empty() else "・".join(target.weak)
				var resist_text := "なし" if target.resist.is_empty() else "・".join(target.resist)
				lines.append("%s　弱点:%s　耐性:%s" % [target.name, weak_text, resist_text])
				target.next_at += CtbScheduler.wait_for(target.effective_agi(), 35)
			actor.pierce_casts = 1
			lines.append("%sの 次の魔法は耐性を抜く" % actor.name)
		"fourfold_collapse":
			for element in ["fire", "ice", "bolt", "dark"]:
				lines.append_array(_ultimate_strike(
					actor, target, 44, true, 1, element, false
				))
				target = _first_foe(actor, target)
				if target == null:
					break
		"shade_pilfer":
			if target != null:
				var had_stolen := stolen_targets.has(target.id)
				lines.append_array(_steal_from(actor, target))
				lines.append_array(_ultimate_strike(actor, target, 145))
				if had_stolen:
					actor.next_at = maxi(actor.next_at - ULTIMATE_TURN_GAIN, 0)
					lines.append("%sは 空いた手で 次へ回った" % actor.name)
		"time_pilfer":
			var receiver := _slowest_friend(actor)
			if target != null and receiver != null:
				target.next_at += CtbScheduler.wait_for(target.effective_agi(), ULTIMATE_DELAY)
				receiver.next_at = maxi(receiver.next_at - ULTIMATE_DELAY, 0)
				lines.append("%sの時間を %sへ渡した" % [target.name, receiver.name])
		"unyielding_line":
			actor.guarding = true
			actor.counter_turns = 3
			actor.endure_hits = maxi(actor.endure_hits, 1)
			for friend in _friends_of(actor):
				if friend != actor:
					friend.protected_by = actor
			lines.append("%sは 崩れない守りを敷いた" % actor.name)
		"vow_of_life":
			for friend in _friends_of(actor):
				friend.endure_hits = maxi(friend.endure_hits, 1)
			actor.next_at += ULTIMATE_DELAY
			lines.append("味方全員が 一度だけ致死傷に耐える")
		"shadow_double":
			actor.decoy_hits = 2
			actor.next_at = maxi(actor.next_at - 45, 0)
			lines.append("%sの前に 二つの影が立った" % actor.name)
		"thousand_shadow_break":
			lines.append_array(_ultimate_strike(actor, target, 62, false, 6, "", true))
		"hunter_mark":
			if target != null:
				target.exposed_hits = 3
				var plan := target.planned_ability
				lines.append("%sを狩標にした　次:%s" % [
					target.name,
					"構えなし" if plan == "" else Database.ability(plan).get("name", plan),
				])
		"sky_arrow_rain":
			lines.append_array(_ultimate_strike(actor, target, 48, false, 8, "", true))
		"opposition_edge":
			if target != null:
				var element := ""
				if not target.weak.is_empty():
					var weak_sorted := target.weak.duplicate()
					weak_sorted.sort()
					element = String(weak_sorted[0])
				else:
					for candidate in ["fire", "ice", "bolt", "dark"]:
						if candidate not in target.resist:
							element = candidate
							break
				lines.append("最も通る %s の刃を選んだ" % element)
				lines.append_array(_ultimate_strike(actor, target, 215, false, 1, element))
		"fourfold_edge":
			for element in ["fire", "ice", "bolt", "dark"]:
				lines.append_array(_ultimate_strike(
					actor, target, 58, false, 1, element, false
				))
				target = _first_foe(actor, target)
				if target == null:
					break
		"guardian_pact":
			var hurt := _most_hurt_friend(actor)
			if hurt != null and hurt.hp * 100 / maxi(hurt.max_hp, 1) <= 55:
				for friend in _friends_of(actor):
					var healed := friend.heal(42 + actor.mag / 2)
					lines.append("%sを 守護獣が癒した（%d）" % [friend.name, healed])
			else:
				for friend in _friends_of(actor):
					friend.guarding = true
					friend.agi_scale = 150
					friend.agi_scale_turns = 2
				lines.append("守護獣が 守りと速さを授けた")
		"astral_beast_array":
			lines.append_array(_ultimate_strike_all(actor, 72, true, "bolt"))
			for friend in _friends_of(actor):
				friend.heal(35 + actor.mag / 2)
			for foe in _foes_of(actor):
				foe.next_at += CtbScheduler.wait_for(foe.effective_agi(), 55)
			lines.append("星獣が 治療と足止めを重ねた")
		"lockbreaker_round":
			lines.append_array(_ultimate_strike(actor, target, 220, false, 1, "", false, true))
			if target != null and target.is_alive():
				target.planned_ability = ""
				target.next_at += CtbScheduler.wait_for(target.effective_agi(), 90)
				lines.append("%sの 構えを撃ち抜いた" % target.name)
		"full_barrage":
			lines.append_array(_ultimate_strike(actor, target, 70, false, 6, "", true, true))
			actor.reload_turns = 3
			lines.append("%sは 弾倉を空にした" % actor.name)
		"chain_compound":
			lines.append_array(_ultimate_strike_all(actor, 64, true))
			for foe in _foes_of(actor):
				if foe.is_alive():
					foe.poison_turns = maxi(foe.poison_turns, 3)
			var hurt := _most_hurt_friend(actor)
			if hurt != null:
				var healed := hurt.heal(55 + actor.mag)
				lines.append("%sへ薬を回した（%d）" % [hurt.name, healed])
		"wise_furnace":
			var fuel := actor.mp
			actor.mp = 0
			lines.append_array(_ultimate_strike_all(actor, 90 + fuel * 2, true, "fire"))
			for friend in _friends_of(actor):
				friend.heal(fuel + actor.mag)
			lines.append("満ちた力を 攻撃と治療へ転化した")
		"formula_reprise":
			lines.append_array(_replay_magic(
				actor, String(_last_magic.get(actor.is_ally, "")), target
			))
		"twin_ring_cast":
			var spells := _attack_spells(actor)
			for i in mini(spells.size(), 2):
				lines.append_array(_replay_magic(actor, spells[i], target))
				target = _first_foe(actor, target)
				if target == null:
					break
		"time_exchange":
			var receiver := _slowest_friend(actor)
			if target != null and receiver != null:
				var held := receiver.next_at
				receiver.next_at = target.next_at
				target.next_at = held
				lines.append("%sと %sの手番を交換した" % [receiver.name, target.name])
		"zero_time_field":
			var living := scheduler.living()
			var first := actor.next_at
			var last := actor.next_at
			for b in living:
				first = mini(first, b.next_at)
				last = maxi(last, b.next_at)
			for friend in _friends_of(actor):
				friend.next_at = first
			actor.mp = 0
			actor.next_at = last + ULTIMATE_DELAY
			lines.append("味方の時を揃え、%sは最後尾へ退いた" % actor.name)
		"pacify":
			if target != null:
				target.tamed = true
				lines.append("%sは 戦いをやめた" % target.name)
				_check_finished()
		"beast_procession":
			if _foes_of(actor).size() >= 2:
				lines.append_array(_ultimate_strike_all(actor, 58))
			else:
				lines.append_array(_ultimate_strike(actor, target, 135))
			var hurt := _most_hurt_friend(actor)
			if hurt != null:
				hurt.heal(35 + actor.mag)
				lines.append("癒しの獣が %sへ寄り添った" % hurt.name)
			var stopped := false
			for foe in _foes_of(actor):
				if foe.planned_ability != "":
					foe.planned_ability = ""
					foe.next_at += CtbScheduler.wait_for(foe.effective_agi(), 55)
					lines.append("牙の獣が %sの構えを崩した" % foe.name)
					stopped = true
					break
			if not stopped:
				actor.next_at = maxi(actor.next_at - 55, 0)
				lines.append("風の獣が %sを先へ運んだ" % actor.name)
		"fate_cards":
			var first_card := rng.range_i(0, 3)
			var second_card := rng.range_i(0, 3)
			var picked := (
				first_card
				if _fate_score(actor, target, first_card)
					>= _fate_score(actor, target, second_card)
				else second_card
			)
			lines.append("二枚の札から よい流れを選んだ")
			lines.append_array(_play_fate_card(actor, target, picked))
		"curtain_return":
			var party := allies if actor.is_ally else enemies
			var fallen: Array[Battler] = []
			for friend in party:
				if not friend.is_alive():
					fallen.append(friend)
			if not fallen.is_empty():
				for friend in fallen:
					friend.tamed = false
					friend.hp = maxi(friend.max_hp * 30 / 100, 1)
				lines.append("倒れた味方を 舞台へ戻した")
			else:
				var hurt := _most_hurt_friend(actor)
				if hurt != null and hurt.hp * 100 / maxi(hurt.max_hp, 1) <= 45:
					for friend in _friends_of(actor):
						friend.heal(48 + actor.mag / 2)
					lines.append("崩れかけた味方を 立て直した")
				else:
					var casting: Battler = null
					for foe in _foes_of(actor):
						if foe.planned_ability != "":
							casting = foe
							break
					if casting != null:
						casting.planned_ability = ""
						casting.next_at += CtbScheduler.wait_for(
							casting.effective_agi(), 90)
						lines.append("%sの見せ場を 奪った" % casting.name)
					else:
						lines.append_array(_ultimate_strike_all(actor, 105, true))
		_:
			lines.append("しかし　奥義は 形にならなかった")
	return lines


## 奥義の効き幅。**1 戦に 1 度きりなので、はっきり効く量にする。**
const ULTIMATE_TURN_GAIN := 120
const REORDER_SHIFT := 90
const CONVERT_RATE := 35
const EXPOSED_RATE := 150
const ULTIMATE_DELAY := 150


## 奥義の使用回数（`[battler.id, ability_id]` → 使った回数）と、再演の印。
##
## **1 戦のあいだだけ持つ。** `start()` で作り直すので、次の戦いへ持ち越さない。
var _ultimate_uses: Dictionary = {}
var _in_ultimate := false
## 陣営ごとの、直前に成立した通常魔法。奥義は記録せず、再演の連鎖を断つ。
var _last_magic: Dictionary = {}


## 装填の倍率と、反撃で返す割合と、残影で戻る量。
## 呼び声が敵 1 体ごとに増える割合。
const SWARM_PER_FOE := 18

const CHARGED_POWER := 170
const COUNTER_RATE := 60
const AFTERIMAGE_GAIN := 70


## ★5 の象徴技が残る手番数と、細かい数値。
const SIGNATURE_TURNS := 3
## 刃に乗せられる属性（`_element_effect` が実装しているもの）。
const RUNE_ELEMENTS: Array[String] = ["fire", "ice", "bolt", "dark"]
## 手懐けの基準。相手の残り体力（%）を引いた値が確率になる。
const TAME_BASE := 85


## 何回引くか、と出目の good さ（`_play_around` の match と同じ並び）。
const WHIM_DRAWS := 3
const WHIM_SCORE: Array[int] = [0, 0, 3, 2, 2, 1]


## あそぶ。何が起きるか読めないが、コストがとても軽い。
##
## 「読めない」を乱数で作るときは、外れも当たりも同じ確率で並べないこと。
## 半分は何も起きないくらいで丁度よく、当たったときだけ強い手になる。
## あそぶ / きまぐれ。対象 1 体ごとに引き直す（グループでも同じ結果が並ばない）。
## とどめ（`ひっさつ`）。**手負いほど深く入る**（F-2）。
##
## 前はただの高威力技で、名前だけが「必殺」だった。連打が最適になるうえ、
## 「いつ使うか」の判断が無い。相手の残り体力で威力が変わる形にすると、
## **削ってから当てる**という手順が生まれる。
func _execute_blow(actor: Battler, target: Battler, ab: Dictionary) -> Array[String]:
	var ratio := target.hp * 100 / maxi(target.max_hp, 1)
	var power := int(ab.get("power", 100))
	if ratio <= EXECUTE_LOW_HP:
		power = power * EXECUTE_BONUS / 100
	var dmg := _damage(actor, target, power, false, String(ab.get("element", "")))
	target.apply_damage(dmg)
	var lines: Array[String] = []
	if ratio <= EXECUTE_LOW_HP:
		lines.append("%sの ひっさつ！ 急所に 入った！" % actor.name)
	else:
		lines.append("%sの ひっさつ！" % actor.name)
	lines.append("%sに %d の ダメージ！" % [target.name, dmg])
	if not target.is_alive():
		lines.append("%sを　たおした！" % target.name)
	return lines


## とどめが深く入る残り体力（百分率）と、そのときの倍率。
const EXECUTE_LOW_HP := 40
const EXECUTE_BONUS := 220

## `ときとまれ` で自分が先に動く量。
const TIME_STOP_GAIN := 60

## 煙幕が張られているか。**逃げやすさに効く**（`けむりだま`）。
var smoke_screen := false


## `roll` を渡すと、その出目で解決する（`きまぐれ` が選んだ目を使う）。
func _play_around(actor: Battler, target: Battler, roll: int = -1) -> Array[String]:
	var lines: Array[String] = []
	match (rng.range_i(0, 5) if roll < 0 else roll):
		0, 1:
			lines.append("%sは おどけてみせた。なにも おこらない" % actor.name)
		2:
			var dmg := _damage(actor, target, 180, false, "")
			target.apply_damage(dmg)
			lines.append("%sの ふいうち！ %sに %d の ダメージ！" % [actor.name, target.name, dmg])
			if not target.is_alive():
				lines.append("%sを　たおした！" % target.name)
		3:
			target.agi_scale = 70
			target.agi_scale_turns = BUFF_TURNS
			target.next_at += CtbScheduler.wait_for(target.effective_agi(), 40)
			lines.append("%sは つられて笑った。すばやさが さがった！" % target.name)
		4:
			var healed := actor.heal(actor.max_hp / 4)
			lines.append("%sは 大笑いして %d 元気になった" % [actor.name, healed])
		_:
			actor.agi_scale = 150
			actor.agi_scale_turns = BUFF_TURNS
			lines.append("%sは 調子に乗った！ すばやさが あがった！" % actor.name)
	return lines


func _is_boss(b: Battler) -> bool:
	return bool(Database.monster(b.source_id).get("boss", false))


## ぬすむ。手番を使う以上、初回は必ずラン内資源を得る。
## 代わりに同じ敵から取れるのは一度だけ。レア枠だけを確率抽選し、
## 外れた場合はコモン枠、コモンが無ければまとまったゴールドを得る。
func _steal_from(actor: Battler, target: Battler) -> Array[String]:
	var lines: Array[String] = []
	if stolen_targets.has(target.id):
		lines.append("%sは　もう なにも もっていない" % target.name)
		return lines

	var table: Dictionary = Database.monster(target.source_id).get("steal", {})
	var bonus := 20 if actor.has_effect("steal_up") else 0
	var agi_edge := maxi(actor.effective_agi() - target.effective_agi(), 0) / 2
	var rare_odds := mini(20 + bonus + agi_edge, 70)

	var rare_id := String(table.get("rare", ""))
	if rare_id != "" and rng.chance(rare_odds):
		stolen_items.append(rare_id)
		stolen_targets[target.id] = true
		lines.append("%sから　%s を ぬすんだ！" % [
			target.name, Database.item(rare_id).get("name", rare_id)
		])
		return lines

	var common_id := String(table.get("common", ""))
	if common_id != "":
		var count := 2 if actor.has_effect("steal_up") else 1
		for _i in count:
			stolen_items.append(common_id)
		stolen_targets[target.id] = true
		lines.append("%sから　%sを %dこ ぬすんだ！" % [
			target.name, Database.item(common_id).get("name", common_id), count
		])
		return lines

	# レアしか持たない相手の抽選外れや空の表も、手番を無報酬にはしない。
	var loot := rng.range_i(8 + floor_number * 3, 16 + floor_number * 6)
	stolen_gold += loot
	stolen_targets[target.id] = true
	lines.append("%sから　%d %sを ぬすんだ！" % [target.name, loot, Terms.GOLD])
	return lines


# --------------------------------------------------------------------------
# 道具
# --------------------------------------------------------------------------


## 道具を使う。技と同じく手番を消費するので、
## 「回復に 1 手番を割く」という CTB 上の判断がそのまま成立する。
##
## 在庫の増減は呼び出し側（GameState）の責任にして、ここは効果の解決だけを持つ。
## 戦闘ロジックがランの持ち物を書き換え始めると、戦闘だけを切り出して
## 何千回も回すことができなくなる。
func use_item(actor: Battler, item_id: String, target: Battler) -> Array[String]:
	var it := Database.item(item_id)
	if it.is_empty():
		push_error("未定義の道具: %s" % item_id)
		return []

	var lines: Array[String] = []
	var who := target if target != null else actor
	lines.append("%sは %s を つかった！" % [actor.name, it.get("name", item_id)])

	var power := int(it.get("power", 0))
	match String(it.get("effect", "")):
		"heal_hp":
			if not who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				lines.append("%sの きずが %d かいふくした" % [who.name, who.heal(power)])
		"heal_mp":
			var before := who.mp
			who.mp = mini(who.mp + power, who.max_mp)
			lines.append("%sの まりょくが %d もどった" % [who.name, who.mp - before])
		"revive":
			if who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				who.hp = maxi(who.max_hp * power / 100, 1)
				lines.append("%sは いきを ふきかえした！" % who.name)
		"cleanse":
			if who.has_status():
				who.clear_status()
				lines.append("%sの ぐあいが よくなった" % who.name)
			else:
				lines.append("しかし　なにも おこらなかった")
		"heal_cleanse":
			if not who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				var healed := who.heal(power)
				var cured := who.has_status()
				who.clear_status()
				if healed > 0:
					lines.append("%sの きずが %d かいふくした" % [who.name, healed])
				if cured:
					lines.append("%sの ぐあいが よくなった" % who.name)
				if healed <= 0 and not cured:
					lines.append("しかし　なにも おこらなかった")
		"item_damage":
			lines.append_array(_use_damage_item(actor, who, it))
		"haste":
			if not who.is_alive():
				lines.append("しかし　なにも おこらなかった")
			else:
				who.agi_scale = 150
				who.agi_scale_turns = BUFF_TURNS
				lines.append("%sの　すばやさが あがった！" % who.name)
		_:
			lines.append("しかし　なにも おこらなかった")

	scheduler.consume(actor, actor.scaled_cost(int(it.get("cost", CtbScheduler.STANDARD_COST))))
	_check_finished()
	return lines


## 攻撃道具は使い手の能力に依存しない。
##
## 魔法職が弱い通常攻撃を補う、MPを温存して弱点だけ突く、という別の資源軸に
## するため。乱数は戦闘の DetRng だけを使い、同じシードの結果を保つ。
func _use_damage_item(actor: Battler, target: Battler, item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if target == null or not target.is_alive():
		lines.append("しかし　なにも おこらなかった")
		return lines

	var receiver := target
	if (
		target.protected_by != null
		and target.protected_by.is_alive()
		and target.protected_by != actor
	):
		receiver = target.protected_by
		lines.append("%sが　%sを かばった！" % [receiver.name, target.name])

	var damage := maxi(int(item.get("power", 0)), 1)
	var element := String(item.get("element", ""))
	if element in receiver.weak:
		damage = damage * ELEMENT_WEAK / 100
	elif element in receiver.resist:
		damage = damage * ELEMENT_RESIST / 100
	damage = damage * rng.range_i(VARIANCE_LOW, VARIANCE_HIGH) / 100
	if receiver.guarding:
		damage = damage / 2
	damage = maxi(damage, 1)
	receiver.apply_damage(damage)
	lines.append("%sに　%d の ダメージ！%s" % [
		receiver.name, damage, _element_tag(receiver, element)
	])
	if not receiver.is_alive():
		lines.append("%sを　たおした！" % receiver.name)
	return lines


# --------------------------------------------------------------------------
# 敵の行動（決定的な単純 AI）
# --------------------------------------------------------------------------


## 敵が次に使う技を決める。**技だけ**を先に決めて予告に出し、対象は実行時に選ぶ。
## 対象まで先に決めると、その相手が先に倒れていた場合に空振りになる。
##
## 等確率で引くと、深層の敵ほど的外れな手を打つ（範囲攻撃を 1 体に撃つ、
## 効いている状態異常を上塗りする）。重み付けで「それらしい」程度まで上げる。
## 賢くしすぎないこと。読めない敵は理不尽になる。
func _choose_enemy_ability(actor: Battler) -> String:
	var usable := usable_abilities(actor)
	if usable.is_empty():
		return "attack"

	# 最善だけを打たせない。
	#
	# 素点の最大だけを選ばせたら、自動操縦の勝率が 14% から 1% まで落ちた。
	# DQ4 の AI が「わざと最善を打たない」作りになっているのはこのためで、
	# 最善を打ち続ける相手は強いのではなく理不尽になる。
	# 上位の候補から引くことで、読める範囲の強さに収める。
	var scores := {}
	var best_score := 0
	for id in usable:
		var score := _enemy_score(actor, id)
		scores[id] = score
		best_score = maxi(best_score, score)

	var pool: Array[String] = []
	for id in usable:
		if int(scores[id]) * 100 >= best_score * ENEMY_PICK_RATIO:
			pool.append(id)
	return String(rng.pick(pool)) if not pool.is_empty() else "attack"


func _enemy_score(actor: Battler, ability_id: String) -> int:
	var ab := Database.ability(ability_id)
	var kind := String(ab.get("kind", "physical"))
	var scope := String(ab.get("target", "one_enemy"))
	var foes := living_allies()  # 敵から見た「相手」＝味方
	var score := 10

	match kind:
		"physical", "magical":
			# 時間あたりの効率で見る。CTB では 1 手あたりではなく時間あたりが効率。
			var power := int(ab.get("power", 0)) * maxi(int(ab.get("hits", 1)), 1)
			score = power * 100 / maxi(int(ab.get("cost", 100)), 1)
			# 範囲は相手が多いときだけ得。1 体に全体攻撃を撃たない。
			if scope in ["group_enemy", "all_enemies"]:
				score = score * mini(foes.size(), 3) / 2
			# 弱点を突けるなら上げる（属性を持たない技は素点のまま）
			var element := String(ab.get("element", ""))
			if element != "":
				var weak := 0
				for f in foes:
					if element in f.weak:
						weak += 1
				score += weak * 30
		"debuff":
			# 既に効いている相手に上塗りしない。全員に効いていれば選ばない。
			var fresh := 0
			for f in foes:
				match String(ab.get("effect", "")):
					"sleep":
						if f.sleep_turns <= 0:
							fresh += 1
					"slow":
						if f.agi_scale >= 100:
							fresh += 1
					_:
						fresh += 1
			score = 0 if fresh == 0 else 60 + fresh * 10
		"buff":
			# 自分にかけ直しても意味が薄い
			score = 20 if actor.agi_scale <= 100 else 0
		"heal":
			# 手負いのときだけ
			score = 90 if actor.hp * 2 < actor.max_hp else 0
	return maxi(score, 1)


## 敵の行動を実行する。LLM は一切関与させない。
## 行動決定は決定的でなければリプレイもバランス測定も成立しないため。
func perform_enemy(actor: Battler) -> Array[String]:
	var ability_id := actor.planned_ability
	if ability_id == "" or not actor.abilities.has(ability_id):
		ability_id = _choose_enemy_ability(actor)
	if not actor.can_pay(Database.ability(ability_id)):
		ability_id = "attack"

	var ab := Database.ability(ability_id)
	var target: Battler = null
	var scope := String(ab.get("target", "one_enemy"))
	if scope in ["one_enemy", "group_enemy"]:
		var pool := living_allies()
		if pool.is_empty():
			return []
		# 手負いの相手を狙いやすくする程度の、素朴だが読める AI。
		target = pool[0]
		for candidate in pool:
			if candidate.hp < target.hp and rng.chance(60):
				target = candidate
	elif scope == "one_ally":
		var friends := living_enemies()
		target = friends[0] if not friends.is_empty() else actor

	var lines := perform(actor, ability_id, target)
	# 次の手を決めて予告に載せる。
	actor.planned_ability = _choose_enemy_ability(actor)
	return lines


# --------------------------------------------------------------------------


func _check_finished() -> void:
	if is_over:
		return
	if scheduler.is_over():
		is_over = true
		finished.emit(scheduler.allies_won())


func victory() -> bool:
	return scheduler.allies_won()


## 勝利報酬。熟練度は戦闘 1 回ごとに入るので、
## 「深く潜るほど職業が育つ」が自然に成立する。
func rewards() -> Dictionary:
	return {
		"exp": Encounter.total_exp_at(enemies, floor_number),
		"gold": Encounter.total_gold_at(enemies, floor_number) + stolen_gold,
		"mastery": 4 + floor_number,
		"items": stolen_items,
	}
