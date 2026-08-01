"""Godot のコア検算を領域別プロセスで並列実行する。

通常は `python tools/test_core.py`。失敗したスイートだけなら
`python tools/test_core.py --suite combat --verbose` を使う。
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
SUITES = (
    "determinism",
    "presentation",
    "progression",
    "world",
    "town",
    "narrative",
    "persistence",
    "combat",
)
SUMMARY_RE = re.compile(r"成功\s+(\d+)\s*/\s*失敗\s+(\d+)")


def _default_workers() -> int:
    """物理コア相当まで使う。16論理CPUなら8並列。"""
    logical = os.cpu_count() or 2
    return min(len(SUITES), max(1, logical // 2), 8)


def _run_suite(
    godot: str,
    suite: str,
    timeout: int,
    shard_index: int = -1,
    shard_count: int = 1,
) -> dict[str, object]:
    label = suite if shard_index < 0 else f"{suite}[{shard_index + 1}/{shard_count}]"
    log_dir = ROOT / ".godot" / "runner_logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    shard_label = "all" if shard_index < 0 else str(shard_index)
    log_path = log_dir / f"test_core_{suite}_{shard_label}_{os.getpid()}_{time.time_ns()}.log"
    command = [
        godot,
        "--headless",
        "--log-file",
        str(log_path),
        "--script",
        "res://tests/test_core.gd",
        "--",
        f"--suite={suite}",
    ]
    if shard_index >= 0:
        command.append(f"--shard={shard_index}/{shard_count}")
    started = time.perf_counter()
    run_env = os.environ.copy()
    run_home = (
        ROOT / ".godot" / "test_user"
        / f"{suite}_{shard_label}_{os.getpid()}_{time.time_ns()}"
    )
    run_home.mkdir(parents=True, exist_ok=True)
    run_env["APPDATA"] = str(run_home)
    run_env["LOCALAPPDATA"] = str(run_home)
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=run_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        output = completed.stdout
        match = SUMMARY_RE.search(output)
        passed = int(match.group(1)) if match else 0
        failed = int(match.group(2)) if match else 1
        ok = completed.returncode == 0 and match is not None and failed == 0
        return {
            "suite": label,
            "ok": ok,
            "passed": passed,
            "failed": failed,
            "seconds": time.perf_counter() - started,
            "output": output,
            "returncode": completed.returncode,
        }
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "") + (exc.stderr or "")
        return {
            "suite": label,
            "ok": False,
            "passed": 0,
            "failed": 1,
            "seconds": time.perf_counter() - started,
            "output": output,
            "returncode": 124,
        }


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--suite",
        action="append",
        choices=SUITES,
        help="指定した領域だけ実行（複数回指定可）",
    )
    parser.add_argument("--workers", type=int, default=_default_workers())
    parser.add_argument(
        "--world-shards",
        type=int,
        default=4,
        help="重い世界生成検算の分割数（既定4）",
    )
    parser.add_argument("--timeout", type=int, default=180, help="各スイートの秒数上限")
    parser.add_argument("--godot", help="Godot実行ファイル。既定はPATHから検索")
    parser.add_argument("--verbose", action="store_true", help="成功時も全ログを表示")
    parser.add_argument("--list", action="store_true", help="スイート名だけ表示")
    return parser.parse_args()


def main() -> int:
    args = _arguments()
    if args.list:
        print("\n".join(SUITES))
        return 0
    godot = args.godot or shutil.which("godot")
    if not godot:
        print("Godot が PATH に見つかりません。--godot で指定してください。", file=sys.stderr)
        return 2
    selected = tuple(args.suite or SUITES)
    world_shards = max(1, min(args.world_shards, 8))
    tasks: list[tuple[str, int, int]] = []
    for suite in selected:
        if suite == "world" and world_shards > 1:
            tasks.extend((suite, index, world_shards) for index in range(world_shards))
        else:
            tasks.append((suite, -1, 1))
    workers = max(1, min(args.workers, len(tasks)))
    started = time.perf_counter()
    print(
        f"core: {len(selected)} suites, {len(tasks)} jobs / {workers} workers "
        f"({os.cpu_count() or '?'} logical CPUs)"
    )

    by_name: dict[str, dict[str, object]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                _run_suite, godot, suite, args.timeout, shard_index, shard_count
            ): (suite, shard_index, shard_count)
            for suite, shard_index, shard_count in tasks
        }
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            by_name[str(result["suite"])] = result
            state = "OK" if result["ok"] else "FAIL"
            print(
                f"  {state:4} {result['suite']:<13} "
                f"{result['passed']:>3}/{result['failed']:<3} "
                f"{result['seconds']:>5.1f}s"
            )

    total_passed = 0
    failed_suites = 0
    ordered_labels = [
        suite if shard_index < 0 else f"{suite}[{shard_index + 1}/{shard_count}]"
        for suite, shard_index, shard_count in tasks
    ]
    for suite in ordered_labels:
        result = by_name[suite]
        total_passed += int(result["passed"])
        if not result["ok"]:
            failed_suites += 1
        if args.verbose or not result["ok"]:
            print(f"\n--- {suite} ---")
            print(str(result["output"]).rstrip())

    elapsed = time.perf_counter() - started
    print(
        f"core: {total_passed} passed / {failed_suites} failed jobs / {elapsed:.1f}s"
    )
    return 1 if failed_suites else 0


if __name__ == "__main__":
    raise SystemExit(main())
