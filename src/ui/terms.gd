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
static var SHOP := Vocabulary.word("terms", "shop", "店")
static var SHOP_ITEMS := Vocabulary.word("terms", "shop_items", "道具")
static var SHOP_WEAPONS := Vocabulary.word("terms", "shop_weapons", "武器")
static var SHOP_ARMOR := Vocabulary.word("terms", "shop_armor", "防具")
static var SHOP_ACCESSORIES := Vocabulary.word("terms", "shop_accessories", "装飾品")
static var SHOP_LEAVE := Vocabulary.word("terms", "shop_leave", "立ち去る")
static var SHOP_LEAVE_DESC := Vocabulary.word(
	"terms", "shop_leave_desc", "街道へ戻る。")
static var SHOP_CATEGORY_EMPTY := Vocabulary.word(
	"terms", "shop_category_empty", "この分類の商品はない。")
static var SHOP_STOCK_SUMMARY := Vocabulary.word(
	"terms", "shop_stock_summary", "道具%d　武器%d　防具%d　装飾%d")
static var SHOP_OWNED_COUNT := Vocabulary.word(
	"terms", "shop_owned_count", "所持 %d個")
static var SHOP_OWNED := Vocabulary.word("terms", "shop_owned", "持ち物")
static var SHOP_CATEGORY_HINT := Vocabulary.word(
	"terms", "shop_category_hint", "←→ 分類")
static var TOWN := Vocabulary.word("terms", "town", "町")
static var TOWN_INN_MARK := Vocabulary.word("terms", "town_inn_mark", "宿")
static var TOWN_SHOP_MARK := Vocabulary.word("terms", "town_shop_mark", "店")
static var TOWN_WORK_MARK := Vocabulary.word("terms", "town_work_mark", "仕事")
static var TOWN_PERSON := Vocabulary.word("terms", "town_person", "町の人")
static var TOWN_WORKPLACE := Vocabulary.word("terms", "town_workplace", "町の仕事場")
static var TOWN_SUPPLY_CHEST := Vocabulary.word("terms", "town_supply_chest", "旅人箱")
static var TOWN_CHEST_OPENED := Vocabulary.word(
	"terms", "town_chest_opened", "旅人用の物資箱を開けた。")
static var TOWN_CHEST_REWARD := Vocabulary.word(
	"terms", "town_chest_reward", "%s%d個と%dゴールドを受け取った。")
static var TOWN_CHEST_EMPTY := Vocabulary.word(
	"terms", "town_chest_empty", "物資箱は空になっている。")
static var TOWN_FACILITY_HINT_FALLBACK := Vocabulary.word(
	"terms", "town_facility_hint_fallback", "旅の準備を整えられる。")
static var TOWN_FACILITY_REPEAT_FALLBACK := Vocabulary.word(
	"terms", "town_facility_repeat_fallback", "この仕事場は利用済みだ。")
static var SEAL := Vocabulary.word("terms", "seal", "封")
static var TOWN_TALK_CLOSE := Vocabulary.word(
	"terms", "town_talk_close", "Ｚ／Ｘで戻る")
static var TOWN_FACILITY_USED := Vocabulary.word(
	"terms", "town_facility_used", "%sを利用した。")
static var TOWN_FARM_SUPPLY := Vocabulary.word(
	"terms", "town_farm_supply", "薬草2個と魔力の水1個を受け取った。")
static var TOWN_GUIDE_REVEAL := Vocabulary.word(
	"terms", "town_guide_reveal", "封「%s」の場所を地図に記した。")
static var TOWN_GUIDE_ALL := Vocabulary.word(
	"terms", "town_guide_all", "封の場所はすべて判明している。")
static var TOWN_GUIDE_DONE := Vocabulary.word(
	"terms", "town_guide_done", "封はすべて解けた。残る目標は城だ。")
static var TOWN_STATUS_POISON := Vocabulary.word(
	"terms", "town_status_poison", "毒を受けた仲間が%d人いる。宿で治せる。")
static var TOWN_STATUS_HURT := Vocabulary.word(
	"terms", "town_status_hurt", "傷ついた仲間が%d人いる。宿なら全回復できる。")
