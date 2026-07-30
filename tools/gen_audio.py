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
    BASS, BELL, BRASS, CHOIR, FLUTE, HARP, LEAD, LOW_BRASS, OBOE, PIANO,
    PIZZ, SFX_BASS, SFX_BELL, SFX_BRASS, SFX_CHOIR, SFX_FLUTE, SFX_HARP,
    SFX_LEAD, SFX_LOW_BRASS, SFX_OBOE, SFX_STRINGS, STRINGS, SAMPLE_RATE,
    Track, finish, finish_loop,
)

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"


class Song:
    """拍で音を置けるようにした薄い層。"""

    def __init__(self, bpm: float, bars: int, beats_per_bar: int = 4, tail: float = 2.5):
        self.spb = 60.0 / bpm
        self.beats_per_bar = beats_per_bar
        total_beats = bars * beats_per_bar
        self.loop_seconds = total_beats * self.spb
        self.track = Track(self.loop_seconds + tail)

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
            self.track.add_note(t, 0.10, "c2", BASS, 0.42)
            self.track.add_noise(t, 0.055, amp=0.12, decay=0.018, pitch=11)
        elif kind == "snare":
            self.track.add_note(t, 0.075, "d3", PIZZ, 0.24)
            self.track.add_noise(t, 0.12, amp=0.18, decay=0.042, pitch=3)
        elif kind == "hat":
            self.track.add_noise(t, 0.040, amp=0.060, decay=0.012, pitch=2)
        elif kind == "tom":
            self.track.add_note(t, 0.16, "a2", PIZZ, 0.36)
            self.track.add_noise(t, 0.055, amp=0.08, decay=0.024, pitch=7)
        elif kind == "timpani":
            self.track.add_note(t, 0.28, "d2", BASS, 0.46)
            self.track.add_noise(t, 0.075, amp=0.07, decay=0.030, pitch=9)

    def finish(self, path: Path, cutoff: float = 5200.0,
               echo_ms: float = 126.0, echo_fb: float = 0.30,
               peak: float = 0.82) -> None:
        finish_loop(self.track, path, self.loop_seconds, cutoff, echo_ms, echo_fb, peak)


# --------------------------------------------------------------------------
# 和音
# --------------------------------------------------------------------------

CHORDS = {
    "Am": (["a3", "c4", "e4"], "a2", "e3"),
    "Am9": (["a3", "b3", "c4", "e4"], "a2", "e3"),
    "F":  (["f3", "a3", "c4"], "f2", "c3"),
    "F6": (["f3", "a3", "c4", "d4"], "f2", "c3"),
    "G":  (["g3", "b3", "d4"], "g2", "d3"),
    "Gsus": (["g3", "c4", "d4"], "g2", "d3"),
    "C":  (["c4", "e4", "g4"], "c3", "g3"),
    "C2": (["c4", "d4", "g4"], "c3", "g3"),
    "C6": (["c4", "e4", "g4", "a4"], "c3", "g3"),
    "Em": (["e3", "g3", "b3"], "e2", "b2"),
    "Dm": (["d3", "f3", "a3"], "d3", "a3"),
    "Dm9": (["d3", "e3", "f3", "a3"], "d3", "a3"),
    "E":  (["e3", "gs3", "b3"], "e2", "b2"),
    "E7": (["e3", "gs3", "b3", "d4"], "e2", "b2"),
    "Bf": (["bf3", "d4", "f4"], "bf2", "f3"),
    "Bf6": (["bf3", "d4", "f4", "g4"], "bf2", "f3"),
}


