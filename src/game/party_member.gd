class_name PartyMember
extends RefCounted

## パーティ 1 人分。ランをまたいで残るものと、ランで失うものを 1 か所で管理する。
##
##   失う  : level / hp / mp / 装備      … ランごとに 1 からやり直す
##   残る  : job_exp / learned / 解放職業 … 死んでも持ち帰る
##
## DQ6 のダーマ神殿がそのままローグライクのメタ進行になる、という設計。
## 「レベルは 1 に戻るが、あの職業の熟練度は 3 上がった」が毎ランの手応えになる。

const BASE_ABILITIES: Array[String] = ["attack", "guard"]

var name: String = ""
var job_id: String = ""

# --- ランごとに失われるもの ---
## 毒の残り歩数。戦闘が終わっても消えない。
##
## 消耗戦（HP と MP を持ち越す）という前提と噛み合う。道中で毒を受けたら、
## 道具を使うか、削られながら出店まで急ぐかの判断が生まれる。
var poison_steps: int = 0
var level: int = 1
var exp_points: int = 0
var hp: int = 0
var mp: int = 0

# --- 持ち帰るもの ---
var job_exp: Dictionary = {}  # job_id -> 熟練度ポイント
var learned: Array[String] = []  # 習得済みアビリティ（転職しても消えない）

## 装備（slot -> equipment.json の ID）。ゴールドと同じくラン内資源で、
## 全滅すると失う。恒久強化が能力値に触れないという不変条件を守るため、
## ここを持ち帰らせてはいけない。
var equipment: Dictionary = {}


static func create(member_name: String, starting_job: String) -> PartyMember:
	var m := PartyMember.new()
	m.name = member_name
	m.job_id = starting_job
	m.reset_for_run()
	return m


# --------------------------------------------------------------------------
# 能力値: 職業の成長率 x レベル
# --------------------------------------------------------------------------


func _growth(stat: String) -> int:
	var g: Dictionary = Database.job(job_id).get("growth", {})
	return int(g.get(stat, 0))


## 装備の合計補正。装備していないスロットは 0。
func gear_bonus(stat: String) -> int:
	var total := 0
	for slot in equipment.keys():
		total += int(Database.gear(String(equipment[slot])).get(stat, 0))
	return total


## 装備由来の特殊効果（ぬすむ の成功率など）。
func gear_effects() -> Array[String]:
	var result: Array[String] = []
	for slot in equipment.keys():
		var e := String(Database.gear(String(equipment[slot])).get("effect", ""))
		if e != "" and e not in result:
			result.append(e)
	return result


## 通常攻撃に乗る属性。武器が持っていれば、それがそのまま乗る。
func attack_element() -> String:
	return String(Database.gear(String(equipment.get("weapon", ""))).get("element", ""))


## 装備する。同じスロットの先客は外れて戻り値で返る（空なら ""）。
func equip(gear_id: String) -> String:
	var slot := String(Database.gear(gear_id).get("slot", ""))
	if slot == "":
		return ""
	var previous := String(equipment.get(slot, ""))
	equipment[slot] = gear_id
	return previous


func unequip(slot: String) -> String:
	var previous := String(equipment.get(slot, ""))
	equipment.erase(slot)
	return previous


func max_hp() -> int:
	return maxi(18 + _growth("hp") * level + gear_bonus("hp"), 1)


func max_mp() -> int:
	return maxi(4 + _growth("mp") * level + gear_bonus("mp"), 0)


func attack_power() -> int:
	return maxi(5 + _growth("atk") * level + gear_bonus("atk"), 1)


## 魔力は MP 成長率に連動させる。魔法職ほど魔法が伸びる、という素直な設計。
func magic_power() -> int:
	return maxi(4 + _growth("mp") * level + gear_bonus("mag"), 1)


func defense_power() -> int:
	return maxi(4 + _growth("def") * level + gear_bonus("def"), 0)


func agility() -> int:
	return maxi(8 + _growth("agi") * level + gear_bonus("agi"), 1)


## 職業ごとの行動コスト倍率。とうぞくは安く、まほうつかいは重い。
## 行動コスト倍率。重い武器を持つほど次の手番が遅れる。
func cost_scale() -> int:
	return maxi(int(Database.job(job_id).get("cost_scale", 100)) + gear_bonus("cost_scale"), 30)


