class_name Encounter
extends RefCounted

## 謨ｵ邱ｨ謌舌・邨・∩遶九※縲ゅ☆縺ｹ縺ｦ貂｡縺輔ｌ縺・RNG 縺九ｉ縺励°蠑輔°縺ｪ縺・・縺ｧ縲・
## 蜷後§繧ｷ繝ｼ繝峨・蜷後§髫主ｱ､繝ｻ蜷後§豁ｩ謨ｰ縺九ｉ縺ｯ蠢・★蜷後§謨ｵ縺悟・繧九・

const MAX_ENEMIES := 3

## --------------------------------------------------------------------------
## いつ敵が出るか。
##
## **この判定はここにしか置かない。** 元は ExploreView の中にあったが、
## シミュレータが同じ式を書き写すと、片方を直したときに黙ってずれる。
## 実際、旧 balance.gd は「1 階につき 4 戦」という書き写した模型を持っていて、
## 通るのに存在しない世界を測っていた。**測る側と遊ぶ側は同じ式を使う。**
## --------------------------------------------------------------------------

## この歩数までは絶対に敵が出ない（場面が切り替わった直後の事故防止）。
## 自動プレイで 150 秒回したら遊んだ時間の 54% が戦闘だったので広げた。
const MIN_SAFE_STEPS := 9


## 重み付き歩数から遭遇するかを決める。
##
## 確率は歩数の半分ずつ上がる。線形に上げると 10 歩そこそこで必ず出るようになり、
## 移動が戦闘の待ち時間になってしまう（実際そうなっていた）。
static func should_meet(rng: DetRng, weighted_steps: int) -> bool:
	if weighted_steps < MIN_SAFE_STEPS:
		return false
	@warning_ignore("integer_division")
	var odds := 3 + weighted_steps / 2
	return rng.chance(odds)

## 蜷悟錐縺御ｸｦ縺ｶ縺ｨ縺阪・隴伜挨蟄舌・Q 縺ｮ縲後せ繝ｩ繧､繝A / 繧ｹ繝ｩ繧､繝B縲阪→蜷後§菴懈ｳ輔・
const SUFFIX := ["・｡", "・｢", "・｣"]


static func build(rng: DetRng, floor_number: int, first_id: int = 100) -> Array[Battler]:
	var pool := Database.monster_ids_for_floor(floor_number)
	var result: Array[Battler] = []
	if pool.is_empty():
		return result

	var count := rng.range_i(1, mini(MAX_ENEMIES, 1 + floor_number / 2))
	var chosen: Array = []
	for _i in count:
		chosen.append(rng.pick(pool))

	# 蜷悟錐縺瑚､・焚縺・ｋ蝣ｴ蜷医□縺第磁蟆ｾ霎槭ｒ莉倥￠繧・
	var tally := {}
	for id in chosen:
		tally[id] = int(tally.get(id, 0)) + 1
	var seen := {}

	for i in chosen.size():
		var id: String = chosen[i]
		var index := int(seen.get(id, 0))
		seen[id] = index + 1
		var b := _to_battler(id, floor_number, first_id + i)
		if tally[id] > 1 and index < SUFFIX.size():
			b.name += SUFFIX[index]
		result.append(b)
	return result


## 荳ｻ縺ｮ髢薙・邱ｨ謌舌ゅ・繧ｹ 1 菴薙□縺代ｒ縲・嚴螻､陬懈ｭ｣縺ｪ縺励・邏縺ｮ蠑ｷ縺輔〒蜃ｺ縺吶・
##
## 騾壼ｸｸ謨ｵ縺ｯ髫主ｱ､縺ｧ邱壼ｽ｢縺ｫ蠑ｷ蛹悶＠縺ｦ縺・ｋ縺後√・繧ｹ縺ｯ縲後◎縺薙↓蠎ｧ縺｣縺ｦ縺・ｋ 1 菴薙阪↑縺ｮ縺ｧ
## 繝・・繧ｿ縺ｫ譖ｸ縺・◆謨ｰ蛟､縺後◎縺ｮ縺ｾ縺ｾ譛邨りｩｦ鬨薙・髮｣蠎ｦ縺ｫ縺ｪ繧九りｪｿ謨ｴ轤ｹ繧・1 縺区園縺ｫ菫昴▽縲・
static func build_boss(rng: DetRng, floor_number: int, first_id: int = 100) -> Array[Battler]:
	var pool := Database.boss_ids_for_floor(floor_number)
	var result: Array[Battler] = []
	if pool.is_empty():
		return result
	result.append(_to_battler(rng.pick(pool), 1, first_id))
	return result


@warning_ignore("integer_division")
static func _to_battler(monster_id: String, floor_number: int, battler_id: int) -> Battler:
	var m := Database.monster(monster_id)
	var b := Battler.new()
	b.id = battler_id
	b.name = String(m.get("name", monster_id))
	b.sprite = String(m.get("sprite", "gel"))
	b.source_id = monster_id
	b.is_ally = false

	# 豺ｱ縺・嚴縺ｻ縺ｩ蠑ｷ縺上☆繧九よｷｱ螻､縺ｧ縺ｯ譁ｰ縺励＞遞ｮ譌上ｂ蜃ｺ繧九・縺ｧ縲・嚴螻､陬懈ｭ｣縺ｾ縺ｧ 10% 蛻ｻ縺ｿ縺縺ｨ
	# 莠碁㍾縺ｫ蜉ｹ縺・※蜻ｳ譁ｹ縺ｮ謌宣聞縺瑚ｿｽ縺・▽縺九↑縺・ｼ域ｸｬ螳壹〒 200 繝ｩ繝ｳ蜈ｨ貊・＠縺滂ｼ峨・
	# 蛻晄悄陬・ｙ繧呈髪邨ｦ縺吶ｋ繧医≧縺ｫ縺励◆繧峨∽ｸｻ縺ｫ謖代ａ縺溘Λ繝ｳ縺・31% 縺九ｉ 66% 縺ｸ邱ｩ繧薙□
	# ・亥・蜩｡縺梧ｭｦ蝎ｨ縺ｨ骼ｧ繧呈戟縺｣縺ｦ 1 髫弱↓遶九▽縺ｮ縺ｧ縲・％荳ｭ縺ｮ蜑翫ｉ繧梧婿縺悟､峨ｏ繧具ｼ峨・
	# 髫主ｱ､陬懈ｭ｣繧・9%/髫・縺九ｉ 12%/髫・縺ｸ荳翫￡縺ｦ謌ｻ縺吶・
	var scale := stat_scale(floor_number)
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
	# 螻樊ｧ縺ｮ蠕玲焔荳榊ｾ玲焔縲ゅ％繧後′謨ｵ縺斐→縺ｫ驕輔≧縺九ｉ縲悟柑縺乗焔縲阪′螟峨ｏ繧九・
	b.weak.assign(m.get("weak", []))
	b.resist.assign(m.get("resist", []))
	return b


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
	return _sum_field(enemies, "exp") * reward_scale(floor_number) / 100


## ゴールドの合計（同上）。稼ぎが伸びないと出店が飾りになる。
static func total_gold_at(enemies: Array[Battler], floor_number: int) -> int:
	return _sum_field(enemies, "gold") * gold_scale(floor_number) / 100

