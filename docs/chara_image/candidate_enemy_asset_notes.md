# 敵キャラクター画像候補

作成日: 2026-07-30

組み込みの imagegen で各敵を1体ずつ生成し、クロマキー除去後にゲーム寸法へ
縮小、BGR555・15可視色・二値アルファへ整形した候補。`assets/`、
`data/monsters.json`、戦闘バランス、出現表には未反映。

## 既存敵のリファイン

| ID | 寸法 | 維持した特徴 |
|---|---:|---|
| `gel_refined` | 48x40 | 緑のドーム体、左右の大きな目 |
| `bat_refined` | 48x34 | 黄褐色の胴、紫の翼 |
| `skull_refined` | 48x32 | 横長の頭蓋、赤い眼窩、大きな歯 |
| `shade_refined` | 48x44 | 三角形の影、紫の襟、一文字の青い眼 |
| `golem_refined` | 48x44 | 矩形の石造胴、横長の橙色炉心 |
| `warden_refined` | 64x64 | 二本角、黒い顔、赤い目、紫の重装甲 |

比較画像:

- `candidate_enemies_refined_existing_contact.png`

## 追加通常敵12種

| ID | 仮称 | 想定環境・役割 |
|---|---|---|
| `arcane_hound` | 魔導猟犬 | 草原・遺跡、高速物理 |
| `lantern_mimic` | 喰らい灯 | ダンジョン、擬態・罠 |
| `plague_moth` | 疫蛾 | 草原・湿地、状態異常 |
| `crystal_drake` | 晶鱗竜 | 雪原・深層、氷属性 |
| `ruin_automaton` | 遺跡機兵 | 遺跡、防御型 |
| `ember_wraith` | 焔亡霊 | 火山、炎魔法 |
| `frost_stalker` | 氷牙獣 | 雪原、高速・氷物理 |
| `mire_oracle` | 沼の眼 | 湿地、弱体・魔法 |
| `fungal_knight` | 菌鎧騎士 | 湿地、防御・反撃 |
| `void_scribe` | 虚字術師 | 深層、暗黒魔法 |
| `chain_ogre` | 鎖鬼 | 火山・深層、鈍足重打 |
| `shattered_seraph` | 欠けた天使 | 神殿・深層、聖遺物型 |

全種48x48。比較画像は `candidate_enemies_modern_12_contact.png`。

## 追加ボス3種

| ID | 仮称 | 想定ステージ | 識別点 |
|---|---|---|---|
| `thorn_crowned_king` | 荊冠の古王 | 草原・古代聖域 | 巨大な枝角と石面 |
| `crucible_colossus` | 炉心巨像 | 火山・黒曜砦 | 円形炉心と非対称の両腕 |
| `frostbound_oracle` | 氷葬の神託者 | 雪原・氷結神殿 | 五枚氷冠と三眼の仮面 |

全種64x64。比較画像は `candidate_bosses_new_3_contact.png`。

## ファイル構成

- `candidate_enemy_<id>_source.png`: imagegen方向性原画
- `candidate_enemy_<id>.png`: 通常敵ゲーム規格候補
- `candidate_enemy_<id>_preview.png`: 拡大プレビュー
- `candidate_boss_<id>_source.png`: ボス方向性原画
- `candidate_boss_<id>.png`: ボス64x64候補
- `candidate_boss_<id>_preview.png`: ボス拡大プレビュー
- `candidate_enemies_all_21_contact.png`: 今回の全21体
- `candidate_enemies_actual_scale_mockup.png`: 通常敵の512x320実寸例
- `candidate_bosses_actual_scale_mockup.png`: ボスの512x320実寸例

## 生成プロンプト

全敵共通:

