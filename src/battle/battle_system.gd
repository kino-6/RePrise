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

## 直近の行動でダメージを受けた者の id と量。演出（点滅と数字）に使う。
## 表示側がログの文字列を読んで判断すると、文言を変えた瞬間に演出が消える。
var last_hit_ids: Array[int] = []
var last_hit_amount: Dictionary = {}


func start(party: Array[Battler], foes: Array[Battler], run_rng: DetRng, floor_no: int = 1) -> void:
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
	scheduler = CtbScheduler.new()
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

	if actor.sleep_turns > 0:
		actor.sleep_turns -= 1
		lines.append("%sは　ねむっている…" % actor.name)
		skipped = true
		# 眠っているぶん、次の手番も後ろへ回る。
		scheduler.consume(actor, CtbScheduler.STANDARD_COST)

	return {"lines": lines, "skipped": skipped}


func turn_order(count: int = 8) -> Array[Battler]:
	return scheduler.preview(count)


## その者が今使える技（MP 不足のものは除く）。
func usable_abilities(actor: Battler) -> Array[String]:
	var result: Array[String] = []
	for id in actor.abilities:
		if actor.can_pay(Database.ability(id)):
			result.append(id)
	return result


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
	var ab := Database.ability(ability_id)
	if ab.is_empty():
		push_error("未定義のアビリティ: %s" % ability_id)
		return []

	last_ability_id = ability_id
	last_hit_ids.clear()
	last_hit_amount.clear()
	var lines: Array[String] = []
	actor.mp = maxi(actor.mp - int(ab.get("mp", 0)), 0)
	lines.append("%sの　%s！" % [actor.name, ab.get("name", ability_id)])

	var targets := _resolve_targets(actor, ab, target)
	var kind := String(ab.get("kind", "physical"))
	var power := int(ab.get("power", 0))

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

	# 行動コスト x 職業のテンポ倍率のぶんだけ、この者の次の手番が先に進む。
	scheduler.consume(actor, actor.scaled_cost(int(ab.get("cost", CtbScheduler.STANDARD_COST))))

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
		for _i in hits:
			if not receiver.is_alive():
				break
			var dmg := _damage(actor, receiver, power * spread / 100, magical, element)
			receiver.apply_damage(dmg)
			total += dmg
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

		if not receiver.is_alive():
			lines.append("%sを　たおした！" % receiver.name)

	# 攻めながら味方も癒す技（賢者の一撃）。攻撃と回復を 1 手で兼ねるので、
	# 手番の価値がいちばん高い。そのぶんコストと MP は重くしてある。
	if String(ab.get("effect", "")) == "mend":
		var mend := actor.mag / 2 + 12
		for friend in (living_allies() if actor.is_ally else living_enemies()):
			var healed := friend.heal(mend)
			if healed > 0:
				lines.append("%sの　きずが %d かいふくした" % [friend.name, healed])
	return lines


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
		elif element in target.resist:
			dmg = dmg * ELEMENT_RESIST / 100
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
				lines.append_array(_play_around(actor, t))
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
