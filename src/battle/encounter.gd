class_name Encounter
extends RefCounted

## 敵編成の組み立て。乱数は渡された RNG からしか引かないので、
## 同じシード・同じ危険度・同じ歩数からは必ず同じ敵が出る。
##
## **このファイルは一度、文字化けした符号で保存されていた。**
## 同名の敵に付ける接尾辞（Ａ/Ｂ/Ｃ）がそのまま画面に出て崩れていた。
## 日本語を含むファイルは UTF-8 で保存すること（BOM は付けない）。


## 1 戦に出る敵の最大数。
##
## **もとは 3 で、理由は書かれていなかった**（初期に置いてそのまま見直していない）。
## SFC 期の JRPG は 6〜8 体を並べていたので、3 は狭すぎた。範囲技と単体技の
## 選び分けが「2 体か 3 体か」でしか起きず、群れと戦っている感じが出ない。
##
## 6 へ上げるために、3 に縛られていた 3 つを外した。
##   * 接尾辞が Ａ/Ｂ/Ｃ の 3 つしかなかった（4 体目が無名になる）
##   * 範囲技の減衰表が 1〜3 しか無く、4 体以上が減衰なしで得だった
##   * 戦闘画面が 1 列に等間隔で並べるだけで、5 体以上は重なった
const MAX_ENEMIES := 6

## --------------------------------------------------------------------------
## いつ敵が出るか。
##
## **この判定はここにしか置かない。** 元は ExploreView の中にあったが、
## シミュレータが同じ式を書き写すと、片方を直したときに黙ってずれる。
## 実際、旧 balance.gd は「1 階につき 4 戦」という書き写した模型を持っていて、
## 通るのに存在しない世界を測っていた。**測る側と遊ぶ側は同じ式を使う。**
## --------------------------------------------------------------------------

## 戦闘後に必ず歩ける実歩数。地形の重みやイベント補正では短縮されない。
##
## 森は1歩を重み3で数えるため、重みだけの安全期間では3歩で次の戦闘が起こり得た。
## 「戦闘が終わったのにほとんど進めない」体感を確実に消すため、別軸で守る。
## 6歩を歩き切るまでは無抽選、7歩目から抽選する。
const MIN_ENCOUNTER_GAP_STEPS := 6

## この重みまでは絶対に敵が出ない（場面が切り替わった直後の事故防止）。
## 自動プレイで 150 秒回したら遊んだ時間の 54% が戦闘だったので広げた。
const MIN_SAFE_STEPS := 9


## 実歩数と重み付き歩数から遭遇するかを決める。
##
## 確率は歩数の半分ずつ上がる。線形に上げると 10 歩そこそこで必ず出るようになり、
## 移動が戦闘の待ち時間になってしまう（実際そうなっていた）。
static func should_meet(
	rng: DetRng, walked_steps: int, weighted_steps: int, event_bias: int = 0
) -> bool:
	if walked_steps <= MIN_ENCOUNTER_GAP_STEPS:
		return false
	if weighted_steps < MIN_SAFE_STEPS:
		return false
	@warning_ignore("integer_division")
	var odds := clampi(3 + weighted_steps / 2 + event_bias * 5, 0, 90)
	return rng.chance(odds)

const SUFFIX := ["Ａ", "Ｂ", "Ｃ", "Ｄ", "Ｅ", "Ｆ"]


static func build(
	rng: DetRng, floor_number: int, first_id: int = 100, biome: String = ""
) -> Array[Battler]:
	var pool := Database.monster_ids_for_floor(floor_number, biome)
	var result: Array[Battler] = []
	if pool.is_empty():
		return result

	# 危険度が上がるほど数も増える。ただし 1 体だけの回も残す
	# （群れしか出ないと、単体技を選ぶ理由が消える）。
	var count := rng.range_i(1, mini(MAX_ENEMIES, 1 + floor_number * 2 / 3))
	var chosen: Array = []
	for _i in count:
		chosen.append(rng.pick(pool))

	var tally := {}
	for id in chosen:
		tally[id] = int(tally.get(id, 0)) + 1
	var seen := {}

	for i in chosen.size():
		var id: String = chosen[i]
		var index := int(seen.get(id, 0))
		seen[id] = index + 1
		var b := _to_battler(id, floor_number, first_id + i, chosen.size())
		if tally[id] > 1 and index < SUFFIX.size():
			b.name += SUFFIX[index]
		result.append(b)
	return result


## イベントで「手強い戦い」と明示された編成。
## 通常遭遇をそのまま出すと選択肢の危険表示が嘘になるため、能力を25%上げる。
static func build_elite(
	rng: DetRng, floor_number: int, first_id: int = 100, biome: String = ""
) -> Array[Battler]:
	var result := build(rng, floor_number, first_id, biome)
	for foe in result:
		foe.name = "強敵 %s" % foe.name
		foe.max_hp = maxi(foe.max_hp * 125 / 100, 1)
		foe.hp = foe.max_hp
		foe.atk = maxi(foe.atk * 125 / 100, 1)
		foe.mag = maxi(foe.mag * 125 / 100, 1)
		foe.defense = maxi(foe.defense * 125 / 100, 1)
	return result


