extends SceneTree

## 窓の割り付け（`UiPanel`）の単独テスト（G-1）。
##
##     godot --headless --script tests/test_window_system.gd
##
## **画面を撮らずに検査する。** `check_ui.py` は 31 画面を立てて撮るので
## 1 分近くかかるうえ、「たまたま今の文言だと収まっている」ことしか言えない。
## ここは**わざと壊した入力**を渡して、詰まる・捨てる・数えるが起きることを見る。
##
## Codex の G-1 は `UiWindowFrame` / `UiWindow` を新規に足す形で書かれていたが、
## **同じ役目の型を 2 つ置かない。** 既にある `UiPanel` を検査する。
## 2 本目を建てると、片方だけ直したずれが必ず出る（Sim と実装で 2 度やった）。

var _pass := 0
var _fail := 0


func _init() -> void:
	Database.reload()
	_test_clip_to_width()
	_test_row_protects_right()
	_test_drops_rows_that_do_not_fit()
	_test_columns_do_not_overlap()
	_test_paragraph_fits()
	_test_kanji_below_14px()
	print("---")
	print("成功 %d / 失敗 %d" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, note: String = "") -> void:
	if ok:
		_pass += 1
		print("  OK   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s %s" % [label, note])


## 幅を 1px 超えただけでも詰める。**「だいたい収まっている」を許さない。**
func _test_clip_to_width() -> void:
	var long_text := "あいうえおかきくけこさしすせそたちつてと"
	var full := PixelUI.text_width(long_text, PixelUI.SIZE_TEXT)

	var wide := UiPanel.inside(null, Rect2(0, 0, full + 8.0, 40))
	wide.line(long_text)
	_check("収まる幅では詰めない", wide.last_text == long_text)

	# 1px だけ足りない。許容（OVERFLOW_SLACK）を超える 3px で試す。
	var tight := UiPanel.inside(null, Rect2(0, 0, full - 3.0, 40))
	tight.line(long_text)
	_check(
		"1 文字ぶんも溢れさせない", tight.last_text != long_text,
		"(詰めずに通した)"
	)
	_check("詰めた印は … で終わる", tight.last_text.ends_with("…"))
	_check(
		"詰めた結果が幅に収まる",
		PixelUI.text_width(tight.last_text, PixelUI.SIZE_TEXT) <= full - 3.0
	)
	_check("詰めたことを記録する", not PixelUI.clipped().is_empty())


## 左右がぶつかったら**左を詰める**。右（数値）は消えては困る。
func _test_row_protects_right() -> void:
	var name := "とてもながいなまえのひと"
	var value := "1234/5678"
	var need := PixelUI.text_width(name + value, PixelUI.SIZE_TEXT)
	var panel := UiPanel.inside(null, Rect2(0, 0, need - 40.0, 40))
	panel.row(name, value)
	_check("ぶつかったら左を詰める", panel.last_text != name)
	_check(
		"詰めた左と右が重ならない",
		(PixelUI.text_width(panel.last_text, PixelUI.SIZE_TEXT)
			+ PixelUI.text_width(value, PixelUI.SIZE_TEXT)) <= need - 40.0
	)


## 高さが足りない行は**描かずに数える**。外へ描かない。
func _test_drops_rows_that_do_not_fit() -> void:
	PixelUI.ui_check_reset()
	# 2 行ぶんだけの高さ。
	var panel := UiPanel.inside(null, Rect2(0, 0, 200, PixelUI.LINE * 2.0))
	for i in 5:
		panel.line("%d 行目" % i)
	_check("入らない行を外へ描かない", panel.overflowed())
	_check("捨てた数を数える（3 行）", panel.dropped() == 3, "(%d)" % panel.dropped())
	_check("捨てた行を全画面Gateへ通知する", PixelUI.dropped_lines().size() == 3)

	var roomy := UiPanel.inside(null, Rect2(0, 0, 200, PixelUI.LINE * 6.0))
	for i in 5:
		roomy.line("%d 行目" % i)
	_check("入るぶんは捨てない", not roomy.overflowed())


