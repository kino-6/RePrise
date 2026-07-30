class_name Lore
extends RefCounted

## 世界の前提の文言。**語そのものは `data/vocabulary.json` にある。**
##
## 根拠と、なぜこの前提にしたのかは docs/premise.md。
## **設定はユーザーの領分なので、差し替えを前提に置いてある。**
## JSON を書き換えれば画面と戦記 AI の両方が揃って変わる。
##
## Terms が「UI の語彙」なのに対して、こちらは「世界の言い分」。混ぜないこと。

## 送られる先の呼び名。
static var WORLD_NAME := Vocabulary.word("lore", "world_name", "世界")

## 出撃を選んだときの 3 行。1 行目が理由、2〜3 行目が持ち帰れるもの／帰らないもの。
## 3 行に収める（長くなると下に並ぶ名簿と重なる）。
static var DEPART_LINES := Vocabulary.words("lore", "depart_lines", [
	"送られる さきは いつも べつの世界。",
	"レベルと そうびは 世界に 返す。",
	"じゅくれんと わざだけが のこる。",
])

## 資源の説明。全滅しても入る、というのがここの肝。
static var ECHO_LINE := Vocabulary.word(
	"lore", "echo_line", "踏んだ ぶんだけ 砦に 記録が 帰る。"
)

## 戦記 AI に渡す世界の前提。
##
## **事実（facts）には混ぜない。** facts はゲームが確定させた数字で、
## こちらは文体側の材料。混ぜると設定が数値と同じ重さで扱われ、
## モデルが設定のほうを膨らませはじめる。
static var WORLD := "世界の前提:
- " + "
- ".join(
	Vocabulary.words("lore", "world_premise", [
		"銀の砦は世界の外にあり、一行はそこから世界へ送られる。",
		"行き先は毎回べつの世界で、地形も町も終点の主も同じものは二度と無い。",
		"終点の主を討てば世界は保たれ、討てなければ失われる。",
		"世界で得た力と得物は世界に返るが、体が覚えた技だけは砦へ帰る。",
	])
)
