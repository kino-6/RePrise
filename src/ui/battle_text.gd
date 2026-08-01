extends RefCounted

## 戦闘ログに出る文（S-6a）。
##
## **戦闘のロジックに文を直書きしない。** 言い回しは何度でも直すものなので、
## 直すたびに `battle_system.gd`（決定性とバランスの中心）を触ることになる。
## 触ってはいけない場所を触る理由を作らないために、文だけをここへ出した。
##
## 呼び名（`Terms`）とは別に置く。あちらは「資源」「危険度」のような**語**で、
## こちらは「%sの　こうげき！」のような**文**。混ぜると語が文に埋もれて、
## 語を見直すときに読めなくなる。
##
## **語そのものは `data/vocabulary.json` の `battle` にある。** ここに在るのは
## 名前の付いた入れ物で、右側の既定値はファイルが無いときの受け皿
## （`Terms` と同じ約束）。
##
## キーは文脈から付けてある ―― 技の `match` の中なら技 id、
## そうでなければ関数名。連番だけにすると、直したい行を探せなくなる。
##
## `class_name` は付けない。`preload` で受ける（`ChestReward` などと同じ作法）。

static var BEGIN_TURN_EFFECTS_1 := Vocabulary.word(
	"battle", "begin_turn_effects_1", "%sは毒で%dダメージ！")
static var BEGIN_TURN_EFFECTS_2 := Vocabulary.word(
	"battle", "begin_turn_effects_2", "%sは倒れた…")
static var BEGIN_TURN_EFFECTS_3 := Vocabulary.word(
	"battle", "begin_turn_effects_3", "%sの刃から属性が消えた")
static var BEGIN_TURN_EFFECTS_4 := Vocabulary.word(
	"battle", "begin_turn_effects_4", "%sは眠っている…")
static var BEGIN_TURN_EFFECTS_5 := Vocabulary.word(
	"battle", "begin_turn_effects_5", "%sは装填を終えた")
static var OPEN_BATTLE_SIGNS_1 := Vocabulary.word(
	"battle", "open_battle_signs_1", "見通しの印: %sが有効")
static var OPEN_BATTLE_SIGNS_2 := Vocabulary.word(
	"battle", "open_battle_signs_2", "見通しの印: 目立つ弱点はない")
static var OPEN_BATTLE_SIGNS_3 := Vocabulary.word(
	"battle", "open_battle_signs_3", "獲物の印: %s 残り%d／次は%s")
static var OPEN_BATTLE_SIGNS_4 := Vocabulary.word(
	"battle", "open_battle_signs_4", "次の行動はまだ読めない")
static var OPEN_BATTLE_SIGNS_5 := Vocabulary.word(
	"battle", "open_battle_signs_5", "初弾の印: 最初の一発を装填した")
static var ECHO_ABILITY_SIGN_1 := Vocabulary.word(
	"battle", "echo_ability_sign_1", "%sは奥義を再演できない")
static var ECHO_ABILITY_SIGN_2 := Vocabulary.word(
	"battle", "echo_ability_sign_2", "%sの再演の印！")
static var PERFORM_1 := Vocabulary.word(
	"battle", "perform_1", "%sは%sを使えない（%s）")
static var PERFORM_2 := Vocabulary.word(
	"battle", "perform_2", "%sは続けて奥義を使えない")
static var PERFORM_3 := Vocabulary.word(
	"battle", "perform_3", "%sはもう%sを使えない")
static var PERFORM_4 := Vocabulary.word(
	"battle", "perform_4", "%sの%s！")
static var HEAL_1 := Vocabulary.word(
	"battle", "heal_1", "しかし何も起こらなかった")
static var HEAL_2 := Vocabulary.word(
	"battle", "heal_2", "%sは息を吹き返した！")
static var HEAL_3 := Vocabulary.word(
	"battle", "heal_3", "%sの状態異常が治った")
static var HEAL_4 := Vocabulary.word(
	"battle", "heal_4", "%sのHPが%d回復した")
static var STRIKE_1 := Vocabulary.word(
	"battle", "strike_1", "%sが%sをかばった！")
static var STRIKE_2 := Vocabulary.word(
	"battle", "strike_2", "%sへ狙いを変えた")
static var STRIKE_3 := Vocabulary.word(
	"battle", "strike_3", "%sは見切りの印でかわした！")