def lay_backing(song: Song, progression: list[str], march: bool = True,
                pad_amp: float = 1.0, bass_amp: float = 1.0) -> None:
    """開いた和声と、旋律として動く低音を敷く。

    全小節を三和音パッドとルート連打で埋めると、曲が違っても同じ古い
    チップチューンに聞こえる。弦は拍の前半だけ、低音は休符と先取りを含める。
    """
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        open_voicing = [triad[0], triad[-1]]
        song.chord(start, 2.65 if song.beats_per_bar >= 4 else 1.8,
                   open_voicing, STRINGS, 0.38 * pad_amp)
        if i % 2 == 1:
            song.note(start + 2.0, 1.45, triad[1], STRINGS, 0.24 * pad_amp)

        if march:
            # 偶数小節は前へ出て、奇数小節は半拍空ける。ルート連打を避ける。
            pattern = (
                [(0.0, root), (1.0, fifth), (2.0, root), (3.5, fifth)]
                if i % 2 == 0 else
                [(0.0, root), (1.5, fifth), (2.5, root), (3.25, fifth)]
            )
            for beat, pitch in pattern:
                song.note(start + beat, 0.68 if beat % 1 else 0.82,
                          pitch, BASS, 0.60 * bass_amp)
        else:
            song.note(start, 1.65, root, BASS, 0.62 * bass_amp)
            song.note(start + 2, 1.35, fifth, BASS, 0.48 * bass_amp)


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
    """指定範囲に皮物中心の拍を置く。常時ノイズハットにはしない。"""
    for i in range(first, last):
        start = song.bar(i)
        song.drum(start, "kick")
        song.drum(start + 2, "tom" if i % 2 == 0 else "kick")
        song.drum(start + 3, "snare")
        if hats:
            for beat in (1.5, 3.5):
                song.drum(start + beat, "hat")


def lay_arpeggio(song: Song, first: int, last: int, progression: list[str],
                 inst, amp: float = 0.30) -> None:
    """余白へ三音の応答を置く。連続した八分音符の壁にはしない。

    「空いているから埋める」は音数過多の原因になる。小節後半だけに置き、
    次の小節では順序を変えて呼吸を作る。
    """
    for i in range(first, last):
        triad, _, _ = CHORDS[progression[i % len(progression)]]
        start = song.bar(i)
        order = [triad[0], triad[-1], triad[1]] if i % 2 == 0 else [triad[-1], triad[1], triad[0]]
        for k, pitch in enumerate(order):
            song.note(start + 2.0 + k * 0.5, 0.34, pitch, inst, amp)


# 全曲をつなぐ「見届ける動機」。上がったあと主音へ戻らず、B で一度止まる。
# 約束はできたが結末はまだ決まっていない、という形。終幕曲だけ最後を A に戻す。
WITNESS = [("a4", 1.5), ("c5", 0.5), ("e5", 1.0), ("b4", 1.0)]
WITNESS_HIGH = [("a5", 1.5), ("c6", 0.5), ("e6", 1.0), ("b5", 1.0)]
WITNESS_HOME = [("a4", 1.5), ("c5", 0.5), ("e5", 1.0), ("a5", 1.0)]


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
    song = Song(bpm=98, bars=bars)

    a_prog = ["C2", "Gsus", "Am9", "Em", "F6", "C", "Dm9", "G"]
    b_prog = ["F6", "G", "Em", "Am9", "Dm9", "Gsus", "C6", "C"]
    c_prog = ["Am9", "F6", "C2", "G", "F6", "Em", "Dm9", "Gsus"]
    progression = a_prog + b_prog + a_prog + c_prog

    lay_backing(song, progression, march=False, pad_amp=0.88, bass_amp=0.78)

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
        inst = OBOE if i < 8 or 16 <= i < 24 else (BRASS if i < 16 else FLUTE)
        amp = 0.68 if inst is OBOE else (0.58 if inst is BRASS else 0.55)
        song.phrase(song.bar(i), phrase, inst, amp)

    # 同じ旋律の薄い重ねではなく、節の終わりへだけ別の声で応答する。
    for i in (9, 11, 13, 15):
        triad, _, _ = CHORDS[progression[i]]
        song.phrase(song.bar(i) + 2, [(triad[1], 1), (triad[-1], 1)],
                    FLUTE, 0.26)
    lay_arpeggio(song, 24, 28, c_prog, HARP, 0.15)

    for i in (7, 15, 31):
        song.drum(song.bar(i) + 3, "timpani")

    song.finish(AUDIO / "bgm" / "stronghold.wav",
                cutoff=5000.0, echo_ms=142.0, echo_fb=0.29)


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

    song.finish(AUDIO / "bgm" / "descent.wav",
                cutoff=4800.0, echo_ms=124.0, echo_fb=0.27)


