"""枠から文字がはみ出ている画面を機械で探す。

    python tools/check_ui.py

各画面を `--shot=<名前> --ui-check` で開き、PixelUI が測った違反を集める。
**目視の代わりではなく、目視の前に通す関門**（見落としと再発を止めるため）。
はみ出しが 1 件でもあれば終了コード 1。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# コンソールが cp932 でも落ちないようにする。報告が読めないと関門の意味が無い
# （実際に「—」で UnicodeEncodeError になって、違反を出す前に死んだ）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# `_capture()` が知っている画面を全部。増えたらここに足す。
SCREENS = [
    "title", "stronghold", "job", "depart", "upgrade", "party",
    "world", "town", "cave", "shop", "event",
    "battle", "commands", "items", "deep", "boss",
    "menu", "status", "equip", "jobmenu", "settings",
    "result", "win",
]


def main() -> int:
    failures: dict[str, list[str]] = {}
    for name in SCREENS:
        proc = subprocess.run(
            ["godot", "--path", str(ROOT), "--", f"--shot={name}", "--ui-check"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=180,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        hits = [
            line.split("はみ出し:", 1)[1].strip()
            for line in out.splitlines()
            if "はみ出し:" in line and "なし" not in line
        ]
        if "撮影:" not in out:
            hits.append("画面が開かなかった（撮影に失敗）")
        if hits:
            failures[name] = hits
        print(f"  {'NG' if hits else 'OK'}  {name}" + (f"  {len(hits)} 件" if hits else ""))

    print("---")
    if not failures:
        print(f"はみ出しなし（{len(SCREENS)} 画面）")
        return 0
    total = sum(len(v) for v in failures.values())
    print(f"はみ出し {total} 件 / {len(failures)} 画面")
    for name, hits in failures.items():
        print(f"\n[{name}]")
        for h in hits:
            print(f"  - {h}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
