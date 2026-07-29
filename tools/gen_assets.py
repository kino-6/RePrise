"""
アセット生成 — assets/ 以下の PNG をここから作る。

ドット絵は原則 ASCII マップで記述する。テクスチャのような反復パターンだけ
手続きで描く。左右対称のものは半分だけ描いて鏡像で綴じる（作業量が半分に
なるうえ、対称性が確実に揃う）。

    python tools/gen_assets.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from sfc_art import Canvas, Palette, dither, from_ascii, mirrored  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
# 拡大プレビューは目視確認用。Godot に取り込ませたくないので assets/ の外へ出す。
PREVIEW = ROOT / "docs" / "preview"

TILE = 16

# --------------------------------------------------------------------------
# パレット
# --------------------------------------------------------------------------

STONE = Palette(
    "stone",
    {
        "K": "#0E1220",  # 輪郭・最暗部
        "d": "#1E2740",  # 影
        "m": "#374460",  # 中間
        "l": "#54648A",  # 明
        "h": "#7C8FB4",  # ハイライト
        "w": "#AEC0DC",  # 最明部
        "e": "#2A1E14",  # 闇（階段の奥・扉の隙間）
        "g": "#C8963C",  # 金（宝箱・扉の金具）
        "G": "#F0D28C",  # 金ハイライト
        "r": "#7A3828",  # 木部の影
        "R": "#B0603C",  # 木部
        # 床は壁と色相をずらす。同じ灰色系で明度だけ変えると層が読めなくなる。
        "n": "#241E16",  # 床 目地
        "f": "#3C3226",  # 床
        "F": "#5A4C38",  # 床 明
    },
)

# キャラクターは docs/chara_image/ の設定画に合わせる。
# 共通項は「白銀の長髪 / 黒基調の装飾過多な衣装 / 金の縁取り / 強い差し色 1 色」。
# 差し色だけを入れ替えて 4 人を作る。同一シルエットのパレット違いという、
# SFC 期にキャラを増やすときの常套手段でもある。
HERO_BASE = {
    "K": "#0E0A16",  # 輪郭
    "B": "#1C1828",  # 衣装 影
    "b": "#302A44",  # 衣装
    "W": "#F8FAFF",  # 髪 最明部
    "w": "#DCE2F0",  # 髪 明
    "h": "#A8B2CC",  # 髪 中
    "H": "#6E7894",  # 髪 影
    "S": "#F8DCC4",  # 肌
    "s": "#D4A488",  # 肌 影
    "G": "#F4D890",  # 金
    "g": "#A8802C",  # 金 影
}

# 職業ごとの差し色（明・暗）。瞳と衣装の差し色を兼ねる。
HERO_ACCENTS = {
    "soldier": ("#58C8F8", "#1C6CB8"),  # 蒼
    "priest": ("#58E0B8", "#189070"),   # 翠
    "mage": ("#F878C8", "#B02878"),     # 桃
    "thief": ("#F86868", "#B01C34"),    # 紅
    # 上級職。基本職 2 つを混ぜた中間色にして、出自が見えるようにする。
    "paladin": ("#F8E070", "#B08018"),  # 金（蒼 x 翠 の格上げ）
    "ninja": ("#A878F8", "#5820B0"),    # 紫（紅 x 桃）
}


def hero_palette(job: str) -> Palette:
    bright, dark = HERO_ACCENTS[job]
    return Palette(f"hero_{job}", dict(HERO_BASE, E=bright, e=dark))

GEL = Palette(
    "gel",
    {
        "K": "#0C2018",  # 輪郭
        "d": "#14603C",  # 影
        "m": "#1E8A50",  # 本体
        "l": "#38B46C",  # 明
        "h": "#7CDC9C",  # ハイライト
        "W": "#E8FFF0",  # 光沢
        "E": "#0C1410",  # 目
        "e": "#FFFFFF",  # 目 白
    },
)

BAT = Palette(
    "bat",
    {
        "K": "#100C18",  # 輪郭
        "d": "#2C2038",  # 翼 影
        "m": "#4A3660",  # 翼
        "l": "#6E5288",  # 翼 明
        "f": "#8A6A44",  # 体毛 影
        "F": "#C09A64",  # 体毛
        "E": "#E04030",  # 目
        "W": "#F0E0C0",  # 牙
    },
)

BONE = Palette(
    "bone",
    {
        "K": "#14100C",  # 輪郭
        "d": "#6E6252",  # 骨 影
        "m": "#A89880",  # 骨 中
        "l": "#D8CCB4",  # 骨
        "W": "#F4EEDC",  # 骨 最明
        "E": "#E8503C",  # 眼窩の火
        "r": "#3A2A1E",  # 具足 影
        "R": "#6A4A30",  # 具足
    },
)

SHADE = Palette(
    "shade",
    {
        "K": "#0A0A12",  # 輪郭
        "d": "#1C1830",  # 裾 影
        "m": "#302A50",  # 衣
        "l": "#4A3E72",  # 衣 明
        "W": "#A894D8",  # 縁の光
        "E": "#78E8F0",  # 眼（青白）
        "e": "#2A6870",  # 眼 影
    },
)

GOLEM = Palette(
    "golem",
    {
        "K": "#100E14",  # 輪郭
        "d": "#2A2A30",  # 石 影
        "m": "#45454E",  # 石
        "l": "#62626E",  # 石 明
        "h": "#85858F",  # 石 ハイライト
        "W": "#B4B4BE",  # 稜線
        "E": "#F0A038",  # 刻まれた印（琥珀）
    },
)

# 最終階の主。主人公と同じ「黒基調 + 金の縁取り + 差し色 1 色」で組み、
# 差し色だけを紅にする。味方と同じ様式で描くと「同じ世界のもの」に見え、
# 寄せ集めの敵より最後の 1 体らしくなる。
WARDEN = Palette(
    "warden",
    {
        "K": "#0A0810",  # 輪郭
        "d": "#1A1626",  # 鎧 影
        "m": "#2E2842",  # 鎧
        "l": "#4A4266",  # 鎧 明
        "h": "#6E668C",  # 鎧 ハイライト
        "W": "#C8C0E0",  # 縁の光
        "G": "#F0D28C",  # 金
        "g": "#A8802C",  # 金 影
        "E": "#F85038",  # 眼（差し色）
        "e": "#7A1810",  # 眼 影
    },
)

UI = Palette(
    "ui",
    {
        "K": "#000814",  # 外枠
        "d": "#0E2050",  # 窓 濃
        "m": "#183070",  # 窓 中（中央部。9-slice で伸ばされる色）
        "n": "#1E3C88",  # 窓 中の上
        "l": "#2648A0",  # 窓 淡
        "w": "#F8F8F8",  # 内枠（白）
        "s": "#9CB4E0",  # 内枠 影
    },
)


# --------------------------------------------------------------------------
# タイル（16x16）
# --------------------------------------------------------------------------


def tile_floor(cracked: bool = False) -> Canvas:
    """石畳の床。目地で 16px グリッドを可視化し、ディザで質感を出す。"""
    c = Canvas(TILE, TILE)
    shade = STONE.get("n")
    dither(c, 0, 0, TILE, TILE, STONE.get("f"), STONE.get("F"), 4)
    # 目地: 外周を暗く、その内側を明るく（浅い彫り込みに見せる）
    for i in range(TILE):
        c.set(i, 0, shade)
        c.set(0, i, shade)
        c.set(i, 1, STONE.get("F"))
        c.set(1, i, STONE.get("F"))
        c.set(i, TILE - 1, shade)
        c.set(TILE - 1, i, shade)
    if cracked:
        for x, y in [(5, 4), (6, 5), (6, 6), (7, 7), (7, 8), (8, 9), (9, 9), (10, 10)]:
            c.set(x, y, shade)
            c.set(x + 1, y, STONE.get("F"))
    return c


def tile_wall() -> Canvas:
    """煉瓦壁。上端に光、下端に影を置いて厚みを出す。"""
    c = Canvas(TILE, TILE)
    dither(c, 0, 0, TILE, TILE, STONE.get("m"), STONE.get("l"), 5)
    mortar = STONE.get("d")
    for y in range(TILE):
        for x in range(TILE):
            row = y // 4
            # 段ごとに半ブロックずらす（互い違いの積み方）
            offset = 0 if row % 2 == 0 else 4
            if y % 4 == 3 or (x + offset) % 8 == 7:
                c.set(x, y, mortar)
    # 各ブロックの上辺に光、下辺に影
    for y in range(TILE):
        if y % 4 == 0:
            for x in range(TILE):
                if c.get(x, y) != mortar:
                    c.set(x, y, STONE.get("h"))
        if y % 4 == 2:
            for x in range(TILE):
                if c.get(x, y) != mortar:
                    c.set(x, y, STONE.get("d"))
    return c


def tile_wall_top() -> Canvas:
    """壁の天面。壁より一段暗くして、見下ろし視点の奥行きを作る。"""
    c = Canvas(TILE, TILE)
    dither(c, 0, 0, TILE, TILE, STONE.get("K"), STONE.get("d"), 6)
    for x in range(TILE):
        c.set(x, TILE - 1, STONE.get("h"))  # 手前の縁に光
        c.set(x, TILE - 2, STONE.get("l"))
    return c


TILE_STAIRS = [
    "KKKKKKKKKKKKKKKK",
    "KeeeeeeeeeeeeeeK",
    "KeeeeeeeeeeeeeeK",
    "KhhhhhhhhhhhhhhK",
    "KllllllllllllllK",
    "KmmmmmmmmmmmmmmK",
    "KKKKKKKKKKKKKKKK",
    "KKhhhhhhhhhhhhKK",
    "KKllllllllllllKK",
    "KKmmmmmmmmmmmmKK",
    "KKKKKKKKKKKKKKKK",
    "KKKKhhhhhhhhKKKK",
    "KKKKllllllllKKKK",
    "KKKKmmmmmmmmKKKK",
    "KKKKddddddddKKKK",
    "KKKKKKKKKKKKKKKK",
]

TILE_DOOR = [
    "KKKKKKKKKKKKKKKK",
    "KRRRRRRRRRRRRRRK",
    "KRrrrrrrrrrrrrRK",
    "KRrRRRRRRRRRRrRK",
    "KRrRddddddddRrRK",
    "KRrRdeeeeeedRrRK",
    "KRrRdeeeeeedRrRK",
    "KRrRdeeeeeedRrRK",
    "KRrRdeeeeeedRrRK",
    "KRrRddddddddRrRK",
    "KRrRRRRRRRRRRrRK",
    "KRrrrrGgggrrrrRK",
    "KRrrrrGgggrrrrRK",
    "KRRRRRRRRRRRRRRK",
    "KrrrrrrrrrrrrrrK",
    "KKKKKKKKKKKKKKKK",
]

TILE_CHEST = [
    "................",
    "................",
    "....KKKKKKKK....",
    "...KGgggggggK...",
    "..KGggggggggGK..",
    "..KgggGGgggggK..",
    "..KRRRRRRRRRRK..",
    "..KRrrGGrrrrrK..",
    "..KRrrGGrrrrrK..",
    "..KRrrrrrrrrrK..",
    "..KRRRRRRRRRRK..",
    "..KrrrrrrrrrrK..",
    "..KKKKKKKKKKKK..",
    "...KddddddddK...",
    "....KKKKKKKK....",
    "................",
]


# 道中の出店。床の上に建っているので、下地は床色で塗りつぶす
# （宝箱と違って背景が透けると、通路の途中に浮いて見える）。
TILE_SHOP = [
    "ffffffffffffffff",
    "fKKKKKKKKKKKKKKf",
    "fKRRRRRRRRRRRRKf",
    "fKGGRRGGRRGGRRKf",
    "fKGGRRGGRRGGRRKf",
    "fKRRRRRRRRRRRRKf",
    "fKrrrrrrrrrrrrKf",
    "fKeeeeeeeeeeeeKf",
    "fKeGGeeeeGGeeeKf",
    "fKeeeeeeeeeeeeKf",
    "fKrrrrrrrrrrrrKf",
    "fKRRRRRRRRRRRRKf",
    "fKrrrrrrrrrrrrKf",
    "fKKKKKKKKKKKKKKf",
    "ffffffffffffffff",
    "ffffffffffffffff",
]


def build_tileset() -> None:
    """9 枚を横一列に並べた 144x16 のタイルシート。"""
    tiles = [
        tile_floor(),
        tile_floor(cracked=True),
        tile_wall(),
        tile_wall_top(),
        from_ascii(TILE_STAIRS, STONE),
        from_ascii(TILE_DOOR, STONE),
        from_ascii(TILE_CHEST, STONE),
        Canvas(TILE, TILE),  # 7: 虚空（マップ外）
        from_ascii(TILE_SHOP, STONE),
    ]
    sheet = Canvas(TILE * len(tiles), TILE)
    for i, t in enumerate(tiles):
        sheet.blit(t, i * TILE, 0)
    sheet.to_png(ASSETS / "tiles" / "dungeon.png")
    sheet.scaled(6).to_png(PREVIEW / "dungeon.png")


# --------------------------------------------------------------------------
# 主人公（24x32 / 4 方向 x 3 フレーム）
#
# 16x16 では顔に使える画素が縦 6 行しかなく、どう描いてもファミコンの density に
# なる。24x32 まで上げると目・口・髪の流れ・衣装の装飾が同時に成立する。
# FF6 やクロノ・トリガーのフィールドキャラがこの辺の寸法。
# --------------------------------------------------------------------------

CHAR_W = 24
CHAR_H = 32
LEG_TOP = 28  # この行から下を「脚」として扱う

HERO_DOWN = [
    "........KKKKKKKK",
    "......KKwwwwwwwwKK",
    ".....KwwwwwwwwwwwwK",
    "....KwwWWWwwwwWWWwwK",
    "....KwWWWwwwwwwWWWwK",
    "...KwwwwwwwwwwwwwwwwK",
    "...KwwhhwwwwwwwwhhwwK",
    "..KwwhSSSSSSSSSSSShwwK",
    "..KwwhSSSSSSSSSSSShwwK",
    "..KwwhSKEEKSSKEEKShwwK",
    "..KwwhSSSSSSSSSSSShwwK",
    "..KwwhSSSSSKKSSSSShwwK",
    "...KwwhhsSSSSSSshhwwK",
    "...KwwwhhKSSSSKhhwwwK",
    "..KwwhhKBBBBBBBBKhhwwK",
    ".KwwhhKBbbbbbbbbBKhhwwK",
    ".KwwhhKBbEEEEEEbBKhhwwK",
    ".KwwhhKBGGGGGGGGBKhhwwK",
    ".KwwhhKBbbbbbbbbBKhhwwK",
    ".KwwhhKBbbeeeebbBKhhwwK",
    "..KwhhKBbbbbbbbbBKhhwK",
    "..KShhKBbbbbbbbbBKhhSK",
    "..KSSKKBbbbbbbbbBKKSSK",
    "...KSKKBBBBBBBBBBKKSK",
    "....KBBBBBBBBBBBBBBK",
    "....KBbbbbbbbbbbbbBK",
    "....KBbbeeeeeeeebbBK",
    "....KKBBBBBBBBBBBBKK",
    ".....KBBBK....KBBBK",
    ".....KBbbK....KBbbK",
    ".....KGGGK....KGGGK",
    ".....KKKKK....KKKKK",
]

HERO_UP = [
    "........KKKKKKKK",
    "......KKwwwwwwwwKK",
    ".....KwwwwwwwwwwwwK",
    "....KwwWWWwwwwWWWwwK",
    "....KwWWWwwwwwwWWWwK",
    "...KwwwwwwwwwwwwwwwwK",
    "...KwwhhwwwwwwwwhhwwK",
    "..KwwhhhhhwwwwhhhhhwwK",
    "..KwwhhhhhhwwhhhhhhwwK",
    "..KwwhhhhhhhhhhhhhhwwK",
    "..KwwhhhhhhhhhhhhhhwwK",
    "..KwwhHHhhhhhhhhHHhwwK",
    "...KwwhHHHHHHHHHHhwwK",
    "...KwwwhHHHHHHHHhwwwK",
    "..KwwhhKBBBBBBBBKhhwwK",
    ".KwwhhKBbbbbbbbbBKhhwwK",
    ".KwwhhKBbEEEEEEbBKhhwwK",
    ".KwwhhKBGGGGGGGGBKhhwwK",
    ".KwwhhKBbbbbbbbbBKhhwwK",
    ".KwwhhKBbbeeeebbBKhhwwK",
    "..KwhhKBbbbbbbbbBKhhwK",
    "..KShhKBbbbbbbbbBKhhSK",
    "..KSSKKBbbbbbbbbBKKSSK",
    "...KSKKBBBBBBBBBBKKSK",
    "....KBBBBBBBBBBBBBBK",
    "....KBbbbbbbbbbbbbBK",
    "....KBbbeeeeeeeebbBK",
    "....KKBBBBBBBBBBBBKK",
    ".....KBBBK....KBBBK",
    ".....KBbbK....KBbbK",
    ".....KGGGK....KGGGK",
    ".....KKKKK....KKKKK",
]

HERO_SIDE = [
    ".......KKKKKKK",
    ".....KKwwwwwwwKK",
    "....KwwwwwwwwwwwK",
    "...KwwWWWwwwwwwwwK",
    "...KwWWWwwwwwwwwwK",
    "..KwwwwwwwwwwwwwwK",
    "..KwwhhwwwwwwwwwhK",
    ".KwwhSSSSSSSSShhwK",
    ".KwwhSSSSSSSSShhwK",
    ".KwwhSKEEKSSSShhwK",
    ".KwwhSSSSSSSSShhwK",
    ".KwwhSSSSKKSSShhwK",
    "..KwwhsSSSSShhwwK",
    "..KwwwhKSSSKhwwwK",
    ".KwwhhKBBBBBBKhhwK",
    "KwwhhKBbbbbbbBKhhwK",
    "KwwhhKBEEEEEEBKhhwK",
    "KwwhhKBGGGGGGBKhhwK",
    "KwwhhKBbbbbbbBKhhwK",
    "KwwhhKBbeeeebBKhhwK",
    ".KwhhKBbbbbbbBKhhwK",
    ".KShhKBbbbbbbBKhSK",
    ".KSSKKBbbbbbbBKKSK",
    "..KSKKBBBBBBBBKKSK",
    "...KBBBBBBBBBBBBK",
    "...KBbbbbbbbbbbBK",
    "...KBbbeeeeeebbBK",
    "...KKBBBBBBBBBBKK",
    "....KBBBK..KBBBK",
    "....KBbbK..KBbbK",
    "....KGGGK..KGGGK",
    "....KKKKK..KKKKK",
]


def build_heroes() -> None:
    """職業ごとに 1 枚。歩行 3 フレーム x 4 方向を 72x128 のシートにまとめる。

    脚だけを 1px 持ち上げて歩きを作る。描き足さずに動きが出る、
    SFC 期の 3 フレーム歩行の定石。
    """
    for job in HERO_ACCENTS:
        palette = hero_palette(job)
        down = from_ascii(HERO_DOWN, palette, CHAR_W)
        up = from_ascii(HERO_UP, palette, CHAR_W)
        left = from_ascii(HERO_SIDE, palette, CHAR_W)
        right = mirrored(left)

        sheet = Canvas(CHAR_W * 3, CHAR_H * 4)
        for row, base in enumerate([down, left, right, up]):
            for col, frame in enumerate([base, _step(base, +1), _step(base, -1)]):
                sheet.blit(frame, col * CHAR_W, row * CHAR_H)
        sheet.to_png(ASSETS / "sprites" / f"hero_{job}.png")
        sheet.scaled(4).to_png(PREVIEW / f"hero_{job}.png")


def _step(base: Canvas, side: int) -> Canvas:
    """片脚だけを 1px 持ち上げる。side<0 で左脚、side>0 で右脚。

    下げると枠外に落ちて脚が欠けるので、必ず「持ち上げる」方向に動かす。
    """
    out = Canvas(base.w, base.h)
    mid = base.w // 2
    for y in range(base.h):
        for x in range(base.w):
            c = base.get(x, y)
            if not c[3]:
                continue
            lifted = y >= LEG_TOP and ((x < mid) == (side < 0))
            out.set(x, y - 1 if lifted else y, c)
    return out


# --------------------------------------------------------------------------
# モンスター（32x32 / 左半分を描いて鏡像で綴じる）
# --------------------------------------------------------------------------

GEL_HALF = [
    "................",
    "................",
    "................",
    "................",
    "...........KKKKK",
    ".........KKhhhhh",
    "........KhhhhhhW",
    ".......KhhhhhWWW",
    "......KhhhhhWWWW",
    ".....KhhhhlWWWWl",
    ".....Khhhlllllll",
    "....Khhhllllllll",
    "....Khhlllllllll",
    "...Khhllllllllll",
    "...Khlllllllllll",
    "..Khllllllllllll",
    "..Khllleeellllll",
    "..KhlleEEEelllll",
    "..KhlleEEEelllll",
    "..Khllleeellllll",
    "..Khllllllllllll",
    ".Khlllllllllllll",
    ".Khmllllllllllll",
    ".Kmmmlllllllllll",
    "Kmmmmmllllllllll",
    "Kmmmmmmmmmmmmmmm",
    "Kdmmmmmmmmmmmmmm",
    "Kddddddddddddddd",
    "KKdddddddddddddd",
    ".KKKKKKKKKKKKKKK",
    "................",
    "................",
]

# コウモリ。32x32 では他の敵（48px 級）の隣で子どもに見えたので描き直した。
#
# 右端は鏡像の合わせ目なので、体が中心をまたぐ行では**右端に輪郭を置かない**。
# ここに K を置くと合わせ目で線が二重になり、胴が左右に割れて別の生き物になる。
# 耳だけは合わせ目まで届かせず、あいだの窪みをそのまま形にしている。
BAT_HALF = [
    "........................",
    "........................",
    "..................KK....",
    ".................KFFK...",
    ".................KFFK...",
    "................KFFFFFFF",
    "..............KFFFFFFFFF",
    ".............KFFFFFFFFFF",
    "............KFFEEFFFFFFF",
    "............KFFEEFFFFFFF",
    "............KFFFFFFFFFFF",
    "............KFFFFWWFFFFF",
    "........KKKKKFFFFFFFFFFF",
    ".....KKmmmKKFFFFFFFFFFFF",
    "..KKmmmmmmmKFFFFFFFFFFFF",
    "KKmmmmmmmmmKFFFFFFFFFFFF",
    "KmmmlllllllKFFFFFFFFFFFF",
    "KmmllllllllKFFFFFFFFFFFF",
    "KmlllllllllKFFFFFFFFFFFF",
    "KdlllllllllKKFFFFFFFFFFF",
    "KddlllllllllKFFFFFFFFFFF",
    "KdddllllllllKFFFFFFFFFFF",
    "KKdddlllllllKFFFFFFFFFFF",
    ".KKddddllllllKFFFFFFFFFF",
    "..KKddddlllllKFFFFFFFFFF",
    "....KKdddlllllKFFFFFFFFF",
    "......KKddddllKFFFFFFFFF",
    "........KKdddlKFFFFFFFFF",
    "..........KKddKKFFFFFFFF",
    "............KKKKFFFFFFFF",
    "................KFFFFFFF",
    "................KKFFFFFF",
    "..................KKFFFF",
    "....................KKKK",
]


# 主は 64x64。通常敵（32x32 / ゲル 48x40）の倍近い寸法にして、
# 扉を抜けた瞬間に「これは別物だ」と大きさで分からせる。
# SFC 期のボスが軒並み 64px 級だったのは、この一目の落差のため。
WARDEN_HALF = [
    "................................",
    "................................",
    "...KKK..........................",
    "..KhhK..........................",
    "..KhhK..........................",
    "..KhhK..........................",
    "..KhhK.................KKKKKKKKK",
    "..KhhK..............KKKhhhhhhhhh",
    "..KhhK............KKhhhhhhhhhhhh",
    "..KhhK..........KKhhhhhlllllllll",
    "..KhhK.........KhhhhhhlllllllllG",
    "..KhhK........KhhhhhhlllllllllGG",
    "..KhhKK......KKhhhhhhlllllllGGGG",
    "..KhhhKKKKKKKhhhhhhhllllllGGGGGG",
    "...KhhhhhhhhhhhhhhhhlllllGGGGGGG",
    "....KhhhhhhhhhhhhhhhllllGGGGGGGG",
    "....KhhhhhhhhhhhhhhlllGGGGGGGGGG",
    "....KhhhhhhhhhhhhhllGGGGGGGGGGGG",
    "....KhhhhhhhhhhhhlGGGGGGGGGGGGGG",
    "....Khhhhhhhhhhhhggggggggggggggg",
    "....KhhhhhhhhhhhKddddddddddddddd",
    "....KhhhhhhhhhhKdddddddddddddddd",
    "....KhhhhhhhhhKddddddddddddddddd",
    "....KhhhhhhhhKdddddddddddddddddd",
    "....KhhhhhhhhKddddeeeeeeeedddddd",
    "....KhhhhhhhhKdddeEEEEEEEEeddddd",
    "....KhhhhhhhhKdddeEEEEEEEEeddddd",
    "....KhhhhhhhhKddddeeeeeeeedddddd",
    "....KhhhhhhhhKdddddddddddddddddd",
    "....KhhhhhhhhhKddddddddddddddddd",
    "....KhhhhhhhhhhKdddddddddddddddd",
    "....KhhhhhhhhhhhKddddddddddddddd",
    "....KhhhhhhhhhhhhKdddddddddddddd",
    "...KhhhhhhhhhhhhhhKggggggggggggg",
    "..KhhhhhhhhhhhhhhhhKGGGGGGGGGGGG",
    ".KhhhhhhhhhhhhhhhhhhKGGGGGGGGGGG",
    "KhhhhhhhhhhhhhhhhhhhhKgggggggggg",
    "KWWWWWWWWWWWWWWWWWWWWWKmmmmmmmmm",
    "KWllllllllllllllllllllWKmmmmmmmm",
    "KWlllllllllllllllllllWKmmmmmmmmm",
    ".KWlllllllllllllllllWKmmmmmmmmmm",
    ".KWllllllllllllllllWKmmmmmmmmmmm",
    "..KWllllllllllllllWKmmmmmmmmmmmm",
    "..KWlllllllllllllWKmmmmmmmmmmmmm",
    "...KWlllllllllllWKmmmmmmmmmmmmmm",
    "...KWllllllllllWKmmmmmmmmmmmmmmm",
    "....KWllllllllWKmmmmmmmmmmmmmmmm",
    "....KWlllllllWKmmmmmmmmmmmmmmmmm",
    ".....KWlllllWKmmmmmmmmmmmmmmmmmm",
    ".....KWllllWKmmmmmmmmmmmmmmmmmmm",
    "......KWllWKmmmmmmmmmmmmmmmmmmmm",
    "......KWWWKmmmmmmmmmmmmmmmmmmmmm",
    ".......KKKGGGGGGGGGGGGGGGGGGGGGG",
    "........Kggggggggggggggggggggggg",
    "........Kmmmmmmmmmmmmmmmmmmmmmmm",
    "........Kmmmmmmmmmmmmmmmmmmmmmmm",
    ".......Kdmmmmmmmmmmmmmmmmmmmmmmm",
    ".......Kddmmmmmmmmmmmmmmmmmmmmmm",
    "......Kdddmmmmmmmmmmmmmmmmmmmmmm",
    "......Kddddddddddddddddddddddddd",
    ".....Kdddddddddddddddddddddddddd",
    ".....KddddddGGGGGGGGGGGGGGGGGGGG",
    "....KKKKKKKKgggggggggggggggggggg",
    "....KKKKKKKKKKKKKKKKKKKKKKKKKKKK",
]


# 中層以降の敵。ゲル（48x40）に合わせて 48x44 に揃える。
# bat の 32x32 は画面から浮くので、以後の敵はこの寸法を基準にする。
# されこうべ。胴や手足を 48px で描くと必ず潰れて家具に見えたので、
# 頭蓋 1 個に絞った。眼窩・鼻腔・歯という 3 つの特徴だけで読ませる。
SKULL_HALF = [
    "........................",
    "..............KKKKKKKKKK",
    "............KKllllllllll",
    "...........KlllllllllllW",
    "..........KllllllllllllW",
    ".........KlllllllllllllW",
    ".........KlllllllllllllW",
    "........KllllllllllllllW",
    "........KllllllllllllllW",
    "........KllKKKKKlllllllW",
    "........KlKEEEEEKllllllW",
    "........KlKEEEEEKllllllW",
    "........KlKKEEEKKllllllW",
    "........Klllllllllllllll",
    "........Klllllllllllllll",
    ".........KlllllllKKlllll",
    ".........KllllllKKKlllll",
    ".........KlllllllKKlllll",
    ".........Kllllllllllllll",
    "..........Kmmmmmmmmmmmmm",
    "..........KKKKKKKKKKKKKK",
    "...........KlKlKlKlKllll",
    "...........Kllllllllllll",
    "...........KlKlKlKlKllll",
    "............KKmmmmmmmmmm",
    "..............KKKKKKKKKK",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
]

# 亡霊。フードの頂点から裾の先まで一本の紡錘にする。
# 中身は空で、開口部に眼だけが灯っている、という一点で読ませる。
SHADE_HALF = [
    "........................",
    "......................KK",
    "....................KKdd",
    "..................KKddmm",
    "................KKddmmmm",
    "..............KKddmmmmmm",
    "............KKddmmmmmmmm",
    "..........KKddmmmmmmmmmm",
    ".........Kddmmmmmmmmmmmm",
    "........Kddmmmmmmmmmmmmm",
    "........KddmKKKKKKKKKKKK",
    "........KddmKKEEEEEEEEEE",
    "........KddmKKeEEEEEEEEE",
    "........KddmKKEEEEEEEEEE",
    "........KddmKKKKKKKKKKKK",
    "........Kddmmmmmmmmmmmmm",
    ".......Kddmmmmmmmmmmmmmm",
    "......Kddmmmmmmmmmmmmmmm",
    ".....KddmmmmmmmmmmmmmmmW",
    ".....KdmWWWWWWWWWWWWWWWW",
    "....KdmmWWWWWWWWWWWWWWWW",
    "....Kdmmmmmmmmmmmmmmmmmm",
    "....Kdmmmmmmmmmmmmmmmmmm",
    ".....Kdmmmmmmmmmmmmmmmmm",
    ".....Kddmmmmmmmmmmmmmmmm",
    "......Kddmmmmmmmmmmmmmmm",
    "......Kdddmmmmmmmmmmmmmm",
    ".......Kdddmmmmmmmmmmmmm",
    ".......Kddddmmmmmmmmmmmm",
    "........Kddddmmmmmmmmmmm",
    "........Kdddddmmmmmmmmmm",
    ".........Kdddddmmmmmmmmm",
    ".........Kdddddddmmmmmmm",
    "..........Kdddddddmmmmmm",
    "..........Kdddddddddmmmm",
    "...........Kddddddddddmm",
    "...........Kdddddddddddd",
    "............Kddddddddddd",
    ".............Kdddddddddd",
    "..............Kddddddddd",
    "...............Kdddddddd",
    "................KKdddddd",
    "..................KKdddd",
    "....................KKKK",
]

# 石の下僕。腕と胴のあいだを抜いて、人型だと一目で分からせる。
# 顔は作らず、刻まれた印だけを光らせる（物ではなく仕掛け、という佇まい）。
GOLEM_HALF = [
    "........................",
    "........................",
    "..............KKKKKKKKKK",
    ".............Kllllllllll",
    ".............Kllllllllll",
    ".............KlKKKEEEEEE",
    ".............KlKKKEEEEEE",
    ".............Kllllllllll",
    ".............Kmmmmmmmmmm",
    ".............KKKKKKKKKKK",
    "................KKmmmmmm",
    "................KKmmmmmm",
    "....KKKKKKKKKKKKKKmmmmmm",
    "..KKhhhhhhhhhhhhhhllllll",
    ".Khhhhhhhhhhhhhh..llllll",
    "KhhhhhhhhhhhhhhK..llllll",
    "KhllllllllllllK...llllll",
    "KhllllllllllllK...llllll",
    "KhllllllllllllK...llllll",
    "KhllllllllllllK...llllll",
    "KmmmmmmmmmmmmmK...llllll",
    "KKKKKKKKKKKKKKK...llllll",
    "..................llllll",
    "..........KKKKKKKKllllll",
    ".......KKKllllllllllllll",
    ".....KKlllllllllllllllll",
    "....Klllllllllllllllllll",
    "....KlllllllllllllEEllll",
    "....KlllllllllllllEEllll",
    "....Klllllllllllllllllll",
    "....Kmmmmmmmmmmmmmmmmmmm",
    "....KKKKKKKKKKKKKKKKKKKK",
    "......KKKKKKmmmmmmmmmmmm",
    "......Klllll..Klllllllll",
    "......Klllll..Klllllllll",
    "......Klllll..Klllllllll",
    "......Klllll..Klllllllll",
    "......Kmmmmm..Kmmmmmmmmm",
    "......KKKKKK..KKKKKKKKKK",
    ".....Kdddddd..Kddddddddd",
    ".....KKKKKKK..KKKKKKKKKK",
    "........................",
    "........................",
    "........................",
]


def build_monster(name: str, half_rows: list[str], palette: Palette, width: int = 16) -> None:
    """左半分から敵グラフィックを綴じる。"""
    half = from_ascii(half_rows, palette, width)
    _emit_monster(name, half)


def _emit_monster(name: str, half: Canvas) -> None:
    full = Canvas(half.w * 2, half.h)
    full.blit(half, 0, 0)
    full.blit(mirrored(half), half.w, 0)
    full.to_png(ASSETS / "sprites" / f"{name}.png")
    full.scaled(4).to_png(PREVIEW / f"{name}.png")


EYE = [
    ".KKKKK.",
    "KeeeeeK",
    "KeeEEeK",
    "KeEEEeK",
    "KeeEEeK",
    "KeeeeeK",
    ".KKKKK.",
]


def build_blob(name: str, palette: Palette, width: int = 24, height: int = 40) -> None:
    """粘体系の敵を手続きで組む。左半身だけ作り、鏡像で綴じる。

    陰影は行ごとの帯ではなく「光源からの距離」で決める。行で切ると横縞に
    なって球に見えないが、距離で切ると素直に丸くなる。
    光源は中央上に置く。鏡像で綴じる以上、左右非対称な光は使えない。
    """
    half = Canvas(width, height)
    top, base = 4, height - 2
    cy = (top + base) * 0.5
    rx = float(width)
    ry = (base - top) * 0.5

    # 光源からの距離のしきい値。小さいほど明るい。
    bands = [(0.42, "W"), (0.66, "h"), (0.98, "l"), (1.26, "m"), (9.9, "d")]
    light = -0.62  # 中心より上

    for y in range(top, base + 1):
        t = (y - top) / float(base - top)
        span = int(round(width * math.sqrt(max(0.0, 1.0 - (1.0 - t) ** 2))))
        if span <= 0:
            continue
        left = width - span
        for x in range(left, width):
            nx = (x - width) / rx      # 中心は x = width（鏡像の合わせ目）
            ny = (y - cy) / ry
            shade = math.sqrt(nx * nx + (ny - light) ** 2)
            half.set(x, y, palette.get(next(ch for limit, ch in bands if shade < limit)))
        half.set(left, y, palette.get("K"))

    for x in range(width):
        if half.get(x, base)[3]:
            half.set(x, base, palette.get("K"))

    half.blit(from_ascii(EYE, palette), int(width * 0.26), int(height * 0.40))
    _emit_monster(name, half)


# --------------------------------------------------------------------------
# UI ウィンドウ（9-slice / 24x24、角 8px）
# --------------------------------------------------------------------------


WINDOW_MARGIN = 8


def build_window() -> None:
    """FF 系の青い窓 + 白い内枠。9-slice で任意サイズへ伸ばす前提で作る。

    伸縮に耐えるための制約が 2 つある。守らないと拡大時に模様が溶ける。

      * 横方向は一切変化させない（左右の辺と中央は横に引き伸ばされるため）
      * 中央 8..15 行は単色にする（縦にも引き伸ばされるため）

    グラデーションは上下 8px の「角スライス」にだけ置く。ここは拡大されない。
    SFC のウィンドウが上辺だけ明るいのは、同じ制約から来た形でもある。
    """
    size = 24
    c = Canvas(size, size)

    # 行ごとに単色を置く。上が明るく、下へ向かって沈む。
    rows = (
        [UI.get("l")] * 4        # 0-3   上辺（拡大されない）
        + [UI.get("n")] * 2      # 4-5
        + [UI.get("m")] * 12     # 6-17  中央（縦に伸びる。必ず単色）
        + [UI.get("d")] * 4      # 18-21 下辺
        + [UI.get("d")] * 2      # 22-23
    )
    for y in range(size):
        for x in range(size):
            c.set(x, y, rows[y])

    # 外枠（黒）と内枠（白 / 下辺は影色）
    for i in range(size):
        c.set(i, 0, UI.get("K"))
        c.set(0, i, UI.get("K"))
        c.set(i, size - 1, UI.get("K"))
        c.set(size - 1, i, UI.get("K"))
        c.set(i, 1, UI.get("w"))
        c.set(1, i, UI.get("w"))
        c.set(i, size - 2, UI.get("s"))
        c.set(size - 2, i, UI.get("s"))
    for x, y in [(1, 1), (size - 2, 1), (1, size - 2), (size - 2, size - 2)]:
        c.set(x, y, UI.get("w"))

    c.to_png(ASSETS / "ui" / "window.png")
    c.scaled(6).to_png(PREVIEW / "window.png")


def build_cursor() -> Canvas:
    """コマンド選択の ▶ カーソル（8x8）。"""
    rows = [
        "K.......",
        "KK......",
        "KwK.....",
        "KwwK....",
        "KwwwK...",
        "KwwK....",
        "KwK.....",
        "KK......",
    ]
    c = from_ascii(rows, UI)
    c.to_png(ASSETS / "ui" / "cursor.png")
    return c


# --------------------------------------------------------------------------


def main() -> None:
    build_tileset()
    build_heroes()
    build_blob("gel", GEL, width=24, height=40)
    build_monster("bat", BAT_HALF, BAT, width=24)
    build_monster("skull", SKULL_HALF, BONE, width=24)
    build_monster("shade", SHADE_HALF, SHADE, width=24)
    build_monster("golem", GOLEM_HALF, GOLEM, width=24)
    build_monster("warden", WARDEN_HALF, WARDEN, width=32)
    build_window()
    build_cursor()
    print("生成完了:")
    for p in sorted(ASSETS.rglob("*.png")):
        print(f"  {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
