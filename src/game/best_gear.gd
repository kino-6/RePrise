class_name BestGear
extends RefCounted

## 「さいきょう装備」の割り当て（C-10）。
##
## 装備画面からも `AutoPlay` からも**同じここを呼ぶ**。別々に書くと、
## 自動プレイが人と違う装備で走り、測っている強さが遊べる強さとずれる。
##
## 守ること:
##
##   * **単純な能力合計にしない。** 重みは職業ごとに変える。僧侶に `いくさ斧`
##     を持たせても振れないし、戦士に `かしの杖` を渡しても意味が無い。
##   * **手持ち 1 個を複数人へ配らない。** 在庫は 1 つずつなので、
##     割り当てたら在庫から抜く。
##   * **乱数を使わない。** 同点は仲間の並び順 → 装備 id 順で決める。
##     `DetRng` すら引かない（装備の割り当てで乱数列を進めたくない）。
##   * **今より悪くなる付け替えはしない。** 空きスロットを埋めるか、
##     いま着けているものより点が高いときだけ替える。

## 能力ごとの重み。**職業の伸び（`growth`）から引く。**
##
## 15 職ぶんの表を手で持つと、職業を足したときに必ず片方だけ古くなる。
## 伸びはすでに「その職が何で戦うか」を表しているので、そこから引く。
##
##   物理 … `growth.atk`   魔法 … `growth.mp`（`magic_power()` が mp を見る）
##   耐久 … `growth.def`   速度 … `growth.agi`   体力 … `growth.hp`
##
## 倍率は、装備の実際の値幅を揃えるためのもの。武器の `atk` は 2〜11、
## 鎧の `def` は 5〜12、`hp` は 12 と桁が違うので、そのまま足すと
## `hp` が常に勝つ（実際 `guard_ring` が全職の最適解になっていた）。
const SCALE := {
	"atk": 1.0,
	"mag": 1.0,
	"def": 0.8,
	"agi": 0.9,
	"hp": 0.25,
	"mp": 0.20,
}

## 行動コストの重み。**負が良い**（軽い装備は次の手番が早い）。
##
## `cost_scale` は ±15 の幅で、能力値より桁が大きい。速さを伸ばす職ほど
## 重く見る（`いくさ斧` の +15 は、盗賊にとっては atk +11 を打ち消す）。
const COST_BASE := 0.20
const COST_PER_AGI := 0.10

## 特殊効果の点。**能力値では表せないものに下駄を履かせる。**
## `ぬすむ` が伸びる手袋は、素の agi +2 だけ見ると誰も選ばない。
const EFFECT_BONUS := 3.0


## その者にとってのその装備の点。**高いほど良い。**
static func score(member: PartyMember, gear_id: String) -> float:
	var gear := Database.gear(gear_id)
	if gear.is_empty() or not member.can_equip(gear_id):
		return -INF
	var growth: Dictionary = Database.job(member.job_id).get("growth", {})
	var total := 0.0
	total += float(gear.get("atk", 0)) * float(growth.get("atk", 0)) * SCALE["atk"]
	total += float(gear.get("mag", 0)) * float(growth.get("mp", 0)) * SCALE["mag"]
	total += float(gear.get("def", 0)) * float(growth.get("def", 0)) * SCALE["def"]
	total += float(gear.get("agi", 0)) * float(growth.get("agi", 0)) * SCALE["agi"]
	total += float(gear.get("hp", 0)) * float(growth.get("hp", 0)) * SCALE["hp"]
	total += float(gear.get("mp", 0)) * float(growth.get("mp", 0)) * SCALE["mp"]
	# 行動コストは負が良い。速さを伸ばす職ほど重く見る。
	var cost_weight := COST_BASE + float(growth.get("agi", 0)) * COST_PER_AGI
	total -= float(gear.get("cost_scale", 0)) * cost_weight
	if String(gear.get("effect", "")) != "":
		total += EFFECT_BONUS
	return total


## 全員へ配る。**在庫を直に触らず、決めた組だけ返す。**
##
## 返るのは `[{ "member": 仲間の番号, "gear": 装備 id }, ...]`。
## 呼ぶ側が `GameState.equip_gear()` を通すので、外れた装備の戻しは
## 既存の一本道に乗る（ここで在庫を触ると二重管理になる）。
##
## `stock` はその時点の手持ち。**同じ id が 2 つあれば 2 人に配れる。**
static func plan(members: Array, stock: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# 在庫は id 順に固定する。同点のときの取り合いを並び順で決めるため。
	var pool: Array[String] = []
	for id in stock:
		pool.append(String(id))
	pool.sort()

	# **仲間の並び順が優先度。** 先頭から順に、その人にとっての最善を取る。
	# 全体最適ではないが、乱数を使わず、結果が読めて、説明できる。
	for index in members.size():
		var member: PartyMember = members[index]
		for slot in ["weapon", "armor", "accessory"]:
			var current := String(member.equipment.get(slot, ""))
			var have := score(member, current) if current != "" else 0.0
			var best := ""
			var best_score := have
			for id in pool:
				if String(Database.gear(id).get("slot", "")) != slot:
					continue
				if not member.can_equip(id):
					continue
				var value := score(member, id)
				# **同点では替えない。** 見た目が動くだけで強さが変わらない。
				if value > best_score:
					best = id
					best_score = value
			if best == "":
				continue
			out.append({"member": index, "gear": best})
			pool.erase(best)   # 1 個を 2 人へ配らない
	return out


## 実際に着せる。着せ替えた数を返す。
##
## `GameState` はオートロードで `--headless --script` から触れないので、
## 状態を持たないここに置き、状態は呼ぶ側から渡してもらう。
static func apply(state, members: Array) -> int:
	var moves := plan(members, state.gear_stock)
	var done := 0
	for move in moves:
		if state.equip_gear(members[int(move["member"])], String(move["gear"])):
			done += 1
	return done
