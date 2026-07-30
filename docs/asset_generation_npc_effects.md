# NPC・イベントエフェクト・トランジション追加仕様

生成日: 2026-07-30

画像生成は組み込みの ImageGen を使い、`docs/chara_image/` の既存候補を
画風の参照にした。生成時のクロマキー原画は
`candidate_*_source.png`、SFC 制約へ変換した採用候補は
`candidate_*.png` に分けてある。ゲーム用画像は候補から
`tools/gen_assets.py` が `assets/` へ生成する。

## NPC 12 種

全員を正面立ちの `24x32`、透明を除いて 15 色以内、BGR555、二値アルファに統一した。
色替えではなく、被り物・肩幅・持ち物・裾の輪郭で役割を判別できるようにしている。

| ID | 役割と輪郭 |
|---|---|
| `healer` | 短い象牙色の肩掛け、青緑の上衣、薬鞄 |
| `blacksmith` | 幅広い革前掛け、片肩当て、腰の金槌 |
| `miner` | 灯火付き兜、短い外套、背のつるはし |
| `ferryman` | 広いつばの笠、雨除け、背の櫂 |
| `farmer` | 麦わら帽、苔色の上衣、種袋と鎌 |
| `beastkeeper` | 耳当て付き頭巾、噛みつき防具、餌袋 |
| `mechanic` | ゴーグル、左右非対称の機械腕、工具と導線 |
| `scribe` | 角帽、長衣、眼鏡、巻物筒 |
| `refugee` | 継ぎ布の外套、毛布、生活道具の包み |
| `pilgrim` | 深い頭巾、淡色の肩衣、祈祷板と鈴 |
| `performer` | 羽根帽子、割れた外套、太鼓と足鈴 |
| `imperial_officer` | 制帽、片肩章、割れ裾の長衣、指揮杖 |

生成プロンプトは次の共通部へ、表の「役割と輪郭」を一件ずつ差し込んだ。

```text
Use case: stylized-concept
Asset type: one NPC source character for a late-16-bit JRPG
Primary request: create one original front-facing standing NPC: <役割と輪郭>
Style/medium: polished late-SFC-era pixel art with slightly modern character design
Composition: one full-body figure, centered, generous padding, no animation grid
Palette: dark navy/brown base, restrained cyan/ivory/brass accents
Constraints: readable after reduction to 24x32; distinguish the job by silhouette;
no text, no watermark, no scene, no cast shadow
Backdrop: perfectly flat solid #00FF00 chroma key; do not use #00FF00 in the subject
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

