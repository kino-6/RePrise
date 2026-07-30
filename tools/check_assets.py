"""候補・生成物・実行時参照の三段を検査する。

    python tools/check_assets.py

**「画像はあるが一度も出ない」を繰り返さないための関門。**

このリポジトリで何度も起きた失敗がこれだった ―― NPC の絵が用意されていたのに
主人公の絵を流用していた、エフェクトを生成したのに参照が無かった、
背景を描いたのに階調背景のままだった。どれも**動くので気づけない**。

三段を数える。

    候補   docs/chara_image/candidate_*.png   （外から置かれた原画）
    生成物 assets/**/*.png                    （生成器が採用したもの）
    参照   src/**/*.gd                        （実行時に読む記述）

採用済み（生成物がある）なのに参照が 0 なら落とす。
候補があるのに生成物が無いものは「まだ取り込んでいない」として報告だけする
（取り込む判断は人がするので、ここでは落とさない）。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAND = ROOT / "docs" / "chara_image"
ASSETS = ROOT / "assets"
SRC = ROOT / "src"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 分類ごとに（候補の接頭辞, 生成物の場所, 生成物の接頭辞）。
#
# 参照は「生成物のファイル名の幹」がソースに出るかで見る。パスを組み立てて
# 読む書き方（"res://assets/sprites/hero_%s.png" % job）があるので、
# 幹そのものではなく**接頭辞と、それを組み立てている行**の両方を探す。
GROUPS = [
    ("職業",          "candidate_hero_",       "sprites",     "hero_"),
    ("NPC",           "candidate_npc_",        "sprites",     "npc_"),
    # 敵だけは接頭辞が無い（`assets/sprites/<敵id>.png`）。
    # 接頭辞で探して 0 と誤報していた。**嘘をつく関門は無いより悪い。**
    ("敵",            "candidate_enemy_",      "sprites",     "@monster"),
    ("戦闘背景",      "candidate_battle_bg_",  "backgrounds", "battle_bg_"),
    ("イベントFX",    "candidate_fx_",         "effects",     "fx_"),
    ("イベント演出",  "candidate_event_",      "effects",     "event_"),
    ("トランジション", "candidate_transition_", "transitions", "transition_"),
    ("マップチップ",  "candidate_tiles_",      "tiles",       ""),
]

# 「まだ取り込んでいない」ことが分かっていて、いま落としたくないもの。
# **理由を書くこと。** 空にするのが目標。
KNOWN_PENDING = {
    "トランジション": "B-3 / 閃光の調査と一緒に入れる",
}


def _monster_sprites() -> set[str]:
    """`data/monsters.json` が使う絵の名前。敵の絵は接頭辞を持たない。"""
    import json
    path = ROOT / "data" / "monsters.json"
    if not path.exists():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        str(v.get("sprite", "")) for v in data.values()
        if isinstance(v, dict) and v.get("sprite")
    }


def _stems(folder: Path, prefix: str) -> set[str]:
    if not folder.exists():
        return set()
    if prefix == "@monster":
        wanted = _monster_sprites()
        return {p.stem for p in folder.glob("*.png") if p.stem in wanted}
    return {
        p.stem for p in folder.glob("*.png")
        if prefix == "" or p.stem.startswith(prefix)
    }


def _candidates(prefix: str) -> set[str]:
    out = set()
    for p in CAND.glob(f"{prefix}*.png"):
        stem = p.stem
        # 参考用の派生（_preview / _source / _mockup）は候補として数えない
        if any(stem.endswith(suffix) for suffix in ("_preview", "_source", "_mockup", "_contact")):
            continue
        out.add(stem[len(prefix):])
    return out


def _source_text() -> str:
    """ソースとデータを 1 つの文字列にする。

    名前を組み立てて読む書き方（`"npc_%s.png" % role`）があるので、パスだけを
    探しても足りない。**その名前がどこかの表に載っているか**で見る必要があり、
    表は `src/` にも `data/` にもある（職業 id は data/jobs.json）。
    """
    parts = []
    for p in SRC.rglob("*.gd"):
        parts.append(p.read_text(encoding="utf-8", errors="replace"))
    for p in (ROOT / "data").glob("*.json"):
        parts.append(p.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(parts)


def main() -> int:
    text = _source_text()
    failures: list[str] = []

    print("候補 / 生成物 / 参照")
    for label, cand_prefix, folder, asset_prefix in GROUPS:
        cands = _candidates(cand_prefix)
        made = _stems(ASSETS / folder, asset_prefix)
        # 参照の数え方。
        #
        # **「組み立てているから全部参照済み」とは数えない。** `npc_%s.png` の
        # ような書き方があるだけで 17 種すべてを参照済みと数えていたが、
        # 実際に繋がっていたのは 5 種だけだった（役の表に 5 つしか無い）。
        # 幹そのもの、または接頭辞を除いた**名前**が表に載っているかで見る。
        referenced = set()
        for stem in made:
            key = stem if asset_prefix in ("", "@monster") else stem[len(asset_prefix):]
            if stem in text or (key and re.search(r'"%s"' % re.escape(key), text)):
                referenced.add(stem)
        note = ""
        if made and referenced and len(referenced) < len(made):
            # **落としはしないが、見えるようにする。** ここが「絵はあるのに
            # 半分しか出ない」の温床で、数字が並んでいれば気づける。
            note = "  ← %d 枚が未接続" % (len(made) - len(referenced))
        if made and not referenced:
            if label in KNOWN_PENDING:
                note = f"  ← 未接続（{KNOWN_PENDING[label]}）"
            else:
                note = "  ← **生成済みなのに一度も読まれていない**"
                failures.append(f"{label}: {len(made)} 枚が参照 0")
        elif cands and not made:
            note = "  ← 候補があるが取り込んでいない"
        print(
            "  %-12s 候補 %3d / 生成 %3d / 参照 %3d%s"
            % (label, len(cands), len(made), len(referenced), note)
        )

    print("---")
    if failures:
        print("生成済みなのに使われていない分類 %d 件" % len(failures))
        for f in failures:
            print(f"  - {f}")
        return 1
    print("生成済みのものはすべて参照されている")
    if KNOWN_PENDING:
        print("（未接続として明示しているもの: %s）" % "、".join(KNOWN_PENDING))
    return 0


if __name__ == "__main__":
    sys.exit(main())
