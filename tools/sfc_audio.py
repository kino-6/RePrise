"""
SFC 風の音を合成する基盤 — 依存ゼロ（標準ライブラリのみ）

SFC の音が「ファミコンでもなく CD でもない」独特の質感になっていた理由は、
主に次の 3 つ。ここではその 3 つを明示的に再現する。

  1. サンプリング周波数 32kHz。高域が素直に伸びない。
  2. SPC700 のガウス補間。これが強めのローパスとして働き、音の角が丸くなる。
     ファミコンの矩形波が刺さるのに対し、SFC の音が「柔らかい」のはこれ。
  3. DSP 内蔵エコー。ほぼ全てのタイトルが使っていた、あの残響。
     これが無いと、音色をいくら似せても SFC には聞こえない。

音色そのものは波形合成で作る（実機はサンプル再生だが、ローパスとエコーを
通した時点で耳の印象は十分に寄る）。
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 32000  # SFC の DSP 出力レート

# --------------------------------------------------------------------------
# 音名
# --------------------------------------------------------------------------

_SEMITONE = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def freq(note: str) -> float:
    """'a4' -> 440.0 / 'gs4' -> G#4 / 'bf3' -> B♭3 / 'r' -> 0（休符）"""
    note = note.strip().lower()
    if note in ("r", "rest", ""):
        return 0.0
    letter = note[0]
    if letter not in _SEMITONE:
        raise ValueError(f"音名が読めない: {note}")
    index = 1
    accidental = 0
    while index < len(note) and note[index] in "sbf#":
        accidental += 1 if note[index] in "s#" else -1
        index += 1
    octave = int(note[index:])
    semitones = _SEMITONE[letter] + accidental + (octave - 4) * 12
    return 440.0 * (2.0 ** ((semitones - 9) / 12.0))


# --------------------------------------------------------------------------
# 音色
# --------------------------------------------------------------------------


class Instrument:
    """波形 + ADSR + 揺らぎ。

    duty はパルス波の幅（0.5 で矩形）。detune は 2 基目の発振器のずれで、
    わずかにずらすと音が太くなる（SFC のストリングス系の常套手段）。
    """

    def __init__(
        self,
        wave_kind: str = "pulse",
        duty: float = 0.5,
        attack: float = 0.005,
        decay: float = 0.08,
        sustain: float = 0.7,
        release: float = 0.12,
        vibrato_hz: float = 0.0,
        vibrato_depth: float = 0.0,
        detune: float = 0.0,
        gain: float = 1.0,
    ):
        self.wave_kind = wave_kind
        self.duty = duty
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.vibrato_hz = vibrato_hz
        self.vibrato_depth = vibrato_depth
        self.detune = detune
        self.gain = gain

    def sample(self, phase: float) -> float:
        p = phase % 1.0
        kind = self.wave_kind
        if kind == "pulse":
            # 直流成分が乗らない形にする。単純な ±1 だと duty 0.5 以外で
            # 波形が上下非対称になり、無音部分にも「押しっぱなし」の圧が残る。
            return (1.0 - self.duty) * 2.0 if p < self.duty else -self.duty * 2.0
        if kind == "triangle":
            return 4.0 * abs(p - 0.5) - 1.0
        if kind == "saw":
            return 2.0 * p - 1.0
        if kind == "sine":
            return math.sin(2.0 * math.pi * p)
        raise ValueError(f"未知の波形: {kind}")

    def envelope(self, t: float, duration: float) -> float:
        if t < 0.0:
            return 0.0
        if t < self.attack:
            return t / max(self.attack, 1e-6)
        if t < self.attack + self.decay:
            k = (t - self.attack) / max(self.decay, 1e-6)
            return 1.0 + (self.sustain - 1.0) * k
        if t < duration:
            return self.sustain
        k = (t - duration) / max(self.release, 1e-6)
        return max(self.sustain * (1.0 - k), 0.0)


# よく使う音色。SFC の RPG に出てくる基本編成を意識している。
LEAD = Instrument("pulse", duty=0.28, attack=0.008, decay=0.10, sustain=0.72,
                  release=0.14, vibrato_hz=5.2, vibrato_depth=0.004, gain=0.62)
BRASS = Instrument("saw", attack=0.02, decay=0.12, sustain=0.66, release=0.16,
                   vibrato_hz=4.4, vibrato_depth=0.003, detune=0.006, gain=0.50)
STRINGS = Instrument("saw", attack=0.14, decay=0.20, sustain=0.62, release=0.34,
                     vibrato_hz=3.6, vibrato_depth=0.005, detune=0.010, gain=0.34)
BASS = Instrument("triangle", attack=0.004, decay=0.06, sustain=0.80, release=0.08, gain=0.85)
BELL = Instrument("sine", attack=0.002, decay=0.45, sustain=0.05, release=0.30, gain=0.65)
FLUTE = Instrument("triangle", attack=0.05, decay=0.10, sustain=0.75, release=0.20,
                   vibrato_hz=5.0, vibrato_depth=0.006, gain=0.48)


# --------------------------------------------------------------------------
# バッファ
# --------------------------------------------------------------------------


