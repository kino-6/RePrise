# 帝国軍・馴致魔獣候補

帝国軍の人型兵・機械兵に加える、捕獲・調教・制御された有機魔物6種。
魔物本体の形を主役にし、帝国装備は拘束具・制御具・小型魔力セルに限定した。
`assets/` へは未反映。

## 一覧

| ID | 表示名案 | 戦場での用途 | シルエット |
|---|---|---|---|
| `war_boar` | 鎧牙猪 | 前線突破・体当たり | 低く幅広い猪、長い牙、額の衝角板 |
| `cinder_drake` | 灼炉竜 | 火炎制圧 | 翼のない低い竜、長い尾、開放型の口枷 |
| `ironbeak_griffin` | 鉄嘴獅鷲 | 飛行追撃・斥候 | 大きな左右非対称の翼、鷲頭、獅子の後肢 |
| `shock_mantis` | 電甲蟷螂 | 待ち伏せ・高速斬撃 | 鎌状の前肢、細い六脚、長い触角 |
| `siege_tortoise` | 城塞亀 | 生体遮蔽・防衛 | 低い甲羅、太い四肢、甲羅を締める鉄帯 |
| `aether_leech` | 導脈蛭 | 魔力吸収・妨害 | とぐろを巻く軟体、環状の口、触手、拘束環 |

## 成果物

- `candidate_imperial_beast_<id>_source.png`: Imagegen原画。
- `candidate_imperial_beast_<id>.png`: 48×48 pxのゲーム規格候補。
- `candidate_imperial_beast_<id>_preview.png`: 8倍拡大確認画像。
- `candidate_imperial_beasts_6_contact.png`: 魔獣6種の比較画像。
- `candidate_imperial_beasts_actual_scale_mockup.png`: 512×320上の実寸確認。
- `candidate_imperial_all_21_contact.png`: 兵士・機械・魔獣・ボスを含む帝国系21種の比較画像。

## 共通生成プロンプト

> Use case: stylized-concept. Asset type: one static 48x48 battle-enemy sprite
> candidate for an original late-SFC industrial-fantasy JRPG. Create exactly
> one organic monster captured, trained, and fielded by an oppressive
> industrial empire. Polished late-16-bit pixel-art concept with large
> deliberate pixel clusters, crisp blue-black outer contour, restrained
> internal highlights, and a readable silhouette at 48x48. Serious and
> threatening, not cute, pop, toy-like, or chibi. Exactly one full creature,
> centered in a front three-quarter battle pose. The creature must remain
> visibly organic. Add only limited blackened-iron, antique-brass,
> dark-canvas and leather restraint or command gear. Imperial equipment must
> cover less than one third of the body and look brutally retrofitted, not
> robotic. Use a perfectly flat uniform #00ff00 chroma-key background.
> No rider, handler, humanoid, floor, shadow, particles, environment, text,
> insignia, logo, UI, border, grid, frame, watermark, named commercial
> design, or modern real-world equipment.

各個体には一覧の体型・用途に加え、以下を追加指定した。

- 鎧牙猪: 粗い黒毛、傷、長い牙、額の鉄板、革の拘束具、琥珀色の制御セル。
- 灼炉竜: 炭色の鱗、喉の熾火、口枷、喉の弁、無人の鞍具、小型熱槽。
- 鉄嘴獅鷲: 鷲獅子の有機体、一方を上げた翼、嘴当て、胸帯、指令リボン。
- 電甲蟷螂: 有機的な外骨格、非対称の鎌、青い神経光、首輪、小型制御節。
- 城塞亀: 有機的な甲羅と四肢、少数の甲羅留め、搬送帯、指令鈴。砲塔は付けない。
- 導脈蛭: 炭紫色の軟体、歯の輪、腹側触手、青い皮下脈、拘束環、魔力槽の籠。

生成にはCodex組み込みのImagegenを使用した。

## 変換・検算

クロマキーを除去し、原画を48×48 pxへ縮小後、シート単位で可視15色以内に量子化。
各色をBGR555相当へ丸め、アルファ値を0 / 255へ固定した。

全6種で以下を確認済み。

- 48×48 px
- 可視色15色以内
- 全可視色がBGR555相当
- アルファ値は0 / 255のみ
- 四隅が透明
- シルエットの欠落なし
- 8倍比較画像と512×320実寸画像を目視確認

`assets/`、敵データ、戦闘バランス、ゲームロジックには未反映。
