"""枠から文字がはみ出ている画面を機械で探す。

    python tools/check_ui.py

各画面を `--shot=<名前> --ui-check` で開き、PixelUI が測った違反を集める。
**目視の代わりではなく、目視の前に通す関門**（見落としと再発を止めるため）。
はみ出しが 1 件でもあれば終了コード 1。
"""

from __future__ import annotations

import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
import sys
from pathlib import Path

# コンソールが cp932 でも落ちないようにする。報告が読めないと関門の意味が無い
# （実際に「—」で UnicodeEncodeError になって、違反を出す前に死んだ）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# `_capture()` が知っている画面を全部。増えたらここに足す。
SCREENS = [
    "title", "prologue", "prologue_shatter", "prologue_worlds", "prologue_oath",
    "stronghold", "job", "depart", "upgrade", "party",
    "world", "town", "cave", "shop", "event", "event_outcome",
    "battle", "commands", "items", "deep", "boss",
    "menu", "status", "equip", "jobmenu", "settings", "save_erase", "run_abandon",
    "result", "win",
    "gearoffer",
]


def _run_or_kill(cmd: list[str], timeout: float = 180.0) -> str:
    """走らせて出力を返す。時間切れなら殺してから空を返す。"""
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace",
    )
    try:
        out, _ = proc.communicate(timeout=timeout)
        return out or ""
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return ""


def _check_one(name: str) -> tuple[str, list[str]]:
    """1 画面を撮って、はみ出しの行だけ返す。

    **撮影に失敗したときは 1 度だけやり直す。** 23 画面を一斉に立てると
    描画の取り合いで稀に落ち、それを「画面が開かなかった」と報告していた
    （jobmenu が単独では通るのに関門だけ赤くなる、という嘘が実際に出た）。
    **嘘をつく関門は無いより悪い。**
    """
    for attempt in range(2):
        # **時間切れの子は必ず殺す。** `subprocess.run(timeout=)` は
        # TimeoutExpired を投げるが、Windows では孫が残ることがある。
        # 実際に Godot が 41 個居残ってデスクトップヒープを枯らし、
        # 以後の起動が accesskit の 0x80070008 で落ちるようになった。
        proc = _run_or_kill(
            # `--accessibility disabled` を付ける。**並列で立てると Windows の
            # デスクトップヒープが枯れて accesskit が落ちる**（0x80070008）。
            # 画面の検査に読み上げは要らない。
            [
                "godot", "--accessibility", "disabled", "--path", str(ROOT),
                "--", f"--shot={name}", "--ui-check",
            ],
        )
        out = proc
        hits = [
            line.split("はみ出し:", 1)[1].strip()
            for line in out.splitlines()
            if "はみ出し:" in line and "なし" not in line
        ]
        # **詰めた文字も違反として数える。** `draw_text` が窓の内側へ収めるので
        # 遊ぶ側にはみ出しは見えなくなったが、詰まっているのは割り付けの誤り。
        # 見えなくなった代わりに黙るのでは、関門を外したのと同じ。
        hits += [
            "詰めた " + line.split("詰めた:", 1)[1].strip()
            for line in out.splitlines()
            if "詰めた:" in line
        ]
        # **14px 未満の漢字も違反**（D-5）。SFC の 12px で漢字は潰れる。
        # 文字列を grep するだけでは足りない ―― 品名も技名も data 側にある。
        hits += [
            "小さすぎる漢字 " + line.split("小さすぎる漢字:", 1)[1].strip()
            for line in out.splitlines()
            if "小さすぎる漢字:" in line
        ]
        if "撮影:" in out:
            return name, hits
        if attempt == 0:
            continue
        return name, hits + ["画面が開かなかった（撮影に失敗）"]
    return name, []


def main() -> int:
    failures: dict[str, list[str]] = {}
    # **並列で立てる。** 23 画面を直列に回すと数分かかり、そのあいだ何も分からない。
    # 1 画面 1 プロセスなので互いに干渉しない（`user://` は読むだけ）。
    workers = max(1, min(len(SCREENS), (os.cpu_count() or 4) // 2))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = dict(pool.map(_check_one, SCREENS))
    for name in SCREENS:
        hits = results[name]
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