class Track:
    """モノラルの浮動小数バッファ。"""

    def __init__(self, seconds: float):
        self.data = [0.0] * int(seconds * SAMPLE_RATE)

    def __len__(self) -> int:
        return len(self.data)

    def add_note(self, start: float, duration: float, note: str, instrument: Instrument,
                 amp: float = 1.0) -> None:
        f = freq(note)
        if f <= 0.0:
            return
        begin = int(start * SAMPLE_RATE)
        total = duration + instrument.release
        count = int(total * SAMPLE_RATE)
        phase = 0.0
        phase2 = 0.0
        gain = amp * instrument.gain
        for i in range(count):
            index = begin + i
            if index >= len(self.data):
                break
            t = i / SAMPLE_RATE
            env = instrument.envelope(t, duration)
            # 減衰しきったら打ち切る。ただし発音直後は attack のせいで
            # 包絡線が 0 なので、そこで止めると音そのものが消える。
            if env <= 0.0 and t > duration:
                break
            # ビブラートは発音から少し遅れて掛かるほうが自然に聞こえる
            depth = instrument.vibrato_depth * min(t * 4.0, 1.0)
            wobble = 1.0 + depth * math.sin(2.0 * math.pi * instrument.vibrato_hz * t)
            step = f * wobble / SAMPLE_RATE
            phase += step
            value = instrument.sample(phase)
            if instrument.detune > 0.0:
                phase2 += step * (1.0 + instrument.detune)
                value = (value + instrument.sample(phase2)) * 0.5
            self.data[index] += value * env * gain

    def add_noise(self, start: float, duration: float, amp: float = 0.5,
                  decay: float = 0.5, pitch: int = 1) -> None:
        """打楽器・打撃音用のノイズ。線形合同法で作るので毎回同じ音になる。"""
        begin = int(start * SAMPLE_RATE)
        count = int(duration * SAMPLE_RATE)
        state = 0x1234 + begin
        held = 0.0
        for i in range(count):
            index = begin + i
            if index >= len(self.data):
                break
            if i % pitch == 0:
                state = (state * 1103515245 + 12345) & 0x7FFFFFFF
                held = (state / 0x3FFFFFFF) - 1.0
            env = math.exp(-i / (SAMPLE_RATE * decay))
            self.data[index] += held * env * amp

    def add_sweep(self, start: float, duration: float, from_note: str, to_note: str,
                  instrument: Instrument, amp: float = 1.0) -> None:
        """音程が滑らかに動く音。遭遇音や魔法音に使う。"""
        f0 = freq(from_note)
        f1 = freq(to_note)
        begin = int(start * SAMPLE_RATE)
        count = int(duration * SAMPLE_RATE)
        phase = 0.0
        for i in range(count):
            index = begin + i
            if index >= len(self.data):
                break
            k = i / max(count - 1, 1)
            f = f0 * ((f1 / f0) ** k)
            phase += f / SAMPLE_RATE
            env = instrument.envelope(i / SAMPLE_RATE, duration)
            self.data[index] += instrument.sample(phase) * env * amp * instrument.gain


# --------------------------------------------------------------------------
# 仕上げ（ここが SFC らしさの本体）
# --------------------------------------------------------------------------


def lowpass(data: list[float], cutoff_hz: float) -> None:
    """一次ローパス。SPC700 のガウス補間が作っていた「丸み」の代用。

    これを外すと途端に「ファミコン風の合成音」に寄る。
    """
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    y = 0.0
    for i, x in enumerate(data):
        y += alpha * (x - y)
        data[i] = y


def echo(data: list[float], delay_ms: float, feedback: float) -> None:
    """DSP 内蔵エコー。フィードバック付きコムフィルタそのもの。

    実機は 8 タップ FIR + フィードバックだが、耳の印象は単純な反復で足りる。
    """
    delay = int(SAMPLE_RATE * delay_ms / 1000.0)
    if delay <= 0:
        return
    for i in range(delay, len(data)):
        data[i] += data[i - delay] * feedback


def remove_dc(data: list[float]) -> None:
    """直流成分を落とす。残っているとスピーカーが無駄に押され、音も濁る。"""
    if not data:
        return
    mean = sum(data) / len(data)
    if abs(mean) < 1e-6:
        return
    for i in range(len(data)):
        data[i] -= mean


def normalize(data: list[float], peak: float = 0.86) -> None:
    high = max((abs(v) for v in data), default=0.0)
    if high <= 1e-9:
        return
    scale = peak / high
    for i in range(len(data)):
        data[i] *= scale


def soft_clip(data: list[float]) -> None:
    for i, v in enumerate(data):
        data[i] = math.tanh(v * 1.15) * 0.92


def write_wav(path: str | Path, left: list[float], right: list[float]) -> None:
    """16bit ステレオ WAV。"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for a, b in zip(left, right):
        frames += struct.pack(
            "<hh",
            max(-32768, min(32767, int(a * 32767))),
            max(-32768, min(32767, int(b * 32767))),
        )
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(bytes(frames))


def finish(track: Track, path: str | Path, cutoff: float = 5200.0,
           echo_ms: float = 126.0, echo_fb: float = 0.30, peak: float = 0.86) -> None:
    """ローパス → 左右で違う遅延のエコー → 整音 → 書き出し。

    左右のエコー長をずらすのが要点。SFC の「広がって聞こえる残響」は
    左右非対称の遅延から来ている。
    """
    mono = track.data
    lowpass(mono, cutoff)

    left = list(mono)
    right = list(mono)
    echo(left, echo_ms, echo_fb)
    echo(right, echo_ms * 1.27, echo_fb * 0.92)

    for channel in (left, right):
        remove_dc(channel)
        normalize(channel, peak)
        soft_clip(channel)
    write_wav(path, left, right)
