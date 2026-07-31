class_name InheritSign
extends RefCounted

## 継承印の選び方（E-2）。**判断はここ、状態は `GameState`。**
##
## `GameState` はオートロードなので `--headless --script` から触れない。
## テストから確かめたい規則は**静的クラスへ出す**（`CrossWorldArc` と同じ形）。
##
## 設計は `docs/progression_reward_design.md`。守っている決めごと:
##
##   * **恒久能力値の加算をしない。** それをやると「上げた人が強い」だけになり、
##     ラン中の判断が増えない。この作品が避けている形。
##   * **全印の常時発動もしない。** 15 職ぶん解放しても、持ち込めるのは
##     基本 1 枠・最大 2 枠。**どれを持つかが判断**になる。
##   * ★6 は構成が開く節目、★8 は職業マスター。役割を分ける。

## 2 枠目が開く `継承印の枠` の値。**1 段で開く。**
##
## 3 段だった頃は 1〜2 段目が何も増やしていなかった（枠は 2 が上限なので、
## 3 段ぶんの差を作れない）。**段を増やすだけの空報酬にしない。**
const SLOT_NEED := 1

## 持ち込める枠の上限。**これ以上は増やさない。**
const MAX_SLOTS := 2


## 持ち込める枠の数。
static func slots(mastery_gain: int) -> int:
	return 1 + (1 if mastery_gain >= SLOT_NEED else 0)


## その職の印の定義（無ければ空）。
static func definition(job_id: String) -> Dictionary:
	return Database.job(job_id).get("inherit_sign", {})


## 選べる印。**★6 に届いている職だけ。**
##
## 届いていない職の印を持ち込めると、★6 に意味が無くなる。
## 並びは職の id 順で固定する（乱数を使わない）。
static func available(members: Array) -> Array[String]:
	var out: Array[String] = []
	for id in Database.job_ids():
		var job := String(id)
		if definition(job).is_empty():
			continue
		for m in members:
			if m.has_inherit_sign(job):
				out.append(job)
				break
	out.sort()
	return out


## 選び直せるか。**未解放・重複・枠外は false。**
static func can_choose(
	chosen: Array, slot: int, job_id: String, members: Array, mastery_gain: int
) -> bool:
	if slot < 0 or slot >= slots(mastery_gain):
		return false
	if job_id == "":
		return true   # 外すのはいつでもよい
	if job_id not in available(members):
		return false
	return job_id not in chosen


## 枠と解放に合わなくなったぶんを空ける。**詰めない。**
##
## 詰めると、選んだ覚えのない印が入る（継承技と同じ理由）。
## 返すのは空けた数。
static func prune(chosen: Array, members: Array, mastery_gain: int) -> int:
	var usable := available(members)
	var dropped := 0
	var room := slots(mastery_gain)
	while chosen.size() > room:
		if String(chosen[chosen.size() - 1]) != "":
			dropped += 1
		chosen.remove_at(chosen.size() - 1)
	for i in chosen.size():
		if String(chosen[i]) != "" and String(chosen[i]) not in usable:
			chosen[i] = ""
			dropped += 1
	return dropped