func available_abilities() -> Array[String]:
	var result: Array[String] = []
	result.append_array(BASE_ABILITIES)
	for a in learned:
		if a not in result:
			result.append(a)
	return result


# --------------------------------------------------------------------------
# 熟練度
# --------------------------------------------------------------------------


func mastery_points(id: String = "") -> int:
	return int(job_exp.get(id if id != "" else job_id, 0))


## 現在の熟練度ランク（0 = 未熟）。
func mastery_rank(id: String = "") -> int:
	var target := id if id != "" else job_id
	var points := mastery_points(target)
	var rank := 0
	for entry in Database.job(target).get("mastery", []):
		if points >= int(entry.get("need", 0)):
			rank = maxi(rank, int(entry.get("rank", 0)))
	return rank


## 次のランクまでに必要な残りポイント。最大まで行っていたら 0。
func mastery_to_next(id: String = "") -> int:
	var target := id if id != "" else job_id
	var points := mastery_points(target)
	for entry in Database.job(target).get("mastery", []):
		var need := int(entry.get("need", 0))
		if points < need:
			return need - points
	return 0


## 熟練度を加算し、新たに覚えたアビリティ ID を返す。
##
## 戻り値をそのまま「〇〇を おぼえた！」の演出に流せる。
func gain_mastery(points: int) -> Array[String]:
	var before := mastery_rank()
	job_exp[job_id] = mastery_points() + maxi(points, 0)
	var after := mastery_rank()
	var newly: Array[String] = []
	if after > before:
		for entry in Database.job(job_id).get("mastery", []):
			var rank := int(entry.get("rank", 0))
			if rank > before and rank <= after:
				var ability_id := String(entry.get("ability", ""))
				if ability_id != "" and ability_id not in learned:
					learned.append(ability_id)
					newly.append(ability_id)
	return newly


# --------------------------------------------------------------------------


## 次のレベルまでに必要な経験値。
##
## 10 階 x 4 戦の 40 戦で最終階に見合うレベルへ届く必要がある。
## 係数はヘッドレス測定（tests/balance.gd）に合わせて決めたもので、
## 勘で触ると到達率が一気に崩れる。
func exp_to_next() -> int:
	return 6 * level * level + 10 * level


## 経験値を加算し、上がったレベル数を返す。
## 増えた最大値のぶんだけ現在値も足す（レベルアップで実質回復する）。
func gain_exp(amount: int) -> int:
	exp_points += maxi(amount, 0)
	var gained := 0
	while exp_points >= exp_to_next():
		exp_points -= exp_to_next()
		var hp_before := max_hp()
		var mp_before := max_mp()
		level += 1
		hp += max_hp() - hp_before
		mp += max_mp() - mp_before
		gained += 1
	return gained


## その職業に就けるか。上級職は本人が解放条件を満たしている必要がある。
##
## 「誰かが極めたから全員が就ける」にはしない。そうすると 1 人を育てるだけで
## 済んでしまい、4 人それぞれの経歴という手応えが消える。
func can_take_job(target_job: String) -> bool:
	var job := Database.job(target_job)
	if job.is_empty():
		return false
	for required_job in job.get("unlock", {}).keys():
		var need := int(job["unlock"][required_job])
		if mastery_rank(String(required_job)) < need:
			return false
	return true


## まだ就けない職業の、残っている条件。拠点で「あと何が要るか」を出すのに使う。
func unmet_requirements(target_job: String) -> Array[String]:
	var missing: Array[String] = []
	var job := Database.job(target_job)
	for required_job in job.get("unlock", {}).keys():
		var need := int(job["unlock"][required_job])
		var have := mastery_rank(String(required_job))
		if have < need:
			var label: String = Database.job(String(required_job)).get("name", required_job)
			missing.append("%s ★%d" % [label, need])
	return missing