# --------------------------------------------------------------------------
# BGM 3: 戦闘 — 速い短調（A8 / B8 / A8）
# --------------------------------------------------------------------------


def bgm_battle() -> None:
    bars = 24
    song = Song(bpm=164, bars=bars)

    a_prog = ["Am9", "Am", "F6", "Gsus", "Am", "Dm9", "E7", "Am"]
    b_prog = ["C2", "G", "Dm9", "Am9", "F6", "Gsus", "E7", "E"]
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
        inst = BRASS if i < 8 or i >= 16 else OBOE
        song.phrase(song.bar(i), phrase, inst, 0.73 if inst is BRASS else 0.61)

    # 中間部は分散和音で埋めず、低い金管の短い応答で圧を保つ。
    for i in (9, 11, 13, 15):
        _, root, fifth = CHORDS[progression[i]]
        song.phrase(song.bar(i) + 2, [(root, 1), (fifth, 1)], LOW_BRASS, 0.24)
    for i in [7, 15, 23]:
        lay_fill(song, i)

    song.finish(AUDIO / "bgm" / "battle.wav",
                cutoff=5200.0, echo_ms=108.0, echo_fb=0.23, peak=0.84)


# --------------------------------------------------------------------------
# BGM 4: 題名 — まだ属する世界のない場所
# --------------------------------------------------------------------------


def bgm_title() -> None:
    bars = 24
    song = Song(bpm=76, bars=bars, tail=3.5)
    progression = (
        ["Am9", "F6", "C2", "Gsus", "Am", "Dm9", "E7", "Am"]
        + ["F6", "C", "Gsus", "Am9", "Dm9", "F", "E7", "E"]
        + ["Am9", "F6", "C2", "G", "Dm9", "E7", "Am", "Am9"]
    )

    # 砦にも世界にもまだ入っていない。二小節単位の呼吸を作り、
    # 合唱・低音・撥弦を同時に常駐させない。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        if i % 2 == 0:
            song.chord(start, 6.8, [triad[0], triad[-1]], CHOIR, 0.25)
            song.note(start, 3.6, root, BASS, 0.34)
        else:
            song.note(start + 2.0, 1.6, fifth, BASS, 0.22)
        for beat, pitch in zip([0.0, 2.5], [triad[0], triad[-1]]):
            song.note(start + beat, 0.62, pitch, HARP, 0.19)

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
            if i % 2 == 0:
                song.phrase(song.bar(section + i), phrase, FLUTE, 0.30)

    song.finish(AUDIO / "bgm" / "title.wav",
                cutoff=4700.0, echo_ms=184.0, echo_fb=0.34, peak=0.76)


# --------------------------------------------------------------------------
# BGM 5: 世界 — 使い捨ての世界を最後まで歩く
# --------------------------------------------------------------------------


def bgm_world() -> None:
    bars = 32
    song = Song(bpm=112, bars=bars)
    a_prog = ["Am9", "F6", "C2", "Gsus", "Am", "F6", "Dm9", "E7"]
    b_prog = ["C6", "G", "Am9", "Em", "F6", "C2", "Dm9", "E7"]
    c_prog = ["Dm9", "Am", "Bf6", "F", "C2", "Gsus", "E7", "Am9"]
    progression = a_prog + b_prog + a_prog + c_prog

    lay_backing(song, progression, march=True, pad_amp=0.74, bass_amp=0.82)
    # 軍楽ではなく足取り。中間部では皮物を抜き、景色が開く余白を作る。
    for i in range(bars):
        start = song.bar(i)
        if 8 <= i < 16:
            continue
        song.drum(start, "kick")
        song.drum(start + 2.5, "tom")
        if i % 2 == 1:
            song.drum(start + 3.5, "hat")

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
        inst = OBOE if i < 8 or 16 <= i < 24 else FLUTE
        amp = 0.58 if inst is OBOE else 0.50
        song.phrase(song.bar(i), phrase, inst, amp)
    lay_arpeggio(song, 10, 15, b_prog, HARP, 0.14)
    lay_arpeggio(song, 26, 31, c_prog, PIANO, 0.12)
    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    song.finish(AUDIO / "bgm" / "world.wav",
                cutoff=5000.0, echo_ms=132.0, echo_fb=0.26, peak=0.80)


