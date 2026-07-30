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
	"銀の門は 毎回 べつの世界へ ひらく。",
	"レベルと そうびは その世界に 返す。",
	"体が おぼえた わざだけが のこる。",
])

## 資源の説明。全滅しても入る、というのがここの肝。
static var ECHO_LINE := Vocabulary.word(
	"lore", "echo_line", "踏んだ ぶんだけ 砦に 記録が 帰る。"
)

## 初回だけ見せるプロローグ。View は構図と入力だけを持ち、表示文はここから読む。
static var PROLOGUE_TITLE := Vocabulary.word("lore", "prologue_title", "砕けた夜")
static var PROLOGUE_BEATS: Array = Vocabulary.words("lore", "prologue_beats", [
	{
		"scene": "assault", "location": "終極の城　主の間", "speaker": "記録",
		"lines": ["世界が滅びる夜、四人は主の間へたどり着いた。", "これが最後の戦いになるはずだった。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "confront", "location": "終極の城　主の間", "speaker": "世界を綴じるもの",
		"lines": ["遅かった。世界はもう、ひとつではいられない。", "無数の明日ごと、ここで砕けよ。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "attack", "location": "終極の城　主の間", "speaker": "アレン",
		"lines": ["今なら届く。", "四人の一撃を、世界の綴じ目へ。"],
		"prompt": "Ｚキーで 斬りこむ",
	},
	{
		"scene": "shatter", "location": "分断", "speaker": "記録",
		"lines": ["刃が届く寸前、主は世界の綴じ目を引き裂いた。", "大地も町も人々も、あり得た未来へ砕け散った。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "fragments", "location": "世界の狭間", "speaker": "名もない声",
		"lines": ["まだ、終わっていない。", "こちらの世界も、向こうの世界も、閉じようとしている。"],
		"prompt": "Ｚキーで 声を追う",
	},
	{
		"scene": "fortress", "location": "銀の砦", "speaker": "砦の記録係",
		"lines": ["銀の門だけが、四人を世界の外へ拾い上げた。", "主もまた、砕けた世界のどこかへ逃れた。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "many_worlds", "location": "銀の門", "speaker": "砦の記録係",
		"lines": ["欠片は、違う大地と歴史を持つ世界へ育った。", "門の行き先も、城の主も、毎回変わる。", "同じ世界へ届くのは、一度だけ。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "oath", "location": "銀の門", "speaker": "アレン",
		"lines": ["なら、ひとつずつ見届ける。", "この世界を失敗させない。あの主へ届くまで。"],
		"prompt": "Ｚキーで 銀の砦へ",
	},
])

## 戦記 AI に渡す世界の前提。
##
## **事実（facts）には混ぜない。** facts はゲームが確定させた数字で、
## こちらは文体側の材料。混ぜると設定が数値と同じ重さで扱われ、
## モデルが設定のほうを膨らませはじめる。
static var WORLD := "世界の前提:
- " + "
- ".join(
	Vocabulary.words("lore", "world_premise", [
		"終局の主が世界の綴じ目を引き裂き、ひとつだった世界は異なる歴史を持つ多数の世界へ分かれた。",
		"分断時に開いていた銀の門だけが一行を回収し、銀の砦は世界の外へ取り残された。",
		"銀の門が捉える世界は毎回異なり、地形も町も終点の主も同じものは二度と無い。",
		"終点の主を討てば世界は保たれ、討てなければ失われる。",
		"世界で得た力と得物は世界に返るが、体が覚えた技だけは砦へ帰る。",
	])
)
