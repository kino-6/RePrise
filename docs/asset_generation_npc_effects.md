# NPC・イベントエフェクト・トランジション追加仕様

生成日: 2026-07-30

キャラクター再生成: 2026-07-30

画像生成は組み込みの ImageGen を使った。NPC の再生成では
`docs/character_art_direction.md` の参照順に従い、ユーザー設定画を最上位、
`reference_character_style_anchor_v2.png` を歩行キャラへの翻訳基準にした。
生成時のクロマキー原画は
`candidate_*_source.png`、SFC 制約へ変換した採用候補は
`candidate_*.png` に分けてある。ゲーム用画像は候補から
`tools/gen_assets.py` が `assets/` へ生成する。

## NPC 12 種

全員を正面立ちの `24x32`、透明を除いて 15 色以内、BGR555、二値アルファに統一した。
色替えではなく、被り物・肩幅・持ち物・裾の輪郭で役割を判別できるようにしている。

| ID | 役割と輪郭 |
|---|---|
| `healer` | 枝角の薄布冠、象牙の聖遺物襟、青緑の呼吸器と薬筒 |
| `blacksmith` | 炉殻の眼盾、漆の前垂れ甲、燃える有機襟と鍛造具 |
| `miner` | 結晶測量冠、紫の多眼レンズ、折り畳み式共鳴つるはし |
| `ferryman` | 三日月形の骨輪頭巾、潮の鈴、儀式用の櫂刃 |
| `farmer` | 枝角と花弁の冠、記憶樹の種子薬筒、剪定刃 |
| `beastkeeper` | 顎骨の頭巾、獣の口輪を思わせる肩、契約鎖と呼笛 |
| `mechanic` | 冠状の眼鏡、左右非対称の義手、青緑の導線と炉心 |
| `scribe` | 黒い書庫冠、封印頁の長衣、鎖付き写本と印章 |
| `refugee` | 欠けた冠、裂けた漆の外套、深紅の形見 |
| `pilgrim` | 枝角と光輪の頭巾、象牙の門衣、紫の小鐘 |
| `performer` | 分かれた髪、肩の仮面、非対称の漆衣。道化服ではない |
| `imperial_officer` | 冠状の眼盾、深紅の有機襟、漆の指揮衣と命令印 |

生成プロンプトは次の共通部へ、表の「役割と輪郭」を一件ずつ差し込んだ。

```text
Use case: stylized-concept
Asset type: one NPC source character for a late-16-bit JRPG
Primary request: create one original front-facing standing NPC: <役割と輪郭>
Art authority: treat the supplied original face concepts as highest authority;
preserve their poised adult feminine/androgynous presence, modern gothic
high-fashion silhouette, glossy black lacquer and ivory bone, organic
horn/coral/reliquary forms, vivid eyes, and one saturated accent
Composition: one full-body figure, centered, generous padding, no animation grid
Pixel translation: use the approved soldier sheet only for scale, density and
late-16-bit readability; keep 2 or 3 large silhouette features for 24x32
Avoid: rustic brown leather, generic medieval adventurer, peasant, monk,
ordinary military cap or uniform, lab coat, round steampunk goggles, circus
motley, jester cap, cards, dice, generic tribal fur
Constraints: no text, watermark, scene or cast shadow
Backdrop: perfectly flat solid #00FF00 chroma key; do not use #00FF00 in subject
```

## イベントエフェクト 4 種

各画像は `48x48` の 4 フレームを左から右へ並べた `192x48` アトラス。

| ID | 用途 | 動き |
|---|---|---|
| `world_gate` | 世界間の門 | 細い亀裂から楕円の門へ開き、光粒へ消える |
| `seal_break` | 封印解除 | 三属性の印が重なり、破砕して残光になる |
| `chronicle_echo` | 年代記・記憶の反響 | 閉じた本が開き、頁から光柱が立って収束する |
| `imperial_alarm` | 帝国警報・機械起動 | 赤い中核と歯車環が拡大し、黒煙へ落ちる |

生成プロンプト:

```text
Use case: stylized-concept
Asset type: one original four-frame retro JRPG event effect atlas
Primary request: exactly four successive frames left-to-right: <上表の動き>
Style: polished late-16-bit pixel art; bold clustered pixels; readable at 48x48
Palette: at most 15 colors after reduction; dark navy, cyan, ivory and brass,
with effect-specific green or alarm red
Constraints: four isolated centered effects, equal cells, no text, no character,
no scenery, no watermark
Backdrop: perfectly flat solid #00FF00 chroma key
```

## 画面トランジション 4 種

各画像は `64x40` の 8 フレームを左から右へ並べた `512x40` アトラス。
原画では 4 列 x 2 行だが、採用候補とゲーム用画像は一列へ正規化している。

| ID | 動き |
|---|---|
| `pixel_dissolve` | 四隅から疑似乱数風の角形ピクセル群が増殖して覆う |
| `iris_gate` | 銀青の魔導機械式アイリスが中央へ閉じる |
| `page_turn` | 象牙色の年代記の頁が右から左へめくれて覆う |
| `gear_shutter` | 帝国風の黒鉄・真鍮歯車シャッターが左右から閉じる |

生成プロンプト:

```text
Use case: stylized-concept
Asset type: one original eight-frame full-screen retro JRPG transition
Primary request: <上表の動き>。frame 1 is nearly uncovered and frame 8 is fully covered
Layout: exactly 8 equal 16:10 panels in a rigid 4x2 storyboard,
read left-to-right across the top row and then the bottom row
Style: polished late-16-bit pixel art, big silhouettes readable at 64x40
Palette: dark navy/cyan/ivory/brass, at most 15 colors after reduction
Constraints: no extra panel, text, number, character, landscape, mock UI or watermark
Backdrop: uncovered portions are perfectly flat solid #00FF00 chroma key
```

## 出力先と再生成

- NPC: `assets/sprites/npc_<id>.png`
- イベント演出: `assets/effects/event_<id>.png`
- トランジション: `assets/transitions/<id>.png`
- 拡大確認: `docs/preview/`

```powershell
python tools/check_candidates.py
python tools/gen_assets.py
```
