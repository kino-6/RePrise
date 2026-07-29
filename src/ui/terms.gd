class_name Terms
extends RefCounted

## 画面に出る言葉を 1 か所に集める。
##
## 呼び名は遊び心地に直結するので、あとから何度でも差し替わる前提で置く。
## 各 View に文字列を直書きすると、変えるたびに全画面を grep することになる。
## ここだけを書き換えれば表示が揃う、という状態を保つこと。
##
## ここに置くのは「UI の語彙」だけ。職業名・技名・道具名は data/*.json 側にある。

# --- 通貨・資源 ---
const ECHO := "資源"  ## 恒久通貨。ランをまたいで残り、拠点の強化に使う
const GOLD := "ゴールド"  ## ラン内資源。全滅で失う

# --- 場所 ---
const STRONGHOLD := "銀の砦"
const SHOP := "みせ"

# --- 戦績 ---
const DEEPEST := "最深"
const FLOOR := "地下%d階"
const RUNS := "%d回目"
const RUNS_TOTAL := "%d回の潜行"

# --- 能力・コスト ---
## 行動の速さ。内部は「待ちコスト」（小さいほど速い）だが、
## 画面では大きいほど速い数字に直して見せる（speed() を通すこと）。
const SPEED := "速さ"
## 戦闘コマンドに添えるコスト。こちらは「この一手で何待つか」なので待ちのまま出す。
const WAIT := "待"
const MASTERY := "じゅくれんど"
const RANK := "段"
const PRICE := "ひつよう"
const MAXED := "きわみ"

# --- 拠点の見出し ---
const UPGRADE := "アップグレード"
const DEPART := "出撃する"


## 待ちコストを「速さ」に読み替える。
##
## 内部の cost_scale は小さいほど速い（とうぞく 70 / まほうつかい 145）。
## そのまま出すと「数字が大きいほど強そう」という直感と逆になるので、
## 基準から引いて向きを揃える。順序は保たれるので比較の意味は変わらない。
const SPEED_BASE := 200


static func speed(cost_scale: int) -> int:
	return SPEED_BASE - cost_scale