static var TOWN_STATUS_READY := Vocabulary.word(
	"terms", "town_status_ready", "一行の体調は万全だ。今は宿を使わなくてよい。")
static var TOWN_SUPPLY_LOW := Vocabulary.word(
	"terms", "town_supply_low", "回復道具は%d個。店の道具を確認しよう。")
static var TOWN_SUPPLY_READY := Vocabulary.word(
	"terms", "town_supply_ready", "回復道具は%d個ある。先へ進む備えはできている。")
static var TOWN_GEAR_EMPTY := Vocabulary.word(
	"terms", "town_gear_empty", "予備の装備はない。店の武器と防具を確認しよう。")
static var TOWN_GEAR_READY := Vocabulary.word(
	"terms", "town_gear_ready", "予備の装備が%d個ある。装備画面で比較できる。")
static var TOWN_ROUTE_KNOWN := Vocabulary.word(
	"terms", "town_route_known", "判明した封は%s、危険度%dの%sにある。")
static var TOWN_ROUTE_UNKNOWN := Vocabulary.word(
	"terms", "town_route_unknown", "封の場所は未確認。町の案内役なら地図に記せる。")
static var TOWN_NEAR := Vocabulary.word("terms", "town_near", "町の近く")
static var EAST := Vocabulary.word("terms", "east", "東")
static var WEST := Vocabulary.word("terms", "west", "西")
static var SOUTH := Vocabulary.word("terms", "south", "南")
static var NORTH := Vocabulary.word("terms", "north", "北")
static var CAVE := Vocabulary.word("terms", "cave", "洞")
static var CASTLE := Vocabulary.word("terms", "castle", "城")
static var GATE := Vocabulary.word("terms", "gate", "門")
static var WORLD_MAP := Vocabulary.word("terms", "world_map", "世界地図")
static var MAP_LEGEND := Vocabulary.word("terms", "map_legend", "地図記号")
static var MAP_CURRENT := Vocabulary.word("terms", "map_current", "現在地")
static var MAP_TOWN := Vocabulary.word("terms", "map_town", "町")
static var MAP_SEAL := Vocabulary.word("terms", "map_seal", "判明した封")
static var MAP_CASTLE := Vocabulary.word("terms", "map_castle", "主の城")
static var MAP_SAFE_ROUTE := Vocabulary.word("terms", "map_safe_route", "記された道")
static var MAP_KNOWN_SEALS := Vocabulary.word(
	"terms", "map_known_seals", "判明した封 %d / %d")
static var MAP_REVEAL_NOTE := Vocabulary.word(
	"terms", "map_reveal_note", "読み解いた地図が 城への道を照らす。")
static var MAP_UNKNOWN_NOTE := Vocabulary.word(
	"terms", "map_unknown_note", "言い伝えを得ると 封の場所が増える。")
static var MAP_CLOSE_HINT := Vocabulary.word(
	"terms", "map_close_hint", "Ｚ／Ｘで戻る")
static var MAP_MENU := Vocabulary.word("terms", "map_menu", "地図")
static var MAP_MENU_LINES: Array[String] = [
	Vocabulary.word("terms", "map_menu_line_1", "大陸、町、主の城を確認する。"),
	Vocabulary.word("terms", "map_menu_line_2", "判明した封と安全な道も確認できる。"),
]

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
static var RUNS_TOTAL := Vocabulary.word("terms", "runs_total", "%d回の遠征")

# --- 能力・コスト ---
## 行動の速さ。内部は「待ちコスト」（小さいほど速い）だが、
## 画面では大きいほど速い数字に直して見せる（speed() を通すこと）。
static var SPEED := Vocabulary.word("terms", "speed", "速さ")