static var STRIKE_4 := Vocabulary.word(
	"battle", "strike_4", "%sは身代わりの印で耐えた！")
static var STRIKE_5 := Vocabulary.word(
	"battle", "strike_5", "%sの影が攻撃を受けた")
static var STRIKE_6 := Vocabulary.word(
	"battle", "strike_6", "%sが迎え撃った！ %sに%dダメージ")
static var STRIKE_7 := Vocabulary.word(
	"battle", "strike_7", "%sに%dダメージ！（%d回）%s")
static var STRIKE_8 := Vocabulary.word(
	"battle", "strike_8", "%sに%dダメージ！%s")
static var STRIKE_9 := Vocabulary.word(
	"battle", "strike_9", "%sは目を覚ました！")
static var STRIKE_10 := Vocabulary.word(
	"battle", "strike_10", "%sは毒に侵された！")
static var STRIKE_11 := Vocabulary.word(
	"battle", "strike_11", "%sを倒した！")
static var STRIKE_12 := Vocabulary.word(
	"battle", "strike_12", "%sは影を残し、次の敵へ向かった")
static var FIRE_1 := Vocabulary.word(
	"battle", "fire_1", "%sにも炎が燃え移った（%d）")
static var ICE_1 := Vocabulary.word(
	"battle", "ice_1", "%sの動きが鈍った")
static var BOLT_1 := Vocabulary.word(
	"battle", "bolt_1", "%sの構えが崩れた！")
static var DARK_1 := Vocabulary.word(
	"battle", "dark_1", "%sは魔力を吸い取った（MP+%d）")
static var ELEMENT_TAG_1 := Vocabulary.word(
	"battle", "element_tag_1", "　弱点！")
static var ELEMENT_TAG_2 := Vocabulary.word(
	"battle", "element_tag_2", "　効果が薄い")
static var APPLY_EFFECT_1 := Vocabulary.word(
	"battle", "apply_effect_1", "%sは身を守っている")
static var HASTE_1 := Vocabulary.word(
	"battle", "haste_1", "%sの素早さが上がった！")
static var SLOW_1 := Vocabulary.word(
	"battle", "slow_1", "%sの素早さが下がった！")
static var SLEEP_1 := Vocabulary.word(
	"battle", "sleep_1", "%sは眠ってしまった！")
static var SLEEP_2 := Vocabulary.word(
	"battle", "sleep_2", "%sには効かなかった")
static var DEFEND_UP_1 := Vocabulary.word(
	"battle", "defend_up_1", "%sが%sをかばう態勢に入った")
static var RANDOM_1 := Vocabulary.word(
	"battle", "random_1", "%sは運試しの印で出目を選んだ")
static var EXTRA_TURN_1 := Vocabulary.word(
	"battle", "extra_turn_1", "%sは　もう一度 動ける！")
static var REORDER_1 := Vocabulary.word(
	"battle", "reorder_1", "%sが行動順を書き換えた")
static var CONVERT_1 := Vocabulary.word(
	"battle", "convert_1", "%sは命を魔力へ変えた（MP+%d）")
static var CONVERT_2 := Vocabulary.word(
	"battle", "convert_2", "%sは魔力を命へ変えた（HP+%d）")
static var BANISH_1 := Vocabulary.word(
	"battle", "banish_1", "%sには通じない")
static var BANISH_2 := Vocabulary.word(
	"battle", "banish_2", "%sは戦いから消えた")
static var COUNTER_1 := Vocabulary.word(
	"battle", "counter_1", "%sは迎え撃ちの構え")
static var CHAIN_1 := Vocabulary.word(
	"battle", "chain_1", "%sの祈りが%sに届いた")
static var COVER_ALL_1 := Vocabulary.word(
	"battle", "cover_all_1", "%sが仲間全員をかばった")
static var RUNE_EDGE_1 := Vocabulary.word(
	"battle", "rune_edge_1", "%sの刃に属性が宿った")
static var RELOAD_1 := Vocabulary.word(
	"battle", "reload_1", "%sは弾を装填した")
static var STILLNESS_1 := Vocabulary.word(
	"battle", "stillness_1", "%sは動きを止められた")
static var PULL_TURN_1 := Vocabulary.word(
	"battle", "pull_turn_1", "%sの手番がすぐ来る！")
