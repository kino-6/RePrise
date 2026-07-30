"""
音声アセットの生成 — assets/audio/ 以下の WAV をここから作る。

    python tools/gen_audio.py

BGM は既存曲の複製ではなく、作品の前提から書いたオリジナル。

  * 銀の砦は世界の外にあり、帰還と喪失を両方見届ける。
  * 一ランは使い捨ての世界を横断する旅で、遠くほど危険になる。
  * 帝国機械の硬さと、同行者の小さな約束が同じ世界に同居する。
  * 勝っても負けても記録は砦へ帰る。

曲ごとに別の旋律を乱造せず、A-C-E-B の 4 音を「見届ける動機」として
題名・旅・物語・主戦・戦記へ形を変えて戻す。後期 SFC の限られた同時発音で
統一感を作る書法に寄せる。
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from sfc_audio import (  # noqa: E402
    BASS, BELL, BRASS, CHOIR, FLUTE, HARP, LEAD, LOW_BRASS, OBOE, STRINGS,
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
# BGM
#
# ループは A → B → A' の 3 部にする。
#
# 8 小節や 16 小節で回すと、1 回の戦闘のあいだに何度も同じところへ戻ってきて、
# それだけで安く聞こえる。SFC 期の曲が短いループでも保っていたのは、
# 中に**抜き差し**（対旋律が入る、打楽器が抜ける、和声が一段上がる）が
# あったから。長さと変化の両方が要る。
# --------------------------------------------------------------------------


def lay_fill(song: Song, bar_index: int) -> None:
    """小節の終わりに打楽器の埋め。区切りが耳で分かるようになる。"""
    start = song.bar(bar_index)
    for k in range(4):
        song.drum(start + 3.0 + k * 0.25, "snare" if k % 2 else "hat")


def lay_march_drums_range(song: Song, first: int, last: int, hats: bool = True) -> None:
    """指定した小節だけに行進の打楽器を敷く（B 部で抜くために範囲を取る）。"""
    for i in range(first, last):
        start = song.bar(i)
        song.drum(start, "kick")
        song.drum(start + 1, "snare")
        song.drum(start + 2, "kick")
        song.drum(start + 3, "snare")
        if hats:
            for k in range(8):
                if k % 2 == 1:
                    song.drum(start + k * 0.5, "hat")


def lay_arpeggio(song: Song, first: int, last: int, progression: list[str],
                 inst, amp: float = 0.30) -> None:
    """和音を八分で分散させて内声に置く。

    旋律と低音のあいだが空いていると、音数が少ないぶん寂しく聞こえる。
    ここを埋めるだけで「作り込まれた」印象になる（SFC 期の常套手段）。
    """
    for i in range(first, last):
        triad, _, _ = CHORDS[progression[i % len(progression)]]
        start = song.bar(i)
        order = [triad[0], triad[1], triad[2], triad[1]]
        for k in range(8):
            song.note(start + k * 0.5, 0.45, order[k % 4], inst, amp)


# 全曲をつなぐ「見届ける動機」。上がったあと主音へ戻らず、B で一度止まる。
# 約束はできたが結末はまだ決まっていない、という形。終幕曲だけ最後を A に戻す。
WITNESS = [("a4", 1.0), ("c5", 1.0), ("e5", 1.0), ("b4", 1.0)]
WITNESS_HIGH = [("a5", 1.0), ("c6", 1.0), ("e6", 1.0), ("b5", 1.0)]
WITNESS_HOME = [("a4", 1.0), ("c5", 1.0), ("e5", 1.0), ("a5", 1.0)]


def lay_witness(song: Song, bar_index: int, inst=OBOE, amp: float = 0.72,
                resolved: bool = False, high: bool = False) -> None:
    phrase = WITNESS_HOME if resolved else (WITNESS_HIGH if high else WITNESS)
    song.phrase(song.bar(bar_index), phrase, inst, amp)


def lay_heartbeat(song: Song, first: int, last: int, amp: float = 0.22) -> None:
    """主戦・物語で使う二打。行進ではなく、守りたい一人の時間を刻む。"""
    for i in range(first, last):
        start = song.bar(i)
        song.drum(start, "kick")
        song.drum(start + 0.75, "kick")
        song.drum(start + 2.5, "hat")
        # 低い A/E の交代で、ノイズだけの打楽器より輪郭を残す。
        song.note(start, 0.22, "a2", BASS, amp)
        song.note(start + 0.75, 0.18, "e3", BASS, amp * 0.72)


# --------------------------------------------------------------------------
# BGM 1: 拠点 — 長調の堂々とした歩調（A8 / B8 / A8 / C8）
# --------------------------------------------------------------------------


def bgm_stronghold() -> None:
    bars = 32
    song = Song(bpm=104, bars=bars)

    a_prog = ["C", "G", "Am", "Em", "F", "C", "Dm", "G"]
    b_prog = ["F", "G", "Em", "Am", "Dm", "G", "C", "C"]
    c_prog = ["Am", "F", "C", "G", "F", "Em", "Dm", "G"]
    progression = a_prog + b_prog + a_prog + c_prog

    lay_backing(song, progression, march=False, pad_amp=1.0)

    # 低音は二分で歩く（行進というより儀式の歩調）
    for i, name in enumerate(progression):
        _, root, fifth = CHORDS[name]
        start = song.bar(i)
        # B 部だけ半分の密度にして、息を抜く
        if 8 <= i < 16:
            song.note(start, 1.9, root, BASS, 0.70)
            song.note(start + 2, 1.9, fifth, BASS, 0.58)
            continue
        song.note(start, 0.95, root, BASS, 0.80)
        song.note(start + 1, 0.95, fifth, BASS, 0.62)
        song.note(start + 2, 0.95, root, BASS, 0.74)
        song.note(start + 3, 0.95, fifth, BASS, 0.58)

    a_melody = [
        [("g4", 1), ("c5", 1), ("e5", 1), ("c5", 1)],
        [("d5", 2), ("b4", 2)],
        [("c5", 1), ("e5", 1), ("a5", 1), ("e5", 1)],
        [("g5", 2), ("e5", 2)],
        [("f5", 1), ("a5", 1), ("f5", 1), ("c5", 1)],
        [("e5", 2), ("g4", 2)],
        [("a4", 1), ("d5", 1), ("f5", 1), ("a5", 1)],
        [("g5", 2.5), ("d5", 1.5)],
    ]
    # B 部は音域を上げて、旋律の輪郭を変える（同じ節を繰り返さない）
    b_melody = [
        [("a5", 1.5), ("g5", 0.5), ("f5", 1), ("e5", 1)],
        [("d5", 2), ("g5", 2)],
        [("e5", 1), ("g5", 1), ("b5", 1), ("g5", 1)],
        [("a5", 3), ("e5", 1)],
        [("f5", 1), ("a5", 1), ("d6", 1), ("a5", 1)],
        [("b5", 2), ("g5", 2)],
        [("c6", 1.5), ("b5", 0.5), ("a5", 1), ("g5", 1)],
        [("e5", 4)],
    ]
    # C 部は短調側へ振ってから戻る（終わりに向かう感じを作る）
    c_melody = [
        [("a5", 1), ("e5", 1), ("c5", 1), ("e5", 1)],
        [("f5", 2), ("a5", 2)],
        [("g5", 1), ("e5", 1), ("c5", 1), ("g4", 1)],
        [("b4", 2), ("d5", 2)],
        [("f5", 1), ("e5", 1), ("d5", 1), ("c5", 1)],
        [("e5", 2), ("g5", 2)],
        [("d5", 1.5), ("c5", 0.5), ("b4", 1), ("d5", 1)],
        [("c5", 4)],
    ]
    melody = a_melody + b_melody + a_melody + c_melody
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, BRASS, 0.92)

    # 対旋律と内声。B 部と C 部だけに入れて、A 部との差を作る。
    for i in range(8, 16):
        song.phrase(song.bar(i), melody[i], FLUTE, 0.32)
    lay_arpeggio(song, 8, 16, b_prog, BELL, 0.22)
    for i in range(24, 32):
        song.phrase(song.bar(i), melody[i], FLUTE, 0.30)

    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    finish(song.track, AUDIO / "bgm" / "stronghold.wav",
           cutoff=5400.0, echo_ms=142.0, echo_fb=0.32)


# --------------------------------------------------------------------------
# BGM 2: 潜行 — 短調の行進（A8 / B8 / A8 / C8）
# --------------------------------------------------------------------------


def bgm_descent() -> None:
    bars = 32
    song = Song(bpm=132, bars=bars)

    a_prog = ["Am", "F", "G", "Am", "Am", "F", "G", "Am"]
    b_prog = ["C", "G", "Am", "F", "C", "G", "E", "Am"]
    c_prog = ["Dm", "Am", "Bf", "F", "Dm", "E", "Am", "Am"]
    progression = a_prog + b_prog + a_prog + c_prog

    lay_backing(song, progression, march=True)
    # B 部は打楽器を抜いて、低音と旋律だけにする（ここで一段静まる）
    lay_march_drums_range(song, 0, 8)
    lay_march_drums_range(song, 8, 16, hats=False)
    lay_march_drums_range(song, 16, 32)

    a_melody = [
        [("a4", 1.5), ("a4", 0.5), ("c5", 1), ("b4", 1)],
        [("a4", 2), ("g4", 1), ("f4", 1)],
        [("g4", 1.5), ("a4", 0.5), ("b4", 1), ("d5", 1)],
        [("a4", 3), ("r", 1)],
        [("e5", 1.5), ("e5", 0.5), ("d5", 1), ("c5", 1)],
        [("c5", 2), ("b4", 1), ("a4", 1)],
        [("b4", 1.5), ("c5", 0.5), ("d5", 1), ("b4", 1)],
        [("a4", 4)],
    ]
    b_melody = [
        [("e5", 1), ("g5", 1), ("e5", 1), ("c5", 1)],
        [("d5", 2), ("b4", 2)],
        [("c5", 1), ("e5", 1), ("a5", 1), ("g5", 1)],
        [("f5", 2), ("e5", 2)],
        [("e5", 1.5), ("d5", 0.5), ("c5", 1), ("d5", 1)],
        [("b4", 2), ("d5", 2)],
        [("gs4", 2), ("b4", 2)],  # 和声的短音階の導音。ここで一段持ち上がる
        [("a4", 4)],
    ]
    c_melody = [
        [("d5", 1), ("f5", 1), ("a5", 1), ("f5", 1)],
        [("e5", 2), ("c5", 2)],
        [("d5", 1), ("f5", 1), ("bf5", 1), ("a5", 1)],
        [("f5", 2), ("c5", 2)],
        [("d5", 1.5), ("e5", 0.5), ("f5", 1), ("d5", 1)],
        [("gs4", 2), ("b4", 2)],
        [("a4", 1), ("c5", 1), ("e5", 1), ("a5", 1)],
        [("a4", 4)],
    ]
    melody = a_melody + b_melody + a_melody + c_melody
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, LEAD, 0.95)

    # 3 度下のブラス（A 部だけ）。B 部は笛に持ち替えて色を変える。
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
        song.phrase(song.bar(16 + i), phrase, BRASS, 0.40)
    for i in range(8, 16):
        song.phrase(song.bar(i), melody[i], FLUTE, 0.28)
    lay_arpeggio(song, 24, 32, c_prog, BELL, 0.20)

    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    finish(song.track, AUDIO / "bgm" / "descent.wav",
           cutoff=5000.0, echo_ms=124.0, echo_fb=0.30)


# --------------------------------------------------------------------------
# BGM 3: 戦闘 — 速い短調（A8 / B8 / A8）
# --------------------------------------------------------------------------


def bgm_battle() -> None:
    bars = 24
    song = Song(bpm=164, bars=bars)

    a_prog = ["Am", "Am", "F", "G", "Am", "Dm", "E", "Am"]
    b_prog = ["C", "G", "Dm", "Am", "F", "G", "E", "E"]
    progression = a_prog + b_prog + a_prog

    lay_backing(song, progression, march=True, pad_amp=0.75)
    lay_march_drums_range(song, 0, 8)
    lay_march_drums_range(song, 8, 16, hats=False)
    lay_march_drums_range(song, 16, 24)

    a_melody = [
        [("a4", 0.5), ("c5", 0.5), ("e5", 0.5), ("a5", 0.5), ("e5", 1), ("c5", 1)],
        [("d5", 0.5), ("c5", 0.5), ("b4", 0.5), ("a4", 0.5), ("b4", 2)],
        [("f5", 0.5), ("e5", 0.5), ("d5", 0.5), ("c5", 0.5), ("f5", 2)],
        [("g5", 0.5), ("f5", 0.5), ("e5", 0.5), ("d5", 0.5), ("g5", 2)],
        [("a5", 1), ("e5", 1), ("c5", 1), ("a4", 1)],
        [("d5", 0.5), ("f5", 0.5), ("a5", 0.5), ("f5", 0.5), ("d5", 2)],
        [("gs4", 0.5), ("b4", 0.5), ("e5", 0.5), ("gs5", 0.5), ("b5", 2)],
        [("a5", 4)],
    ]
    # B 部は刻みを止めて長い音にする。速い曲は、緩む部分があると速さが際立つ。
    b_melody = [
        [("g5", 2), ("e5", 2)],
        [("d5", 2), ("b4", 2)],
        [("f5", 2), ("d5", 2)],
        [("e5", 2), ("c5", 2)],
        [("a5", 1), ("g5", 1), ("f5", 2)],
        [("g5", 1), ("f5", 1), ("e5", 2)],
        [("gs5", 0.5), ("b5", 0.5), ("gs5", 0.5), ("e5", 0.5), ("b4", 2)],
        [("e5", 4)],
    ]
    melody = a_melody + b_melody + a_melody
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, LEAD, 1.0)

    lay_arpeggio(song, 8, 16, b_prog, BELL, 0.26)
    for i in [7, 15, 23]:
        lay_fill(song, i)

    finish(song.track, AUDIO / "bgm" / "battle.wav",
           cutoff=5600.0, echo_ms=108.0, echo_fb=0.26)


# --------------------------------------------------------------------------
# BGM 4: 題名 — まだ属する世界のない場所
# --------------------------------------------------------------------------


def bgm_title() -> None:
    bars = 24
    song = Song(bpm=76, bars=bars, tail=3.5)
    progression = (
        ["Am", "F", "C", "G", "Am", "Dm", "E", "Am"]
        + ["F", "C", "G", "Am", "Dm", "F", "E", "E"]
        + ["Am", "F", "C", "G", "Dm", "E", "Am", "Am"]
    )

    # 砦にも世界にもまだ入っていない。行進を置かず、遠い合唱と単音だけにする。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, 3.9, triad, CHOIR, 0.34)
        song.note(start, 3.8, root, BASS, 0.42)
        if i % 2 == 1:
            song.note(start + 2.0, 1.8, fifth, BASS, 0.26)
        for beat, pitch in zip([0.0, 1.5, 2.5], [triad[0], triad[2], triad[1]]):
            song.note(start + beat, 0.75, pitch, HARP, 0.24)

    lay_witness(song, 0, OBOE, 0.66)
    lay_witness(song, 8, FLUTE, 0.52, high=True)
    # 最後は完全解決させない。出撃するまで物語は始まっていない。
    lay_witness(song, 16, OBOE, 0.60)
    countermelody = [
        [("e5", 2), ("d5", 1), ("c5", 1)],
        [("a4", 3), ("r", 1)],
        [("g4", 1), ("c5", 2), ("b4", 1)],
        [("e4", 4)],
    ]
    for section in [4, 12, 20]:
        for i, phrase in enumerate(countermelody):
            song.phrase(song.bar(section + i), phrase, FLUTE, 0.38)

    finish(song.track, AUDIO / "bgm" / "title.wav",
           cutoff=5000.0, echo_ms=184.0, echo_fb=0.38, peak=0.78)


# --------------------------------------------------------------------------
# BGM 5: 世界 — 使い捨ての世界を最後まで歩く
# --------------------------------------------------------------------------


def bgm_world() -> None:
    bars = 32
    song = Song(bpm=116, bars=bars)
    a_prog = ["Am", "F", "C", "G", "Am", "F", "Dm", "E"]
    b_prog = ["C", "G", "Am", "Em", "F", "C", "Dm", "E"]
    c_prog = ["Dm", "Am", "Bf", "F", "C", "G", "E", "Am"]
    progression = a_prog + b_prog + a_prog + c_prog

    lay_backing(song, progression, march=True, pad_amp=0.74, bass_amp=0.82)
    # 通常の軍楽より軽い。スネアを半分にし、旅の歩調を前へ出す。
    for i in range(bars):
        start = song.bar(i)
        song.drum(start, "kick")
        song.drum(start + 2, "kick")
        if i % 2 == 1:
            song.drum(start + 3, "snare")
        for k in [1, 3, 5, 7]:
            song.drum(start + k * 0.5, "hat")

    a_melody = [
        WITNESS,
        [("a4", 2), ("g4", 1), ("f4", 1)],
        [("g4", 1), ("c5", 1), ("e5", 1), ("g5", 1)],
        [("d5", 2), ("b4", 2)],
        [("e5", 1.5), ("d5", 0.5), ("c5", 1), ("a4", 1)],
        [("c5", 2), ("a4", 2)],
        [("d5", 1), ("f5", 1), ("e5", 1), ("d5", 1)],
        [("b4", 1), ("gs4", 1), ("a4", 2)],
    ]
    b_melody = [
        [("g5", 1), ("e5", 1), ("c5", 2)],
        [("d5", 1), ("g5", 1), ("b5", 2)],
        [("a5", 1.5), ("g5", 0.5), ("e5", 1), ("c5", 1)],
        [("b4", 2), ("e5", 2)],
        [("f5", 1), ("a5", 1), ("c6", 1), ("a5", 1)],
        [("g5", 2), ("e5", 2)],
        [("f5", 1), ("e5", 1), ("d5", 1), ("b4", 1)],
        [("gs4", 1), ("b4", 1), ("e5", 2)],
    ]
    c_melody = [
        [("d5", 1), ("f5", 1), ("a5", 2)],
        [("e5", 1), ("c5", 1), ("a4", 2)],
        [("bf4", 1), ("d5", 1), ("f5", 1), ("a5", 1)],
        [("c6", 2), ("a5", 2)],
        [("g5", 1), ("e5", 1), ("d5", 1), ("c5", 1)],
        [("b4", 1), ("d5", 1), ("g5", 2)],
        [("gs5", 1), ("e5", 1), ("b4", 2)],
        WITNESS_HOME,
    ]
    melody = a_melody + b_melody + a_melody + c_melody
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, OBOE if i < 16 else FLUTE, 0.74)
    lay_arpeggio(song, 8, 16, b_prog, HARP, 0.17)
    lay_arpeggio(song, 24, 32, c_prog, BELL, 0.16)
    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    finish(song.track, AUDIO / "bgm" / "world.wav",
           cutoff=5300.0, echo_ms=132.0, echo_fb=0.29)


# --------------------------------------------------------------------------
# BGM 6: 町 — 失われる世界にある一時の家
# --------------------------------------------------------------------------


def bgm_town() -> None:
    bars = 24
    song = Song(bpm=88, bars=bars, tail=3.0)
    a_prog = ["C", "Am", "F", "G", "C", "Em", "Dm", "G"]
    b_prog = ["Am", "Em", "F", "C", "Dm", "Am", "E", "E"]
    progression = a_prog + b_prog + a_prog

    lay_backing(song, progression, march=False, pad_amp=0.62, bass_amp=0.58)
    lay_arpeggio(song, 0, bars, progression, HARP, 0.25)

    melody = [
        WITNESS,
        [("a4", 2), ("c5", 2)],
        [("f5", 1), ("e5", 1), ("c5", 2)],
        [("d5", 1), ("b4", 1), ("g4", 2)],
        [("e5", 1), ("g5", 1), ("c6", 2)],
        [("b5", 2), ("g5", 2)],
        [("f5", 1), ("d5", 1), ("c5", 1), ("a4", 1)],
        [("b4", 3), ("r", 1)],
        [("a4", 1.5), ("c5", 0.5), ("e5", 2)],
        [("g5", 1), ("e5", 1), ("b4", 2)],
        [("c5", 1), ("f5", 1), ("a5", 2)],
        [("g5", 2), ("e5", 2)],
        [("d5", 1), ("f5", 1), ("a5", 1), ("f5", 1)],
        [("e5", 2), ("c5", 2)],
        [("b4", 1), ("gs4", 1), ("b4", 2)],
        [("e5", 4)],
    ] + [
        WITNESS_HOME,
        [("a4", 2), ("c5", 2)],
        [("f5", 1), ("e5", 1), ("c5", 2)],
        [("d5", 1), ("b4", 1), ("g4", 2)],
        [("e5", 1), ("g5", 1), ("c6", 2)],
        [("b5", 2), ("g5", 2)],
        [("f5", 1), ("d5", 1), ("b4", 1), ("d5", 1)],
        [("c5", 4)],
    ]
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, OBOE, 0.62)
    for i in range(8, 16):
        triad, _, _ = CHORDS[progression[i]]
        song.note(song.bar(i) + 2, 1.7, triad[2], FLUTE, 0.23)

    finish(song.track, AUDIO / "bgm" / "town.wav",
           cutoff=5200.0, echo_ms=154.0, echo_fb=0.32, peak=0.80)


# --------------------------------------------------------------------------
# BGM 7: 洞 — 世界の傷へ降りる
# --------------------------------------------------------------------------


def bgm_cave() -> None:
    bars = 24
    song = Song(bpm=94, bars=bars, tail=3.2)
    a_prog = ["Dm", "Am", "Bf", "E", "Dm", "F", "E", "Am"]
    b_prog = ["Am", "Bf", "Dm", "E", "F", "Dm", "E", "E"]
    progression = a_prog + b_prog + a_prog

    # 洞では拍を埋めない。長い低音と、空間の奥で返る短い音だけ。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.note(start, 3.8, root, BASS, 0.56)
        song.note(start + 2, 1.7, fifth, BASS, 0.30)
        song.chord(start, 3.7, triad, STRINGS, 0.24)
        if i % 2 == 0:
            song.note(start + 0.5, 0.32, triad[2], BELL, 0.25)
            song.note(start + 2.75, 0.28, triad[1], BELL, 0.19)

    melody = [
        [("d4", 2), ("a4", 1), ("c5", 1)],
        [("e5", 3), ("r", 1)],
        [("f5", 1), ("d5", 1), ("bf4", 2)],
        [("b4", 1), ("gs4", 1), ("e4", 2)],
        WITNESS,
        [("f4", 2), ("a4", 2)],
        [("b4", 1), ("e5", 1), ("gs5", 1), ("e5", 1)],
        [("a4", 3), ("r", 1)],
    ]
    for section in [0, 8, 16]:
        for i, phrase in enumerate(melody):
            inst = OBOE if section == 8 else FLUTE
            song.phrase(song.bar(section + i), phrase, inst, 0.46 if section == 8 else 0.40)
    # 地鳴りは規則的にしない。予告として数小節にだけ置く。
    for i in [3, 7, 11, 15, 20, 23]:
        song.drum(song.bar(i) + 3.0, "kick")

    finish(song.track, AUDIO / "bgm" / "cave.wav",
           cutoff=4200.0, echo_ms=202.0, echo_fb=0.40, peak=0.78)


# --------------------------------------------------------------------------
# BGM 8: 物語 — 守りたい一人と約束を交わす
# --------------------------------------------------------------------------


def bgm_story() -> None:
    bars = 16
    song = Song(bpm=72, bars=bars, tail=3.6)
    progression = (
        ["Am", "F", "C", "E", "Am", "Dm", "F", "E"]
        + ["C", "G", "Am", "F", "Dm", "E", "Am", "Am"]
    )
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, 3.8, triad, CHOIR, 0.22)
        song.note(start, 3.7, root, BASS, 0.30)
        for k, pitch in enumerate([triad[0], triad[2], triad[1], triad[2]]):
            song.note(start + k, 0.72, pitch, HARP, 0.26)

    lay_witness(song, 0, OBOE, 0.64)
    song.phrase(song.bar(1), [("a4", 2), ("e5", 1), ("d5", 1)], OBOE, 0.50)
    song.phrase(song.bar(2), [("e5", 2), ("g5", 2)], FLUTE, 0.34)
    song.phrase(song.bar(3), [("b4", 1), ("gs4", 1), ("e4", 2)], OBOE, 0.48)
    for i in range(4, 8):
        triad, _, _ = CHORDS[progression[i]]
        song.phrase(song.bar(i), [(triad[1], 2), (triad[2], 2)], FLUTE, 0.32)
    lay_witness(song, 8, FLUTE, 0.52, high=True)
    song.phrase(song.bar(12), [("d5", 1), ("f5", 1), ("a5", 2)], OBOE, 0.46)
    song.phrase(song.bar(13), [("b4", 1), ("e5", 1), ("gs5", 2)], OBOE, 0.46)
    song.phrase(song.bar(14), [("a5", 2), ("e5", 2)], FLUTE, 0.42)
    lay_witness(song, 15, OBOE, 0.56, resolved=True)
    lay_heartbeat(song, 0, bars, 0.10)

    finish(song.track, AUDIO / "bgm" / "story.wav",
           cutoff=4700.0, echo_ms=176.0, echo_fb=0.36, peak=0.77)


# --------------------------------------------------------------------------
# BGM 9: 主 — 世界を閉じる機械と、約束を守る者
# --------------------------------------------------------------------------


def bgm_boss() -> None:
    bars = 32
    song = Song(bpm=152, bars=bars)
    a_prog = ["Am", "Bf", "Am", "E", "Am", "F", "Bf", "E"]
    b_prog = ["Dm", "Am", "Bf", "E", "F", "Dm", "E", "E"]
    c_prog = ["Bf", "F", "Dm", "Am", "Bf", "E", "Am", "E"]
    progression = a_prog + b_prog + a_prog + c_prog

    # 帝国機械の歯車。ルートと五度を八分で交互にし、全小節で止めない。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, 3.8, triad, STRINGS, 0.34)
        for k in range(8):
            song.note(start + k * 0.5, 0.44, root if k % 2 == 0 else fifth,
                      BASS, 0.82)
        song.drum(start, "kick")
        song.drum(start + 1, "snare")
        song.drum(start + 2, "kick")
        song.drum(start + 2.5, "kick")
        song.drum(start + 3, "snare")
        for k in [1, 3, 5, 7]:
            song.drum(start + k * 0.5, "hat")

    # 見届ける動機を逆から鳴らす。主は約束を諦めさせる側。
    inverse = [
        [("e5", 0.5), ("c5", 0.5), ("a4", 1), ("b4", 2)],
        [("bf4", 1), ("d5", 1), ("f5", 1), ("a5", 1)],
        [("e5", 0.5), ("c5", 0.5), ("a4", 1), ("e5", 2)],
        [("gs5", 1), ("e5", 1), ("b4", 2)],
        [("a5", 1), ("e5", 1), ("c5", 1), ("a4", 1)],
        [("f5", 1), ("a5", 1), ("c6", 2)],
        [("bf5", 0.5), ("a5", 0.5), ("f5", 1), ("d5", 2)],
        [("gs5", 1), ("b5", 1), ("e6", 2)],
    ]
    answer = [
        WITNESS_HIGH,
        [("d6", 1), ("bf5", 1), ("a5", 2)],
        [("a5", 0.5), ("c6", 0.5), ("e6", 1), ("d6", 2)],
        [("b5", 1), ("gs5", 1), ("e5", 2)],
        [("c6", 1), ("a5", 1), ("f5", 2)],
        [("a5", 1), ("f5", 1), ("d5", 2)],
        [("b4", 0.5), ("e5", 0.5), ("gs5", 1), ("b5", 2)],
        [("a5", 4)],
    ]
    melody = inverse + answer + inverse + answer
    for i, phrase in enumerate(melody):
        song.phrase(song.bar(i), phrase, LOW_BRASS if i < 8 or 16 <= i < 24 else LEAD,
                    0.88)
    for i in range(8, 16):
        song.phrase(song.bar(i), melody[i], OBOE, 0.24)
    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    finish(song.track, AUDIO / "bgm" / "boss.wav",
           cutoff=5700.0, echo_ms=96.0, echo_fb=0.24, peak=0.88)


# --------------------------------------------------------------------------
# BGM 10: 戦記 — 勝敗にかかわらず、踏んだ記録は帰る
# --------------------------------------------------------------------------


def bgm_chronicle() -> None:
    bars = 24
    song = Song(bpm=80, bars=bars, tail=4.0)
    a_prog = ["Am", "F", "C", "G", "Am", "Dm", "E", "Am"]
    b_prog = ["Dm", "Am", "Bf", "F", "Dm", "E", "Am", "E"]
    c_prog = ["C", "G", "Am", "F", "Dm", "E", "Am", "Am"]
    progression = a_prog + b_prog + c_prog

    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, 3.8, triad, STRINGS, 0.34)
        song.note(start, 1.8, root, BASS, 0.46)
        song.note(start + 2, 1.8, fifth, BASS, 0.32)
        # 戦記へ文字が一行ずつ刻まれるような、四分の撥弦。
        for k, pitch in enumerate([triad[0], triad[1], triad[2], triad[1]]):
            song.note(start + k, 0.55, pitch, HARP, 0.20)

    lay_witness(song, 0, OBOE, 0.58)
    lay_witness(song, 8, FLUTE, 0.48, high=True)
    # 勝敗どちらにも使うため、勝利の大終止ではなく「記録が帰った」解決。
    lay_witness(song, 16, OBOE, 0.62, resolved=True)
    coda = [
        [("f5", 1), ("e5", 1), ("d5", 2)],
        [("b4", 1), ("gs4", 1), ("e5", 2)],
        [("a4", 1), ("c5", 1), ("e5", 1), ("a5", 1)],
        [("a4", 4)],
    ]
    for i, phrase in enumerate(coda):
        song.phrase(song.bar(20 + i), phrase, FLUTE, 0.42)

    finish(song.track, AUDIO / "bgm" / "chronicle.wav",
           cutoff=4900.0, echo_ms=168.0, echo_fb=0.35, peak=0.79)



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

    # 出撃: 砦から新しい世界へ踏み出す。上昇だけで終わらず B に止め、
    # ワールド曲の「見届ける動機」へそのまま渡す。
    def _depart(t: Track) -> None:
        for i, n in enumerate(["a4", "c5", "e5", "b5"]):
            t.add_note(i * 0.095, 0.22, n, BRASS, 0.68)
        t.add_note(0.38, 0.46, "e3", LOW_BRASS, 0.58)
    sfx("depart", _depart, 1.16, cutoff=6100.0, echo_ms=122.0,
        echo_fb=0.26, peak=0.74)

    # 任意イベント: 宝箱ほど明るくなく、遭遇ほど敵対的でもない。
    def _event(t: Track) -> None:
        t.add_note(0.00, 0.34, "a4", BELL, 0.52)
        t.add_note(0.11, 0.34, "e5", BELL, 0.46)
        t.add_note(0.22, 0.46, "b4", OBOE, 0.40)
    sfx("event", _event, 0.96, cutoff=6800.0, echo_ms=146.0,
        echo_fb=0.30, peak=0.62)

    # 物語の拍: 同じ人物・同じモチーフが戻ってきたことを知らせる四音。
    def _story_open(t: Track) -> None:
        for i, n in enumerate(["a4", "c5", "e5", "b4"]):
            t.add_note(i * 0.12, 0.31, n, HARP, 0.58)
        t.add_note(0.48, 0.42, "a3", CHOIR, 0.34)
    sfx("story_open", _story_open, 1.22, cutoff=5700.0, echo_ms=162.0,
        echo_fb=0.34, peak=0.64)

    # 物語の選択: 明るい決定音ではなく、低い代償と高い意志を同時に鳴らす。
    def _story_choice(t: Track) -> None:
        t.add_note(0.00, 0.36, "a2", LOW_BRASS, 0.62)
        t.add_note(0.04, 0.28, "e3", LOW_BRASS, 0.46)
        t.add_note(0.14, 0.36, "a5", OBOE, 0.52)
        t.add_note(0.27, 0.52, "e5", OBOE, 0.46)
    sfx("story_choice", _story_choice, 1.24, cutoff=5200.0,
        echo_ms=138.0, echo_fb=0.28, peak=0.70)

    # 封の破壊: 低い亀裂、ノイズ、最後に澄んだ解放音。
    def _seal_break(t: Track) -> None:
        t.add_sweep(0.00, 0.34, "e3", "a1", LOW_BRASS, 0.66)
        t.add_noise(0.08, 0.42, amp=0.58, decay=0.055, pitch=3)
        for i, n in enumerate(["a4", "e5", "a5"]):
            t.add_note(0.38 + i * 0.09, 0.38, n, BELL, 0.54)
    sfx("seal_break", _seal_break, 1.38, cutoff=6100.0,
        echo_ms=126.0, echo_fb=0.28, peak=0.82)

    # 主の門: 機械の起動と、戻れない一歩。
    def _boss_gate(t: Track) -> None:
        t.add_note(0.00, 0.58, "a1", LOW_BRASS, 0.78)
        t.add_note(0.12, 0.50, "e2", LOW_BRASS, 0.66)
        t.add_noise(0.00, 0.50, amp=0.36, decay=0.09, pitch=5)
        t.add_sweep(0.34, 0.36, "e3", "e5", LEAD, 0.46)
    sfx("boss_gate", _boss_gate, 1.28, cutoff=4700.0,
        echo_ms=112.0, echo_fb=0.22, peak=0.84)

    # 生還: 勝利の誇示ではなく、約束が最後まで届いた短い終止。
    def _victory(t: Track) -> None:
        for i, n in enumerate(["a4", "c5", "e5", "a5"]):
            t.add_note(i * 0.13, 0.34, n, BRASS, 0.72)
        t.add_note(0.52, 0.74, "a5", BRASS, 0.82)
        t.add_note(0.52, 0.74, "c6", BRASS, 0.48)
        t.add_note(0.52, 0.74, "e6", OBOE, 0.36)
    sfx("victory", _victory, 1.86, cutoff=6500.0,
        echo_ms=144.0, echo_fb=0.32, peak=0.78)

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
