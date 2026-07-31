"""ゲーム内文章の差し替え構造と、既知のAI文事故を検査する。

    python tools/check_writing.py
    python tools/check_writing.py --selftest

文章の良し悪きを機械だけで決めるのではなく、過去に実画面で起きた回帰を止める。
画面幅、町台詞のデータ化、話者と地の文の混同、意味深な定型句を対象にする。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EXPECTED_ROLES = {
    "innkeeper",
    "merchant",
    "elder",
    "scout",
    "guard",
    "blacksmith",
    "healer",
    "farmer",
    "miner",
    "ferryman",
    "mechanic",
    "scribe",
    "pilgrim",
    "refugee",
    "performer",
    "beastkeeper",
    "imperial_officer",
}
EXPECTED_PROFILES = {
    "industries": {
        "farming",
        "mining",
        "trade",
        "workshop",
        "pilgrimage",
        "beast_ranch",
        "ferry",
        "imperial_supply",
    },
    "rulers": {"council", "watch", "guild", "imperial_bureau"},
    "problems": {
        "shortage",
        "broken_road",
        "sickness",
        "requisition",
        "beast_attacks",
        "failing_mine",
        "lost_records",
        "dry_well",
    },
}

# 実画面で「誰がなぜ言ったのか分からない」となった旧文。
REGRESSION_PHRASES = {
    "世界を綴じるもの",
    "無数の明日",
    "世界の綴じ目",
    "あり得た未来へ砕け散った",
    "この世界を失敗させない",
    "名もない声",
    "鉄は うそを つかん",
    "記録に のこらぬ もの",
    "歩くことが いのり",
    "かなしい話ほど よく はやる",
    "にげてきた。それだけだ",
    "詮索は せぬ",
}

PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")
SENTENCE_END = re.compile(r"[。！？]$")


def _load(relative: str) -> dict:
    path = ROOT / relative
    return json.loads(path.read_text(encoding="utf-8"))


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)


def _regressions(label: str, value) -> list[str]:
    problems: list[str] = []
    for text in _strings(value):
        for phrase in REGRESSION_PHRASES:
            if phrase in text:
                problems.append(f"{label}: 旧AI文が残る（{phrase}）")
    return problems


def check_town(data: dict) -> list[str]:
    problems: list[str] = []
    if data.get("version") != 1:
        problems.append("town: version は1")
    roles = data.get("roles", {})
    if set(roles) != EXPECTED_ROLES:
        problems.append("town: rolesのIDが実装と一致しない")
    for role in sorted(EXPECTED_ROLES):
        lines = roles.get(role, [])
        if not isinstance(lines, list) or len(lines) < 3:
            problems.append(f"town/roles/{role}: 台詞は3件以上")
            continue
        for index, line in enumerate(lines):
            if not isinstance(line, str) or not line:
                problems.append(f"town/roles/{role}[{index}]: 空")
                continue
            if len(line) > 34:
                problems.append(f"town/roles/{role}[{index}]: 34文字超過")
            if " " in line or "　" in line:
                problems.append(f"town/roles/{role}[{index}]: 不自然な空白")
            if not SENTENCE_END.search(line):
                problems.append(f"town/roles/{role}[{index}]: 文末記号が無い")

    profiles = data.get("profiles", {})
    for group, expected in EXPECTED_PROFILES.items():
        entries = profiles.get(group, {})
        if set(entries) != expected:
            problems.append(f"town/profiles/{group}: IDが実装と一致しない")
        for profile_id in sorted(expected):
            lines = entries.get(profile_id, [])
            if not isinstance(lines, list) or len(lines) < 2:
                problems.append(f"town/profiles/{group}/{profile_id}: 台詞は2件以上")
                continue
            for index, line in enumerate(lines):
                if not isinstance(line, str) or not line:
                    problems.append(
                        f"town/profiles/{group}/{profile_id}[{index}]: 空"
                    )
                    continue
                if len(line) > 34:
                    problems.append(
                        f"town/profiles/{group}/{profile_id}[{index}]: 34文字超過"
                    )
                if " " in line or "　" in line:
                    problems.append(
                        f"town/profiles/{group}/{profile_id}[{index}]: 不自然な空白"
                    )
                if not SENTENCE_END.search(line):
                    problems.append(
                        f"town/profiles/{group}/{profile_id}[{index}]: 文末記号が無い"
                    )
    problems.extend(_regressions("town", data))
    return problems


def _longest_skin(arc: dict) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, values in arc.get("skin", {}).items():
        if isinstance(values, list) and values:
            result[key] = max((str(value) for value in values), key=len)
    return result


def _expand(text: str, skin: dict[str, str]) -> tuple[str, set[str]]:
    expanded = text
    for key, value in skin.items():
        expanded = expanded.replace("{" + key + "}", value)
    return expanded, set(PLACEHOLDER.findall(expanded))


def check_story(data: dict) -> list[str]:
    problems: list[str] = []
    for arc in data.get("arcs", []):
        arc_id = str(arc.get("id", "<no-id>"))
        skin = _longest_skin(arc)
        for beat in arc.get("beats", []):
            phase = str(beat.get("phase", "?"))
            expanded, unresolved = _expand(str(beat.get("line", "")), skin)
            if unresolved:
                problems.append(
                    f"story/{arc_id}/{phase}: 未解決プレースホルダー {sorted(unresolved)}"
                )
            # EventViewの見出し本文は実測で約2行。以前の87文字は末尾が落ちた。
            if len(expanded) > 54:
                problems.append(
                    f"story/{arc_id}/{phase}: 差し込み後54文字超過（{len(expanded)}）"
                )
    problems.extend(_regressions("story", data))
    return problems


def check_cross_world(data: dict) -> list[str]:
    problems: list[str] = []
    for arc in data.get("arcs", []):
        arc_id = str(arc.get("id", "<no-id>"))
        skin = _longest_skin(arc)
        for beat in arc.get("beats", []):
            if beat.get("phase") != "reckoning":
                continue
            expanded, unresolved = _expand(str(beat.get("line", "")), skin)
            if unresolved:
                problems.append(
                    f"cross/{arc_id}: 未解決プレースホルダー {sorted(unresolved)}"
                )
            if len(expanded) > 54:
                problems.append(
                    f"cross/{arc_id}: 決着文が差し込み後54文字超過（{len(expanded)}）"
                )
    problems.extend(_regressions("cross", data))
    return problems


def check_vocabulary(data: dict) -> list[str]:
    problems: list[str] = []
    lore = data.get("lore", {})
    beats = lore.get("prologue_beats", [])
    if len(beats) != 8:
        problems.append("vocabulary/lore: prologue_beatsは8件")
    for index, beat in enumerate(beats):
        speaker = str(beat.get("speaker", ""))
        if not speaker:
            problems.append(f"prologue[{index}]: 話者が空")
        for line in beat.get("lines", []):
            if len(str(line)) > 36:
                problems.append(f"prologue[{index}]: 36文字超過")
    problems.extend(_regressions("vocabulary", lore))
    return problems


def check_sources() -> list[str]:
    problems: list[str] = []
    generator = (ROOT / "src/world/town_generator.gd").read_text(encoding="utf-8")
    profile = (ROOT / "src/world/town_profile.gd").read_text(encoding="utf-8")
    if "TownDialogue.role_lines" not in generator:
        problems.append("source: 町NPC台詞がtown_dialogue.json経由ではない")
    if "TownDialogue.profile_lines" not in profile:
        problems.append("source: 町設定台詞がtown_dialogue.json経由ではない")

    event_view = (ROOT / "src/scenes/event_view.gd").read_text(encoding="utf-8")
    main = (ROOT / "src/scenes/main.gd").read_text(encoding="utf-8")
    if '"actor": ""' not in event_view:
        problems.append("source: 一世界の地の文が人物の発話欄へ出る")
    if '"actor": ""' not in main:
        problems.append("source: 世界横断の地の文が人物の発話欄へ出る")
    for old_label in ['"はらう"', '"のこす"', '"手ばなす"', '"あぶない"', '"もらう"']:
        if old_label in event_view:
            problems.append(f"source: 旧イベントUI語が直書き（{old_label}）")

    quality_users = [
        "src/quest/world_event_catalog.gd",
        "src/game/quest_text.gd",
        "src/quest/quest_text.gd",
        "src/quest/story_arc_generator.gd",
        "src/game/chronicle_ai.gd",
    ]
    for relative in quality_users:
        source = (ROOT / relative).read_text(encoding="utf-8")
        if "WritingQuality" not in source:
            problems.append(f"source: {relative}が文章品質Gateを通らない")

    old_prompt = "あなたは SFC 期の日本語 RPG"
    for relative in ["src/scenes/main.gd", "src/game/chronicle_ai.gd"]:
        if old_prompt in (ROOT / relative).read_text(encoding="utf-8"):
            problems.append(f"source: {relative}に旧文体プロンプトが残る")
    return problems


def run_checks() -> list[str]:
    problems: list[str] = []
    problems.extend(check_town(_load("data/town_dialogue.json")))
    problems.extend(check_story(_load("data/story_arcs.json")))
    problems.extend(check_cross_world(_load("data/cross_world_arcs.json")))
    problems.extend(check_vocabulary(_load("data/vocabulary.json")))
    problems.extend(check_sources())
    return problems


def _selftest() -> int:
    base = {
        "version": 1,
        "roles": {role: ["町の状況を説明する。"] * 3 for role in EXPECTED_ROLES},
        "profiles": {
            group: {key: ["町の状況を説明する。"] * 2 for key in keys}
            for group, keys in EXPECTED_PROFILES.items()
        },
    }
    cases: list[tuple[str, dict, bool]] = []
    cases.append(("正常な町台詞を通す", json.loads(json.dumps(base)), False))

    missing = json.loads(json.dumps(base))
    del missing["roles"]["guard"]
    cases.append(("役の欠落を落とす", missing, True))

    obscure = json.loads(json.dumps(base))
    obscure["roles"]["guard"][0] = "名もない声が世界の綴じ目を呼ぶ。"
    cases.append(("旧AI文を落とす", obscure, True))

    no_period = json.loads(json.dumps(base))
    no_period["roles"]["guard"][0] = "門を守っている"
    cases.append(("文末の無い台詞を落とす", no_period, True))

    bad = 0
    for name, fixture, want_fail in cases:
        got_fail = bool(check_town(fixture))
        ok = got_fail == want_fail
        bad += 0 if ok else 1
        print("  %s  %s" % ("OK" if ok else "NG", name))

    long_story = {
        "arcs": [
            {
                "id": "fixture",
                "skin": {"anchor_name": ["長い名前"]},
                "beats": [{"phase": "hook", "line": "{anchor_name}" + "長" * 60}],
            }
        ]
    }
    ok = bool(check_story(long_story))
    bad += 0 if ok else 1
    print("  %s  差し込み後の画面超過を落とす" % ("OK" if ok else "NG"))
    print("---")
    if bad:
        print("文章Gateの自己検査に失敗（%d件）" % bad)
        return 1
    print("文章Gateは期待どおり動く（%d件）" % (len(cases) + 1))
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    try:
        problems = run_checks()
    except (OSError, json.JSONDecodeError) as error:
        print("文章データを読めない: %s" % error)
        return 1

    print("文章品質Gate")
    print("  町NPC: 17役 / 町設定: 8生業・4支配・8問題")
    print("  一世界物語: 差し込み後54文字以内")
    print("  世界横断: 決着文が差し込み後54文字以内")
    print("  AI候補: 意味不明・古風・抽象語過多を項目ごとに拒否")
    print("---")
    if problems:
        for problem in problems:
            print("  - %s" % problem)
        return 1
    print("文章の差し替え構造と既知の回帰は正常")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