## そうび回り（C-9 / C-10）。
##
## `data/vocabulary.json` にまだ書かれていなくても既定へ落ちるので、
## 語の見直しは後からできる（`Vocabulary.word` の約束）。
static var BEST_GEAR := Vocabulary.word("terms", "best_gear", "最強装備")
static var EQUIP_NOW := Vocabulary.word("terms", "equip_now", "今すぐ装備する")
static var TO_BAG := Vocabulary.word("terms", "to_bag", "持ち物へ入れる")
static var GOT_GEAR := Vocabulary.word("terms", "got_gear", "%sを見つけた")
static var TAKES_OFF := Vocabulary.word("terms", "takes_off", "外れる")
static var CANNOT_EQUIP := Vocabulary.word("terms", "cannot_equip", "装備できない")
static var CAN_EQUIP := Vocabulary.word("terms", "can_equip", "装備できる")
static var GEAR_FIT := Vocabulary.word("terms", "gear_fit", "装備可能")
static var BATTLE_ONLY := Vocabulary.word("terms", "battle_only", "戦闘中のみ使用可能")
## 戦闘開始の一拍。BattleView に直書きすると、遭遇文を直すたび全画面を探すことになる。
static var BATTLE_ENEMY_APPEARED := Vocabulary.word(
	"terms", "battle_enemy_appeared", "%sが行く手を塞いだ！")
static var BATTLE_ENEMIES_APPEARED := Vocabulary.word(
	"terms", "battle_enemies_appeared", "%sたちが行く手を塞いだ！")
static var BATTLE_ENEMY_FIRST := Vocabulary.word(
	"terms", "battle_enemy_first", "敵が先に動く！")
static var BATTLE_VANGUARD_FIRST := Vocabulary.word(
	"terms", "battle_vanguard_first", "敵の先陣が先に動く！")
static var NO_ONE_CAN := Vocabulary.word(
	"terms", "no_one_can", "誰も装備できない")
## 戦闘コマンドに添えるコスト。こちらは「この一手で何待つか」なので待ちのまま出す。
static var WAIT := Vocabulary.word("terms", "wait", "待")
static var MASTERY := Vocabulary.word("terms", "mastery", "熟練度")
static var RANK := Vocabulary.word("terms", "rank", "段")
static var PRICE := Vocabulary.word("terms", "price", "必要")
static var MAXED := Vocabulary.word("terms", "maxed", "最大")

# --- 拠点の見出し ---
static var PARTY := Vocabulary.word("terms", "party", "編成")
static var UPGRADE := Vocabulary.word("terms", "upgrade", "アップグレード")
static var RUN_RULES := Vocabulary.word("terms", "run_rules", "旅の規律")
static var DIFFICULTY := Vocabulary.word("terms", "difficulty", "難しさ")
static var PACE := Vocabulary.word("terms", "pace", "旅の速さ")
static var CONTRACT := Vocabulary.word("terms", "contract", "誓約")
static var CONTRACT_LIMIT := Vocabulary.word(
	"terms", "contract_limit", "誓約は %dつまで。")
static var REWARD_RATE := Vocabulary.word("terms", "reward_rate", "資源倍率")
static var SHOP_CLOSED_BY_CONTRACT := Vocabulary.word(
	"terms", "shop_closed_by_contract", "誓約により 商人は いない。")
static var ESCAPE_CLOSED_BY_CONTRACT := Vocabulary.word(
	"terms", "escape_closed_by_contract", "退路を断つ 誓約がある！")
static var DEPART := Vocabulary.word("terms", "depart", "出撃する")

# --- 銀の砦 ---
## 拠点は現在の世界設定を短く反復する場所。操作説明も含め、View に直書きしない。
static var STRONGHOLD_BODY_LEVEL := Vocabulary.word(
	"stronghold", "body_level", "借りる体 Lv1")
static var STRONGHOLD_DEPART_TITLE := Vocabulary.word(
	"stronghold", "depart_title", "銀の門を開く")
static var STRONGHOLD_PARTY_CAPACITY := Vocabulary.word(
	"stronghold", "party_capacity", "銀の門をくぐるのは%d人。")
static var STRONGHOLD_PARTY_PICK := Vocabulary.word(
	"stronghold", "party_pick", "銀の門をくぐる一行を選ぶ")
static var STRONGHOLD_PARTY_MARK := Vocabulary.word(
	"stronghold", "party_mark", "●が渡る仲間。Ｚで入れ替える。")
static var STRONGHOLD_PARTY_REST := Vocabulary.word(
	"stronghold", "party_rest", "砦に残る仲間は熟練を得ない。")
