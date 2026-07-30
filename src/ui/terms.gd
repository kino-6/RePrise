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

## そうび回り（C-9 / C-10）。
##
## `data/vocabulary.json` にまだ書かれていなくても既定へ落ちるので、
## 語の見直しは後からできる（`Vocabulary.word` の約束）。
static var BEST_GEAR := Vocabulary.word("terms", "best_gear", "さいきょう")
static var EQUIP_NOW := Vocabulary.word("terms", "equip_now", "いま そうびする")
static var TO_BAG := Vocabulary.word("terms", "to_bag", "もちものへ")
static var GOT_GEAR := Vocabulary.word("terms", "got_gear", "%s を みつけた")
static var TAKES_OFF := Vocabulary.word("terms", "takes_off", "はずれる")
static var CANNOT_EQUIP := Vocabulary.word("terms", "cannot_equip", "そうびできない")
static var BATTLE_ONLY := Vocabulary.word("terms", "battle_only", "戦闘中だけ つかえる")
static var NO_ONE_CAN := Vocabulary.word(
	"terms", "no_one_can", "だれも そうびできない")
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

# --- セーブ消去 ---
static var SAVE_ERASE := Vocabulary.word("terms", "save_erase", "セーブを けす")
static var SAVE_ERASE_QUESTION := Vocabulary.word(
	"terms", "save_erase_question", "セーブを けしますか？"
)
static var SAVE_ERASE_WARNING := Vocabulary.word(
	"terms", "save_erase_warning", "戦績・資源・熟練・中断は すべて消える"
)
static var SAVE_ERASE_CANCEL := Vocabulary.word("terms", "save_erase_cancel", "やめる")
static var SAVE_ERASE_EXECUTE := Vocabulary.word(
	"terms", "save_erase_execute", "すべて けす"
)
static var SAVE_ERASE_HINT := Vocabulary.word(
	"terms", "save_erase_hint", "Ｚで えらぶ　Ｘで やめる"
)
static var SAVE_ERASE_DONE := Vocabulary.word(
	"terms", "save_erase_done", "セーブを けしました"
)
static var SAVE_ERASE_FAILED := Vocabulary.word(
	"terms", "save_erase_failed", "セーブを けせませんでした"
)
static var SAVE_ERASE_NONE := Vocabulary.word(
	"terms", "save_erase_none", "けすものが ない"
)
static var SAVE_ERASE_TITLE_ONLY := Vocabulary.word(
	"terms", "save_erase_title_only", "タイトルから"
)

# --- ランの放棄 ---
static var RUN_ABANDON := Vocabulary.word("terms", "run_abandon", "ランを あきらめる")
static var RUN_ABANDON_FIRST_QUESTION := Vocabulary.word(
	"terms", "run_abandon_first_question", "このランを あきらめますか？"
)
static var RUN_ABANDON_FIRST_WARNING := Vocabulary.word(
	"terms", "run_abandon_first_warning", "レベル・そうび・ゴールドは うしなう"
)
static var RUN_ABANDON_FINAL_QUESTION := Vocabulary.word(
	"terms", "run_abandon_final_question", "ほんとうに 砦へ 戻りますか？"
)
static var RUN_ABANDON_FINAL_WARNING := Vocabulary.word(
	"terms", "run_abandon_final_warning", "この世界には 二度と もどれない"
)
static var RUN_ABANDON_CANCEL := Vocabulary.word("terms", "run_abandon_cancel", "もどる")
static var RUN_ABANDON_NEXT := Vocabulary.word(
	"terms", "run_abandon_next", "あきらめる"
)
static var RUN_ABANDON_EXECUTE := Vocabulary.word(
	"terms", "run_abandon_execute", "ランを終えて 砦へ"
)
static var RUN_ABANDON_HINT := Vocabulary.word(
	"terms", "run_abandon_hint", "2回の確認が必要　Ｘで もどる"
)
static var RUN_ABANDON_IN_RUN := Vocabulary.word(
	"terms", "run_abandon_in_run", "ラン中のみ"
)
static var RUN_ABANDON_RESULT := Vocabulary.word("terms", "run_abandon_result", "帰還")
static var RUN_ABANDON_CHRONICLE := Vocabulary.word(
	"terms", "run_abandon_chronicle", "一行は 危険度 %d の 地から 帰還を選んだ。"
)

