# キャラクター美術基準

更新日: 2026-07-30

キャラクター生成では、職業名から連想した一般的な RPG の衣装よりも、
この作品の設定画にある造形言語を優先する。職業は「何をする人物か」を決める情報であり、
麦わら帽、革鎧、制帽、白衣などの定番記号を自動的に足す指示ではない。

## 参照の優先順位

1. ユーザー設定画:
   `docs/chara_image/ComfyUI2026_*_face.png`、`face*.png`
2. 設定画を歩行キャラへ翻訳した基準:
   `docs/chara_image/reference_character_style_anchor_v2.png`
3. 既存の採用済み初期職:
   `candidate_hero_soldier_source.png` と最初の 6 職の候補
4. 職業・役割の個別指定

下位の指定が上位の雰囲気を上書きしてはいけない。性別や年齢を特に指定しない場合は、
設定画と同じく成人の女性または中性的な人物を基本とする。

## 造形言語

- 現代寄りのゴシック・ハイファッションを、SFC 後期相当の明快なドットへ翻訳する。
- 主材は艶のある黒い漆・象牙・骨。布だけでなく硬質な襟、胸当て、仮面を使う。
- 角、枝角、冠、骨格、珊瑚、甲殻、聖遺物のような有機的形状を頭部や襟へ置く。
- 基本色は黒と象牙。青緑、深紅、紫、マゼンタなど強い差し色を一人につき一系統だけ使う。
- 表情は落ち着き、挑発、いたずらっぽさ、危うさのいずれかを持たせる。
- 24x32 では、頭飾り・襟・肩・裾のうち 2〜3 個を大きな輪郭として残す。
- 同じ世界の人物に見せつつ、役割の違いは帽子の色ではなく輪郭と道具で読ませる。

## 避ける造形

- 茶革中心の素朴な中世、農民、旅人、修道士、狩人への安易な置き換え
- 実用品を重ねただけの汎用冒険者、普通の兵士、現代軍服
- 制帽、丸ゴーグル、白衣、歯車を足すだけのスチームパンク
- 二股帽、道化服、カード、サイコロを足すだけのサーカス風「遊び人」
- 毛皮、獣耳、部族柄を足すだけの「魔獣使い」
- 若い男性を基準にした既視感の強いソーシャル RPG 風職業デザイン
- 参照画にない暖かな茶色、土色、居心地のよい牧歌調を全員の基調にすること

## 役割を作品語彙へ翻訳する例

| 一般的な役割 | この作品での解釈 |
|---|---|
| 遊び人 | 道化師ではなく、割れた仮面と非対称の髪を持つ「愉悦の異端者」 |
| 賢者 | 学者帽ではなく、骨角の書庫冠と封印頁を持つ「記録の託宣者」 |
| 銃士 | 軍人ではなく、民生の刻印銃と漆の長衣を持つ「刻印射手」 |
| 錬金術師 | 白衣ではなく、聖遺物の薬筒と義手を持つ「遺物調律師」 |
| 時術師 | 時計職人ではなく、骨の円環と欠けた時相をまとう「時縛り」 |
| 魔獣使い | 狩人ではなく、顎骨の頭巾と契約鎖を持つ「契獣の番人」 |
| 鍛冶師 | 革前掛けの職人ではなく、炉心の襟と眼盾を持つ「炉殻師」 |
| 農夫 | 麦わら帽ではなく、記憶樹の種子を扱う「記憶果樹師」 |

## 画像生成の共通指定

```text
Treat the supplied original face concepts as the highest-authority art
direction. Preserve their poised adult feminine/androgynous presence,
modern gothic high-fashion silhouette, glossy black lacquer and ivory bone,
organic horn/coral/reliquary shapes, vivid eyes, and one saturated accent.
Translate the role into that visual language instead of dressing a generic
medieval RPG character.

Use the approved soldier walking sheet only for pixel density, body scale,
3x4 layout, and late-16-bit readability. It is not permission to replace
the face-concept art direction with a generic soldier.

Avoid rustic brown leather, peasant or monk clothing, ordinary military
uniforms and caps, lab coats, round steampunk goggles, circus motley,
jester caps, cards, dice, generic tribal fur, text, UI, and watermark.
```

原画からゲーム候補へ落とすときは、`24x32`、15 色以内、BGR555、二値アルファの
規約を守る。縮小で細部が消える場合は装飾を増やさず、頭・襟・肩の輪郭を優先する。

## 実画面へ載せる寸法

`24x32` はファイルのセル寸法であり、人物の実体がその中で何pxを使うかも揃える。
寸法だけ24x32でも、細長い14x30と幅広い22x27を並べれば別規格に見える。
実画面では現行のまほうつかいを密度の基準とし、生成時に次へ正規化する。

- セルは従来どおり偶数の `24x32`。描画、3x4シート、足元座標は変えない。
- 不透明領域の設計枠は、幅 `20` または `22`、高さ `28`。奇数寸法は使わない。
- 上端は y=4、下端は y=31。全職・全NPCを同じ床へ接地させる。
- 幅20と22の差は、外套や肩、帽子など役割の輪郭に使う。身長差には使わない。
- NPCは黒い漆、象牙、一系統の差し色へ翻訳する。候補の茶革や低コントラストを
  そのまま実画面へ持ち込まない。
- 地形上では主人公とNPCへ同じ16x3px以内の接地影を置く。

実装は `tools/gen_assets.py` の `_prepare_hero_sheet()` と `_prepare_npc()` が担う。
生成時のGateは幅20/22、高さ28、上端4、下端31を外れた画像を失敗にする。
候補原画 `docs/chara_image/` は変更せず、ゲーム用 `assets/` への変換で揃える。

評価は拡大プレビューだけで完了にしない。`--shot=town` では先頭を
まほうつかいにして、NPC、16px地形、HUDを含む512x320の実画面で比較する。

## 町の床と職業輪郭のGate

探索用の別床を町の街路へ流用しない。`town_<生物相>.png` は通常地面2枚に加え、
街路4変種と広場4変種を持つ。1タイル内の非ベース画素は12px以下とし、変種は
座標だけで選ぶ。町の構造乱数を増やさず、16px周期の反復だけを弱める。

職業の描き分けは、候補原画を20/22x28へ正規化した時点の共通胴体を固定し、
その外側の輪郭IoUを測る。成果物から共通胴体を求め直すと、一職を直しただけで
無関係な組の判定対象が変わるため禁止する。IoU 0.44以上は生成を終了コード1で止め、
盾、弓、刻印銃、骨の円環、杖、非対称の髪・外套で分ける。追加色は使わず、
各候補がすでに持つ輪郭色・差し色・中明度だけを再利用する。

5生物相の町は `--shot=town_dungeon`、`town_grassland`、`town_wetland`、
`town_snowfield`、`town_volcano` で同じ構造を撮影できる。