static var STRONGHOLD_LEARNED_TITLE := Vocabulary.word(
	"stronghold", "learned_title", "砦に残る技")
static var STRONGHOLD_LEARNED_EMPTY := Vocabulary.word(
	"stronghold", "learned_empty", "まだ砦へ帰った技はない。")
static var STRONGHOLD_LEARNED_HELP := Vocabulary.word(
	"stronghold", "learned_help", "世界で覚えた技は次の体にも残る。")
static var STRONGHOLD_CONTROLS := Vocabulary.word(
	"stronghold", "controls", "↑↓ 選択　Ｚ 決定　Ｘ 戻る")
static var STRONGHOLD_DEPART_CONTROLS := Vocabulary.word(
	"stronghold", "depart_controls", "↑↓ 項目　←→ 変更　Ｚ 出撃　Ｘ 戻る")
static var STRONGHOLD_DEPART_PREP := Vocabulary.word(
	"stronghold", "depart_prep", "出撃前に 編成と 旅の規律を 確かめる。")
static var STRONGHOLD_WORLD_ONCE := Vocabulary.word(
	"stronghold", "world_once", "門が閉じれば 同じ世界へは 二度と届かない。")

# --- 設定 ---
static var AUTO_ITEMS := Vocabulary.word("terms", "auto_items", "オートの道具")
static var AUTO_ITEMS_ON := Vocabulary.word(
	"terms", "auto_items_on", "ピンチ時に使う")
static var AUTO_ITEMS_OFF := Vocabulary.word(
	"terms", "auto_items_off", "使わない")
static var AUTO_ITEMS_HINT := Vocabulary.word(
	"terms", "auto_items_hint", "許可すると 蘇生・瀕死回復・状態回復にだけ使う")
static var AUTO_ITEMS_SHORT_ON := Vocabulary.word(
	"terms", "auto_items_short_on", "道具○")
static var AUTO_ITEMS_SHORT_OFF := Vocabulary.word(
	"terms", "auto_items_short_off", "道具×")

# --- セーブ消去 ---
static var SAVE_ERASE := Vocabulary.word("terms", "save_erase", "セーブを消す")
static var SAVE_ERASE_QUESTION := Vocabulary.word(
	"terms", "save_erase_question", "セーブを消しますか？"
)
static var SAVE_ERASE_WARNING := Vocabulary.word(
	"terms", "save_erase_warning", "戦績・資源・熟練・中断記録がすべて消える"
)
static var SAVE_ERASE_CANCEL := Vocabulary.word("terms", "save_erase_cancel", "戻る")
static var SAVE_ERASE_EXECUTE := Vocabulary.word(
	"terms", "save_erase_execute", "すべて消す"
)
static var SAVE_ERASE_HINT := Vocabulary.word(
	"terms", "save_erase_hint", "Ｚ 決定　Ｘ 戻る"
)
static var SAVE_ERASE_DONE := Vocabulary.word(
	"terms", "save_erase_done", "セーブを消しました"
)
static var SAVE_ERASE_FAILED := Vocabulary.word(
	"terms", "save_erase_failed", "セーブを消せませんでした"
)
static var SAVE_ERASE_NONE := Vocabulary.word(
	"terms", "save_erase_none", "消せるデータがない"
)
static var SAVE_ERASE_TITLE_ONLY := Vocabulary.word(
	"terms", "save_erase_title_only", "タイトルから"
)

