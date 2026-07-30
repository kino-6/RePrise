"""
音声アセットの生成 — assets/audio/ 以下の WAV をここから作る。

    python tools/gen_audio.py

BGM は既存曲の複製ではなく、同じ書法で書いたオリジナル。狙っている質感は
次の 2 系統で、どちらも「和声は素直、旋律は歌える、伴奏は行進」という
SFC 期 RPG の作法に沿っている。

  * 拠点曲  … 長調、堂々とした行進。古典的な和声進行（I - V - vi - iii …）を
              そのまま辿る、王宮的な品のある曲。
  * 潜行曲  … 短調、i - ♭VI - ♭VII - i の反復。決意と反抗の響き。
              低音が八分で刻み続けることで「進軍している」感じを出す。
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from sfc_audio import (  # noqa: E402
    BASS, BELL, BRASS, FLUTE, LEAD, STRINGS,
    SAMPLE_RATE, Track, finish,
)

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"


class Song:
    """拍で音を置けるようにした薄い層。"""

    def __init__(self, bpm: float, bars: int, beats_per_bar: int = 4, tail: float = 2.5):
        self.spb = 60.0 / bpm
        self.beats_per_bar = beats_per_bar
        total_beats = bars * beats_per_bar
        self.track = Track(total_beats * self.spb + tail)

    def note(self, beat: float, length: float, name: str, inst, amp: float = 1.0) -> None:
        if name in ("r", ""):
            return
        self.track.add_note(beat * self.spb, length * self.spb, name, inst, amp)

    def phrase(self, start_beat: float, items: list[tuple[str, float]], inst, amp: float = 1.0) -> None:
        t = start_beat
        for name, length in items:
            self.note(t, length, name, inst, amp)
            t += length

    def chord(self, beat: float, length: float, names: list[str], inst, amp: float = 1.0) -> None:
        for name in names:
            self.note(beat, length, name, inst, amp)

    def bar(self, index: int) -> float:
        return index * self.beats_per_bar

    def drum(self, beat: float, kind: str) -> None:
        t = beat * self.spb
        if kind == "kick":
            self.track.add_noise(t, 0.10, amp=0.34, decay=0.035, pitch=9)
        elif kind == "snare":
            self.track.add_noise(t, 0.14, amp=0.24, decay=0.055, pitch=2)
        elif kind == "hat":
            self.track.add_noise(t, 0.05, amp=0.09, decay=0.018, pitch=1)


# --------------------------------------------------------------------------
# 和音
# --------------------------------------------------------------------------

CHORDS = {
    "Am": (["a3", "c4", "e4"], "a2", "e3"),
    "F":  (["f3", "a3", "c4"], "f2", "c3"),
    "G":  (["g3", "b3", "d4"], "g2", "d3"),
    "C":  (["c4", "e4", "g4"], "c3", "g3"),
    "Em": (["e3", "g3", "b3"], "e2", "b2"),
    "Dm": (["d3", "f3", "a3"], "d3", "a3"),
    "E":  (["e3", "gs3", "b3"], "e2", "b2"),
    "Bf": (["bf3", "d4", "f4"], "bf2", "f3"),
}


def lay_backing(song: Song, progression: list[str], march: bool = True,
                pad_amp: float = 1.0, bass_amp: float = 1.0) -> None:
    """和音パッドと、八分で刻む低音を敷く。

    低音が休まず動き続けることが「行進している」印象の正体なので、
    ここは装飾せず淡々と刻む。
    """
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, song.beats_per_bar, triad, STRINGS, 0.55 * pad_amp)

        if march:
            pattern = [root, root, root, root, fifth, fifth, root, root]
            for k, pitch in enumerate(pattern):
                song.note(start + k * 0.5, 0.48, pitch, BASS, 0.72 * bass_amp)
        else:
            song.note(start, 1.9, root, BASS, 0.78 * bass_amp)
            song.note(start + 2, 1.9, fifth, BASS, 0.70 * bass_amp)


def lay_march_drums(song: Song, bars: int) -> None:
    for i in range(bars):
        start = song.bar(i)
        song.drum(start, "kick")
        song.drum(start + 1, "snare")
        song.drum(start + 2, "kick")
        song.drum(start + 3, "snare")
        for k in range(8):
            if k % 2 == 1:
                song.drum(start + k * 0.5, "hat")


# --------------------------------------------------------------------------
# BGM 1: 拠点 — 長調の堂々とした行進
# --------------------------------------------------------------------------


def bgm_stronghold() -> None:
    bars = 16
    song = Song(bpm=104, bars=bars)

    progression = [
        "C", "G", "Am", "Em",
        "F", "C", "Dm", "G",
        "C", "Am", "F", "G",
        "C", "F", "G", "C",
    ]
    lay_backing(song, progression, march=False, pad_amp=1.0)

    # 低音は二分で歩く（行進というより儀式の歩調）
    for i, name in enumerate(progression):
        _, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.note(start, 0.95, root, BASS, 0.80)
        song.note(start + 1, 0.95, fifth, BASS, 0.62)
        song.note(start + 2, 0.95, root, BASS, 0.74)
        song.note(start + 3, 0.95, fifth, BASS, 0.58)

    melody = [
        [("g4", 1), ("c5", 1), ("e5", 1), ("c5", 1)],
        [("d5", 2), ("b4", 2)],
        [("c5", 1), ("e5", 1), ("a5", 1), ("e5", 1)],
        [("g5", 2), ("e5", 2)],
        [("f5", 1), ("a5", 1), ("f5", 1), ("c5", 1)],
        [("e5", 2), ("g4", 2)],
        [("a4", 1), ("d5", 1), ("f5", 1), ("a5", 1)],
        [("g5", 2.5), ("d5", 1.5)],
        [("e5", 1), ("g5", 1), ("c6", 1), ("g5", 1)],
        [("a5", 2), ("e5", 2)],
        [("f5", 1), ("a5", 1), ("c6", 1), ("a5", 1)],
        [("b5", 2), ("g5", 2)],
        [("c6", 1), ("b5", 1), ("a5", 1), ("g5", 1)],
        [("f5", 1), ("e5", 1), ("d5", 1), ("c5", 1)],
        [("d5", 2), ("b4", 2)],
        [("c5", 4)],
    ]
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, BRASS, 0.92)

    # 後半だけ、旋律の 1 オクターブ上に笛を重ねて厚みを足す
    for i in range(8, bars):
        song.phrase(song.bar(i), melody[i], FLUTE, 0.34)

    finish(song.track, AUDIO / "bgm" / "stronghold.wav",
           cutoff=5400.0, echo_ms=142.0, echo_fb=0.32)


# --------------------------------------------------------------------------
# BGM 2: 潜行 — 短調の行進（i - ♭VI - ♭VII - i）
# --------------------------------------------------------------------------


def bgm_descent() -> None:
    bars = 16
    song = Song(bpm=132, bars=bars)

    progression = [
        "Am", "F", "G", "Am",
        "Am", "F", "G", "Am",
        "C", "G", "Am", "F",
        "C", "G", "E", "Am",
    ]
    lay_backing(song, progression, march=True)
    lay_march_drums(song, bars)

    melody = [
        [("a4", 1.5), ("a4", 0.5), ("c5", 1), ("b4", 1)],
        [("a4", 2), ("g4", 1), ("f4", 1)],
        [("g4", 1.5), ("a4", 0.5), ("b4", 1), ("d5", 1)],
        [("a4", 3), ("r", 1)],
        [("e5", 1.5), ("e5", 0.5), ("d5", 1), ("c5", 1)],
        [("c5", 2), ("b4", 1), ("a4", 1)],
        [("b4", 1.5), ("c5", 0.5), ("d5", 1), ("b4", 1)],
        [("a4", 4)],
        [("e5", 1), ("g5", 1), ("e5", 1), ("c5", 1)],
        [("d5", 2), ("b4", 2)],
        [("c5", 1), ("e5", 1), ("a5", 1), ("g5", 1)],
        [("f5", 2), ("e5", 2)],
        [("e5", 1.5), ("d5", 0.5), ("c5", 1), ("d5", 1)],
        [("b4", 2), ("d5", 2)],
        [("gs4", 2), ("b4", 2)],  # G# は和声的短音階の導音。ここで一段持ち上がる
        [("a4", 4)],
    ]
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, LEAD, 0.95)

    # 主旋律の下に 3 度でブラスを重ねる（SFC の勇ましい曲の定番）
    harmony = [
        [("c4", 1.5), ("c4", 0.5), ("e4", 1), ("d4", 1)],
        [("c4", 2), ("bf3", 1), ("a3", 1)],
        [("b3", 1.5), ("c4", 0.5), ("d4", 1), ("f4", 1)],
        [("c4", 3), ("r", 1)],
        [("a4", 1.5), ("a4", 0.5), ("f4", 1), ("e4", 1)],
        [("a3", 2), ("d4", 1), ("c4", 1)],
        [("d4", 1.5), ("e4", 0.5), ("f4", 1), ("d4", 1)],
        [("c4", 4)],
    ]
    for i, phrase in enumerate(harmony):
        song.phrase(song.bar(i), phrase, BRASS, 0.40)

    finish(song.track, AUDIO / "bgm" / "descent.wav",
           cutoff=5000.0, echo_ms=124.0, echo_fb=0.30)


# --------------------------------------------------------------------------
# BGM 3: 戦闘 — 短く速い 8 小節ループ
# --------------------------------------------------------------------------


def bgm_battle() -> None:
    bars = 8
    song = Song(bpm=164, bars=bars)

    progression = ["Am", "Am", "F", "G", "Am", "Dm", "E", "Am"]
    lay_backing(song, progression, march=True, pad_amp=0.75)
    lay_march_drums(song, bars)

    melody = [
        [("a4", 0.5), ("c5", 0.5), ("e5", 0.5), ("a5", 0.5), ("e5", 1), ("c5", 1)],
        [("d5", 0.5), ("c5", 0.5), ("b4", 0.5), ("a4", 0.5), ("b4", 2)],
        [("f5", 0.5), ("e5", 0.5), ("d5", 0.5), ("c5", 0.5), ("f5", 2)],
        [("g5", 0.5), ("f5", 0.5), ("e5", 0.5), ("d5", 0.5), ("g5", 2)],
        [("a5", 1), ("e5", 1), ("c5", 1), ("a4", 1)],
        [("d5", 0.5), ("f5", 0.5), ("a5", 0.5), ("f5", 0.5), ("d5", 2)],
        [("gs4", 0.5), ("b4", 0.5), ("e5", 0.5), ("gs5", 0.5), ("b5", 2)],
        [("a5", 4)],
    ]
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, LEAD, 1.0)

    finish(song.track, AUDIO / "bgm" / "battle.wav",
           cutoff=5600.0, echo_ms=108.0, echo_fb=0.26)


# --------------------------------------------------------------------------
# 効果音
# --------------------------------------------------------------------------


def sfx(name: str, build, seconds: float, cutoff: float = 6800.0,
        echo_ms: float = 92.0, echo_fb: float = 0.16, peak: float = 0.78) -> None:
    track = Track(seconds)
    build(track)
    finish(track, AUDIO / "sfx" / f"{name}.wav",
           cutoff=cutoff, echo_ms=echo_ms, echo_fb=echo_fb, peak=peak)


def build_sfx() -> None:
    # カーソル移動: 短く硬い。連打されるので余韻を残さない。
    sfx("cursor", lambda t: t.add_note(0.0, 0.030, "e6", LEAD, 0.7), 0.16,
        echo_fb=0.08, peak=0.55)

    # 決定: 上向きの 2 音。「進む」感じ。
    def _confirm(t: Track) -> None:
        t.add_note(0.000, 0.040, "e5", LEAD, 0.8)
        t.add_note(0.045, 0.090, "a5", LEAD, 0.8)
    sfx("confirm", _confirm, 0.34, peak=0.62)

    # キャンセル: 下向きの 2 音。決定の裏返し。
    def _cancel(t: Track) -> None:
        t.add_note(0.000, 0.040, "a4", LEAD, 0.7)
        t.add_note(0.045, 0.090, "d4", LEAD, 0.7)
    sfx("cancel", _cancel, 0.34, peak=0.58)

    # 打撃: ノイズの立ち上がり + 低い胴鳴り。
    def _hit(t: Track) -> None:
        t.add_noise(0.0, 0.14, amp=0.85, decay=0.035, pitch=2)
        t.add_note(0.0, 0.070, "a2", BASS, 0.9)
        t.add_note(0.0, 0.050, "d3", BASS, 0.5)
    sfx("hit", _hit, 0.40, cutoff=5200.0, peak=0.86)

    # 魔法: 上昇スイープ。
    def _magic(t: Track) -> None:
        t.add_sweep(0.0, 0.30, "a3", "a6", LEAD, 0.55)
        t.add_noise(0.24, 0.16, amp=0.28, decay=0.05, pitch=3)
    sfx("magic", _magic, 0.62, cutoff=7200.0, echo_fb=0.24)

    # 回復: 澄んだ上昇アルペジオ。
    def _heal(t: Track) -> None:
        for i, n in enumerate(["c5", "e5", "g5", "c6"]):
            t.add_note(i * 0.055, 0.22, n, BELL, 0.62)
    sfx("heal", _heal, 0.80, cutoff=8000.0, echo_ms=118.0, echo_fb=0.28)

    # 属性ごとの魔法音。
    #
    # 炎・氷・雷が同じ「魔法」の音で鳴ると、属性を切り替えている手応えが出ない。
    # 音の作り分けは音色ではなく**動きの向き**で付ける（SFC 期の作法）。
    #   炎 … ノイズ主体で下から膨らむ
    #   氷 … 高い鈴が硬く刺さって減衰する
    #   雷 … 一瞬で立ち上がって切れる
    def _fire(t: Track) -> None:
        t.add_noise(0.0, 0.34, amp=0.62, decay=0.012, pitch=2)
        t.add_sweep(0.0, 0.26, "a2", "a4", BASS, 0.5)
    sfx("fire", _fire, 0.66, cutoff=5600.0, echo_fb=0.22)

    def _ice(t: Track) -> None:
        for i, n in enumerate(["c6", "g6", "e6"]):
            t.add_note(i * 0.035, 0.20, n, BELL, 0.55)
        t.add_noise(0.10, 0.20, amp=0.20, decay=0.06, pitch=4)
    sfx("ice", _ice, 0.62, cutoff=9000.0, echo_ms=132.0, echo_fb=0.30)

    def _bolt(t: Track) -> None:
        t.add_noise(0.0, 0.06, amp=0.95, decay=0.002, pitch=5)
        t.add_sweep(0.0, 0.12, "a6", "a3", LEAD, 0.6)
        t.add_note(0.05, 0.10, "e2", BASS, 0.7)
    sfx("bolt", _bolt, 0.48, cutoff=7600.0, echo_fb=0.18, peak=0.88)

    # 状態異常: かかった瞬間が分かる音。眠りは沈み、毒は濁る。
    def _sleep(t: Track) -> None:
        t.add_sweep(0.0, 0.40, "c5", "c3", STRINGS, 0.5)
    sfx("sleep", _sleep, 0.70, cutoff=4200.0, echo_ms=140.0, echo_fb=0.30)

    def _poison(t: Track) -> None:
        t.add_noise(0.0, 0.26, amp=0.34, decay=0.02, pitch=1)
        t.add_note(0.0, 0.24, "ef3", BASS, 0.55)
        t.add_note(0.06, 0.22, "a3", BASS, 0.40)
    sfx("poison", _poison, 0.56, cutoff=4000.0, echo_fb=0.20)

    # 習得・レベルアップ: 短いファンファーレ。ここが毎ランの報酬の瞬間。
    def _learn(t: Track) -> None:
        for i, n in enumerate(["c5", "e5", "g5"]):
            t.add_note(i * 0.085, 0.12, n, BRASS, 0.85)
        t.add_note(0.255, 0.45, "c6", BRASS, 0.95)
        t.add_note(0.255, 0.45, "e6", BRASS, 0.55)
    sfx("learn", _learn, 1.10, cutoff=6400.0, echo_ms=132.0, echo_fb=0.30)

    # 遭遇: 下降スイープ + 打撃。画面が切り替わる合図。
    def _encounter(t: Track) -> None:
        t.add_sweep(0.0, 0.26, "a5", "a3", LEAD, 0.6)
        t.add_noise(0.0, 0.35, amp=0.35, decay=0.10, pitch=4)
        t.add_note(0.26, 0.30, "a2", BASS, 0.9)
    sfx("encounter", _encounter, 0.80, cutoff=5000.0, echo_fb=0.26)

    # 宝箱: 明るいアルペジオ。
    def _chest(t: Track) -> None:
        for i, n in enumerate(["g5", "b5", "d6", "g6"]):
            t.add_note(i * 0.060, 0.26, n, BELL, 0.55)
    sfx("chest", _chest, 0.80, cutoff=8600.0, echo_ms=126.0, echo_fb=0.30)

    # 階段: 短い下降。潜っていく感じ。
    def _stairs(t: Track) -> None:
        for i, n in enumerate(["g5", "e5", "c5", "g4"]):
            t.add_note(i * 0.070, 0.20, n, FLUTE, 0.6)
    sfx("stairs", _stairs, 0.70, echo_fb=0.24)

    # 全滅: 沈んでいく短調の下降。
    def _defeat(t: Track) -> None:
        for i, n in enumerate(["a4", "g4", "f4", "e4"]):
            t.add_note(i * 0.28, 0.34, n, STRINGS, 0.8)
        t.add_note(1.12, 1.30, "a3", STRINGS, 0.9)
        t.add_note(1.12, 1.30, "c4", STRINGS, 0.7)
    sfx("defeat", _defeat, 2.90, cutoff=4200.0, echo_ms=160.0, echo_fb=0.34, peak=0.72)


# --------------------------------------------------------------------------


def main() -> None:
    jobs = [
        ("効果音", build_sfx),
        ("BGM 拠点", bgm_stronghold),
        ("BGM 潜行", bgm_descent),
        ("BGM 戦闘", bgm_battle),
    ]
    for label, job in jobs:
        started = time.time()
        job()
        print("  %-10s %.1f 秒" % (label, time.time() - started))

    total = 0
    print("生成完了 (%d Hz / 16bit ステレオ):" % SAMPLE_RATE)
    for path in sorted(AUDIO.rglob("*.wav")):
        size = path.stat().st_size
        total += size
        print("  %-34s %6.1f KB" % (path.relative_to(ROOT), size / 1024))
    print("  合計 %.1f MB" % (total / 1024 / 1024))


if __name__ == "__main__":
    main()
