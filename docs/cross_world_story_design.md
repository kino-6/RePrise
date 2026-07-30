# 世界をまたぐ連作シナリオ

## 目的

一ランの物語は [story_arc_design.md](story_arc_design.md) の六拍で完結する。
この文書が定義するのは、その上へ薄く重ねる**複数ランの連作**である。

各世界を長編の通過点にはしない。訪れた世界にはその世界だけの人物、約束、結末があり、
連作は帰還後に残った一文、身体の癖、名、傷、砦へ来た例外的な人物だけを拾う。

原本は [cross_world_arcs.json](../data/cross_world_arcs.json)。全十二型に四段階、
三つの決着、三種類の失敗継続を持たせている。

## 前提の更新

従来の「世界どうしに繋がりはない」は、次のように狭める。

> 世界は地理、国家、通常の歴史を共有せず、世界から世界へ直接移動できない。
> ただし銀の砦を通過した記録、身体が覚えた技、帰還の事故、帝国の世界間技術、
> 狭間からの信号は、別世界で反響することがある。

これにより「同じ世界へ二度と戻れない」は維持する。以前の町を再訪するのではなく、
以前の選択が別の世界で異なる形を取る。

## 二層構造

```text
一つの世界
  出会い → 共同行動 → 反転 → 選択 → 主戦 → 後日談
     └──────── 一ランで必ず意味を閉じる ────────┘

世界横断
  種を残す世界 → 反響する世界 → 真相が反転する世界 → 決着
       1ラン目        2～3ラン目          3～5ラン目       砦または決着世界
```

同時に進める世界横断シナリオは一型だけ。一世界へ出す横断ビートも一件までとする。
これを守らないと、現在の人物より昔の伏線のほうが画面を占有する。

## 四段階

| 段階 | ID | 役割 | 失敗した場合 |
|---|---|---|---|
| 種 | `seed` | 一文、技、名、人物などを砦へ残す | 敗北の戦記に別形式で残す |
| 反響 | `echo` | 無関係な別世界で同じ印を見せる | 痕跡、道標、敵の行動から知る |
| 反転 | `reversal` | 反復の理由と代償を明かす | 情報を欠けさせたまま決着へ運ぶ |
| 決着 | `reckoning` | 三択と固有後日談を出す | 終了させず、次の世界で再試行する |

`seed`から`reversal`は見逃しや全滅でも先へ進める。`reckoning`だけは自動決着させない。
選択を出せなかった場合、傷や遅延を記録して次のランへ持ち越す。

## 永続状態

セーブへ追加する状態は、生成済みの一型と進行だけに絞る。

```json
{
  "schema": 1,
  "active_id": "undelivered_reply",
  "phase_index": 1,
  "skin": {
    "title": "宛先のない返書",
    "anchor_name": "ユラ",
    "motif": "青い返書",
    "origin_name": "鈴雨の町"
  },
  "started_run": 4,
  "next_due_run": 6,
  "setbacks": ["run_lost"],
  "history": [
    {"phase": "seed", "run": 4, "result": "seen"}
  ],
  "completed": {
    "chronicle_margins": "double_ledger"
  },
  "recent_ids": ["chronicle_margins"]
}
```

- `active_id`と`skin`は選出時に確定して即保存する。
- `phase_index`は表示前でなく、表示または失敗継続の確定後に進める。
- `setbacks`は結末文脈へ使い、物語を打ち切る条件にはしない。
- `completed`は結末IDだけを残す。長文をセーブへ複製しない。
- 古いセーブでは空の状態へ落とす。導入時は`SAVE_VERSION`を上げる。

この更新は、失うものと残るものの境界を守るため
`GameState.end_run()`へ集約する。世界側から恒久状態を直接書き換えない。

## 選出と決定性

1. 進行中の型がなければ、選出条件を満たす候補だけを集める。
2. `DetRng`の専用系列で重み付き抽選する。
3. 型、四つの表示語、次の発生ランを確定し、その場で保存する。
4. 一つ終えた後は`cooldown_runs`の間、新しい連作を始めない。
5. `recent_ids`にある型は候補から外し、同じ型の連続を防ぐ。

乱数系列は用途ごとに分ける。

```text
meta_arc_select
meta_arc_skin
meta_arc_schedule
meta_arc_site
```

既存の地形、敵編成、世界内六拍へ使う乱数を消費してはならない。横断シナリオを
追加しても同じシードの地形が変わらないことをテストで守る。

## 配置

カタログの`placement`を、現在の世界の候補地点へ結ぶ。

| placement | 接続先 |
|---|---|
| `run_result` | `end_run()`が作った戦記の後 |
| `town_low` | 危険度一～四の町 |
| `town_mid` | 危険度四～七の町 |
| `cave_mid` | 危険度四～七の洞 |
| `castle_pre_boss` | 主戦へ入る直前 |
| `stronghold` | 帰還後、次の出撃操作を受け付ける前 |

世界内六拍と同じ場所へ重なった場合は、世界内の物語を先に表示する。
横断ビートは同じ場所の再訪時か帰還時へ送る。横断シナリオのために町、洞、城の
配置を動かしてはならない。

## カタログ形式

各型は次を持つ。