# --- ランの放棄 ---
static var RUN_ABANDON := Vocabulary.word("terms", "run_abandon", "ランを中止する")
static var RUN_ABANDON_FIRST_QUESTION := Vocabulary.word(
	"terms", "run_abandon_first_question", "このランを中止しますか？"
)
static var RUN_ABANDON_FIRST_WARNING := Vocabulary.word(
	"terms", "run_abandon_first_warning", "レベル・装備・ゴールドを失う"
)
static var RUN_ABANDON_FINAL_QUESTION := Vocabulary.word(
	"terms", "run_abandon_final_question", "本当に砦へ戻りますか？"
)
static var RUN_ABANDON_FINAL_WARNING := Vocabulary.word(
	"terms", "run_abandon_final_warning", "この世界には二度と戻れない"
)
static var RUN_ABANDON_CANCEL := Vocabulary.word("terms", "run_abandon_cancel", "戻る")
static var RUN_ABANDON_NEXT := Vocabulary.word(
	"terms", "run_abandon_next", "中止する"
)
static var RUN_ABANDON_EXECUTE := Vocabulary.word(
	"terms", "run_abandon_execute", "ランを中止して砦へ"
)
static var RUN_ABANDON_HINT := Vocabulary.word(
	"terms", "run_abandon_hint", "確認は2回必要　Ｘ 戻る"
)
static var RUN_ABANDON_IN_RUN := Vocabulary.word(
	"terms", "run_abandon_in_run", "ラン中のみ"
)
static var RUN_ABANDON_RESULT := Vocabulary.word("terms", "run_abandon_result", "帰還")
static var RUN_ABANDON_CHRONICLE := Vocabulary.word(
	"terms", "run_abandon_chronicle", "一行は危険度%dで遠征を中止し、砦へ帰還した。"
)

# --- 任意イベント ---
static var EVENT_CLOSE := Vocabulary.word("terms", "event_close", "Ｚ 閉じる")
static var EVENT_CLOSE_CHOICE := Vocabulary.word(
	"terms", "event_close_choice", "閉じる"
)
static var EVENT_OTHER_COUNT := Vocabulary.word(
	"terms", "event_other_count", "他%d"
)
static var EVENT_STORY_COST := Vocabulary.word(
	"terms", "event_story_cost", "代償"
)
static var EVENT_STORY_KEEP := Vocabulary.word(
	"terms", "event_story_keep", "守る"
)
static var EVENT_STORY_LOSE := Vocabulary.word(
	"terms", "event_story_lose", "失う"
)
static var EVENT_PAY := Vocabulary.word("terms", "event_pay", "代償")
static var EVENT_RISK := Vocabulary.word("terms", "event_risk", "危険")
static var EVENT_GAIN := Vocabulary.word("terms", "event_gain", "得る")
static var EVENT_MISSING := Vocabulary.word("terms", "event_missing", "不足")
static var EVENT_CONTINUE := Vocabulary.word(
	"terms", "event_continue", "Ｚ 続ける"
)
static var EVENT_CONTINUE_CHOICE := Vocabulary.word(
	"terms", "event_continue_choice", "話を続ける"
)
static var EVENT_CONFIRM_HINT := Vocabulary.word(
	"terms", "event_confirm_hint", "Ｚ 決定　Ｘ 見送る"
)
static var EVENT_DEFER_SUMMARY := Vocabulary.word(
	"terms", "event_defer_summary", "保留 → 再訪できる"
)
static var EVENT_DEFER_DETAIL := Vocabulary.word(
	"terms", "event_defer_detail", "今は立ち去る。後で選び直せる。"
)
static var EVENT_DEFER_OUTCOME := Vocabulary.word(
	"terms", "event_defer_outcome", "今は手を出さず離れた。戻れば、まだ選べる。"
)
static var EVENT_UNRESOLVED := Vocabulary.word(
	"terms", "event_unresolved", "何も起きなかった。この選択肢は未解決だ。"
)
static var EVENT_TASK_PREVIEW_FIGHT := Vocabulary.word(
	"terms", "event_task_preview_fight", "この後: 敵を退ける"
)
static var EVENT_TASK_PREVIEW_TOWN := Vocabulary.word(
	"terms", "event_task_preview_town", "この後: 町で関係者に話す"
)
static var EVENT_TASK_PREVIEW_CAVE := Vocabulary.word(
	"terms", "event_task_preview_cave", "この後: 洞を実際に調べる"
)
static var EVENT_TASK_PREVIEW_TRAVEL := Vocabulary.word(
	"terms", "event_task_preview_travel", "この後: 街道を%d歩進む"
)
static var EVENT_TASK_STARTED := Vocabulary.word(
	"terms", "event_task_started", "目的: %s"
)
static var EVENT_TASK_OBJECTIVE_FIGHT := Vocabulary.word(
	"terms", "event_task_objective_fight", "イベントの敵を退ける"
)
static var EVENT_TASK_OBJECTIVE_TOWN := Vocabulary.word(
	"terms", "event_task_objective_town", "町の関係者に話す"
)
static var EVENT_TASK_OBJECTIVE_CAVE := Vocabulary.word(
	"terms", "event_task_objective_cave", "箱か次の階を調べる"
)
static var EVENT_TASK_OBJECTIVE_TRAVEL := Vocabulary.word(
	"terms", "event_task_objective_travel", "現場を進む %d/%d歩"
)
static var EVENT_TASK_DONE_FIGHT := Vocabulary.word(
	"terms", "event_task_done_fight", "敵を退け、選んだ行動をやり遂げた。"
)
static var EVENT_TASK_DONE_TOWN := Vocabulary.word(
	"terms", "event_task_done_town", "町の関係者と話し、必要な手を打った。"
)
static var EVENT_TASK_DONE_CAVE := Vocabulary.word(
	"terms", "event_task_done_cave", "洞を調べ、選んだ行動をやり遂げた。"
)
static var EVENT_TASK_DONE_TRAVEL := Vocabulary.word(
	"terms", "event_task_done_travel", "現場を抜けるまで行動を続けた。"
)
static var EVENT_TASK_RETRY := Vocabulary.word(
	"terms", "event_task_retry", "目的は未完了。現場へ戻れば再挑戦できる。"
)
static var ELITE_EVENT_TITLE := Vocabulary.word(
	"terms", "elite_event_title", "%sの群れ")