# --- 任意イベント ---
static var EVENT_CLOSE := Vocabulary.word("terms", "event_close", "Ｚで とじる")
static var EVENT_DEFER_SUMMARY := Vocabulary.word(
	"terms", "event_defer_summary", "保留 → 再訪できる"
)
static var EVENT_DEFER_DETAIL := Vocabulary.word(
	"terms", "event_defer_detail", "いまは立ち去る。あとで選び直せる。"
)
static var EVENT_DEFER_OUTCOME := Vocabulary.word(
	"terms", "event_defer_outcome", "いまは手を出さず離れた。戻れば、まだ選べる。"
)
static var EVENT_UNRESOLVED := Vocabulary.word(
	"terms", "event_unresolved", "何も起きなかった。この選択肢は未解決だ。"
)
static var EVENT_ITEM_MISSING := Vocabulary.word(
	"terms", "event_item_missing", "渡す物がなく、みんな 傷ついた"
)
static var EVENT_GEAR_MISSING := Vocabulary.word(
	"terms", "event_gear_missing", "失う装備がなく、みんな 傷ついた"
)
static var EVENT_ENCOUNTER_UP := Vocabulary.word(
	"terms", "event_encounter_up", "この先 %d歩、敵が 増える"
)
static var EVENT_ENCOUNTER_DOWN := Vocabulary.word(
	"terms", "event_encounter_down", "%d歩のあいだ 敵が 減る"
)
static var EVENT_ROUTE_LOST := Vocabulary.word(
	"terms", "event_route_lost", "道を失い、%d歩ぶん 敵が 増える"
)
static var EVENT_SERVICE_LOST := Vocabulary.word(
	"terms", "event_service_lost", "次の宿で 世話を 受けられない"
)
static var EVENT_BIOME_DAMAGED := Vocabulary.word(
	"terms", "event_biome_damaged", "%sの土地が 荒れた"
)
static var EVENT_SHOP_STOCK := Vocabulary.word(
	"terms", "event_shop_stock", "この先のみせで 各どうぐが 1つ増える"
)
static var EVENT_ROUTE_SAFE := Vocabulary.word(
	"terms", "event_route_safe", "この道は %d歩ぶん 安全になった"
)
static var EVENT_SHORTCUT := Vocabulary.word(
	"terms", "event_shortcut", "近道で %d歩ぶん 遭遇を避けられる"
)
static var EVENT_MAP_SEALS := Vocabulary.word(
	"terms", "event_map_seals", "地図に 未知の封 %dつと 安全な道を 記した"
)
static var EVENT_MAP_ROUTE := Vocabulary.word(
	"terms", "event_map_route", "城までの 安全な道を 地図に 記した"
)
static var EVENT_SEALS_KNOWN := Vocabulary.word(
	"terms", "event_seals_known", "封のありかは すべて分かっている"
)
static var EVENT_BIOME_CALMED := Vocabulary.word(
	"terms", "event_biome_calmed", "%sの土地が 鎮まった"
)
static var EVENT_BOSS_INTEL := Vocabulary.word(
	"terms", "event_boss_intel", "主戦で 敵の初動が %d段階 遅くなる"
)
static var EVENT_BOSS_WEAKEN := Vocabulary.word(
	"terms", "event_boss_weaken", "主戦で 主の力が %d段階 下がる"
)
static var EVENT_INN_BONUS := Vocabulary.word(
	"terms", "event_inn_bonus", "次の宿で よく休んだ効果を 得る"
)
static var EVENT_TOWN_SERVICE := Vocabulary.word(
	"terms", "event_town_service", "次の宿で 旅の物資を 受け取れる"
)
static var EVENT_BOON := Vocabulary.word("terms", "event_boon", "%sが %d歩 続く")
static var EVENT_BATTLE_BOON := Vocabulary.word(
	"terms", "event_battle_boon", "旅の助けが 戦いに 効いている"
)
static var EVENT_BOSS_INTEL_ACTIVE := Vocabulary.word(
	"terms", "event_boss_intel_active", "主の初動を 読んだ"
)
static var EVENT_BOSS_WEAKEN_ACTIVE := Vocabulary.word(
	"terms", "event_boss_weaken_active", "主の力が 弱っている"
)
static var EVENT_INN_DENIED := Vocabulary.word(
	"terms", "event_inn_denied", "世話の約束を失い、今夜は 休めなかった。"
)
static var EVENT_INN_SUPPLY := Vocabulary.word(
	"terms", "event_inn_supply", "%s を 受け取った"
)
static var EVENT_INN_RESTED := Vocabulary.word(
	"terms", "event_inn_rested", "よく休み、ひとときの守りを 得た"
)


## 待ちコストを「速さ」に読み替える。
##
## 内部の cost_scale は小さいほど速い（とうぞく 70 / まほうつかい 145）。
## そのまま出すと「数字が大きいほど強そう」という直感と逆になるので、
## 基準から引いて向きを揃える。順序は保たれるので比較の意味は変わらない。
const SPEED_BASE := 200


static func speed(cost_scale: int) -> int:
	return SPEED_BASE - cost_scale


## 能力の呼び名（C-9 の差分表示）。**画面へ直に英字を出さない。**
static var STAT_NAMES := {
	"atk": Vocabulary.word("terms", "stat_atk", "こうげき"),
	"def": Vocabulary.word("terms", "stat_def", "しゅび"),
	"agi": Vocabulary.word("terms", "stat_agi", "すばやさ"),
	"hp": Vocabulary.word("terms", "stat_hp", "たいりょく"),
	"mag": Vocabulary.word("terms", "stat_mag", "まりょく"),
}


static func stat(key: String) -> String:
	return String(STAT_NAMES.get(key, key))