## 列は重ならない。**格子を手計算で置いていたのが重なりの原因だった。**
func _test_columns_do_not_overlap() -> void:
	var panel := UiPanel.inside(null, Rect2(0, 0, 300, 100))
	var cols := panel.columns(3, 10.0)
	_check("頼んだ数だけ列が返る", cols.size() == 3)
	var ok := true
	for i in cols.size() - 1:
		if cols[i].inner().end.x > cols[i + 1].inner().position.x:
			ok = false
	_check("隣の列に食い込まない", ok)
	_check(
		"列の合計が枠を超えない",
		cols[cols.size() - 1].inner().end.x <= 300.0 + PixelUI.OVERFLOW_SLACK
	)


## 折り返した行は、**1 行も詰まらずに**収まる。
##
## `wrap()` は行頭に置けない字（、。）」など）を前の行へ送り返すので、
## 頼んだ幅をわずかに超える行を返すことがある。`paragraph()` は
## そのぶんを見越して狭く折る。ここはその約束が生きているかを見る。
func _test_paragraph_fits() -> void:
	PixelUI.ui_check_reset()
	var text := (
		"銀の門は、毎回べつの世界へひらく。レベルとそうびはその世界に返す。"
		+ "体がおぼえたわざだけがのこる（それが、次の世界で最初に効く）。"
	)
	var panel := UiPanel.inside(null, Rect2(0, 0, 240, 400))
	panel.paragraph(text)
	_check("折り返した行は詰まらない", PixelUI.clipped().is_empty(),
		"(%s)" % ", ".join(PixelUI.clipped()))


## 12px に漢字を置かない（D-5 の一部）。
##
## `SIZE_SUB` は「かなと数字のみ」と決めてある。SFC の 12px で漢字は潰れる。
func _test_kanji_below_14px() -> void:
	_check("添え物の寸法は 12px のまま", PixelUI.SIZE_SUB == 12)
	_check("本文の寸法は 14px 以上", PixelUI.SIZE_TEXT >= 14)
	# 検出そのものの試験。**壊した入力で引っかかること**を見る。
	_check("漢字を見つけられる", _has_kanji("危険度"))
	_check("かなと数字は見逃す", not _has_kanji("あぶなさ 12"))

	# **寸法の判断は窓の側でやる**（S-8）。
	#
	# 呼ぶ側 79 か所へ「ここは 14px」と書いて回る形にすると、次に語を
	# 漢字へ寄せた人がまた同じ穴に落ちる。12px を頼まれても漢字なら上げる。
	_equal_int(
		"12px を頼まれても漢字なら上げる",
		PixelUI.readable_size("熟練度 12/15", PixelUI.SIZE_SUB), PixelUI.SIZE_TEXT
	)
	_equal_int(
		"かなと数字は 12px のまま",
		PixelUI.readable_size("のこり 640", PixelUI.SIZE_SUB), PixelUI.SIZE_SUB
	)
	_equal_int(
		"もともと大きい寸法は下げない",
		PixelUI.readable_size("銀の砦", PixelUI.SIZE_HEAD), PixelUI.SIZE_HEAD
	)
	# **測る側と描く側で同じ寸法を通す。** 片方だけ上げると、12px で測って
	# 14px で描くことになり、右寄せと中央寄せが必ずずれる。
	_check(
		"幅も上げたあとの寸法で測る",
		is_equal_approx(
			PixelUI.text_width("熟練度", PixelUI.SIZE_SUB),
			PixelUI.text_width("熟練度", PixelUI.SIZE_TEXT)
		)
	)
	_check(
		"かなの幅は 12px のまま",
		PixelUI.text_width("じゅくれん", PixelUI.SIZE_SUB)
		< PixelUI.text_width("じゅくれん", PixelUI.SIZE_TEXT)
	)


func _equal_int(label: String, actual: int, expected: int) -> void:
	_check(label, actual == expected, "(実際: %d / 期待: %d)" % [actual, expected])


## 漢字（CJK 統合漢字）を含むか。
static func _has_kanji(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
