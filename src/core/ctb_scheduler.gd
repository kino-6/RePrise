class_name CtbScheduler
extends RefCounted

## CTB（カウントタイムバトル）スケジューラ。
##
## 仮想時間軸上の優先度キューでしかない。「次に行動できる時刻 next_at が
## 最も早い者から動く」だけ。行動を終えたら、その行動のコストと自分の素早さから
## 決まる待ち時間だけ next_at が先に進む。
##
## 重要な性質が 2 つある。
##
## 1. 演算が整数だけで閉じている。実時間にも浮動小数にも依存しないので、
##    同じ入力からは必ず同じ行動順が出る（＝リプレイと自動テストが成立する）。
## 2. これは伝統的ローグライクのエナジー系スケジューラと同じもの。だから
##    フィールドの歩行ターンと戦闘のターンを、この 1 本で回せる。

## 待ち時間の分解能。大きいほど素早さ差が細かく効く。
const TICK := 10000

## 標準的な行動のコスト。これを基準に、重い技は高く軽い技は安く設定する。
const STANDARD_COST := 100

## next_at が育ちすぎないように全員から最小値を引く閾値。
const REBASE_THRESHOLD := 1 << 40

var _battlers: Array[Battler] = []


## 素早さ agi の者がコスト cost の行動を取ったときの待ち時間。
##
## 素早いほど短い。コストは MP に次ぐ第 2 のリソース軸で、
## 「強いが次の手番が遅れる技」をここで表現する。
@warning_ignore("integer_division")
static func wait_for(agi: int, cost: int) -> int:
	return (cost * TICK) / maxi(agi, 1)


func add(battler: Battler) -> void:
	# 初期待ち時間も素早さで決まるので、速い者が自然に先手を取る。
	battler.next_at = wait_for(battler.effective_agi(), STANDARD_COST)
	_battlers.append(battler)


func add_all(battlers: Array) -> void:
	for b in battlers:
		add(b)


func all() -> Array[Battler]:
	return _battlers


func living() -> Array[Battler]:
	return _battlers.filter(func(b: Battler) -> bool: return b.is_alive())


func living_allies() -> Array[Battler]:
	return living().filter(func(b: Battler) -> bool: return b.is_ally)


func living_enemies() -> Array[Battler]:
	return living().filter(func(b: Battler) -> bool: return not b.is_ally)


## 次に行動する者。同時刻なら id の小さい順で決める。
##
## このタイブレークが無いと、配列の並び順という「たまたま」で結果が変わり、
## 同一シードでも再現しなくなる。決定性の要。
func next_actor() -> Battler:
	var candidates := living()
	if candidates.is_empty():
		return null
	var best: Battler = candidates[0]
	for b in candidates:
		if b.next_at < best.next_at or (b.next_at == best.next_at and b.id < best.id):
			best = b
	return best


## 行動を消費して時間を進める。
func consume(battler: Battler, cost: int = STANDARD_COST) -> void:
	battler.next_at += wait_for(battler.effective_agi(), cost)
	_rebase_if_needed()


## これから count 手ぶんの行動順を先読みする。
##
## 実際のキューには一切触らず、複製した時刻だけを空回しする純粋な計算。
## 行動順バーの描画はこれを呼ぶだけでよい。
func preview(count: int) -> Array[Battler]:
	var sim: Array = []
	for b in living():
		sim.append({"battler": b, "at": b.next_at})

	var result: Array[Battler] = []
	if sim.is_empty():
		return result

	for _i in count:
		var best: Dictionary = sim[0]
		for e in sim:
			var earlier: bool = e["at"] < best["at"]
			var same_time_lower_id: bool = (
				e["at"] == best["at"] and e["battler"].id < best["battler"].id
			)
			if earlier or same_time_lower_id:
				best = e
		var b: Battler = best["battler"]
		result.append(b)
		# 次に何をするかは未定なので、標準コストで動くものとして先読みする。
		best["at"] = best["at"] + wait_for(b.effective_agi(), STANDARD_COST)
	return result


func remove(battler: Battler) -> void:
	_battlers.erase(battler)


func is_over() -> bool:
	return living_allies().is_empty() or living_enemies().is_empty()


func allies_won() -> bool:
	return living_enemies().is_empty() and not living_allies().is_empty()


## 長期戦で next_at が際限なく増えるのを防ぐ。差分だけが意味を持つので、
## 全員から一律に引いても行動順は一切変わらない。
func _rebase_if_needed() -> void:
	if _battlers.is_empty():
		return
	var lowest: int = _battlers[0].next_at
	for b in _battlers:
		lowest = mini(lowest, b.next_at)
	if lowest > REBASE_THRESHOLD:
		for b in _battlers:
			b.next_at -= lowest
