# キャラクタースプライト差し替え候補

`imagegen` の組み込み画像生成で設定画を参照し、後期 SFC 風の歩行シートへ
落とし込んだ候補。現行の `assets/` と `tools/gen_assets.py` は変更していない。

## 成果物

| 職業 | 設定画 | ゲーム用候補 |
|---|---|---|
| せんし | `ComfyUI2026_405869_face.png` | `candidate_hero_soldier.png` |
| そうりょ | `ComfyUI2026_411700_face.png` | `candidate_hero_priest.png` |
| まほうつかい | `ComfyUI2026_406109_face.png` | `candidate_hero_mage.png` |
| とうぞく | `ComfyUI2026_407888_face.png` | `candidate_hero_thief.png` |
| せいきし | `ComfyUI2026_414950_face.png` | `candidate_hero_paladin.png` |
| にんじゃ | `ComfyUI2026_408302_face.png` | `candidate_hero_ninja.png` |

- `candidate_hero_*.png`: 72x128、透過済みの差し替え候補。
- `candidate_hero_*_preview.png`: 8 倍の目視確認用。
- `candidate_hero_*_source.png`: 画像生成器から得た高解像度のクロマキー原画。
- `candidate_heroes_contact.png`: 6 職を一度に比較する確認用画像。

## シート仕様

- 1 コマ 24x32、3 列 x 4 行、合計 12 コマ。
- 行順は正面、左、右、背面。
- 各行は停止、左足、右足。
- 各コマは下端を基準に配置。
- 透明を除いて 12〜13 色。上限 15 色を超えない。
- RGB は `tools/sfc_art.py` と同じ BGR555 表示値へ量子化。
- アルファは 0 / 255 のみ。

## 生成プロンプト

全職共通のプロンプトは次の指定を使用した。

```text
Use case: stylized-concept
Asset type: production-ready late-16-bit JRPG overworld character sprite sheet
Input images: Image 1 is the character identity and design reference.
Image 2 is the current low-quality sprite sheet and is used ONLY to communicate
the required 3-columns-by-4-rows frame order. Do not preserve its crude design.

Redraw the character from Image 1 as a polished late-SFC-era overworld pixel-art
sprite sheet with a slightly modern anime character-design sensibility.

EXACTLY 12 separate frames in a rigid 3 columns x 4 rows grid.
Row 1 = facing camera/down, idle-left-step-right-step.
Row 2 = facing screen-left, idle-left-step-right-step.
Row 3 = facing screen-right, idle-left-step-right-step.
Row 4 = facing away/up, idle-left-step-right-step.
Every frame is the same scale, aligned to the same bottom baseline, centered in
its cell, and shows one full body. No frame may overlap another.

Each frame must read as a genuine 24x32 logical-pixel game sprite, displayed with
large perfectly square nearest-neighbor pixels. Crisp hard pixel clusters only:
no anti-aliasing, blur, painterly brushwork, or vector-smooth curves. Use
selective dark outlines, a strong silhouette, clustered shading, compact readable
facial features, and dense top-tier late-16-bit console RPG polish.

Use one coherent SFC-compatible character subpalette, maximum 15 visible subject
colors plus transparency key, with BGR555-friendly stepped colors.

The backdrop is perfectly flat uniform solid #00FF00 chroma key. Output only the
sprite sheet: no title, labels, grid lines, borders, UI, floor, shadow, glow,
particles, loose weapons, watermark, signature, or extra characters. Do not use
#00FF00 in the character. Keep all frames clearly separated.
```

職業ごとの主題指定は次のとおり。

```text
soldier:
Adult woman warrior; long ivory-white hair, vivid blue eyes, turquoise forehead
band, pale antler-like or winged head ornament with dark-blue ribbons,
silver-and-charcoal fitted armor, and a deep cobalt short cloak.

priest:
Adult woman healer-priest; short mint-to-silver hair, deep teal hood and layered
cloak, rose-pink lining, magenta reliquary jewel, ivory vestments, and charcoal
gloves and boots.

mage:
Adult blonde witch; long golden hair, large black pointed hat with violet
underside, magenta gemstone ornament, and an elegant black/deep-violet robe.

thief:
Adult woman rogue; long blue-black hair with cat-ear-like twin tufts, amber-gold
eyes, gold bell and pink knot ornaments, rust-red scarf, and a dark navy rogue
outfit.

paladin:
Adult woman sacred knight; short ivory hair, crimson eyes, black-and-ivory
crown-like armored headpiece with a central red gem, fitted plate armor, and
restrained crimson/antique-gold trim.

ninja:
Adult woman shinobi; short charcoal bob with a tied-back section, red-orange
eyes, low black armored headguard, graphite layered clothing, and a deep crimson
hood-scarf and sash.
```

生成後はクロマキーを除去し、各セルでキャラクター本体の連結領域だけを残して
24x32 に縮小した。最後に 15 色以下へ整理し、BGR555 量子化を行っている。
