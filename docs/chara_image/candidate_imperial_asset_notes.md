# 産業幻想・帝国軍アセット候補

作成日: 2026-07-30

SFC後期RPGの産業幻想・軍制・魔導工学を題材にした独自勢力。
特定作品の機体、兵士、紋章、名称は使用していない。

組み込みの imagegen で各ユニットを1体ずつ生成し、クロマキー除去後に
ゲーム寸法へ縮小、BGR555・15可視色・二値アルファへ整形した。
`assets/`、`data/monsters.json`、戦闘バランス、出現表には未反映。

## 帝国兵6種

| ID | 仮称 | 想定役割 |
|---|---|---|
| `rifleman` | 帝国銃兵 | 標準遠隔兵 |
| `lancer` | 帝国盾槍兵 | 防御・隊列兵 |
| `officer` | 帝国監察官 | 指揮・強化 |
| `magus` | 軍属魔導士 | 魔法・属性攻撃 |
| `medic` | 衛生技官 | 回復・状態支援 |
| `sapper` | 帝国工兵 | 防御破壊・設置攻撃 |

比較画像: `candidate_imperial_soldiers_6_contact.png`

## 帝国機械・遺物6種

| ID | 仮称 | 想定役割 |
|---|---|---|
| `clockwork_hound` | 機装猟犬 | 高速追跡 |
| `sentry_orb` | 監視球 | 索敵・遠隔 |
| `boiler_automaton` | ボイラー機兵 | 量産前衛 |
| `siege_walker` | 二脚砲台 | 範囲砲撃 |
| `iron_cavalier` | 鉄騎兵 | 重装エリート |
| `ash_revenant` | 灰の廃兵 | 暗黒・自己再生 |

比較画像: `candidate_imperial_machines_6_contact.png`

## 帝国ボス3種

| ID | 仮称 | 識別点 |
|---|---|---|
| `land_dreadnought` | 帝国陸上艦 | 四脚砲郭と中央炉 |
| `iron_margrave` | 鉄侯 | 外套状装甲、盾、杭打ち腕 |
| `aetheric_war_engine` | 天穹炉機 | 縦型炉心と壊れた回転環 |

比較画像: `candidate_imperial_bosses_3_contact.png`

## ファイル

- `candidate_imperial_enemy_<id>_source.png`: imagegen方向性原画
- `candidate_imperial_enemy_<id>.png`: 48x48ゲーム規格候補
- `candidate_imperial_enemy_<id>_preview.png`: 拡大プレビュー
- `candidate_imperial_boss_<id>_source.png`: ボス方向性原画
- `candidate_imperial_boss_<id>.png`: 64x64ゲーム規格候補
- `candidate_imperial_boss_<id>_preview.png`: ボス拡大プレビュー
- `candidate_imperial_enemies_12_contact.png`: 通常敵12種
- `candidate_imperial_all_15_contact.png`: 全15種
- `candidate_imperial_actual_scale_mockup.png`: 通常敵の512x320実寸例
- `candidate_imperial_bosses_actual_scale_mockup.png`: ボスの実寸例

## 生成プロンプト

全種共通:

> Use case: stylized-concept. Asset type: one battle-enemy sprite concept for
> an original industrial-fantasy empire. Use the supplied project images only
> for approved late-16-bit density, heavy material rendering, outline weight
> and frontal battle presentation; do not copy their exact bodies. Sober
> late-SFC industrial fantasy with grounded imperial military engineering:
> blackened iron, gunmetal, antique brass, dark canvas, leather, hoses,
> rivets and contained arcane reactors. Disciplined, oppressive and weathered,
> not colorful, cute, toy-like or pop. Polished pixel-art concept translated
> into large deliberate clusters with a crisp blue-black outline and
> restrained highlights, readable at 48x48 or 64x64. Exactly one centered
> enemy, front three-quarter pose, isolated on a uniform chroma-key
> background. No floor, shadow, particles, environment, text, insignia,
> logo, UI or watermark. No named commercial design, chibi proportions,
> mascot face, glossy toy finish or modern real-world vehicle.

兵士別の追加指定:

- Rifleman: lean armored infantry, closed kettle helmet, narrow amber visor,
  short rune rifle, gunmetal breastplate, crimson shoulder tab and three
  brass mana cells.
- Lancer: broad soldier behind a tall riveted shield, telescoping spear,
  closed sallet, square shoulders and reinforced boots.
- Officer: split black military coat, half-mask with red lens, low saber,
  brass command relay and folded signal baton.
- Magus: rigid iron hood frame, dark veil, hose-fed gauntlet, compact brass
  aether tank, short tuning-fork focus and armored robe panels.
- Medic: ivory beaked respirator, reagent backpack, hose-fed injector tool,
  leather apron, sealed vials and no real-world medical symbol.
- Sapper: low blast helmet, square tool pack, mechanical gripping gauntlet,
  rivet hammer and cable coil.

機械別の追加指定:

- Clockwork Hound: low riveted quadruped, wedge skull, piston rear legs,
  red sensor slit, ceramic jaw and brass governor.
- Sentry Orb: heavy iron sphere, attached aether vanes, amber lens, folding
  gun ports, cable claw and maintenance hatch.
- Boiler Automaton: cylindrical boiler torso, piston shoulders, clamp hands,
  barred gauge, bent exhaust and contained red heat seam.
- Siege Walker: reverse-jointed legs, low hull, short aether cannon,
  counterweight coil and narrow observation visor.
- Iron Cavalier: enclosed power armor, buried visor, pile-driver forearm,
  slab guard, cable spine and crimson waist pennant.
- Ash Revenant: scorched empty armor, dim cyan slit, hollow rib breastplate,
  failed core and unusable rifle fused across the torso.

ボス別の追加指定:

- Land Dreadnought: wide low fortress on four articulated legs, central
  casemate, thick forward cannon, two side turrets and exposed reactor cage.
- Iron Margrave: ceremonial power armor, split coat plates, masked helmet,
  command shield, pile-bunker arm, ivory mantle and brass cable spine.
- Aetheric War Engine: vertical reactor in a broken brass gyroscope ring,
  barred cyan core, three armor fins, stabilizer pylons and ring cannons.

## 検証

- 通常敵12種: 全て48x48
- ボス3種: 全て64x64
- 全15種: 15可視色、BGR555、アルファ0/255
- 全画像で透明四隅と欠落のないシルエットを確認
- 4〜6倍比較画像と512x320実寸モックアップを目視確認済み
