# 背景・戦闘FX・帝国施設装飾 候補

現行のキャラクター・敵素材を活かすための補助アセット候補。
Codex組み込みのImagegenで原画を生成し、SFC向け規格へ変換した。
`assets/`、描画コード、ゲームデータには未反映。

## 1. 戦闘背景 6種

| ID | 用途 |
|---|---|
| `dungeon_depths` | 地下遺跡・石造ダンジョン |
| `snowfield_ruins` | 雪原・凍結遺跡 |
| `grassland_twilight` | 草原・古代遺構 |
| `volcanic_caldera` | 火山・溶岩地帯 |
| `drowned_wetland` | 湿地・水没遺跡 |
| `imperial_foundry` | 帝国工廠・魔獣収容区 |

成果物:

- `candidate_battle_bg_<id>_source.png`: Imagegen原画。
- `candidate_battle_bg_<id>.png`: 512×176 pxのゲーム画面上部用候補。
- `candidate_battle_backgrounds_6_contact.png`: 6背景の比較画像。
- `candidate_battle_backgrounds_game_mockup.png`: 現行戦闘UIへ合成した実寸比較。

共通プロンプト:

> Use case: stylized-concept. Asset type: original battle background candidate
> for a 512x320 late-SFC JRPG; only the upper 176 pixels are visible behind
> enemies. Create one environment-only battle backdrop in a very wide
> panoramic composition, designed to be cropped to 512x176. Sober polished
> late-16-bit pixel art, large deliberate pixel clusters, strong depth
> planes, restrained detail and grounded materials. Use a very wide 3:1
> panorama with a low floor plane and distant wall or horizon. Keep the
> central 55 percent dark and uncluttered so 48x48 enemy sprites remain
> readable. Environment only; no people, monsters, creatures, vehicles,
> weapons, loot, text, logos, UI, border or watermark.

各背景には表の環境に加え、中央へ明るい構造物を置かないこと、左右端で地形の特徴を
出すこと、敵の足元となる床面を下側へ確保することを個別指定した。

検算:

- 全6種 512×176 px
- 可視色12～15色
- 全色BGR555相当
- 完全不透明
- 現行UI・48px敵スプライトとの合成を目視確認

## 2. 戦闘エフェクト 12種

| ID | 内容 |
|---|---|
| `slash` | 斬撃 |
| `thrust` | 刺突 |
| `gunshot` | 魔導銃撃 |
| `explosion` | 爆発 |
| `fire` | 炎 |
| `ice` | 氷 |
| `bolt` | 雷 |
| `heal` | 回復 |
| `poison` | 毒 |
| `sleep` | 睡眠 |
| `buff` | 強化 |
| `debuff` | 弱体 |

成果物:

- `candidate_fx_<id>_source.png`: Imagegen原画。
- `candidate_fx_<id>.png`: 128×32 px、32×32 px×4コマの候補。
- `candidate_fx_<id>_preview.png`: 6倍拡大確認画像。
- `candidate_battle_fx_12_contact.png`: 全12種のアニメーション比較。

共通プロンプト:

> Use case: stylized-concept. Asset type: original four-frame combat effect
> animation sprite sheet for a late-SFC JRPG. Create exactly four successive
> animation frames of one effect, arranged left-to-right in one single
> horizontal row. Crisp opaque late-16-bit pixel art, large deliberate
> clusters, compact high-impact silhouette, readable when each frame is
> reduced to 32x32 pixels. Frame 1 onset, frame 2 impact, frame 3 peak,
> frame 4 dissipation. Perfectly flat uniform #00ff00 chroma-key background.
> Effect only; no character, enemy, hand, weapon, environment, floor, text,
> number, logo, UI, grid, border or watermark.

検算:

- 全12種 128×32 px
- 32×32 px×4コマ
- 全48コマ非空
- 可視色14～15色
- 全色BGR555相当
- アルファ値0 / 255のみ
- 四隅透明

## 3. 帝国施設装飾 12種

| ID | 内容 |
|---|---|
| `beast_cage` | 空の魔獣檻 |
| `restraint_post` | 拘束・制御柱 |
| `feed_trough` | 餌槽 |
| `pipe_valve` | 配管弁 |
| `specimen_vat` | 空の培養槽 |
| `command_pylon` | 魔獣制御杭 |
| `supply_crate` | 帝国補給箱 |
| `imperial_banner` | 無紋章の施設旗 |
| `chain_bundle` | 拘束鎖 |
| `incubator_egg` | 卵と孵化台 |
| `broken_harness` | 壊れた制御具 |
| `furnace_vent` | 炉床排熱口 |

成果物:

- `candidate_imperial_prop_<id>_source.png`: Imagegen原画。
- `candidate_imperial_prop_<id>.png`: 32×32 pxの個別候補。
- `candidate_imperial_prop_<id>_preview.png`: 8倍拡大確認画像。
- `candidate_imperial_props_12_atlas.png`: 4列×3行、128×96 pxの共通パレット版。
- `candidate_imperial_props_12_contact.png`: 12種の比較画像。
- `candidate_imperial_props_map_mockup.png`: 現行16pxタイル上の実寸確認。

共通プロンプト:

> Use case: stylized-concept. Asset type: one original imperial-facility map
> prop candidate for a top-down late-SFC industrial-fantasy JRPG. Create
> exactly one isolated environmental prop, readable when reduced to a 32x32
> pixel cell. Sober polished late-16-bit pixel art, large deliberate clusters,
> crisp blue-black outline, restrained highlights and strong silhouette.
> Consistent three-quarter top-down map view with light from upper left.
> Blackened iron, gunmetal, antique brass, dark leather, weathered wood,
> muted crimson cloth and tiny amber or cyan accents. Perfectly flat uniform
> #00ff00 chroma-key background. No people, monsters, body parts, floor tile,
> room, wall, shadow, smoke, text, emblem, logo, UI, border or watermark.

12種を一度128×96 pxのアトラスへ組み、アトラス全体を共通の15色へ量子化してから
個別セルへ切り出した。これにより同じ施設内で色調が揃う。

検算:

- 個別12種 32×32 px
- アトラス 128×96 px、4列×3行
- アトラス全体で可視15色
- 全色BGR555相当
- アルファ値0 / 255のみ
- 全個別セルの四隅が透明
- 16pxタイル上の実寸モックアップを目視確認
