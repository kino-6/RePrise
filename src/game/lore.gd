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
	"銀の門が、新たな世界への道を開いた。",
	"この世界で得た体と装備は、帰還時に失われる。",
	"覚えた技と遠征の記録は、銀の砦へ持ち帰れる。",
])

## 資源の説明。全滅しても入る、というのがここの肝。
static var ECHO_LINE := Vocabulary.word(
	"lore", "echo_line", "遠征の記録に応じて、砦の資源を獲得する。"
)

## 初回だけ見せるプロローグ。View は構図と入力だけを持ち、表示文はここから読む。
static var PROLOGUE_TITLE := Vocabulary.word("lore", "prologue_title", "世界が砕けた夜")
static var PROLOGUE_BEATS: Array = Vocabulary.words("lore", "prologue_beats", [
	{
		"scene": "assault", "location": "終極の城　主の間", "speaker": "語り",
		"lines": ["世界が滅びかけた夜、四人は終局の主を追い詰めた。", "あと一撃で、すべてを終えられるはずだった。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "confront", "location": "終極の城　主の間", "speaker": "終局の主",
		"lines": ["もう遅い。この世界は崩れ始めている。", "お前たちも、分かれた世界とともに消えろ。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "attack", "location": "終極の城　主の間", "speaker": "アレン",
		"lines": ["まだ間に合う。みんな、力を貸してくれ！", "奴の核を狙う！"],
		"prompt": "Ｚキーで 斬りこむ",
	},
	{
		"scene": "shatter", "location": "分断", "speaker": "語り",
		"lines": ["攻撃が届く直前、終局の主は世界を分断した。", "大地と人々は、いくつもの世界へ引き離された。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "fragments", "location": "世界の狭間", "speaker": "砦からの通信",
		"lines": ["聞こえますか。応答してください。", "銀の門から、あなたたちを捜しています。"],
		"prompt": "Ｚキーで 声を追う",
	},
	{
		"scene": "fortress", "location": "銀の砦", "speaker": "砦の記録係",
		"lines": ["銀の門は、崩壊の直前に四人を救い出しました。", "終局の主も、分断された世界のどこかへ逃げています。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "many_worlds", "location": "銀の門", "speaker": "砦の記録係",
		"lines": ["分かれた世界は、それぞれ異なる大地と歴史を持っています。", "門の行き先も、城を支配する者も毎回変わります。", "一度閉じた門を、同じ世界へ開くことはできません。"],
		"prompt": "Ｚキーで すすむ",
	},
	{
		"scene": "oath", "location": "銀の門", "speaker": "アレン",
		"lines": ["なら、門がつながるたびに俺たちが行く。", "どの世界も見捨てない。終局の主を見つけるまで。"],
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
		"終局の主が世界を分断し、ひとつだった世界は異なる歴史を持つ多数の世界へ分かれた。",
		"分断時に開いていた銀の門が一行を救い、銀の砦は世界の外へ取り残された。",
		"銀の門がつながる先は毎回異なり、地形、町、城を支配する者も変わる。",
		"城を支配する者を倒せば世界は保たれ、倒せなければ失われる。",
		"世界で得た体と装備は帰還時に失うが、覚えた技と遠征の記録は砦へ持ち帰れる。",
	])
)
