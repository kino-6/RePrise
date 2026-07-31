"""技どうしが「押す理由」で分かれているかを見る（F-1）。

    python tools/check_abilities.py
    python tools/check_abilities.py --selftest

**同じ役割で数値だけ違う技を並べても、技は増えていない。** 強いほうだけが
使われて、弱いほうは一覧の場所を取るだけになる。40 技それぞれに
「通常攻撃より、また他の技より、これを押す状況」が要る。

判定は 2 つ。

  * **見劣り（dominated）。** 同じ役割（種別・対象・属性・効果）の技で、
    威力が同じか低く、MP も行動コストも同じか高いものがあれば、
    それは押す理由が無い。片方を消すか、役割を変える。
  * **同点（identical）。** 役割も威力も MP も行動コストも同じ技。

`allowlist` に載せるときは、**共有する設計理由と、それを使う職**を書く。
理由の無い許可は許可ではなく放置。

CTB なので「威力が低い代わりに軽い」は**正当な違い**であり、見劣りではない。
そこを潰すと、速い職の押し引きが消える。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 見劣りしていても残すもの。**共有する設計理由と、使う職を書く。**
ALLOWED: dict[str, str] = {
    # いまは空。足すときは「なぜ両方要るか」と「どの職が使うか」を書く。
}


def _role(ability: dict) -> tuple:
    """役割。ここが同じなら「同じ用途の技」とみなす。"""
    return (
        str(ability.get("kind", "")),
        str(ability.get("target", "")),
        str(ability.get("element", "")),
        str(ability.get("effect", "")),
    )


def _axes(ability: dict) -> tuple[int, int, int]:
    """押すときに払うもの・得るもの。**総威力** / MP / 行動コスト。

    **多段は掛け算で数える。** `れんげき` は威力 62 だが 3 回当たるので
    総威力は 186。段数を見ないと、多段技がすべて「通常攻撃に見劣り」と
    誤報される（実際そうなった）。
    段数の違いは、防御力の引かれ方でも意味が変わる（1 発ごとに引かれる）が、
    ここは「押す理由があるか」を見る関門なので、総量で足りる。
    """
    return (
        int(ability.get("power", 0)) * maxi(int(ability.get("hits", 1)), 1),
        int(ability.get("mp", 0)),
        int(ability.get("cost", 100)),
    )


def maxi(a: int, b: int) -> int:
    return a if a > b else b


def find_dominated(abilities: dict) -> list[tuple[str, str, str]]:
    """`(見劣りする技, 上位の技, 種類)` の一覧。"""
    out: list[tuple[str, str, str]] = []
    ids = sorted(abilities)
    for a in ids:
        for b in ids:
            if a == b:
                continue
            if _role(abilities[a]) != _role(abilities[b]):
                continue
            pa, ma, ca = _axes(abilities[a])
            pb, mb, cb = _axes(abilities[b])
            # b が a と同じか良い（威力は高いほど、MP と行動コストは低いほど良い）
            better = pb >= pa and mb <= ma and cb <= ca
            same = (pa, ma, ca) == (pb, mb, cb)
            if not better:
                continue
            if same:
                # 同点は片方だけ挙げる（a < b の順で 1 回）。
                if a < b:
                    out.append((a, b, "同点"))
            else:
                out.append((a, b, "見劣り"))
    return out


def judge(dominated: list[tuple[str, str, str]], allowed: dict[str, str]) -> list[str]:
    """落とす理由。**ここが判定の全部。**"""
    problems: list[str] = []
    for weak, strong, kind in dominated:
        if weak in allowed:
            continue
        problems.append("%s は %s に%s（押す理由が無い）" % (weak, strong, kind))
    for name, why in sorted(allowed.items()):
        if "職" not in why:
            problems.append("許可 %s の理由に、使う職が書かれていない（%r）" % (name, why))
    return problems


def _selftest() -> int:
    """**検査器そのものを試す。** 正常系だけ見ても、壊れた関門は見つからない。"""
    same_role = {"kind": "physical", "target": "one_enemy"}
    cases = [
        (
            "完全に見劣りする技を見つける",
            {
                "weak": dict(same_role, power=50, mp=5, cost=120),
                "strong": dict(same_role, power=90, mp=3, cost=100),
            },
            {}, True,
        ),
        (
            "軽いぶん弱い技は見劣りではない",
            {
                "light": dict(same_role, power=50, mp=0, cost=55),
                "heavy": dict(same_role, power=185, mp=0, cost=175),
            },
            {}, False,
        ),
        (
            "役割が違えば比べない",
            {
                "a": dict(kind="physical", target="one_enemy", power=50, mp=5, cost=120),
                "b": dict(kind="magical", target="one_enemy", power=90, mp=3, cost=100),
            },
            {}, False,
        ),
        (
            "許可があれば通す",
            {
                "weak": dict(same_role, power=50, mp=5, cost=120),
                "strong": dict(same_role, power=90, mp=3, cost=100),
            },
            {"weak": "職 A と職 B が共有する入門技として両方要る"}, False,
        ),
        (
            "使う職の無い許可は落ちる",
            {}, {"weak": "あとで見る"}, True,
        ),
    ]
    bad = 0
    for name, abilities, allowed, want_fail in cases:
        got = bool(judge(find_dominated(abilities), allowed))
        ok = got == want_fail
        bad += 0 if ok else 1
        print("  %s  %s" % ("OK" if ok else "NG", name))
    # 奥義 Gate も、意図的に壊した「回数 2・固有ルールなし」を拒否する。
    broken_ultimate = {
        "broken": {
            "uses_per_battle": 2,
            "kind": "special",
            "target": "self",
            "effect": "ultimate_broken",
        }
    }
    ultimate_problems = check_ultimate_contracts(
        broken_ultimate, {}, "var _in_ultimate\nfunc ultimate_uses_left():\n\tpass")
    ultimate_ok = (
        any("1 戦 1 回ではない" in p for p in ultimate_problems)
        and any("固有ルールが無い" in p for p in ultimate_problems)
    )
    bad += 0 if ultimate_ok else 1
    print("  %s  %s" % ("OK" if ultimate_ok else "NG", "壊れた奥義契約を落とす"))
    print("---")
    if bad:
        print("検査器が壊れている（%d 件）" % bad)
        return 1
    print("検査器は期待どおり動く（%d 件）" % (len(cases) + 1))
    return 0


## 属性が「弱点倍率だけ」で終わっていないか（F-5）。
##
## 倍率しか無いと、弱点表を持たない相手に対して炎も氷も雷も同じ技になり、
## 「属性を切り替える」判断が消える。`_element_effect` に各属性の枝が要る。
ELEMENT_RULES = {
    "fire": "波及",
    "ice": "足止め",
    "bolt": "中断",
    "dark": "交換",
}


def check_vocabulary() -> list[str]:
    """職の「毎手番の問い」と、技の戦術語と、属性の効き目（F-5）。"""
    problems: list[str] = []
    jobs = {
        k: v for k, v in
        json.loads((ROOT / "data" / "jobs.json").read_text(encoding="utf-8")).items()
        if isinstance(v, dict)
    }
    for name, job in sorted(jobs.items()):
        if not str(job.get("question", "")).strip():
            problems.append("職 %s に「毎手番の問い」が無い" % name)

    abilities = {
        k: v for k, v in
        json.loads((ROOT / "data" / "abilities.json").read_text(encoding="utf-8")).items()
        if isinstance(v, dict)
    }
    for name, ability in sorted(abilities.items()):
        if not str(ability.get("role", "")).strip():
            problems.append("技 %s に戦術語が無い" % name)

    # 属性の効き目が**実装されている**こと。データだけ在っても意味が無い。
    source = (ROOT / "src" / "battle" / "battle_system.gd").read_text(encoding="utf-8")
    for element in sorted(ELEMENT_RULES):
        if '"%s":' % element not in source:
            problems.append(
                "属性 %s の効き目（%s）が実装されていない" % (element, ELEMENT_RULES[element]))
    return problems


def check_ultimate_contracts(
    abilities: dict, jobs: dict, source: str
) -> list[str]:
    """★7・8 奥義 30 種の、データと共通入口の接続を見る（F-6b）。"""
    problems: list[str] = []
    ultimate_ids = {
        name for name, ability in abilities.items()
        if int(ability.get("uses_per_battle", 0)) > 0
    }
    if len(ultimate_ids) != 30:
        problems.append("奥義が 30 種ではない（%d 種）" % len(ultimate_ids))

    rules: dict[str, str] = {}
    ranked: dict[int, list[str]] = {7: [], 8: []}
    for job_id, job in sorted(jobs.items()):
        for entry in job.get("mastery", []):
            rank = int(entry.get("rank", 0))
            if rank not in ranked:
                continue
            ability_id = str(entry.get("ability", ""))
            if ability_id:
                ranked[rank].append(ability_id)
    for rank in [7, 8]:
        if len(ranked[rank]) != 15:
            problems.append("★%d の奥義が 15 職ぶん無い（%d）" % (
                rank, len(ranked[rank])))

    for ability_id in sorted(ultimate_ids):
        ability = abilities[ability_id]
        if int(ability.get("uses_per_battle", 0)) != 1:
            problems.append("奥義 %s が 1 戦 1 回ではない" % ability_id)
        rule = str(ability.get("ultimate_rule", ""))
        if not rule:
            problems.append("奥義 %s に固有ルールが無い" % ability_id)
            continue
        if rule in rules:
            problems.append("奥義 %s と %s が同じ固有ルール %s" % (
                rules[rule], ability_id, rule))
        rules[rule] = ability_id
        if '"%s":' % rule not in source:
            problems.append("奥義 %s のルール %s が戦闘へ未接続" % (
                ability_id, rule))

    if "_in_ultimate" not in source:
        problems.append("奥義から奥義を再演しない再帰防止が無い")
    if "ultimate_uses_left" not in source:
        problems.append("奥義の残り回数を UI/オートから読めない")
    return problems


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    path = ROOT / "data" / "abilities.json"
    abilities = {
        k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items()
        if isinstance(v, dict)
    }
    dominated = find_dominated(abilities)
    print("技 %d 個を、役割（種別・対象・属性・効果）ごとに突き合わせた" % len(abilities))
    problems = judge(dominated, ALLOWED)
    problems += check_vocabulary()
    jobs = {
        k: v for k, v in
        json.loads((ROOT / "data" / "jobs.json").read_text(encoding="utf-8")).items()
        if isinstance(v, dict)
    }
    source = (ROOT / "src" / "battle" / "battle_system.gd").read_text(encoding="utf-8")
    problems += check_ultimate_contracts(abilities, jobs, source)
    if problems:
        for note in problems:
            print("  - %s" % note)
        print("---")
        print("押す理由が無い技が %d 件。役割を変えるか、統合する。" % len(problems))
        return 1
    print("---")
    print("押す理由が無い技は無い")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