static var ELITE_EVENT_ACTOR := Vocabulary.word(
	"terms", "elite_event_actor", "格上の魔物")
static var ELITE_EVENT_RULE := Vocabulary.word(
	"terms", "elite_event_rule", "型は「%s」。%s")
static var ELITE_EVENT_FLAVOR := Vocabulary.word(
	"terms", "elite_event_flavor", "街道へ戻れば、戦わずに先へ進める。")
static var ELITE_EVENT_FIGHT := Vocabulary.word(
	"terms", "elite_event_fight", "戦いを挑む")
static var ELITE_EVENT_LEAVE := Vocabulary.word(
	"terms", "elite_event_leave", "街道へ戻る")
static var ELITE_REWARD_TITLE := Vocabulary.word(
	"terms", "elite_reward_title", "格上への勝利")
static var ELITE_REWARD_CAUSE := Vocabulary.word(
	"terms", "elite_reward_cause", "戦利品を一つ選べる。")
static var ELITE_REWARD_GEAR := Vocabulary.word(
	"terms", "elite_reward_gear", "装備を選ぶ")
static var ELITE_REWARD_SUPPLY := Vocabulary.word(
	"terms", "elite_reward_supply", "物資と手当てを選ぶ")
static var ELITE_REWARD_ROUTE := Vocabulary.word(
	"terms", "elite_reward_route", "地図と安全な道を選ぶ")
static var ELITE_REWARD_CONFIRM := Vocabulary.word(
	"terms", "elite_reward_confirm", "Ｚ 報酬を一つ選ぶ")
static var MAP_ELITE := Vocabulary.word("terms", "map_elite", "格上の敵")
## 欲が呼ぶ格上（R-3）。**予告は湧く前に出す**ので、この 2 行は順に読まれる。
static var GREED_WARNING := Vocabulary.word(
	"terms", "greed_warning", "この階を これ以上 あさると、格上が 気づく。")
static var GREED_SUMMONED := Vocabulary.word(
	"terms", "greed_summoned", "%s が 気づいた。")
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
	"terms", "event_shop_stock", "この先の店で各道具が1個増える"
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
	"terms", "event_inn_rested", "よく休み、ひとときの守りを得た"
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
	"atk": Vocabulary.word("terms", "stat_atk", "攻撃"),
	"def": Vocabulary.word("terms", "stat_def", "守備"),
	"agi": Vocabulary.word("terms", "stat_agi", "素早さ"),
	"hp": Vocabulary.word("terms", "stat_hp", "体力"),
	"mag": Vocabulary.word("terms", "stat_mag", "魔力"),
}


static func stat(key: String) -> String:
	return String(STAT_NAMES.get(key, key))