> Use case: stylized-concept. Asset type: single SFC-late-era JRPG battle
> enemy sprite concept. Use the supplied existing enemy or approved boss
> source for identity, rendering density, outline weight and frontal battle
> presentation; use the approved hero contact for the shared modern-fantasy
> palette mood. Polished late-SFC pixel-art concept translated into large
> deliberate pixel clusters, crisp blue-black outline, controlled highlights
> and a strong silhouette readable at 48x48 or 64x64. Exactly one centered
> monster in a front three-quarter battle view, isolated, entire silhouette
> visible. Perfectly flat chroma-key background. No floor, cast shadow,
> reflection, halo, loose particles, environment, frame, UI, text, logo,
> watermark or copied commercial character. Avoid tiny fragile detail.

既存敵の追加指定:

- Gel: low emerald gelatinous dome with puddled base, two side-set ivory eyes,
  trapped brass coin and faint inner core; no limbs.
- Bat: compact ochre cave bat, broad angular muted-violet wings, tiny fangs,
  crimson eyes and tucked feet.
- Skull: broad cracked skull, heavy brow, rectangular ember eye sockets,
  missing nasal shard, readable teeth and short burial-cloth scraps.
- Shade: floating indigo triangular robe, lavender folded collar, void face
  crossed by one narrow cyan eye-slit; no hands or legs.
- Golem: squat fortress-like stone automaton, rectangular torso and arms,
  inset head, amber horizontal core and asymmetrical cracks.
- Warden: monumental violet-black armor, tall swept horns, black face, paired
  red eyes, pale-gold brow plate and broad faceted pauldrons.

追加通常敵の追加指定:

- Arcane Hound: lean black wolf in a low stance, ivory rune plates, broken
  horn, cyan mana jaw and ribs, hooked tail.
- Lantern Mimic: antique lantern opened into a toothed square maw, red glass
  eye, bent-handle feet and bronze body.
- Plague Moth: ragged broad wings, mask-like eye spots and bone-white
  plague-mask thorax.
- Crystal Drake: crouching juvenile drake, slate hide, folded wings and large
  blue crystal crest, shoulders and tail blade.
- Ruin Automaton: ivory ceramic guardian over black frame, horizontal teal
  visor, shield forearm, blade hand and red seal cloth.
- Ember Wraith: tapered cinder spirit, horned furnace mask, angular arms and
  three contained ember cracks.
- Frost Stalker: low six-legged navy feline, swept ice mane, icy forearm
  blades and pale-cyan eyes.
- Mire Oracle: squat amphibian seer inside a reed-limb ring, one amber central
  eye, moss crown and ivory belly rune.
- Fungal Knight: wide mushroom-cap helmet, moss plate skirt, bark shield arm
  and blunt root-sword arm.
- Void Scribe: floating robed construct, vertical glyph-eye, parchment sleeve
  blades and chained closed book.
- Chain Ogre: hunched one-eyed ogre, broken iron collar, chain-wrapped
  forearms, scrap shoulder armor and ivory tusks.
- Shattered Seraph: cracked porcelain automaton, four blade-like stone wings,
  broken attached halo and crimson sash.

追加ボスの追加指定:

- Thorn-Crowned King: colossal spectral stag, vast asymmetric branch-antler
  crown, cracked slate mask, deep-wine gem eye, moss mantle, shrine bells and
  armored chest.
- Crucible Colossus: two-legged obsidian furnace titan, caldera shoulders,
  circular ember core, hammer-like forearm, shield-like forearm and sealed
  horned head.
- Frostbound Oracle: nonhuman floating shrine sovereign, bell-shaped ice
  robes, ivory three-eyed mask, five-blade ice crown and broad frozen sleeves.

## 検証結果

- 既存通常敵は現行寸法を維持、既存番人は64x64
- 追加通常敵12種は全て48x48
- 追加ボス3種は全て64x64
- 全21体が15可視色、BGR555、アルファ0/255
- 全画像で透明四隅、欠落のない単一シルエットを確認
- 4倍・6倍比較画像と512x320実寸モックアップを目視確認済み
