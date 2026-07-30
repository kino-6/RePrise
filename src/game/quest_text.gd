class_name QuestText
extends RefCounted

## AI が書いた文字列を、画面に出してよい形へ落とす検算層。
##
## **AI を繋ぐ前にこれを作る。** 繋いでから作ると、変な出力を見るたびに
## プロンプトをいじる方へ流れる。プロンプトは頼みごとであって保証ではないので、
## 最後は受け取る側が弾くしかない。
##
## 方針は 3 つ。
##
##   1. **項目ごとに落とす。** 1 つ変でも全部捨てない。封の名が 1 つ駄目でも、
##      残り 2 つは使える。落ちた項目だけテンプレートへ差し替える。
##   2. **数値は受け取らない。** 数字を含む項目は理由を問わず却下する。
##      1 点の atk が到達率を 2 倍動かす世界で、言葉の生成器に数を触らせない。
##   3. **落ちた理由を残す。** 黙って落とすと「AI を繋いだのに文章が変わらない」
##      の原因が分からなくなる。

## 封の名に許す長さ。画面の幅から決めた（`PixelUI.wrap` の実測に合わせる）。
const MAX_NAME := 10

## 一文に許す長さ。戦記の 1 行と同じ。
const MAX_LINE := 34

## 他社作品の固有名詞。**ここは必ず要る。**
##
## 初版で呪文名に DQ の名前をそのまま置いた経緯があり、モデルは頼まなくても
## 同じことをする（学習元にそう書いてあるので当然そうなる）。
## 語幹を借りるのはよいが、語そのものは通さない。
const BANNED := [
	"ホイミ", "ベホイミ", "ベホマ", "メラ", "メラミ", "メラゾーマ",
	"ギラ", "イオ", "バギ", "ヒャド", "ラリホー", "ザオラル", "ザオリク",
	"ルーラ", "ピオラ", "ボミオス", "スカラ", "マホカンタ", "パルプンテ",
	"ケアル", "ケアルガ", "ファイガ", "ブリザガ", "サンダガ", "アルテマ",
	"バハムート", "チョコボ", "モーグリ", "エスナ", "レイズ",
	"メタルスライム", "はぐれメタル", "ドラゴンクエスト", "ファイナルファンタジー",
]

## 受け取らない文字。記号・英数字・思考の断片が混ざったものは捨てる。
const REJECT_CHARS := "0123456789０１２３４５６７８９{}[]<>#*`\\|_=+@"


## 封の名として使えるか。使えなければ空を返す。
static func accept_name(raw: String) -> String:
	var text := _tidy(raw)
	if text == "" or text.length() > MAX_NAME:
		return ""
	if not _clean_enough(text):
		return ""
	return text


## 一文として使えるか。使えなければ空を返す。
static func accept_line(raw: String) -> String:
	var text := _tidy(raw)
	if text == "" or text.length() > MAX_LINE:
		return ""
	if not _clean_enough(text):
		return ""
	return text


## 前後の飾りを落とす。モデルは指示しても記号を付けてくる。
static func _tidy(raw: String) -> String:
	var text := raw.strip_edges()
	# 引用符は単引用符で書く（GDScript の二重引用符の中に " は置きづらい）。
	for mark in ["- ", "・", "* ", "「", "」", '"', "'"]:
		text = text.trim_prefix(mark).trim_suffix(mark)
	return text.strip_edges()


static func _clean_enough(text: String) -> bool:
	# 数値の混入。「HP300 の主」のようなものを書かせない。
	for ch in REJECT_CHARS:
		if ch in text:
			return false
	# 英字。日本語の画面に混ざると一気に浮く。
	for c in text.to_utf8_buffer():
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return false
	for word in BANNED:
		if word in text:
			return false
	return true


## 世界の封に、AI が書いた名と由来を当てる。
##
## **構造には触らない。** 位置も帯も危険度も生成器が決めたままで、
## 変わるのは表示用の文字列だけ。だから途中で差し替えても安全だし、
## 届かなくても遊びは何も変わらない。
##
## 戻り値は何を採ってなぜ落としたかの記録（`--ai-debug` で出す）。
static func apply_to_world(world: WorldMap, reply: Dictionary) -> Dictionary:
	var report := {"taken": 0, "rejected": []}
	if world == null:
		return report

	var seals: Array = reply.get("seals", [])
	var used := {}
	for i in world.seals.size():
		if i >= seals.size():
			break
		var entry: Variant = seals[i]
		if typeof(entry) != TYPE_DICTIONARY:
			report["rejected"].append("封%d: 形が違う" % i)
			continue
		var got: Dictionary = entry

		var name := accept_name(String(got.get("name", "")))
		if name == "":
			report["rejected"].append("封%d: 名を却下" % i)
		elif used.has(name):
			# 同じ名前が並ぶと、どれを解いたのか分からなくなる。
			report["rejected"].append("封%d: 名が重複" % i)
		else:
			used[name] = true
			world.seals[i]["name"] = name
			report["taken"] = int(report["taken"]) + 1

		var why := accept_line(String(got.get("why", "")))
		if why == "":
			report["rejected"].append("封%d: 由来を却下" % i)
		else:
			world.seals[i]["why"] = why
			report["taken"] = int(report["taken"]) + 1

	return report


## AI に渡す事実。**構造だけを渡し、文体は渡さない。**
## `Chronicle.facts_for_llm()` と同じ作り。
static func facts_for_llm(world: WorldMap) -> Dictionary:
	if world == null:
		return {}
	var bands := []
	for s in world.seals:
		bands.append({
			"帯": String(s.get("band_name", "")),
			"土地": world.biome_name_at(
				Vector2i(s.get("pos", Vector2i.ZERO)).x, Vector2i(s.get("pos", Vector2i.ZERO)).y
			),
		})
	return {"封の数": world.seals.size(), "封": bands}
