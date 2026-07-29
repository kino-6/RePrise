# 追加アセット候補

前回のキャラクター候補と同じ雰囲気を保って作成した、マップチップと
拡張職の候補。組み込みの `imagegen` で原画を作り、実際のゲーム寸法へ
縮小・整理した。

`assets/`、`tools/gen_assets.py`、`data/jobs.json` にはまだ反映していない。

## マップチップ

| ファイル | 用途 |
|---|---|
| `candidate_tiles_dungeon.png` | ゲーム用候補。144x16、16x16 を 9 枚 |
| `candidate_tiles_dungeon_preview.png` | 8 倍のタイル確認用 |
| `candidate_tiles_dungeon_mockup.png` | 実寸タイルと既存候補キャラを使った配置確認 |
| `candidate_tiles_dungeon_source.png` | `imagegen` が作った高解像度の美術原画 |

タイル順は既存の `assets/tiles/dungeon.png` と同じ。

1. 通常床
2. ひび割れ床
3. 壁面
4. 壁の天面
5. 階段
6. 主の扉
7. 宝箱
8. 虚空
9. 出店

床は正方形の目地を廃止し、継ぎ目をまたぐ不規則な石組みにした。壁面と
壁の天面は明度を分け、通れる床と通れない地形が一目で分かるようにしている。
階段・扉・宝箱・出店は、16x16 でもシルエットで用途を判別できる。

### マップ原画のプロンプト

```text
Use case: stylized-concept
Asset type: production-ready late-16-bit JRPG dungeon tileset source board
Input images:
Image 1 is only the current nine-tile order and semantic layout reference.
Image 2 is the approved character-sprite style and palette-harmony reference.
Image 3 is the gameplay context and readability reference.

Create a polished late-SFC-era dark-fantasy dungeon tileset with a slightly
modern anime-fantasy sensibility. The environment is a forgotten subterranean
citadel: cool slate and blue-black stone, muted violet shadows, aged bronze,
and restrained ivory and crimson accents.

Create exactly nine equal square cells in a rigid 3x3 grid:
floor, cracked floor, wall face,
wall top, descending stairs, sealed boss door,
closed chest, solid #00FF00 void key, tiny dungeon shop.

Each cell must read as a genuine 16x16 logical-pixel tile. Use crisp square
pixel clusters, selective outlines, clustered shading, restrained texture,
upper-left lighting, and one coherent SFC-compatible palette of at most
15 visible colors. Floor tiles must be seamless and must not have a square
frame. Floor must be lighter than wall tops. Interactive tiles must remain
recognizable at actual size.

No gutters, labels, borders, characters, monsters, UI, text, watermark,
anti-aliasing, blur, painterly detail, or photorealism.
```

生成原画をそのまま縮小すると細部が潰れるため、原画の石組み・寒色・金属装飾を
基準に、最終 16x16 版では形と明度を再整理している。

## 拡張職

現行の6職は前回ですべて作成済みだったため、残っていた3枚の設定画を
将来用の拡張職候補へ割り当てた。今回は画像のみで、職業能力や解放条件は
ゲームへ追加していない。

| 仮 ID | 仮称 | 設定画 | 想定する組み合わせ |
|---|---|---|---|
| `spellblade` | まけんし | `face copy 2.png` | せんし + まほうつかい |
| `summoner` | しょうかんし | `face copy.png` | そうりょ + まほうつかい |
| `ranger` | かりうど | `face.png` | せんし + とうぞく |

各職共通で次を出力した。

- `candidate_hero_<id>.png`: 72x128 のゲーム用候補。
- `candidate_hero_<id>_preview.png`: 8 倍の確認用。
- `candidate_hero_<id>_source.png`: 高解像度クロマキー原画。
- `candidate_expansion_jobs_contact.png`: 3職の比較画像。
- `candidate_heroes_contact_all.png`: 現行候補6職を含む9職の比較画像。

### 拡張職の共通プロンプト

```text
Use case: stylized-concept
Asset type: production-ready late-16-bit JRPG overworld character sprite sheet
for an expansion job

Image 1 is the new character identity and design reference.
Image 2 is an approved style, scale, pixel-density, chroma-background, and
exact 3-columns-by-4-rows layout reference only.

Translate Image 1 into the requested advanced job while preserving the approved
modern-anime-meets-late-SFC atmosphere.

Create exactly 12 separate full-body frames in a rigid 3x4 grid.
Rows: facing down, left, right, up.
Columns: idle, left step, right step.
Use the same scale and bottom baseline in every cell.

Every frame must read as a genuine 24x32 logical-pixel overworld sprite.
Use crisp hard pixel clusters, selective dark outlines, compact expressive
facial features, a job-specific silhouette, clustered shading, and at most
15 visible BGR555-friendly subject colors.

Use a perfectly flat uniform #00FF00 chroma-key background.
No labels, grid lines, UI, floor, shadows, effects, weapons, text, watermark,
extra characters, anti-aliasing, blur, or painterly strokes.
```

職ごとの主題は次のように指定した。

```text
spellblade:
Silver-white one-eye fringe; black/crimson combat circlet with a central eye
gem; light charcoal plate-and-cloth battle dress; angular red split mantle.
Lighter and more arcane than the paladin.

summoner:
Long silver-white hair; magenta eyes; paired dark-crimson horn ornaments;
black high collar; ivory/charcoal/deep-wine ritual coat; broad split sleeves
and a central seal. No hat, hood, armor, staff, or summoned creature.

ranger:
Long silver-white hair; magenta eyes; ivory field cap with a small antique-gold
compass-leaf emblem; charcoal fitted coat; short muted moss-blue cape; leather
belts and pouches. No plate armor, red scarf, bow, gun, or loose weapon.
```

生成後はクロマキーを除去し、各セルのキャラクター本体だけを残して 24x32 へ
縮小した。各シートは透明を除いて 15 色以下、BGR555、アルファ 0 / 255 に
整理している。
