# 帝国系プレイヤー職候補

`assets/` へは未反映の候補素材。既存の帝国兵・機械兵と同じ工業幻想の背景を持ちつつ、
味方として顔と個性が読めるデザインにしている。

## 職業一覧

| ID | 表示案 | 主なシルエット・装備 |
|---|---|---|
| `imperial_gunner` | 魔導銃士 | 銀髪、上げた照準器、片肩装甲、暗赤色のスカーフ、短い魔導銃、魔力セル |
| `bombardier` | 砲術士 | 栗色の髪、防爆帽、角張った肩、砲弾鞄、背中に折り畳んだ迫撃砲 |
| `machinist` | 機工士 | 銅色の髪、ゴーグル、機械義手、ケーブルリール、折り畳み工具、青緑の炉心 |
| `iron_guard` | 鉄衛士 | 灰金の三つ編み、半兜、幅広い片肩装甲、背中の大盾、重い脚甲 |
| `tactician` | 戦術士 | 黒いボブと灰色の前髪、制帽、指揮官外套、通信器、地図筒、指揮杖 |
| `aether_medic` | 衛生術士 | 淡い青緑の髪、首元の開いた呼吸器、象牙色の野戦外套、治療籠手、琥珀色の薬管 |

`imperial_gunner` は既存の民間的な `gunner` と分け、帝国式の魔導銃・片肩装甲・
魔力セルを使った軍用シルエットにしている。

## 成果物

- `candidate_hero_<id>_source.png`: Imagegen の原画。緑背景、3列×4行。
- `candidate_hero_<id>.png`: ゲーム規格候補。72×128 px、1コマ24×32 px、3列×4行。
- `candidate_hero_<id>_preview.png`: 各シートの8倍拡大確認画像。
- `candidate_imperial_jobs_6_contact.png`: 帝国系6職の比較画像。
- `candidate_heroes_contact_all_v3.png`: 既存候補を含む全21職の比較画像。

行の向きは上から正面・右・左・背面、各行は歩行3コマ。

## Imagegen プロンプト

共通プロンプト:

> Create one original playable JRPG character as a clean 3 columns by 4 rows walking
> sprite sheet on a flat bright green chroma background. Exactly 12 isolated full-body
> sprites: rows front, right, left, back; columns left-step, neutral, right-step. Match
> the supplied modern late-16-bit industrial-fantasy character style and proportions.
> Serious rather than cute or chibi, readable eyes and visible face, compact silhouette,
> strong class identity, no text, labels, grid, frame, shadows, UI, extra figures, enemy
> insignia, or copied franchise design. Keep every pose centered with clear empty space.

参照:

- レイアウトと味方職の画風: `candidate_heroes_contact_all_v2.png`
- 帝国側の素材・色・機械意匠: `candidate_imperial_soldiers_6_contact.png`

職業ごとに上表の髪型、被り物、肩、裾、背負い物、手持ち装備を追加指定した。
既存職と色だけでなくシルエットで区別し、敵兵の閉じた兜や無個性な制服は避けている。

生成には Codex 組み込みの Imagegen を使用した。

## 変換と検算

原画からクロマキーを除去し、各セルの最大連結成分を抽出して24×32 pxへ収めた。
シート全体を透明色以外15色へ量子化し、全色をBGR555の段階へ丸めている。

全6シートで以下を確認済み:

- 72×128 px
- 24×32 px × 12コマ
- 可視色15色
- 全可視色がBGR555相当
- アルファ値は0 / 255のみ
- 12コマすべて非空
- 四隅は透明

`assets/`、職業データ、ゲームロジックには未反映。
