"""候補アセットの取り込み可否を一覧する。

    python tools/check_candidates.py

`docs/chara_image/` に置かれた candidate_*.png を測って、生成器が採用するかを出す。
別のエージェントが素材を置いたら、まずこれを回して「何が通って何が落ちるか」を見る。
落ちた理由は数値で出るので、そのまま描き直しの指示になる。

条件は tools/gen_assets.py 側と同じ:
  * 透明を除いて 15 色以内
  * アルファは 0 か 255 だけ
  * BGR555 に乗っていない色は取り込み時に丸める（落とさない）
  * 味方 72x128 / タイル 144x16 / 敵と主は 64x64 以内
  * タイルは床と壁の色が RGB 距離 40 以上 離れていること
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from sfc_art import load_png, snes  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "chara_image"

MAX_COLORS = 15
HERO_SIZE = (72, 128)
TILESET_SIZE = (144, 16)
MONSTER_MAX = (64, 64)
MIN_FLOOR_WALL_DISTANCE = 40.0


def tile_mean(sheet, index: int, tile: int = 16) -> tuple[float, float, float]:
    px = [
        sheet.get(index * tile + x, y)
        for y in range(tile)
        for x in range(tile)
        if sheet.get(index * tile + x, y)[3]
    ]
    n = max(len(px), 1)
    return tuple(sum(p[i] for p in px) / n for i in range(3))


def check(path: Path) -> tuple[str, str]:
    sheet = load_png(path)
    colors = {p[:3] for p in sheet.px if p[3] == 255}
    alphas = {p[3] for p in sheet.px}
    off = sum(1 for c in colors if snes("#%02X%02X%02X" % c) != c)
    note = f"{sheet.w}x{sheet.h} {len(colors)}色"
    if off:
        note += f" 丸め{off}色"

    if not alphas <= {0, 255}:
        return "落", note + " アルファが 2 値でない"
    if len(colors) > MAX_COLORS:
        return "落", note + f" 色が多い（上限 {MAX_COLORS}）"

    name = path.stem
    if name.startswith("candidate_hero_"):
        if (sheet.w, sheet.h) != HERO_SIZE:
            return "落", note + f" 寸法が違う（{HERO_SIZE[0]}x{HERO_SIZE[1]} 必要）"
        return "通", note
    if name.startswith("candidate_tiles_"):
        if (sheet.w, sheet.h) != TILESET_SIZE:
            return "落", note + f" 寸法が違う（{TILESET_SIZE[0]}x{TILESET_SIZE[1]} 必要）"
        gap = math.dist(tile_mean(sheet, 0), tile_mean(sheet, 2))
        if gap < MIN_FLOOR_WALL_DISTANCE:
            return "落", note + f" 床と壁の距離 {gap:.1f}（{MIN_FLOOR_WALL_DISTANCE:.0f} 必要）"
        return "通", note + f" 床と壁の距離 {gap:.1f}"
    if sheet.w > MONSTER_MAX[0] or sheet.h > MONSTER_MAX[1]:
        return "落", note + f" 大きすぎる（上限 {MONSTER_MAX[0]}x{MONSTER_MAX[1]}）"
    return "通", note


def main() -> None:
    targets = sorted(
        f for f in SOURCE.glob("candidate_*.png")
        if not any(k in f.name for k in ("_source", "_preview", "contact", "mockup"))
    )
    if not targets:
        print("候補が無い")
        return

    passed = 0
    for f in targets:
        verdict, note = check(f)
        if verdict == "通":
            passed += 1
        print(f"  [{verdict}] {f.stem:<40} {note}")
    print(f"\n{passed} / {len(targets)} 通る")


if __name__ == "__main__":
    main()