# --------------------------------------------------------------------------
# BGM 6: 町 — 失われる世界にある一時の家
# --------------------------------------------------------------------------


def bgm_town() -> None:
    bars = 24
    song = Song(bpm=102, bars=bars, beats_per_bar=3, tail=2.6)
    a_prog = ["C6", "Am9", "F6", "Gsus", "C2", "Em", "Dm9", "G"]
    b_prog = ["Am9", "Em", "F6", "C2", "Dm9", "Am", "E7", "G"]
    progression = a_prog + b_prog + a_prog

    # 三拍子の小編成。低音・ピアノ・木管だけで、仮の故郷の人肌を作る。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.note(start, 1.45, root, PIZZ, 0.34)
        song.chord(start + 1.0, 0.62, [triad[1], triad[-1]], PIANO, 0.24)
        song.chord(start + 2.0, 0.62, [triad[0], triad[1]], PIANO, 0.20)
        if i % 4 == 3:
            song.note(start + 2.5, 0.32, fifth, HARP, 0.13)

    melody = [
        [("c5", 1.0), ("e5", 0.5), ("g5", 0.75), ("d5", 0.75)],
        [("c5", 1.5), ("a4", 1.5)],
        [("f5", 0.75), ("e5", 0.75), ("c5", 1.5)],
        [("d5", 1.0), ("b4", 0.5), ("g4", 1.5)],
        [("e5", 1.0), ("g5", 0.5), ("c6", 1.5)],
        [("b5", 1.5), ("g5", 1.5)],
        [("f5", 0.75), ("d5", 0.75), ("c5", 0.75), ("a4", 0.75)],
        [("b4", 2.25), ("r", 0.75)],
        [("a4", 1.0), ("c5", 0.5), ("e5", 1.5)],
        [("g5", 1.0), ("e5", 0.5), ("b4", 1.5)],
        [("c5", 0.75), ("f5", 0.75), ("a5", 1.5)],
        [("g5", 1.5), ("e5", 1.5)],
        [("d5", 0.75), ("f5", 0.75), ("a5", 0.75), ("f5", 0.75)],
        [("e5", 1.5), ("c5", 1.5)],
        [("b4", 0.75), ("gs4", 0.75), ("b4", 1.5)],
        [("d5", 2.25), ("r", 0.75)],
        [("c5", 1.0), ("e5", 0.5), ("g5", 0.75), ("c5", 0.75)],
        [("a4", 1.5), ("c5", 1.5)],
        [("f5", 0.75), ("e5", 0.75), ("c5", 1.5)],
        [("d5", 1.0), ("b4", 0.5), ("g4", 1.5)],
        [("e5", 1.0), ("g5", 0.5), ("c6", 1.5)],
        [("b5", 1.5), ("g5", 1.5)],
        [("f5", 0.75), ("d5", 0.75), ("b4", 0.75), ("d5", 0.75)],
        [("c5", 3.0)],
    ]
    for i, phrase in enumerate(melody):
        inst = FLUTE if 8 <= i < 16 else OBOE
        song.phrase(song.bar(i), phrase, inst, 0.46 if inst is FLUTE else 0.51)
    for i in (9, 11, 13):
        triad, _, _ = CHORDS[progression[i]]
        song.note(song.bar(i) + 2.0, 0.72, triad[-1], HARP, 0.15)

    song.finish(AUDIO / "bgm" / "town.wav",
                cutoff=4900.0, echo_ms=154.0, echo_fb=0.29, peak=0.77)


