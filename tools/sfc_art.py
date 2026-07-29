"""
SFC 風アセット生成の基盤 — 依存ゼロ（標準ライブラリのみ）

実機と同じ制約を「守れる仕組み」として実装する。SFC らしさは技巧ではなく
制約の徹底から出るので、ここを迂回できないようにしておくのが要点。

  * 色は BGR555（各チャンネル 5bit / 32段階）に量子化される
  * 1 サブパレットは 16 色、index 0 は透明
  * ドット絵は ASCII マップ + 凡例で記述する（差分がレビューできる形式）
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

# --------------------------------------------------------------------------
# 色: BGR555 量子化
# --------------------------------------------------------------------------


def snes(hex_color: str) -> tuple[int, int, int]:
    """#RRGGBB を SNES が実際に表示できる色へ丸める。

    各チャンネル 5bit なので 32 段階。31 で割り戻すことで白が 255 に届く。
    """
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    return tuple((c >> 3) * 255 // 31 for c in (r, g, b))


TRANSPARENT = (0, 0, 0, 0)


class Palette:
    """16 色のサブパレット。index 0 は透明で固定。"""

    def __init__(self, name: str, colors: dict[str, str]):
        if len(colors) > 15:
            raise ValueError(f"{name}: サブパレットは透明を除き 15 色まで（{len(colors)} 色指定された）")
        self.name = name
        self.keys = list(colors)
        self.rgba: dict[str, tuple[int, int, int, int]] = {".": TRANSPARENT}
        for key, hex_color in colors.items():
            if key == ".":
                raise ValueError("'.' は透明用に予約されている")
            r, g, b = snes(hex_color)
            self.rgba[key] = (r, g, b, 255)

    def get(self, ch: str) -> tuple[int, int, int, int]:
        try:
            return self.rgba[ch]
        except KeyError:
            raise KeyError(f"パレット {self.name} に '{ch}' が無い。定義済み: {''.join(self.rgba)}") from None


# --------------------------------------------------------------------------
# キャンバス
# --------------------------------------------------------------------------


class Canvas:
    """RGBA のピクセルバッファ。"""

    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.px = [TRANSPARENT] * (w * h)

    def set(self, x: int, y: int, color: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = color

    def get(self, x: int, y: int) -> tuple[int, int, int, int]:
        return self.px[y * self.w + x]

    def blit(self, src: "Canvas", dx: int, dy: int) -> None:
        for y in range(src.h):
            for x in range(src.w):
                c = src.get(x, y)
                if c[3]:
                    self.set(dx + x, dy + y, c)

    def scaled(self, factor: int) -> "Canvas":
        """最近傍で整数倍拡大（目視確認用。ゲームには等倍を渡す）。"""
        out = Canvas(self.w * factor, self.h * factor)
        for y in range(out.h):
            row = (y // factor) * self.w
            for x in range(out.w):
                out.px[y * out.w + x] = self.px[row + x // factor]
        return out

    def to_png(self, path: str | Path) -> None:
        write_png(path, self.w, self.h, self.px)


def from_ascii(rows: list[str], palette: Palette, width: int | None = None) -> Canvas:
    """ASCII マップからタイル/スプライトを起こす。

    行末は透明で自動的に埋める。右端の '.' を数え続けるのは事故のもとなので、
    意味があるのは行頭からの位置だけ、と割り切る。ただし鏡像で綴じる半身は
    右端が中心線になるため、その場合だけ width を明示すること。
    """
    h = len(rows)
    w = width if width is not None else max(len(r) for r in rows)
    for i, row in enumerate(rows):
        if len(row) > w:
            raise ValueError(f"行 {i} の幅が {len(row)} で、指定の {w} を超えている")
    rows = [row.ljust(w, ".") for row in rows]
    c = Canvas(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c.set(x, y, palette.get(ch))
    return c


def mirrored(src: Canvas) -> Canvas:
    """左右反転。横向きスプライトの反対向きを作る定石。"""
    out = Canvas(src.w, src.h)
    for y in range(src.h):
        for x in range(src.w):
            out.set(src.w - 1 - x, y, src.get(x, y))
    return out


def shifted(src: Canvas, dx: int, dy: int, y_range: tuple[int, int] | None = None) -> Canvas:
    """指定した行帯だけをずらす。歩行フレームの脚を動かすのに使う。"""
    lo, hi = y_range if y_range else (0, src.h)
    out = Canvas(src.w, src.h)
    for y in range(src.h):
        for x in range(src.w):
            c = src.get(x, y)
            if not c[3]:
                continue
            if lo <= y < hi:
                out.set(x + dx, y + dy, c)
            else:
                out.set(x, y, c)
    return out


# --------------------------------------------------------------------------
# ディザ: 4x4 Bayer
# --------------------------------------------------------------------------

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def dither(c: Canvas, x0: int, y0: int, w: int, h: int, a: tuple, b: tuple, ratio: int) -> None:
    """a と b を Bayer パターンで混ぜる。ratio は 0..16（b の割合）。

    SFC は半透明が贅沢品だったので、階調はディザで作るのが時代の作法。
    """
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            threshold = BAYER4[y % 4][x % 4]
            c.set(x, y, b if threshold < ratio else a)


# --------------------------------------------------------------------------
# PNG 書き出し（標準ライブラリのみ）
# --------------------------------------------------------------------------


def write_png(path: str | Path, w: int, h: int, pixels: list[tuple[int, int, int, int]]) -> None:
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # フィルタタイプ: None
        for x in range(w):
            raw.extend(pixels[y * w + x])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