static var TAME_1 := Vocabulary.word(
	"battle", "tame_1", "%sは戦いから退いた")
static var TAME_2 := Vocabulary.word(
	"battle", "tame_2", "%sは応じない")
static var STEAL_AND_HASTE_1 := Vocabulary.word(
	"battle", "steal_and_haste_1", "%sの次の手番が近づいた")
static var ULTIMATE_STRIKE_1 := Vocabulary.word(
	"battle", "ultimate_strike_1", "しかし対象がいない")
static var REPLAY_MAGIC_1 := Vocabulary.word(
	"battle", "replay_magic_1", "再演できる術式がなかった")
static var REPLAY_MAGIC_2 := Vocabulary.word(
	"battle", "replay_magic_2", "%sを 再演！")
static var PLAY_FATE_CARD_1 := Vocabulary.word(
	"battle", "play_fate_card_1", "剣の札を選んだ")
static var PLAY_FATE_CARD_2 := Vocabulary.word(
	"battle", "play_fate_card_2", "杯の札！ %sのHPが%d回復")
static var PLAY_FATE_CARD_3 := Vocabulary.word(
	"battle", "play_fate_card_3", "鎖の札！ %sの構えが解けた")
static var PLAY_FATE_CARD_4 := Vocabulary.word(
	"battle", "play_fate_card_4", "翼の札！ %sの手番が近づいた")
static var COUNTER_PHALANX_1 := Vocabulary.word(
	"battle", "counter_phalanx_1", "%sは 全員を背に置き、反撃に備えた")
static var SANCTUARY_1 := Vocabulary.word(
	"battle", "sanctuary_1", "%sの 傷と異常が癒えた（%d）")
static var RETURNING_BELL_1 := Vocabulary.word(
	"battle", "returning_bell_1", "%sは 一度だけ踏みとどまれる")
static var RETURNING_BELL_2 := Vocabulary.word(
	"battle", "returning_bell_2", "%sは息を吹き返した！")
static var PHASE_REVEAL_1 := Vocabulary.word(
	"battle", "phase_reveal_1", "なし")
static var PHASE_REVEAL_2 := Vocabulary.word(
	"battle", "phase_reveal_2", "・")
static var PHASE_REVEAL_3 := Vocabulary.word(
	"battle", "phase_reveal_3", "%s　弱点:%s　耐性:%s")
static var PHASE_REVEAL_4 := Vocabulary.word(
	"battle", "phase_reveal_4", "%sの 次の魔法は耐性を抜く")
static var SHADE_PILFER_1 := Vocabulary.word(
	"battle", "shade_pilfer_1", "%sは 空いた手で 次へ回った")
static var TIME_PILFER_1 := Vocabulary.word(
	"battle", "time_pilfer_1", "%sの時間を %sへ渡した")
static var UNYIELDING_LINE_1 := Vocabulary.word(
	"battle", "unyielding_line_1", "%sは 崩れない守りを敷いた")
static var VOW_OF_LIFE_1 := Vocabulary.word(
	"battle", "vow_of_life_1", "味方全員が 一度だけ致死傷に耐える")
static var SHADOW_DOUBLE_1 := Vocabulary.word(
	"battle", "shadow_double_1", "%sの前に 二つの影が立った")
static var HUNTER_MARK_1 := Vocabulary.word(
	"battle", "hunter_mark_1", "%sを狩標にした　次:%s")
static var HUNTER_MARK_2 := Vocabulary.word(
	"battle", "hunter_mark_2", "構えなし")
static var OPPOSITION_EDGE_1 := Vocabulary.word(
	"battle", "opposition_edge_1", "最も通る %s の刃を選んだ")
static var GUARDIAN_PACT_1 := Vocabulary.word(
	"battle", "guardian_pact_1", "%sを 守護獣が癒した（%d）")
static var GUARDIAN_PACT_2 := Vocabulary.word(
	"battle", "guardian_pact_2", "守護獣が 守りと速さを授けた")
static var ASTRAL_BEAST_ARRAY_1 := Vocabulary.word(
	"battle", "astral_beast_array_1", "星獣が 治療と足止めを重ねた")
static var LOCKBREAKER_ROUND_1 := Vocabulary.word(
	"battle", "lockbreaker_round_1", "%sの 構えを撃ち抜いた")