```json
{
  "id": "undelivered_reply",
  "theme": "届かなかった言葉と継承",
  "carrier": "chronicle",
  "selection": {
    "weight": 10,
    "min_runs_attempted": 2,
    "min_completed_arcs": 0
  },
  "span": {
    "min_runs": 4,
    "max_runs": 6,
    "cooldown_runs": 3
  },
  "promise": "構造上固定する約束",
  "reversal": "構造上固定する真相",
  "skin": {
    "title": ["候補を三つ以上"],
    "anchor_name": ["候補を三つ以上"],
    "motif": ["候補を三つ以上"],
    "origin_name": ["候補を三つ以上"]
  },
  "beats": [
    {
      "id": "seed",
      "phase": "seed",
      "placement": "run_result",
      "line": "通常表示",
      "loss_line": "全滅または未到達時の表示"
    }
  ],
  "choices": [
    {
      "id": "broadcast",
      "label": "全世界へ流す",
      "immediate_cost": "今払う代償",
      "preserves": "守れるもの",
      "sacrifices": "失うもの",
      "ending_id": "many_receivers",
      "result_flags": ["reply_broadcast"]
    }
  ],
  "endings": {
    "many_receivers": {
      "tone": "bittersweet",
      "line": "固有の後日談",
      "chronicle_line": "戦記へ残す短文"
    }
  },
  "fallback_choice": "rewrite_song",
  "fail_forward": [
    {"when": "run_lost", "change": "結末へ残す変化"}
  ]
}
```

`result_flags`は物語上の恒久フラグで、数値報酬ではない。能力や敵編成へ影響させる場合は
別のScript側対応表へ置き、`tests/balance.gd`で測る。JSONへ倍率を直書きしない。

## 十二型

| ID | 運ぶもの | 中盤の反転 | 決着 |
|---|---|---|---|
| `undelivered_reply` | 戦記に混じった返書 | 個人の返事は世界間の避難信号 | 全世界／一人／歌へ変える |
| `name_rebellion` | 機械が選んだ名前 | 名前は全機械の停止符号 | 使用／破壊／機械へ返す |
| `remembered_technique` | 身体が覚えた技 | 英雄の型は門を閉じる処刑技 | 完成／改変／封印 |
| `silver_homing_beast` | 同じ仕草の魔獣 | 魔獣は帝国の生体追跡標 | 切断／偽装／魔獣へ返す |
| `empty_fifth_seat` | 名簿にない同行者の痕跡 | 記憶と技が現在の仲間へ分散 | 復元／分散したまま／記録 |
| `chronicle_margins` | 戦記の余白の訂正 | 砦が勝利を美談へ整えていた | 真実／英雄譚／二冊 |
| `same_named_towns` | 別世界に現れる同じ町名 | 戦記の名が新世界へ染み出す | 消去／複数を承認／正史化 |
| `lords_testament` | 異なる主の遺言 | 主は砦からの流入も封じていた | 討伐継続／交渉／門を閉じる |
| `drifting_imperial_fleet` | 艦章と漂着部隊 | 全部隊は砕けた同一艦隊 | 反乱／撃沈／非戦闘員救助 |
| `child_of_the_fortress` | 砦へ来た子ども | 子どもが門を不安定にする | 故郷／砦／選んだ新世界 |
| `repeated_execution` | 同じ形の処刑 | 砦が悲劇の強い世界を選別 | 代償分配／選別停止／公表 |
| `world_that_did_not_close` | 複数戦記の救難信号 | 過去の記録が狭間で世界化 | 回収／再始動／完全に閉じる |

`world_that_did_not_close`は三型以上の完了後にだけ候補へ入る総決算型である。
過去の固有名詞をそのまま再登場させず、完了フラグに対応する短い反響を一つか二つ選ぶ。

## 失敗継続

共通する失敗IDは三つ。

| ID | 意味 | 原則 |
|---|---|---|
| `run_lost` | その世界で全滅した | 敗北時にしか得られない記録へ置換 |
| `beat_missed` | 配置地点へ到達しなかった | 道標、瓦礫、戦記の追記へ置換 |
| `carrier_damaged` | 手紙、名札などを失った | 欠落を複数世界の反復から補う |

失敗は成功扱いにはしない。人物、町、情報の完全性は失われる。ただし最終選択を見る
権利は奪わず、`reckoning`へ文脈を持ち越す。

## AI境界

この層はAIなしで完成させる。`skin`も`DetRng`でカタログから選ぶ。

- AIへ進行、選択、真相、結末、永続フラグを渡さない。
- AIの遅延や失敗で横断ビートを待たせない。
- LLMの接続点を増やさない。
- 戦記の文章化が必要なら、既存の`src/game/chronicle.gd`へ構造化済み事実だけを渡す。

## 実装境界

追加する想定の担当は次の通り。

| 場所 | 担当 |
|---|---|
| `data/cross_world_arcs.json` | 十二型の原本 |
| `src/quest/cross_world_arc_catalog.gd` | 読込、検算、表示語の確定 |
| `src/game/game_state.gd` | 永続状態、選出、`end_run()`での進行 |
| `src/world/world_generator.gd` | 現在段階を候補地点へ重ねる |
| `src/scenes/main.gd` | `EventView`で表示し選択を受け取る |
| `src/game/chronicle.gd` | 完了済み結末を一行追加 |

ローダーは最低限、次を検算する。

1. 型が十二件でIDが重複しない。
2. 四段階が`phase_order`どおりである。
3. `placement`が許可語彙に含まれる。
4. 選択と結末が三件ずつ一対一である。
5. `fallback_choice`が実在する。
6. 三つの失敗継続がすべてある。
7. 四つの`skin`が三候補以上ある。
8. テンプレートの波括弧がすべて解決する。

## 導入順

1. `chronicle_margins`だけをローダーとセーブへ接続する。
2. `run_result`と`stronghold`だけで四段階を通し、全滅を挟んでも完了できるか試す。
3. 町・洞・主戦前の配置を接続する。
4. 十二型を解放し、同じ型が連続しないことを多数シードで検査する。
5. 結末フラグを戦記へ反映する。
6. 最後に`world_that_did_not_close`の過去反響を接続する。

最初から十二型を本体へつながない。永続セーブを使う物語なので、一型で旧セーブ、
全滅、途中終了、再開、決着の全経路を通してからカタログを広げる。

