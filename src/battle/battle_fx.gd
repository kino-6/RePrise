class_name BattleFx
extends RefCounted

## 技から出す絵を選ぶ表。
##
## **属性が最優先**（炎の技は炎に見えるべき）。属性が無ければ系統で選ぶ。
## 対応が無ければ空を返し、**従来の点滅と数字だけ**になる
## （絵が 1 枚も無くても遊べる、が取り込みの前提）。
##
## 画面（`BattleView`）ではなくここに置くのは、**テストから呼べるようにする**ため。
## Node に属する静的関数は `--headless --script` から呼べない。

const BY_ELEMENT := {
	"fire": "fx_fire", "ice": "fx_ice", "bolt": "fx_bolt", "dark": "fx_debuff",
}

const BY_KIND := {
	"physical": "fx_slash", "magical": "fx_explosion",
	"heal": "fx_heal", "buff": "fx_buff", "debuff": "fx_debuff",
	"special": "fx_thrust",
}

## 技ごとの指定。系統だけでは足りないもの（突き・銃・眠り・毒）を拾う。
const BY_ABILITY := {
	"quick_stab": "fx_thrust", "pierce": "fx_thrust",
	"sleep": "fx_sleep", "poison": "fx_poison", "venom": "fx_poison",
	"shot": "fx_gunshot", "snipe": "fx_gunshot",
}


static func for_ability(ability_id: String) -> String:
	if BY_ABILITY.has(ability_id):
		return String(BY_ABILITY[ability_id])
	var ab := Database.ability(ability_id)
	if ab.is_empty():
		return ""
	var element := String(ab.get("element", ""))
	if BY_ELEMENT.has(element):
		return String(BY_ELEMENT[element])
	return String(BY_KIND.get(String(ab.get("kind", "")), ""))
