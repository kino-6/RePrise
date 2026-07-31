# ゲーム内文章の基準

## 目的

画面はSFC後期相当の制約を持つが、文章まで古風にしない。
自然で簡潔な現代日本語を使い、暗い設定は「意味の分からなさ」ではなく、
状況、人物の目的、選択の代償から伝える。

## 文章の順序

プレイヤーが読む順に、次を明らかにする。

1. 誰が、どこで困っているか。
2. 今、何が起きているか。
3. プレイヤーは何を選べるか。
4. 選ぶと何を払い、何を守り、何を失うか。

設定用語や比喩は、この四点を伝えた後にだけ足す。

## 用途別の規約

### UI

- ボタンと選択肢は、実行後の動作が予測できる動詞で終える。
- 同じ概念には同じ語を使う。
- 「はらう／あぶない／もらう」のような幼い説明語は、
  「代償／危険／得る」のような短く一般的な語へそろえる。
- 操作説明は一画面で読み切れる長さにする。

### NPCの一言

- 一文目で役割か現在の問題を示す。
- 役割に関係する情報を一つだけ話す。
- 哲学、予言、意味深な独り言を町人の汎用台詞へ置かない。
- 一行34文字を目安にし、二文にする場合も一つの話題だけを扱う。
- 古風な語尾や方言は、固有人物の設定がある場合だけ使う。

良い例:

> 街道が崩れている。石の目印に沿って進んで。

避ける例:

> 人の通らぬ道ほど速い。

後者は雰囲気はあるが、誰の経験なのか、どの道なのか、助言なのかが分からない。

### 任意イベント

- `title`: 場所や問題を想像できる短い名詞句。
- `actor`: 職業や立場が分かる具体的な人物。
- `cause`: 原因の主体と行動を含む完結した一文。
- `flavor`: 現場で見える物、聞こえる音、匂いのいずれか。
- `choice`: 選択後の行動が分かる動詞句。
- 代償、危険、報酬は選ぶ前に表示する。

### 物語

- 地の文を人物の発話として表示しない。
- 一つの拍では「新しい事実」と「次の判断」を一つずつに絞る。
- 通常のイベント見出しでは、差し込み後64文字以内を目安にする。
- 抽象語を重ねず、人物、物、行動を先に書く。
- 暗い結末でも、何が起きたかを明記する。

### AI生成文

- AIは表示用の表層だけを変更し、進行、数値、報酬、正解へ触れない。
- 文字数、固有名詞、数字だけでなく、次も検査する。
  - 意味深な定型句
  - 抽象語の積み重ね
  - 古風な語尾
  - 役割が分からないactor
  - 感覚情報のないflavor
- 一項目でも不合格なら、手書きの既定文へ戻す。
- AI文を採用できないことはエラーではない。既定文だけでゲームを完成させる。

## 差し替え場所

| 種類 | 原本 |
|---|---|
| 固定UI、プロローグ、戦記 | `data/vocabulary.json` |
| 町のNPC台詞 | `data/town_dialogue.json` |
| 任意イベント | `data/world_events.json` |
| 一世界の中核物語 | `data/story_arcs.json` |
| 世界をまたぐ物語 | `data/cross_world_arcs.json` |

キーとIDはコードが参照するため変更しない。文章の配列と表示文だけを差し替える。

## 検証

```bash
python tools/check_writing.py
python tools/check_writing.py --selftest
godot --headless --script res://tests/test_core.gd
godot --path . --accessibility disabled -- --no-ai --shot=prologue_oath --ui-check
godot --path . --accessibility disabled -- --no-ai --shot=story --ui-check
godot --path . --accessibility disabled -- --no-ai --shot=choicebeat --ui-check
godot --path . --accessibility disabled -- --no-ai --shot=acrosschoice --ui-check
```

画面では、文字が収まるだけでなく、話者と本文が一致し、選択の意味が一読で分かることを
確認する。

## 参考にした一次資料

- [Microsoft: Localize games](https://learn.microsoft.com/ja-jp/globalization/localization/localize-games)
  は、自然でジャンルに合う言葉と、人物設定・用語集・文脈の共有を求めている。
- [Microsoft Style Guide: Use simple words, concise sentences](https://learn.microsoft.com/en-us/style-guide/word-choice/use-simple-words-concise-sentences)
  は、簡潔な文、明確な意味の語、一概念一用語を推奨している。
- [Xbox Accessibility Guideline 104](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/104)
  は、話者の識別、短い行、意味のある位置での改行を求めている。
- [Apple Human Interface Guidelines: Inclusion](https://developer.apple.com/design/human-interface-guidelines/inclusion)
  は、明確、直接的、敬意のある文章を推奨している。
