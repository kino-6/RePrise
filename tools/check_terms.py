"""View に日本語を直書きしていないかを見る（D-7）。

    python tools/check_terms.py
    python tools/check_terms.py --selftest

**見るのは「造語と固有の語」だけ。** 日本語の文をすべて追い出す関門も書けるが、
それは目的ではない。困るのは「奈落」「銀の砦」「資源」「危険度」「封」のような
**この作品でしか通じない語**が View に散っていることで、語を見直すたびに
全 View を grep することになる。ふつうの案内文（「たおれている ものには つかえない」）
は差し替えの対象ではないので、そこまで追い出すと関門が仕事の邪魔になる。

判定はこう:

  * `data/vocabulary.json` に載っている語が、View に**直書きされていたら落とす**。
    その語は差し替えの対象なので、`Terms` 経由でなければ意味が無い。
  * 語彙に無い普通の文は見ない。

見るのは `src/scenes/` と `src/ui/`。コメントは対象外。
残していいものは `ALLOWED` に**理由付きで**書く。理由の無い許可は許可ではなく放置。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

JAPANESE = re.compile(r"[぀-ヿ一-鿿]")
LITERAL = re.compile(r'"([^"]{1,80})"')

## 語彙として差し替えの対象になる語の最小の長さ。
## 1 文字の語（「城」「待」）まで見ると、普通の文の中の 1 文字に当たって誤検出する。
MIN_TERM_LEN = 2


def coined_words() -> set[str]:
    """`data/vocabulary.json` に載っている語。**これだけが検査の対象。**"""
    import json
    path = ROOT / "data" / "vocabulary.json"
    if not path.exists():
        return set()
    out: set[str] = set()

    def walk(value) -> None:
        if isinstance(value, str):
            if MIN_TERM_LEN <= len(value) <= 10 and "%" not in value:
                out.add(value)
        elif isinstance(value, dict):
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    data = json.loads(path.read_text(encoding="utf-8"))
    walk(data.get("terms", {}))
    walk(data.get("biomes", {}))
    return out

# 語の置き場そのもの。ここに日本語が在るのが正しい。
HOMES = {"terms.gd", "vocabulary.gd", "lore.gd"}

# 残していい直書きと、その理由。**理由の無い許可は許可ではない。**
ALLOWED: dict[str, str] = {
    # **いまは空。** 語彙に載っている語は全部 `Terms` 経由になっている。
    # ここへ足すときは理由を書く。期限のある許可はタスク ID を、
    # 遊ぶ側が読まないものは「永続」で始める理由を書く。
}

## 許可の理由に要るタスク ID（`D-9` など）。書き捨てを防ぐ。
TASK_ID = re.compile(r"\b[A-Z]-\d+\b")


def scan(paths, words: set[str]) -> dict[str, list[str]]:
    """ファイルごとの、**語彙に載っている語**の直書き。コメント行は見ない。"""
    found: dict[str, list[str]] = {}
    for path in paths:
        if path.name in HOMES:
            continue
        hits: list[str] = []
        for line in path.read_text(encoding="utf-8").split("\n"):
            if line.strip().startswith("#"):
                continue
            for match in LITERAL.finditer(line):
                text = match.group(1)
                if not JAPANESE.search(text):
                    continue
                # **語彙に載っている語だけを見る。** 普通の案内文は対象外。
                if text not in words:
                    continue
                if text not in hits:
                    hits.append(text)
        if hits:
            found[path.name] = hits
    return found


def judge(found: dict[str, list[str]], allowed: dict[str, str]) -> list[str]:
    """落とす理由を組み立てる。**ここが判定の全部。**"""
    problems: list[str] = []
    for name in sorted(found):
        if name not in allowed:
            problems.append(
                "%s: 直書きが %d 件（例: %s）" % (name, len(found[name]), found[name][0]))
    for name, why in sorted(allowed.items()):
        if why.startswith("永続"):
            continue   # 期限の無い許可に ID は要らない
        if not TASK_ID.search(why):
            problems.append("許可 %s の理由にタスク ID が無い（%r）" % (name, why))
    return problems


def _selftest() -> int:
    """**検査器そのものを試す。** 正常系だけ見ても、壊れた関門は見つからない。"""
    cases = [
        ("許可の無い直書きを見つける", {"a.gd": ["あ"]}, {}, True),
        ("許可があれば通す", {"a.gd": ["あ"]}, {"a.gd": "D-9 で寄せる"}, False),
        ("ID の無い許可は落ちる", {}, {"a.gd": "あとでやる"}, True),
        ("永続の許可は ID が要らない", {}, {"a.gd": "永続。読まれない"}, False),
        ("直書きが無ければ通る", {}, {}, False),
    ]
    bad = 0
    for name, found, allowed, want_fail in cases:
        got = bool(judge(found, allowed))
        ok = got == want_fail
        bad += 0 if ok else 1
        print("  %s  %s" % ("OK" if ok else "NG", name))
    # 記号と数字だけの語は拾わないこと（誤検出だと関門が使えない）。
    quiet = scan_text('var a := "Lv%d/%d"\nvar b := "→"\n')
    ok = not quiet
    bad += 0 if ok else 1
    print("  %s  記号と数字だけは拾わない" % ("OK" if ok else "NG"))
    print("---")
    if bad:
        print("検査器が壊れている（%d 件）" % bad)
        return 1
    print("検査器は期待どおり動く（%d 件）" % (len(cases) + 1))
    return 0


def scan_text(text: str) -> list[str]:
    """文字列 1 つぶんの検出（自己検査用）。"""
    hits = []
    for line in text.split("\n"):
        if line.strip().startswith("#"):
            continue
        for match in LITERAL.finditer(line):
            if JAPANESE.search(match.group(1)):
                hits.append(match.group(1))
    return hits


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    paths = sorted(
        list((ROOT / "src" / "scenes").glob("*.gd"))
        + list((ROOT / "src" / "ui").glob("*.gd"))
    )
    words = coined_words()
    found = scan(paths, words)
    total = sum(len(v) for v in found.values())
    print("View に直書きされた語彙（%d 語を照合）" % len(words))
    for name in sorted(found):
        mark = "  ← 許可（%s）" % ALLOWED[name] if name in ALLOWED else "  ← **直書き**"
        print("  %-24s %3d 種%s" % (name, len(found[name]), mark))
    print("---")
    problems = judge(found, ALLOWED)
    if problems:
        for note in problems:
            print("  - %s" % note)
        return 1
    print("許可していない直書きは無い（%d 種が許可つきで残っている）" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
