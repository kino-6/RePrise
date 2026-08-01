# イベント品質設計

## 結論

この作品でいうイベントは文章画面ではない。最小単位を次の三段にする。

1. プレイヤーが次に行うことを知る
2. 地図・施設・探索・戦闘のいずれかを自分で操作する
3. 世界またはランの状態が変わり、画面上で結果を確かめる

会話や短い説明は補助には使えるが、それだけで一件のイベントを完了させない。
「話を続ける」一択、文章を閉じただけで進行、結末文だけが違ってゲーム内には何も
残らない選択は、実装済みとして数えない。

## 往年のRPGから採る構造

- 『クロノ・トリガー』開発者インタビューでは Active Time Event Logic を、イベント中も
  動ける、別の人物へ話せる、場面へプレイヤーが関与できる仕組みとして説明している。
  作り手が見せたいものとプレイヤーの自由の均衡も明言されている。
  [Chrono Trigger – 1994/1995 Developer Interviews](https://shmuplations.com/chronotrigger/)
- 『FINAL FANTASY VI』30周年公式インタビューでは、物語をカットシーンだけでなく戦闘中にも
  展開したこと、待つというプレイヤー行動がシャドウの恒久的な結果へつながることが語られる。
  [Final Fantasy VI 30th Anniversary Special Interview Vol. 2](https://na.finalfantasy.com/topics/528)
- 堀井雄二氏は『ドラゴンクエスト』の町について、村人全員を世界へ関与させ、複数人との
  接触で理解が深まり、プレイヤーの遊び方がゲームへ影響することを重視している。
  [25 Years of Dragon Quest: An Interview with Yuji Horii](https://www.gamedeveloper.com/business/25-years-of-i-dragon-quest-i-an-interview-with-yuji-horii)
- 『Children of Morta』のポストモーテムは、物語とゲームプレイの仕組みが互いを支えないと
  遊びと物語が分離すると整理している。ランダム性のある連作でも同じ条件が要る。
  [Postmortem: Children of Morta](https://www.gamedeveloper.com/design/postmortem-children-of-morta)
- 『牧場物語』のクラシック・ポストモーテムでは「田舎の生活を体験する」という構想を、
  交流・農作業・家畜という操作へ具体化している。設定を説明するより、設定らしい動詞を
  プレイヤーへ渡す考え方を採る。
  [Classic Game Postmortem: Harvest Moon](https://media.gdcvault.com/gdc2012/slides/Yasuhiro_Wada_Classic%20Game%20Postmortem.pdf)

以上から本作では「読む量」ではなく、物語固有の目的を既存のプレイ動詞へ結び、選択の
結果を主戦・遭遇・戦記へ持ち越すことを品質基準にする。

## 一世界物語の六拍

| 拍 | 必須のプレイ | 完了条件 |
|---|---|---|
| 導入 | 町の仕事場を使う | 施設の効果が実際に発生する |
| 同行 | 洞を探索する | 宝箱を開ける、または下り階段へ着く |
| 反転 | 町の仕事または洞の調査 | 配置先に対応する実操作を終える |
| 選択 | 三択を選び、その方法を現地で実行 | 実操作完了時にラン状態へ効果を渡す |
| 決戦 | 短い物語行を開戦文へ載せ、主と戦う | 勝利する |
| 後日談 | 戦記へ統合する | 独立した「次へ」画面を出さない |

三択は選ぶ前に「払うもの・守るもの・失うもの」と直近のゲーム内効果を見せる。選択時には
拍を進めず、現地の工程を終えた時だけ効果を配布して進行する。

## 自動Gate

`tests/test_world_events.gd` は次を検査する。

- 全六型・三十六拍に明示的な `operation` がある
- `dialogue` / `cutscene` / `continue` / `story` を完了工程として認めない
- 選択の無い物語拍を `EventView` で開かない
- 全十八択に実装済みのラン状態変化がある
- 選択時に効果配布や `advance_story()` を行わない
- 町または洞の実操作完了点だけが効果を配り、拍を進める
- またぐ物語の中間拍を一枚文章のモーダルにしない
- 主戦勝利後の後日談を別の送り画面にせず、戦記へ回収する

壊れる側は次で確認できる。

```bash
godot --headless --script res://tests/test_world_events.gd -- --fixture=paper_story
```

このコマンドは「会話を読んだだけ」を完了条件へ戻したfixtureを意図どおり検出し、終了値1に
なることが成功条件である。