## 転職。熟練度は職業ごとに別勘定で貯まり、覚えた技は職業に紐付かないので、
## ここでやることは「現在職を差し替えて能力値を計算し直す」だけでよい。
##
## 失うのはレベルだけ、というダーマ神殿の扱いをそのまま採用している。
## ラン中は呼ばない前提（拠点でのみ転職できる）。
func change_job(new_job: String) -> bool:
	if new_job == job_id or not Database.all_jobs().has(new_job):
		return false
	if not can_take_job(new_job):
		return false
	job_id = new_job
	reset_for_run()
	return true


func reset_for_run() -> void:
	level = 1
	exp_points = 0
	poison_steps = 0
	# 装備はラン内資源。全滅すれば裸から出直す。
	equipment.clear()
	hp = max_hp()
	mp = max_mp()


func to_battler(battler_id: int) -> Battler:
	var b := Battler.new()
	b.id = battler_id
	b.name = name
	b.is_ally = true
	b.sprite = "hero"
	b.job_id = job_id
	b.max_hp = max_hp()
	b.hp = clampi(hp, 0, b.max_hp)
	b.max_mp = max_mp()
	b.mp = clampi(mp, 0, b.max_mp)
	b.atk = attack_power()
	b.mag = magic_power()
	b.defense = defense_power()
	b.agi = agility()
	b.cost_scale = cost_scale()
	b.abilities = available_abilities()
	b.attack_element = attack_element()
	b.effects = gear_effects()
	# 道中で受けた毒は戦闘にも持ち込む（休めば治る、では消耗戦にならない）。
	if poison_steps > 0:
		b.poison_turns = BattleSystem.POISON_TURNS
	return b


## 毒が抜けるまでの歩数。深いところで受けるほど長く効く。
const POISON_STEPS := 60


## 戦闘後、Battler 側の残 HP/MP と毒を本体へ書き戻す。
func sync_from_battler(b: Battler) -> void:
	hp = b.hp
	mp = b.mp
	# 戦闘の終わりに毒が消えると、状態異常が「その戦闘だけの飾り」になる。
	if b.poison_turns > 0:
		poison_steps = maxi(poison_steps, POISON_STEPS)
	if hp <= 0:
		poison_steps = 0  # 倒れている者は毒で減らない


## 歩いたときの毒の進行。減った量を返す（0 なら何も起きていない）。
##
## **毒では死なせない。** HP 1 で止める。歩いているだけで全滅すると、
## プレイヤーに打つ手が無いまま終わってしまう。
func step_poison() -> int:
	if poison_steps <= 0 or hp <= 1:
		return 0
	poison_steps -= 1
	var damage := maxi(max_hp() / 40, 1)
	var before := hp
	hp = maxi(hp - damage, 1)
	return before - hp


func cure_poison() -> bool:
	if poison_steps <= 0:
		return false
	poison_steps = 0
	return true


func to_dict() -> Dictionary:
	return {
		"name": name,
		"job_id": job_id,
		"job_exp": job_exp,
		"learned": learned,
	}


## ラン中の状態（中断のときだけ書き出す）。
##
## `to_dict()` は**恒久データ専用**なので分けてある。混ぜると、拠点のセーブに
## ラン中の HP が混ざり込む（境界を 1 か所に集める、という決めごとが崩れる）。
func to_run_dict() -> Dictionary:
	return {
		"level": level,
		"exp": exp_points,
		"hp": hp,
		"mp": mp,
		"equipment": equipment.duplicate(),
		"poison": poison_steps,
	}


func load_run_dict(d: Dictionary) -> void:
	level = maxi(int(d.get("level", 1)), 1)
	exp_points = int(d.get("exp", 0))
	equipment = d.get("equipment", {}).duplicate()
	poison_steps = int(d.get("poison", 0))
	# HP と MP は最大値を出したあとに入れる（装備で最大値が変わる）。
	hp = clampi(int(d.get("hp", max_hp())), 0, max_hp())
	mp = clampi(int(d.get("mp", max_mp())), 0, max_mp())


static func from_dict(d: Dictionary) -> PartyMember:
	var m := PartyMember.new()
	m.name = String(d.get("name", ""))
	m.job_id = String(d.get("job_id", ""))
	m.job_exp = d.get("job_exp", {})
	var raw: Array = d.get("learned", [])
	m.learned.assign(raw)
	m.reset_for_run()
	return m