# --------------------------------------------------------------------------
# BGM 7: 洞 — 世界の傷へ降りる
# --------------------------------------------------------------------------


def bgm_cave() -> None:
    bars = 24
    song = Song(bpm=94, bars=bars, tail=3.2)
    a_prog = ["Dm9", "Am9", "Bf6", "E7", "Dm", "F6", "E7", "Am"]
    b_prog = ["Am9", "Bf6", "Dm9", "E7", "F6", "Dm", "E7", "E"]
    progression = a_prog + b_prog + a_prog

    # 洞では拍を埋めない。長い低音と、空間の奥で返る短い音だけ。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.note(start, 3.5, root, BASS, 0.43)
        if i % 2 == 1:
            song.note(start + 2, 1.4, fifth, BASS, 0.23)
        if i % 2 == 0:
            song.chord(start, 6.6, [triad[0], triad[-1]], STRINGS, 0.18)
        if i % 2 == 0:
            song.note(start + 0.5, 0.32, triad[-1], BELL, 0.19)
            song.note(start + 2.75, 0.28, triad[1], BELL, 0.14)

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
            if section == 8 and i % 2 == 1:
                continue
            if section == 16 and i not in (0, 3, 4, 7):
                continue
            inst = OBOE if section == 8 else FLUTE
            song.phrase(song.bar(section + i), phrase, inst, 0.38 if section == 8 else 0.34)
    # 地鳴りは規則的にしない。予告として数小節にだけ置く。
    for i in [3, 7, 11, 15, 20, 23]:
        song.drum(song.bar(i) + 3.0, "kick")

    song.finish(AUDIO / "bgm" / "cave.wav",
                cutoff=4000.0, echo_ms=202.0, echo_fb=0.36, peak=0.75)


# --------------------------------------------------------------------------
# BGM 8: 物語 — 守りたい一人と約束を交わす
# --------------------------------------------------------------------------


def bgm_story() -> None:
    bars = 16
    song = Song(bpm=72, bars=bars, tail=3.6)
    progression = (
        ["Am9", "F6", "C2", "E7", "Am", "Dm9", "F6", "E7"]
        + ["C6", "Gsus", "Am9", "F6", "Dm9", "E7", "Am", "Am9"]
    )
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        if i % 2 == 0:
            song.chord(start, 6.8, [triad[0], triad[-1]], CHOIR, 0.16)
        song.note(start, 2.6, root, BASS, 0.24)
        if i % 2 == 0:
            song.note(start + 1.0, 0.62, triad[-1], HARP, 0.20)
            song.note(start + 2.5, 0.62, triad[1], HARP, 0.16)
        else:
            song.note(start + 2.0, 0.68, fifth, PIZZ, 0.15)

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
    # 心拍はノイズ打楽器ではなく、二小節ごとの低い撥弦に留める。
    for i in range(0, bars, 2):
        song.note(song.bar(i), 0.28, "a2", PIZZ, 0.16)
        song.note(song.bar(i) + 0.75, 0.22, "e3", PIZZ, 0.11)

    song.finish(AUDIO / "bgm" / "story.wav",
                cutoff=4500.0, echo_ms=176.0, echo_fb=0.32, peak=0.74)


# --------------------------------------------------------------------------
# BGM 9: 主 — 世界を閉じる機械と、約束を守る者
# --------------------------------------------------------------------------