## 画面の表示語（D-7）。**View に直書きしない。**
##
## 直書きしていると、語を見直すたびに全 View を grep することになる。
## `data/vocabulary.json` に無くても既定へ落ちるので、差し替えは後からできる。
static var SLOT_WEAPON := Vocabulary.word("terms", "slot_weapon", "武器")
static var SLOT_ARMOR := Vocabulary.word("terms", "slot_armor", "防具")
static var SLOT_ACCESSORY := Vocabulary.word("terms", "slot_accessory", "装飾品")
static var MENU_ITEMS := Vocabulary.word("terms", "menu_items", "道具")
static var MENU_STATUS := Vocabulary.word("terms", "menu_status", "強さ")
static var MENU_EQUIP := Vocabulary.word("terms", "menu_equip", "装備")
static var MENU_JOB := Vocabulary.word("terms", "menu_job", "転職")
static var MENU_SETTINGS := Vocabulary.word("terms", "menu_settings", "設定")
static var MENU_SUSPEND := Vocabulary.word("terms", "menu_suspend", "中断")
static var MENU_ESCAPE := Vocabulary.word("terms", "menu_escape", "脱出")
static var MENU_CLOSE := Vocabulary.word("terms", "menu_close", "閉じる")
static var BAG := Vocabulary.word("terms", "bag", "持ち物")
static var TAKE_OFF := Vocabulary.word("terms", "take_off", "外す")
static var SWAP := Vocabulary.word("terms", "swap", "付け替える")
static var STAT_ATK_LABEL := Vocabulary.word("terms", "stat_atk_label", "攻撃")
static var STAT_MAG_LABEL := Vocabulary.word("terms", "stat_mag_label", "魔力")
static var STAT_DEF_LABEL := Vocabulary.word("terms", "stat_def_label", "守備")
static var STAT_AGI_LABEL := Vocabulary.word("terms", "stat_agi_label", "素早さ")
static var OWN_LEVEL := Vocabulary.word("terms", "own_level", "本人のレベル")
static var JOB_MASTERY := Vocabulary.word("terms", "job_mastery", "職業の熟練")
static var POISON := Vocabulary.word("terms", "poison", "毒")
static var BAG_EMPTY := Vocabulary.word("terms", "bag_empty", "持ち物は空です。")
static var NO_ITEMS := Vocabulary.word("terms", "no_items", "道具を持っていない")
static var HINT_LIST := Vocabulary.word("terms", "hint_list", "↑↓ 選択　Ｚ 決定　Ｘ 戻る")
static var NOTHING_EQUIPPED := Vocabulary.word("terms", "nothing_equipped", "何も装備していない")
static var NO_BETTER_GEAR := Vocabulary.word("terms", "no_better_gear", "これ以上強くならない")
static var CANNOT_USE_HERE := Vocabulary.word("terms", "cannot_use_here", "ここでは使えない")
static var CANNOT_USE_ON_FALLEN := Vocabulary.word("terms", "cannot_use_on_fallen", "倒れた仲間には使えない")
static var CMD_FIGHT := Vocabulary.word("terms", "cmd_fight", "戦う")
static var CMD_SPELL := Vocabulary.word("terms", "cmd_spell", "魔法")
static var CMD_SKILL := Vocabulary.word("terms", "cmd_skill", "特技")
static var CMD_GUARD := Vocabulary.word("terms", "cmd_guard", "防御")
static var CMD_ESCAPE := Vocabulary.word("terms", "cmd_escape", "逃げる")
static var ABILITY_WAIT_REMAIN := Vocabulary.word(
	"terms", "ability_wait_remain", "待ち / 残り")
static var ABILITY_CANNOT_USE := Vocabulary.word(
	"terms", "ability_cannot_use", "使用不可: %s")
static var REASON_NO_ABILITY := Vocabulary.word(
	"terms", "reason_no_ability", "技のデータがない")
static var REASON_MP := Vocabulary.word("terms", "reason_mp", "MPが足りない")
static var REASON_RELOADING := Vocabulary.word(
	"terms", "reason_reloading", "装填中は攻撃か防御のみ")
static var REASON_USED := Vocabulary.word(
	"terms", "reason_used", "この戦闘ではもう使えない")