##
## 城の主が動く速さ（百分率）。**小さいほど速く、何度も動く。**
##
## ここを入れるまで、主は関門になっていなかった ―― Lv14 の万全な party は
## 7 体の主すべてに **100% 勝っていた**（`--boss=140` の実測）。
##
## 原因は数値ではなく**行動回数**だった。1 対 4 なので、23 手番の戦いで主が
## 動けるのは 4 回ほど。しかもデータ側の `cost_scale` は 115〜160 と、
## 標準（100）より**遅い**。山場のはずの相手が、いちばん動けない相手だった。
##
## HP や攻撃力を盛る手もあるが、それは「硬いだけの壁」になる。
## **動く回数で釣り合わせる**ほうが、CTB の土俵の上で戦いになる。
## 主ごとの差（重い機械は遅い、託宣は速い）は割合として残る。
const BOSS_COST_PERCENT := 59

## 主の能力の倍率と、速さの下限。**数字はすべて実測で決める**
## （`tests/balance.gd -- --boss=200` が主戦だけを取り出して測る）。
const BOSS_STAT_PERCENT := 122
const BOSS_AGI_FLOOR := 27


static func build_boss(rng: DetRng, floor_number: int, first_id: int = 100) -> Array[Battler]:
	var pool := Database.boss_ids_for_floor(floor_number)
	var result: Array[Battler] = []
	if pool.is_empty():
		return result
	var boss := _to_battler(rng.pick(pool), 1, first_id)
	# **主は階層補正を受けない**（`_to_battler` へ 1 を渡している）。
	# 生の数値が終点用に書かれているからだが、party 側は装備と Lv で伸びるので、
	# 相対的に主だけが取り残されていた。ここで 1 か所だけ倍率を掛ける
	# ―― 7 体それぞれの持ち味（重い機械は硬い、託宣は速い）は割合として残る。
	boss.max_hp = maxi(boss.max_hp * BOSS_STAT_PERCENT / 100, 1)
	boss.hp = boss.max_hp
	boss.atk = maxi(boss.atk * BOSS_STAT_PERCENT / 100, 1)
	boss.mag = boss.atk
	boss.defense = maxi(boss.defense * BOSS_STAT_PERCENT / 100, 1)
	# **場でいちばん鈍い駒にしない。** 生の agi は 9〜18 で、Lv14 の party
	# （22〜78）より遅い。山場の相手が最も動けないのは筋が通らない。
	boss.agi = maxi(boss.agi, BOSS_AGI_FLOOR)
	boss.cost_scale = maxi(boss.cost_scale * BOSS_COST_PERCENT / 100, 20)
	result.append(boss)
	return result


## 封の番人。**城の主とは別格。**
##
## 洞の底に封を置いたのに守るものが居ないのは不自然だった。ただし城の主と
## 同じ扱いにすると、寄り道が本筋と同じ重さになって「寄るか急ぐか」が消える。
## そこで**通常の敵を 1 体だけ、はっきり強くして**置く（群れの割り引きを掛けず、
## 危険度を 2 上げる）。1 体なので範囲技が効かず、単体技の出番になる。
static func build_guardian(rng: DetRng, floor_number: int, biome: String = "") -> Array[Battler]:
	var pool := Database.monster_ids_for_floor(mini(floor_number + 2, WorldMap.MAX_DANGER), biome)
	if pool.is_empty():
		pool = Database.monster_ids_for_floor(floor_number, "")
	var result: Array[Battler] = []
	if pool.is_empty():
		return result
	var b := _to_battler(String(rng.pick(pool)), mini(floor_number + 2, WorldMap.MAX_DANGER), 100, 1)
	b.name = "封の番人 %s" % b.name
	result.append(b)
	return result


@warning_ignore("integer_division")
static func _to_battler(
	monster_id: String, floor_number: int, battler_id: int, pack: int = 1
) -> Battler:
	var m := Database.monster(monster_id)
	var b := Battler.new()
	b.id = battler_id
	b.name = String(m.get("name", monster_id))
	b.sprite = String(m.get("sprite", "gel"))
	b.source_id = monster_id
	b.is_ally = false

	# 階層補正めE9%/隁Eから 12%/隁Eへ上げて戻す、E
	# 危険度の倍率に、群れの大きさによる割り引きを掛ける。
	var scale := stat_scale(floor_number) * pack_scale(pack) / 100
	b.max_hp = maxi(int(m.get("hp", 10)) * scale / 100, 1)
	b.hp = b.max_hp
	b.max_mp = int(m.get("mp", 0))
	b.mp = b.max_mp
	b.atk = maxi(int(m.get("atk", 1)) * scale / 100, 1)
	b.mag = b.atk
	b.defense = maxi(int(m.get("def", 1)) * scale / 100, 1)
	b.agi = int(m.get("agi", 10))
	b.cost_scale = int(m.get("cost_scale", 100))

	var raw: Array = m.get("abilities", ["attack"])
	b.abilities.assign(raw)
	# 属性の得手不得手。これが敵ごとに違うから「効く手」が変わる、E
	b.weak.assign(m.get("weak", []))
	b.resist.assign(m.get("resist", []))
	return b


