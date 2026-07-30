"""
生成した音声の検算 — 依存ゼロ

耳で確かめられない環境でも「無音になっていないか」「意図した音程が
鳴っているか」「潰れていないか」を機械的に確認する。

    python tools/verify_audio.py
"""

from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from sfc_audio import freq  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"


def read_mono(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as f:
        rate = f.getframerate()
        channels = f.getnchannels()
        raw = f.readframes(f.getnframes())
    values = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if channels == 2:
        mono = [(values[i] + values[i + 1]) / 65534.0 for i in range(0, len(values), 2)]
    else:
        mono = [v / 32767.0 for v in values]
    return mono, rate


def goertzel(samples: list[float], rate: int, target_hz: float) -> float:
    """1 つの周波数のエネルギーだけを取り出す。FFT を持ち込まずに済む。"""
    n = len(samples)
    k = int(0.5 + n * target_hz / rate)
    omega = 2.0 * math.pi * k / n
    coeff = 2.0 * math.cos(omega)
    s1 = s2 = 0.0
    for x in samples:
        s0 = x + coeff * s1 - s2
        s2 = s1
        s1 = s0
    return math.sqrt(max(s1 * s1 + s2 * s2 - coeff * s1 * s2, 0.0)) / n


def stats(samples: list[float]) -> dict:
    peak = max(abs(v) for v in samples)
    rms = math.sqrt(sum(v * v for v in samples) / len(samples))
    dc = sum(samples) / len(samples)
    clipped = sum(1 for v in samples if abs(v) > 0.995)
    return {"peak": peak, "rms": rms, "dc": dc, "clipped": clipped}


def envelope_variation(samples: list[float], rate: int) -> float:
    """20ms ごとの音量のばらつき。音楽なら動き、無音や定常音なら平坦。

    窓を短くしてあるのは、0.1 秒程度しかない効果音でも十分な数の窓を
    取れるようにするため（窓が 1 個だとばらつきが常に 0 になる）。
    """
    window = max(rate // 50, 1)
    levels = []
    for i in range(0, len(samples) - window, window):
        chunk = samples[i:i + window]
        levels.append(math.sqrt(sum(v * v for v in chunk) / window))
    if not levels:
        return 0.0
    mean = sum(levels) / len(levels)
    if mean <= 1e-9:
        return 0.0
    var = sum((v - mean) ** 2 for v in levels) / len(levels)
    return math.sqrt(var) / mean


# 各 BGM の冒頭小節で鳴っているはずの音（和音の構成音）
EXPECTED = {
    "bgm/title.wav": ["a2", "a3", "c4", "e4"],
    "bgm/stronghold.wav": ["c3", "g4", "c5", "e5"],
    "bgm/world.wav": ["a3", "c4", "e4"],
    "bgm/town.wav": ["c3", "c4", "e4", "g4"],
    "bgm/cave.wav": ["d3", "f3", "a3"],
    "bgm/story.wav": ["a2", "a3", "c4", "e4"],
    "bgm/descent.wav": ["a2", "a3", "c4", "e4", "a4"],
    "bgm/battle.wav": ["a2", "a3", "c4", "e4"],
    "bgm/boss.wav": ["a2", "a3", "c4", "e4"],
    "bgm/chronicle.wav": ["a2", "a3", "c4", "e4"],
}

REQUIRED_SFX = {
    "boss_gate", "cancel", "chest", "confirm", "cursor", "defeat", "depart",
    "encounter", "event", "fire", "heal", "hit", "ice", "learn", "magic",
    "poison", "seal_break", "sleep", "stairs", "story_choice", "story_open",
    "victory",
}

failures = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global failures
    if ok:
        print("  OK   %s %s" % (label, detail))
    else:
        failures += 1
        print("  FAIL %s %s" % (label, detail))


def main() -> None:
    files = sorted(AUDIO.rglob("*.wav"))
    if not files:
        print("音声がまだ生成されていない。先に python tools/gen_audio.py を実行すること。")
        sys.exit(1)

    print("=== 音声の検算 ===")
    actual = {path.relative_to(AUDIO).as_posix() for path in files}
    required = set(EXPECTED)
    required.update("sfx/%s.wav" % name for name in REQUIRED_SFX)
    missing_files = sorted(required - actual)
    check("必要な音声が揃っている", not missing_files,
          "不足 %s" % (", ".join(missing_files) if missing_files else "なし"))

    for path in files:
        rel = path.relative_to(AUDIO).as_posix()
        samples, rate = read_mono(path)
        s = stats(samples)
        seconds = len(samples) / rate

        print("%s  (%.2f 秒 / %d Hz)" % (rel, seconds, rate))
        check("無音でない", s["rms"] > 0.02, "RMS %.3f" % s["rms"])
        check("潰れていない", s["clipped"] < len(samples) * 0.001,
              "クリップ %d サンプル" % s["clipped"])
        check("直流成分が小さい", abs(s["dc"]) < 0.02, "DC %.4f" % s["dc"])
        check("音量に起伏がある", envelope_variation(samples, rate) > 0.15,
              "変動 %.2f" % envelope_variation(samples, rate))

        if rel in EXPECTED:
            # 冒頭 1 秒に、狙った音程のエネルギーが乗っているかを見る
            head = samples[: rate]
            found = []
            missing = []
            for note in EXPECTED[rel]:
                target = freq(note)
                energy = goertzel(head, rate, target)
                # 半音ずれた場所より強ければ、その音が鳴っていると判断する
                neighbour = max(
                    goertzel(head, rate, target * 1.0595),
                    goertzel(head, rate, target / 1.0595),
                )
                (found if energy > neighbour * 1.2 else missing).append(note)
            check("狙った和音が鳴っている", not missing,
                  "検出 %s / 未検出 %s" % (",".join(found), ",".join(missing) or "なし"))
        print()

    print("---")
    if failures:
        print("失敗 %d 件" % failures)
        sys.exit(1)
    print("すべて問題なし")


if __name__ == "__main__":
    main()
