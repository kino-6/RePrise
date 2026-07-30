class_name Terms
extends RefCounted

## 画面に出る言葉を 1 か所に集める。
##
## 呼び名は遊び心地に直結するので、あとから何度でも差し替わる前提で置く。
## 各 View に文字列を直書きすると、変えるたびに全画面を grep することになる。
## ここだけを書き換えれば表示が揃う、という状態を保つこと。
##
## **語そのものは `data/vocabulary.json` にある。** ここに在るのは名前の付いた
## 入れ物で、中身は外から差し替えられる（造語は見直しの対象なので、コードを
## 触らずに変えられる状態にしておく）。右側の既定値はファイルが無いときの受け皿。
##
## ここに置くのは「UI の語彙」だけ。職業名・技名・道具名は data/*.json 側にある。

# --- 通貨・資源 ---
static var ECHO := Vocabulary.word("terms", "echo", "資源")  ## 恒久通貨。ランをまたいで残り、拠点の強化に使う
static var GOLD := Vocabulary.word("terms", "gold", "ゴールド")  ## ラン内資源。全滅で失う

# --- 場所 ---
static var STRONGHOLD := Vocabulary.word("terms", "stronghold", "銀の砦")
static var SHOP := Vocabulary.word("terms", "shop", "みせ")
static var TOWN := Vocabulary.word("terms", "town", "町")
static var CAVE := Vocabulary.word("terms", "cave", "洞")
static var CASTLE := Vocabulary.word("terms", "castle", "城")
static var GATE := Vocabulary.word("terms", "gate", "門")

# --- 戦績 ---
## 難度の軸。もとは「地下 N 階」だったが、世界を歩く形になったので
## 「門からどれだけ離れたか」を表す数字になった。目盛りは 1..10 のまま
## （data/*.json の floor_min もこの目盛りで書かれている）。
static var DANGER := Vocabulary.word("terms", "danger", "危険度")
static var DANGER_AT := Vocabulary.word("terms", "danger_at", "危険度 %d")
static var DEEPEST := Vocabulary.word("terms", "deepest", "最も危険")
static var FLOOR := Vocabulary.word("terms", "floor", "危険度 %d")
static var CAVE_FLOOR := Vocabulary.word("terms", "cave_floor", "洞 %d階")
static var RUNS := Vocabulary.word("terms", "runs", "%d回目")
static var RUNS_TOTAL := Vocabulary.word("terms", "runs_total", "%d回の潜行")

# --- 能力・コスト ---
## 行動の速さ。内部は「待ちコスト」（小さいほど速い）だが、
## 画面では大きいほど速い数字に直して見せる（speed() を通すこと）。
static var SPEED := Vocabulary.word("terms", "speed", "速さ")
## 戦闘コマンドに添えるコスト。こちらは「この一手で何待つか」なので待ちのまま出す。
static var WAIT := Vocabulary.word("terms", "wait", "待")
static var MASTERY := Vocabulary.word("terms", "mastery", "じゅくれんど")
static var RANK := Vocabulary.word("terms", "rank", "段")
static var PRICE := Vocabulary.word("terms", "price", "ひつよう")
static var MAXED := Vocabulary.word("terms", "maxed", "きわみ")

# --- 拠点の見出し ---
static var PARTY := Vocabulary.word("terms", "party", "へんせい")
static var UPGRADE := Vocabulary.word("terms", "upgrade", "アップグレード")
static var DEPART := Vocabulary.word("terms", "depart", "出撃する")


## 待ちコストを「速さ」に読み替える。
##
## 内部の cost_scale は小さいほど速い（とうぞく 70 / まほうつかい 145）。
## そのまま出すと「数字が大きいほど強そう」という直感と逆になるので、
## 基準から引いて向きを揃える。順序は保たれるので比較の意味は変わらない。
const SPEED_BASE := 200


static func speed(cost_scale: int) -> int:
	return SPEED_BASE - cost_scale