## 群れの大きさによる 1 体あたりの倍率（百分率）。
##
## **数だけ増やして強さを据え置くと成立しない。** 上限を 3 → 6 にした直後、
## シミュレータで全方針 0% になった（6 体が横並びで殴ってくるので当然）。
##
## 群れで出るものは 1 体ずつ弱い、というのが往年の作法。ここを式にすると、
## 「1 体の強敵」と「6 体の群れ」が別の脅威になり、範囲技と単体技の
## 選び分けが初めて意味を持つ。総量は count を掛けて 100 → 171% と緩く上がる。
##   1 体 100% / 2 体 67% / 3 体 50% / 4 体 40% / 5 体 33% / 6 体 29%
## 1 体増えるごとに引く割合（百分率）。**実測で決めた**（tests/balance.gd）。
##   割り引き 0  … 全方針 0%。6 体が横並びで殴るので成立しない
##   割り引き 5  … 封 6% / 全周 14%
##   割り引き 8  … 封 18% / 全周 32%。**採用**
##   200/(n+1)   … 封 88% / 全周 94%。自動操縦で素通りになる
## 直行が 0% であることは全通りで保たれている（封の門が効いている）。
const PACK_DISCOUNT := 8


static func pack_scale(count: int) -> int:
	return maxi(100 - (maxi(count, 1) - 1) * PACK_DISCOUNT, 40)


## 危険度による能力値の倍率（百分率）。報酬もこれを土台にする。
@warning_ignore("integer_division")
static func stat_scale(floor_number: int) -> int:
	return 100 + (floor_number - 1) * 11 + (floor_number - 1) * (floor_number - 1) / 14


static func total_exp(enemies: Array[Battler]) -> int:
	return _sum_field(enemies, "exp")


static func total_gold(enemies: Array[Battler]) -> int:
	return _sum_field(enemies, "gold")


## 経験値とゴールドも危険度で伸ばす。
##
## **ここを伸ばさないと世界が成立しない。**
## 地下 10 階の潜行だったころは 1 階につき 4 戦あり、階が深まるほど
## 高い経験値の種族に入れ替わることで自然に追いついていた。
## ワールドでは危険度が「距離」で上がるので、危険度 +1 あたり 0.8 戦しかない。
## 実測では危険度 5 で Lv 3.3、つまり必要量の 1/5 しか稼げず全滅していた。
##
## そこで**能力値と同じ倍率**を経験値にも掛ける。2.2 倍強い敵は 2.2 倍の
## 経験をくれる、という素直な形にしておけば、洞（同じ危険度）でも矛盾しない。
## 掲げる不変条件は「その土地の危険度に見合うレベルは、そこまで歩いて
## 戦えば自然に届く」。倍率をここ以外に散らさないこと。
static func reward_scale(floor_number: int) -> int:
	return stat_scale(floor_number) * EXP_GAIN / 100


## ゴールドは経験値ほど伸ばさない。
##
## 同じ倍率にしたら城に着く頃に 4500 ゴールド持っていた（品物は 36〜186）。
## **経験値とゴールドは役目が違う。** 経験値は「その土地に見合う強さ」を
## 追いつかせるためのもので、伸ばさないと世界が成立しない。
## ゴールドは買い物の判断を作るためのもので、伸ばしすぎると
## 全部買えてしまって選ぶ意味が消える。だから別の数字にする。
static func gold_scale(floor_number: int) -> int:
	return stat_scale(floor_number) * GOLD_GAIN / 100


## ゴールドの伸び（百分率）。能力値と同じ伸びにしてある。
const GOLD_GAIN := 100


## 経験値の伸び（百分率）。100 なら能力値と同じ伸び。
##
## 実測で決めた（tests/balance.gd で 140 / 180 / 260 を挟み込み）。
##   140 … 全周しても 8%% しか勝てない。辛すぎる
##   180 … 直行 0%% / 寄り道 5%% / 全周 25%%。**採用**
##   260 … 全周 70%%。自動操縦でこれだけ勝てると人が操作して素通りになる
## 直行が 0%% であることが大事で、「急げば着くが勝てない」が判断を作る。
const EXP_GAIN := 180


static func _sum_field(enemies: Array[Battler], field: String) -> int:
	var total := 0
	for b in enemies:
		total += int(Database.monster(b.source_id).get(field, 0))
	return total


## 経験値の合計（危険度で伸ばしたもの）。
static func total_exp_at(enemies: Array[Battler], floor_number: int) -> int:
	# 群れは 1 体あたりの経験も割り引く（弱いものを数で狩るのが得になりすぎない）。
	return _sum_field(enemies, "exp") * reward_scale(floor_number) 		* pack_scale(enemies.size()) / 10000


## ゴールドの合計（同上）。稼ぎが伸びないと出店が飾りになる。
static func total_gold_at(enemies: Array[Battler], floor_number: int) -> int:
	return _sum_field(enemies, "gold") * gold_scale(floor_number) 		* pack_scale(enemies.size()) / 10000

