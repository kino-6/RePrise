class_name Chronicle
extends RefCounted

## ラン終了時の「戦記」を組み立てる。
##
## ここがローカル AI の唯一の接続点になる予定の場所。設計上の要点は 2 つ。
##
##   1. 入力は end_run() が返す構造化された事実だけ。文章生成はゲームの状態を
##      一切変更しない。生成が失敗しても、遅くても、ゲームは完全に成立する。
##   2. 生成待ちが許される画面（＝もう操作するものが無い画面）でしか呼ばない。
##
## 現状は決定的なテンプレート出力。LLM 版はこれをフォールバックとして使う。

## 事実の羅列から短い年代記を書く。
static func write(summary: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var floor_no := int(summary.get("floor", 1))
	var gold := int(summary.get("gold", 0))
	var members: Array = summary.get("members", [])

	if bool(summary.get("victory", false)):
		lines.append("一行は 地下 %d 階から 生還した。" % floor_no)
	else:
		lines.append("一行は 地下 %d 階で ついえた。" % floor_no)

	lines.append("持ち帰った金貨 %d 枚。" % gold)

	var learned_all: Array = []
	for m in members:
		for a in m.get("learned", []):
			var ability_name: String = Database.ability(String(a)).get("name", String(a))
			if ability_name not in learned_all:
				learned_all.append(ability_name)

	if learned_all.is_empty():
		lines.append("この旅で 得た technique は なかった。")
	else:
		lines.append("だが %s の技は 残った。" % ", ".join(learned_all))

	for m in members:
		lines.append(
			"%s／%s  熟練 %d" % [m.get("name", ""), m.get("job_name", ""), int(m.get("mastery_rank", 0))]
		)
	return lines


## LLM に渡す事実。プロンプトではなく「事実の構造」を作るのがここの役目。
## 文章の指示はプロンプト側に持たせ、事実の抽出はゲーム側で確定させておく。
static func facts_for_llm(summary: Dictionary) -> Dictionary:
	var members: Array = []
	for m in summary.get("members", []):
		members.append({
			"name": m.get("name", ""),
			"job": m.get("job_name", ""),
			"level": int(m.get("level", 1)),
			"mastery_rank": int(m.get("mastery_rank", 0)),
		})
	return {
		"outcome": "生還" if bool(summary.get("victory", false)) else "全滅",
		"floor": int(summary.get("floor", 1)),
		"gold": int(summary.get("gold", 0)),
		"steps": int(summary.get("steps", 0)),
		"party": members,
	}
