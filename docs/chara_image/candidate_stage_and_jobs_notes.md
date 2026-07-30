# 職業・ステージ追加候補

作成日: 2026-07-30

組み込みの ImageGen で方向性画像を生成し、ゲーム内寸法に縮小したあと、
BGR555・15色サブパレット・二値アルファへローカルで整形した候補。
採用候補は `tools/gen_assets.py` を通して `assets/sprites/hero_<id>.png` に反映する。
職業データとゲームロジックは既存のものを変えず、今回は画像だけを差し替えた。
2026-07-30 の再生成では `docs/character_art_direction.md` に従い、
ユーザー設定画を最上位の画風基準として 6 職すべてを描き直した。

## 職業候補

| ID | 仮称 | シルエット上の特徴 |
|---|---|---|
| `jester` | 遊び人 | 分かれた髪、肩の割れ仮面、左右非対称の漆衣 |
| `sage` | 賢者 | 象牙の枝角書庫冠、幅広い黒襟、封印頁の長衣 |
| `gunner` | 銃士 | 冠状の眼盾、白黒の分割長衣、民生の深紅刻印銃 |
| `alchemist` | 錬金術師 | 聖遺物の薬筒冠、象牙の義手、非対称の調律衣 |
| `chronomancer` | 時術師 | 紫に発光する骨円環、欠けた時相、振り子状の裾 |
| `beastmaster` | 魔獣使い | 顎骨の頭巾、深紅の獣口輪肩、太い契約鎖 |

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
> sprite sheet concept. Treat the supplied original face concepts as the
> highest-authority art direction. Preserve their poised adult
> feminine/androgynous presence, modern gothic high-fashion silhouette,
> glossy black lacquer and ivory bone, organic horn/coral/reliquary forms,
> vivid eyes, and one saturated accent. Use the approved soldier sheet only
> for pixel density, proportions and 3x4 layout. Create one complete 3 columns by 4 rows;
> rows are front, right-facing, left-facing, back; exactly three walking
> frames per row; equal spacing, no overlap, consistent identity. Polished
> late-16-bit-console pixel-art concept, modern fantasy design translated
> into chunky readable pixels, crisp clusters, no blur, strong silhouette.
> Perfectly flat solid #00ff00 chroma-key background. No shadow, texture,
> grid, captions, UI, numbers, watermark, photorealism, or copied commercial
> character. Do not use #00ff00 in the subject. Avoid rustic brown leather,
> generic medieval adventurer, ordinary military uniforms and caps, lab coats,
> round steampunk goggles, circus motley, jester caps, cards, dice and generic tribal fur.

職別の追加指定:

- 遊び人: poised androgynous adult “playful anomaly”; split black-and-ivory
  hair, fractured mask ornaments at the shoulders, magenta accent and
  asymmetric lacquer mantle; mischievous and dangerous; no circus symbols.
- 賢者: adult archive oracle; ash-silver hair, ivory antler archive crown,
  broad black reliquary collar, cyan sealed pages and chained codex;
  not a conventional robed scholar.
- 銃士: adult civilian rune gunner; short silver hair, crown-like eye shield,
  fitted black-and-ivory split coat and compact crimson rune hand-cannon;
  no military cap, rank badge or ordinary uniform.
- 錬金術師: adult reliquary alchemist; pale hair, crown of reagent ampoules,
  asymmetric ivory prosthetic glove and black lacquer tuning mantle;
  no lab coat or round goggles.
- 時術師: adult time binder; dark-violet bob, luminous violet bone ring behind
  the head, broken phase plates and pendulum hem; no clockmaker costume.
- 魔獣使い: adult bound-beast keeper; bone-jaw hood, crimson beast-muzzle
  shoulder, black lacquer coat and heavy contract chain; no tribal fur or animal ears.

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