static var FULL_BARRAGE_1 := Vocabulary.word(
	"battle", "full_barrage_1", "%sは 弾倉を空にした")
static var CHAIN_COMPOUND_1 := Vocabulary.word(
	"battle", "chain_compound_1", "%sへ薬を回した（%d）")
static var WISE_FURNACE_1 := Vocabulary.word(
	"battle", "wise_furnace_1", "満ちた力を 攻撃と治療へ転化した")
static var TIME_EXCHANGE_1 := Vocabulary.word(
	"battle", "time_exchange_1", "%sと %sの手番を交換した")
static var ZERO_TIME_FIELD_1 := Vocabulary.word(
	"battle", "zero_time_field_1", "味方の時を揃え、%sは最後尾へ退いた")
static var PACIFY_1 := Vocabulary.word(
	"battle", "pacify_1", "%sは 戦いをやめた")
static var BEAST_PROCESSION_1 := Vocabulary.word(
	"battle", "beast_procession_1", "癒しの獣が %sへ寄り添った")
static var BEAST_PROCESSION_2 := Vocabulary.word(
	"battle", "beast_procession_2", "牙の獣が %sの構えを崩した")
static var BEAST_PROCESSION_3 := Vocabulary.word(
	"battle", "beast_procession_3", "風の獣が %sを先へ運んだ")
static var FATE_CARDS_1 := Vocabulary.word(
	"battle", "fate_cards_1", "二枚の札から よい流れを選んだ")
static var CURTAIN_RETURN_1 := Vocabulary.word(
	"battle", "curtain_return_1", "倒れた味方を 舞台へ戻した")
static var CURTAIN_RETURN_2 := Vocabulary.word(
	"battle", "curtain_return_2", "崩れかけた味方を 立て直した")
static var CURTAIN_RETURN_3 := Vocabulary.word(
	"battle", "curtain_return_3", "%sの見せ場を 奪った")
static var PERFORM_ULTIMATE_1 := Vocabulary.word(
	"battle", "perform_ultimate_1", "しかし奥義は発動しなかった")
static var EXECUTE_BLOW_1 := Vocabulary.word(
	"battle", "execute_blow_1", "%sの必殺！ 急所に入った！")
static var EXECUTE_BLOW_2 := Vocabulary.word(
	"battle", "execute_blow_2", "%sの必殺！")
static var EXECUTE_BLOW_3 := Vocabulary.word(
	"battle", "execute_blow_3", "%sに%dダメージ！")
static var PLAY_AROUND_1 := Vocabulary.word(
	"battle", "play_around_1", "%sはおどけてみせた。何も起こらない")
static var PLAY_AROUND_2 := Vocabulary.word(
	"battle", "play_around_2", "%sの不意打ち！ %sに%dダメージ！")
static var PLAY_AROUND_3 := Vocabulary.word(
	"battle", "play_around_3", "%sはつられて笑った。素早さが下がった！")
static var PLAY_AROUND_4 := Vocabulary.word(
	"battle", "play_around_4", "%sは大笑いしてHPが%d回復した")
static var PLAY_AROUND_5 := Vocabulary.word(
	"battle", "play_around_5", "%sは調子に乗った！ 素早さが上がった！")
static var STEAL_FROM_1 := Vocabulary.word(
	"battle", "steal_from_1", "%sはもう何も持っていない")
static var STEAL_FROM_2 := Vocabulary.word(
	"battle", "steal_from_2", "%sから%sを盗んだ！")
static var STEAL_FROM_3 := Vocabulary.word(
	"battle", "steal_from_3", "%sから%sを%d個盗んだ！")
static var STEAL_FROM_4 := Vocabulary.word(
	"battle", "steal_from_4", "%sから%d%sを盗んだ！")
static var USE_TOOL_1 := Vocabulary.word(
	"battle", "use_tool_1", "%sは%sを使った！")
static var HEAL_HP_1 := Vocabulary.word(
	"battle", "heal_hp_1", "%sのHPが%d回復した")
static var HEAL_MP_1 := Vocabulary.word(
	"battle", "heal_mp_1", "%sのMPが%d回復した")
static var CLEANSE_1 := Vocabulary.word(
	"battle", "cleanse_1", "%sの状態異常が治った")