static var REASON_NO_FALLEN := Vocabulary.word(
	"terms", "reason_no_fallen", "倒れた仲間がいない")
static var REASON_NO_TARGET := Vocabulary.word(
	"terms", "reason_no_target", "対象がいない")
static var REASON_PICK_CASTING := Vocabulary.word(
	"terms", "reason_pick_casting", "構えている敵を選ぶ")
static var REASON_NO_CASTING := Vocabulary.word(
	"terms", "reason_no_casting", "構えている敵がいない")
static var REASON_FULL_MP := Vocabulary.word(
	"terms", "reason_full_mp", "MPが満ちていない")
static var REASON_NO_REPLAY := Vocabulary.word(
	"terms", "reason_no_replay", "再演できる魔法がまだない")
static var REASON_TWO_SPELLS := Vocabulary.word(
	"terms", "reason_two_spells", "攻撃魔法を2つ習得していない")
static var REASON_BOSS := Vocabulary.word("terms", "reason_boss", "主には通じない")
static var REASON_ALERT := Vocabulary.word(
	"terms", "reason_alert", "相手がまだ警戒している")
static var REASON_NO_PACIFY := Vocabulary.word(
	"terms", "reason_no_pacify", "弱った通常敵がいない")
static var NONE := Vocabulary.word("terms", "none", "なし")
static var RESULT_SURVIVED := Vocabulary.word("terms", "result_survived", "生還")
static var RESULT_WIPED := Vocabulary.word("terms", "result_wiped", "全滅")
static var NO_CHANGE := Vocabulary.word("terms", "no_change", "変化なし")
static var MASTERY_LEARNED := Vocabulary.word("terms", "mastery_learned", "習得")
static var MASTERY_REMAIN := Vocabulary.word("terms", "mastery_remain", "残り%d")
static var CURRENT_JOB_SKILLS := Vocabulary.word(
	"terms", "current_job_skills", "現職の技 %d")
static var CURRENT_JOB_SKILLS_HELP := Vocabulary.word(
	"terms", "current_job_skills_help",
	"現職技は常設。下2枠に過去職を足す。")
static var INHERIT_SKILL_SLOT := Vocabulary.word(
	"terms", "inherit_skill_slot", "継承技 %d")
static var INHERIT_SIGN_SLOT := Vocabulary.word(
	"terms", "inherit_sign_slot", "継承印 %d")
static var STRONGHOLD_LOADOUT_HINT := Vocabulary.word(
	"terms", "stronghold_loadout_hint", "→ 継承技と継承印")
static var SOLD_OUT := Vocabulary.word("terms", "sold_out", "売り切れ")
static var BOUGHT := Vocabulary.word("terms", "bought", "%sを購入した")
static var TURN_ORDER := Vocabulary.word("terms", "turn_order", "順")
static var RESULT_NEXT := Vocabulary.word(
	"terms", "result_next", "Ｚキーで次の旅へ")

## 出撃時の選択（E-3）。**選べるのに選ぶ場所が無い**状態を無くすための行。
static var DEPART_SUPPLY := Vocabulary.word("terms", "depart_supply", "支給品")
static var DEPART_FOCUS := Vocabulary.word("terms", "depart_focus", "店の品揃え")
static var DEPART_SIGN := Vocabulary.word("terms", "depart_sign", "継承印")
static var DEPART_TOOL := Vocabulary.word("terms", "depart_tool", "戦具")
static var ITEM_REUSABLE := Vocabulary.word("terms", "item_reusable", "常用")
static var ITEM_TOOL_FALLBACK := Vocabulary.word("terms", "item_tool_fallback", "戦具")
static var ITEM_EQUIPPED := Vocabulary.word("terms", "item_equipped", "装備")
static var ITEM_EQUIPPED_PREFIX := Vocabulary.word(
	"terms", "item_equipped_prefix", "装：%s")
static var ITEM_BATTLE_ONLY := Vocabulary.word(
	"terms", "item_battle_only", "これは戦闘中のみ使用可能。")
static var ITEM_USED_UP := Vocabulary.word(
	"terms", "item_used_up", "この戦闘ではもう力を引き出せない")