def bgm_boss() -> None:
    bars = 32
    song = Song(bpm=152, bars=bars)
    a_prog = ["Am9", "Bf6", "Am", "E7", "Am9", "F6", "Bf", "E7"]
    b_prog = ["Dm9", "Am", "Bf6", "E7", "F6", "Dm", "E7", "E"]
    c_prog = ["Bf6", "F", "Dm9", "Am", "Bf", "E7", "Am9", "E7"]
    progression = a_prog + b_prog + a_prog + c_prog

    # 帝国機械の歯車。四つの短い歯だけを反復し、隙間を金属打音へ渡す。
    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        song.chord(start, 2.7, [triad[0], triad[-1]], STRINGS, 0.24)
        for beat, pitch in ((0.0, root), (0.75, fifth), (2.0, root), (2.75, fifth)):
            song.note(start + beat, 0.46, pitch, BASS, 0.64)
        song.drum(start, "kick")
        song.drum(start + 1.5, "tom")
        song.drum(start + 3, "snare")
        if i % 2 == 1:
            song.drum(start + 3.5, "hat")

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
        inst = LOW_BRASS if i < 8 or 16 <= i < 24 else BRASS
        song.phrase(song.bar(i), phrase, inst, 0.69 if inst is LOW_BRASS else 0.62)
    # 人の旋律が答える区間だけ、木管を一音ずつ差し込む。
    for i in (9, 11, 13, 15):
        song.note(song.bar(i) + 2.0, 1.5, melody[i][-1][0], OBOE, 0.20)
    for i in [7, 15, 23, 31]:
        lay_fill(song, i)

    song.finish(AUDIO / "bgm" / "boss.wav",
                cutoff=5300.0, echo_ms=96.0, echo_fb=0.21, peak=0.86)


# --------------------------------------------------------------------------
# BGM 10: 戦記 — 勝敗にかかわらず、踏んだ記録は帰る
# --------------------------------------------------------------------------


def bgm_chronicle() -> None:
    bars = 24
    song = Song(bpm=80, bars=bars, tail=4.0)
    a_prog = ["Am9", "F6", "C2", "Gsus", "Am", "Dm9", "E7", "Am"]
    b_prog = ["Dm9", "Am", "Bf6", "F", "Dm", "E7", "Am9", "E"]
    c_prog = ["C6", "G", "Am9", "F6", "Dm9", "E7", "Am", "Am9"]
    progression = a_prog + b_prog + c_prog

    for i, name in enumerate(progression):
        triad, root, fifth = CHORDS[name]
        start = song.bar(i)
        if i % 2 == 0:
            song.chord(start, 6.7, [triad[0], triad[-1]], STRINGS, 0.22)
        song.note(start, 1.6, root, BASS, 0.34)
        song.note(start + 2.25, 1.2, fifth, BASS, 0.22)
        # 一行ずつ刻む撥弦は小節後半だけ。記録画面の文字と競合させない。
        if i % 2 == 1:
            song.note(start + 2.0, 0.48, triad[1], HARP, 0.16)
            song.note(start + 3.0, 0.48, triad[-1], HARP, 0.13)

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

    song.finish(AUDIO / "bgm" / "chronicle.wav",
                cutoff=4600.0, echo_ms=168.0, echo_fb=0.31, peak=0.76)



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
    # BGM の室内楽音色とは分離する。既存 SE の短い波形と操作感を保つ。
    LEAD = SFX_LEAD
    BRASS = SFX_BRASS
    STRINGS = SFX_STRINGS
    BASS = SFX_BASS
    BELL = SFX_BELL
    FLUTE = SFX_FLUTE
    OBOE = SFX_OBOE
    HARP = SFX_HARP
    CHOIR = SFX_CHOIR
    LOW_BRASS = SFX_LOW_BRASS

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
        ("BGM 題名", bgm_title),
        ("BGM 拠点", bgm_stronghold),
        ("BGM 世界", bgm_world),
        ("BGM 町", bgm_town),
        ("BGM 洞窟", bgm_cave),
        ("BGM 物語", bgm_story),
        ("BGM 戦闘", bgm_battle),
        ("BGM 主", bgm_boss),
        ("BGM 戦記", bgm_chronicle),
        # 古いセーブや作業中の画面から参照されても鳴るように残す。
        ("BGM 潜行（旧）", bgm_descent),
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
