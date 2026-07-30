"""git から版の刻印を作る。

    python tools/stamp_version.py

`data/build.json` に「いまの commit」を書き出す。**手で上げる番号を当てにしない。**
project.godot の `application/config/version` は一度も上がらなかった（0.1.0 のまま
数十コミット進んだ）ので、**必ず変わるもの**を identity にする。

書くのは 3 つだけ。

  hash   … 短縮ハッシュ。どのコミットかが一意に決まる
  date   … そのコミットの日付。新旧が人にも読める
  dirty  … コミットしていない変更を含むか。**「手元のビルド」を見分けるため**

`git` が無い環境（配布物を作り直すときなど）では空を書く。**空でも動くこと。**
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "build.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def _git(*args: str) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), *args],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=20,
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def main() -> int:
    stamp = {
        "_comment": (
            "tools/stamp_version.py が git から作る。手で書かない。"
            "書き出しは gen_assets.py と書き出し（export）の前に走らせる。"
        ),
        "hash": _git("rev-parse", "--short", "HEAD"),
        "date": _git("log", "-1", "--format=%cs"),
        # --porcelain が空でなければ、コミットしていない変更を含むビルド。
        "dirty": bool(_git("status", "--porcelain")),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("刻印: %s %s%s" % (
        stamp["hash"] or "(git なし)", stamp["date"], "  変更あり" if stamp["dirty"] else ""
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
