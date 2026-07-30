# 職業・ステージ追加候補

作成日: 2026-07-30

組み込みの imagegen で方向性画像を生成し、ゲーム内寸法に縮小したあと、
BGR555・15色サブパレット・二値アルファへローカルで整形した候補。
`assets/`、`data/jobs.json`、ゲームロジックには未反映。

## 職業候補

| ID | 仮称 | シルエット上の特徴 |
|---|---|---|
| `jester` | 遊び人 | 二股帽、鈴、左右非対称のカード柄コート |
| `sage` | 賢者 | 折り返した学匠帽、幅広の襟、長い学術ローブ |
| `gunner` | 銃士 | 制帽、分割ロングコート、腰の小型魔導銃 |
| `alchemist` | 錬金術師 | 額のゴーグル、作業外套、薬瓶ラックと金属手袋 |
| `chronomancer` | 時術師 | 円環状のフード枠、振り子風の裾、砂時計飾り |
| `beastmaster` | 魔獣使い | 獣耳の毛皮頭巾、片側だけ広い毛皮肩、太い編み髪 |

各職業には次の3種類がある。

- `candidate_hero_<id>_source.png`: imagegen の方向性原画
- `candidate_hero_<id>.png`: 72x128、24x32 x 12コマのゲーム規格候補
- `candidate_hero_<id>_preview.png`: 最終候補の8倍プレビュー

比較画像:

- `candidate_modern_jobs_contact.png`: 今回の6職
- `candidate_heroes_contact_all_v2.png`: 既存候補を含む全15職

### キャラクター生成プロンプト

全職共通:

> Use case: stylized-concept. Asset type: SFC-era JRPG playable character
> sprite sheet concept. Use the approved sprite candidates only as the exact
> style, rendering density, proportions, palette mood, and 3x4 sheet-layout
> reference. Create one complete 3 columns by 4 rows walking sprite sheet;
> rows are front, right-facing, left-facing, back; exactly three walking
> frames per row; equal spacing, no overlap, consistent identity. Polished
> late-16-bit-console pixel-art concept, modern fantasy design translated
> into chunky readable pixels, crisp clusters, no blur, strong silhouette.
> Perfectly flat solid #00ff00 chroma-key background. No shadow, texture,
> grid, captions, UI, numbers, watermark, photorealism, or copied commercial
> character. Do not use #00ff00 in the subject.

職別の追加指定:

- 遊び人: androgynous young adult; asymmetric two-point soft cap with tiny
  brass bells; lively wide eyes; cropped ivory-and-deep-wine motley coat;
  one flared shoulder and one narrow shoulder; card-and-dice charm; playful
  but capable, not a circus clown.
- 賢者: mature but youthful scholar-mage; long ash-silver hair; calm luminous
  eyes; tall layered scholar hood folded back like a soft crown; ivory mantle
  with broad teal collar; geometric arcane hems; grimoire and astrolabe;
  distinct from pointed-hat mage and horned summoner.
- 銃士: short silver hair and dark undercut; compact field cap; fitted charcoal
  split long coat; cross-belts and mana capsules; compact rune hand-cannon at
  the hip; practical modern fantasy, not military science fiction.
- 錬金術師: tousled pale-blond hair; round goggles on forehead; asymmetric
  ivory workshop coat with teal lining; apron panels; bottle rack, satchel,
  metal reagent glove; not a modern laboratory scientist.
- 時術師: dark-violet bob with one silver forelock; crescent-shaped hood frame;
  asymmetric ivory mantle; brass clockwork ring and hourglass charm;
  pendulum-like skirt panels; mysterious but not evil.
- 魔獣使い: dark auburn braid; open wolf-eared hide hood; one broad fur
  shoulder; hunter tunic, leather straps, claw buckle, rope and whistle;
  no animal companion and no oversized weapon.

## ステージ用マップチップ

| ID | 環境 | 主素材・色 |
|---|---|---|
| `grassland` | 草原・古道 | 夕暮れの草、露出土、石垣、蔦 |
| `volcano` | 火山・黒曜砦 | 玄武岩、黒曜石、細い溶岩亀裂 |
| `snowfield` | 雪原・氷結神殿 | 圧雪、青氷、雪庇、氷柱 |
| `wetland` | 湿地・水没遺跡 | 泥炭、浅い青緑の水、苔、根 |

各環境には次の4種類がある。

- `candidate_tiles_<id>_source.png`: imagegen の3x3方向性ボード
- `candidate_tiles_<id>.png`: 144x16のゲーム規格候補
- `candidate_tiles_<id>_preview.png`: 最終9タイルの拡大表示
- `candidate_tiles_<id>_mockup.png`: 512x320の実寸配置例

比較画像:

- `candidate_stage_tiles_contact.png`: 4環境の9タイル比較
- `candidate_stage_mockups_contact.png`: 4環境の実寸比較

9タイルの意味と順序は現行ダンジョンと互換:

1. 通常床
2. 変化床・傷んだ床
3. 壁面
4. 壁上端
5. 階段
6. 主の扉
7. 宝箱
8. 透明な外部領域
9. 出店

### マップ生成プロンプト

全環境共通:

> Use case: stylized-concept. Asset type: top-down late-16-bit JRPG biome
> tileset concept board. Use the existing dungeon source as the exact
> nine-tile semantic layout reference and its mockup as the in-game scale,
> dark-fantasy palette mood, and pixel-density reference. Create one square
> 3-by-3 board of nine equal cells, edge-to-edge, without labels or gutters.
> Row 1 = walkable floor, damaged walkable floor, impassable wall face.
> Row 2 = wall top, descending stair, boss gate. Row 3 = treasure chest,
> uniform chroma-key void, traveling merchant stall. Polished SFC-late-era
> pixel art with modern dark-fantasy art direction, chunky clusters and
> simplified forms that survive reduction to 16x16. Strict top-down/slight
> classic JRPG tile perspective. No characters, creatures, text, logos, UI,
> grid lines, cross-cell shadows, or watermark.

環境別の追加指定:

- 草原: dusk short grass, exposed earth and stones, hedge-and-low-cliff walls,
  ivy-covered standing-stone gate, weathered chest, canvas merchant awning;
  olive, slate, ivory, bronze, and deep-wine accents.
- 火山: cooled basalt, dim magma seams, jagged obsidian walls, volcanic rock
  arch, heat-scorched chest, fireproof stall; blue-black, ash, rust, ember,
  bronze; avoid broad saturated orange.
- 雪原: wind-packed snow, blue ice and exposed stone, snow-capped ice wall,
  frozen shrine gate, frost-covered chest, fur-lined stall; blue-black,
  desaturated ice blue, dirty ivory, bronze, deep wine.
- 湿地: dark peat, shallow teal puddles, roots, moss embankment, drowned
  standing stones, mossy chest, raised patched stall; peat brown, swamp teal,
  moss olive, gray stone; avoid neon poison green.

方向性原画をそのまま16x16へ縮小すると形が潰れるため、最終チップは原画の
素材・明暗・ランドマークを基に1px単位で再構成している。

## 検証結果

- キャラクター: 全6枚が72x128、各15可視色、透明角、アルファ0/255
- マップ: 全4枚が144x16、12〜15可視色、8番のみ透明、他は不透明
- 全可視色がBGR555へ正確に量子化済み
- 最終比較画像と512x320実寸モックアップを目視確認済み
