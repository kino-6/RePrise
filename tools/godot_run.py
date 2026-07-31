"""Godot を走らせて、**終わったら必ず始末する**。

    python tools/godot_run.py --shot=title
    python tools/godot_run.py --headless --script tests/test_core.gd
    python tools/godot_run.py --reap          # 居残りを掃除するだけ

**なぜ要るか。** 撮影や自動プレイの Godot が居残る。1 回や 2 回なら気づかないが、
関門は 33 画面を並列で立てるので、失敗するたびに溜まる。実際に **41 個**まで
増えて Windows のデスクトップヒープが枯れ、以後の起動が accesskit の
`0x80070008` で落ちるようになった。**症状が起動失敗の形で出るので、
原因が居残りだと気づきにくい。**

`subprocess.run(timeout=)` では足りない。TimeoutExpired を投げるが、
Windows では子が生き残る（親を殺しても孫が残る）。ここでは
`taskkill /T /F` で**木ごと**落とす。
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## Godot の実行ファイル名（居残りを探すときに使う）。
NAMES = ("Godot_v4.7.1-stable_win64.exe", "godot.exe")

## 既定の待ち時間。撮影は数秒、通しの検査は数分かかる。
DEFAULT_TIMEOUT = 300.0


def _kill_tree(pid: int) -> None:
    """プロセスを**木ごと**落とす。Windows では孫が残るので `/T` が要る。"""
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            capture_output=True, check=False,
        )
    else:
        import signal
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def strays() -> list[int]:
    """走っている Godot の PID。**この道具が起動したものとは限らない。**"""
    if os.name != "nt":
        return []
    out = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=False,
    ).stdout or ""
    found: list[int] = []
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) < 2:
            continue
        if any(parts[0].lower().startswith(n.lower().split(".")[0]) for n in NAMES):
            try:
                found.append(int(parts[1]))
            except ValueError:
                pass
    return found


def reap(quiet: bool = False) -> int:
    """居残りを全部落とす。落とした数を返す。"""
    pids = strays()
    for pid in pids:
        _kill_tree(pid)
    if not quiet:
        print("居残りを %d 個 落とした" % len(pids))
    return len(pids)


def run(args: list[str], timeout: float = DEFAULT_TIMEOUT) -> tuple[int, str]:
    """Godot を走らせて `(終了コード, 出力)` を返す。

    **どう終わっても木ごと落とす。** 正常終了でも、時間切れでも、
    こちらが例外で抜けても。
    """
    cmd = ["godot", "--accessibility", "disabled"] + args
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace",
    )
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out or ""
    except subprocess.TimeoutExpired:
        _kill_tree(proc.pid)
        proc.communicate()
        return 124, "（時間切れ %.0f 秒で落とした）" % timeout
    finally:
        if proc.poll() is None:
            _kill_tree(proc.pid)


def main(argv: list[str]) -> int:
    if "--reap" in argv:
        return 0 if reap() >= 0 else 1
    if not argv:
        print(__doc__)
        return 2
    # `--path` が無ければ、このリポジトリを見るようにする。
    args = list(argv)
    if "--path" not in args and "--script" not in args:
        args = ["--path", str(ROOT), "--"] + args
    code, out = run(args)
    sys.stdout.write(out)
    # **終わったら念のため掃除する。** 走らせたぶんが残っていなくても、
    # 前の失敗の残りが居ることがある。
    left = strays()
    if left:
        print("（Godot が %d 個 残っていたので落とした）" % len(left))
        reap(quiet=True)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
