"""候補・生成物・実行時参照の三段を検査する。

    python tools/check_assets.py
    python tools/check_assets.py --selftest   # 検査器そのものを試す

**「画像はあるが一度も出ない」を繰り返さないための関門。**

このリポジトリで何度も起きた失敗がこれだった ―― NPC の絵が用意されていたのに
主人公の絵を流用していた、エフェクトを生成したのに参照が無かった、
背景を描いたのに階調背景のままだった。どれも**動くので気づけない**。

三段を数える。

    候補   docs/chara_image/candidate_*.png   （外から置かれた原画）
    生成物 assets/**/*.png                    （生成器が採用したもの）
    参照   src/**/*.gd                        （実行時に読む記述）

**1 枚でも未接続なら落とす。** 以前は「全部が未接続」のときしか落とさず、
4 枚中 1 枚でも繋がっていれば「生成済みはすべて参照されている」と表示していた。
保留したいものは `PENDING` に**タスク ID 付きで**書く。ID の無い理由は
書き捨てになり、いつまでも残る。
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
    # 生成物に接頭辞は付かない（`assets/transitions/iris_gate.png`）。
    # `transition_` で探していたので「生成 0 / 候補があるが取り込んでいない」と
    # 誤報していた ―― 実際は 4 枚とも生成済みで、未接続なだけだった。
    ("トランジション", "candidate_transition_", "transitions", ""),
    ("マップチップ",  "candidate_tiles_",      "tiles",       ""),
]

# まだ繋いでいないと分かっていて、いま落としたくないもの。
#
# **キーは生成物の名前、値には必ずタスク ID を書く。**
# 分類ごとに保留していたので、その分類の絵は何枚増えても素通りだった。
# 理由だけ書くと「あとで」のまま残る。空にするのが目標。
PENDING: dict[str, str] = {
    # B-3 で採用を見送った。洞・町・世界の出入りは遭遇と同じモザイクにした
    # ―― 角形の画素が増殖する覆いは甘く、中途半端な演出は無いほうがましだった。
    "pixel_dissolve": "B-3 採用見送り（洞の出入りはモザイクへ）",
}

## タスク ID の形（`B-3`、`D-4`、`C-10` など）。
TASK_ID = re.compile(r"\b[A-Z]-\d+\b")


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
        if any(stem.endswith(s) for s in ("_preview", "_source", "_mockup", "_contact")):
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


def judge(unreferenced: dict[str, set[str]], pending: dict[str, str]) -> list[str]:
    """未接続の一覧から、落とす理由を組み立てる。**ここが判定の全部。**

    実データからも `--selftest` の作り物からも同じ関数を通すので、
    「本番は通るのに検査器のほうが壊れている」が起きない。
    """
    failures: list[str] = []
    for label, stems in sorted(unreferenced.items()):
        loose = sorted(s for s in stems if s not in pending)
        if loose:
            failures.append(
                "%s: %d 枚が生成済みなのに一度も読まれていない（%s）"
                % (label, len(loose), "、".join(loose))
            )
    # 保留にはタスク ID を必須にする。**ID の無い保留は保留ではなく放置。**
    for stem, why in sorted(pending.items()):
        if not TASK_ID.search(why):
            failures.append("保留 %s の理由にタスク ID が無い（%r）" % (stem, why))
    return failures


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()

    text = _source_text()
    unreferenced: dict[str, set[str]] = {}

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
        missing = made - referenced
        if missing:
            unreferenced[label] = missing
        held = sorted(s for s in missing if s in PENDING)
        loose = sorted(s for s in missing if s not in PENDING)
        note = ""
        if loose:
            note = "  ← **%d 枚が一度も読まれていない**（%s）" % (
                len(loose), "、".join(loose))
        elif held:
            note = "  ← %d 枚を保留（%s）" % (len(held), PENDING[held[0]])
        elif cands and not made:
            note = "  ← 候補があるが取り込んでいない"
        print(
            "  %-12s 候補 %3d / 生成 %3d / 参照 %3d%s"
            % (label, len(cands), len(made), len(referenced), note)
        )

    print("---")
    failures = judge(unreferenced, PENDING)
    if failures:
        for f in failures:
            print("  - %s" % f)
        return 1
    print("生成済みのものはすべて参照されている")
    if PENDING:
        print("（保留: %s）" % "、".join(sorted(PENDING)))
    return 0


def _selftest() -> int:
    """**検査器そのものを試す。** 正常系だけ見ても、壊れた関門は見つからない。

    実際この関門は 3 度嘘をついた ―― 敵を「参照 0」と誤報し、
    トランジションを「生成 0」と誤報し、4 枚中 1 枚しか繋がっていなくても
    「すべて参照されている」と言った。どれも本番では静かに通っていた。
    """
    cases = [
        ("未接続が 1 枚でもあれば落ちる", {"演出": {"a", "b"}}, {"a": "B-3 理由"}, 1),
        ("全部が保留なら通る", {"演出": {"a"}}, {"a": "B-3 理由"}, 0),
        ("未接続が無ければ通る", {}, {}, 0),
        ("ID の無い保留は落ちる", {}, {"a": "あとでやる"}, 1),
    ]
    bad = 0
    for name, unref, pending, want in cases:
        got = 1 if judge(unref, pending) else 0
        ok = got == want
        bad += 0 if ok else 1
        print("  %s  %s（終了コード %d を期待、%d）" % (
            "OK" if ok else "NG", name, want, got))
    print("---")
    if bad:
        print("検査器が壊れている（%d 件）" % bad)
        return 1
    print("検査器は期待どおり動く（%d 件）" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
