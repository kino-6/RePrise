class_name GearText
extends RefCounted

## 装備の効き目を 1 行にまとめる。
##
## 出店と そうび 画面の両方で同じ文字列が要る。数字が見えないと選べないので
## 説明文の有無に関係なく必ず出す。2 か所に同じ関数を書いていたので集約した。

## 表示する順番。列挙順に依存させない（辞書の並びで表示が揺れるのを防ぐ）。
const STATS := ["atk", "mag", "def", "agi", "hp", "mp"]


static func summary(gear: Dictionary) -> String:
	var parts: Array[String] = []
	for key in STATS:
		var value := int(gear.get(key, 0))
		if value != 0:
			parts.append("%s%+d" % [key.to_upper(), value])
	# 行動コストは「小さいほど速い」ので、符号を反転して速さとして見せる。
	var tempo := int(gear.get("cost_scale", 0))
	if tempo != 0:
		parts.append("%s%+d" % [Terms.SPEED, -tempo])
	return "　".join(parts)
