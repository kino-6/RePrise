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

from sfc_art import Canvas, Palette, dither, from_ascii, load_png, mirrored, snes  # noqa: E402

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

# 宝箱。金の蓋と錠前で「箱」だと分かる形にする。
# 出店と見分けが付かないと、道中で何を踏んだのか分からなくなる。
TILE_CHEST = [
    "................",
    "................",
    "................",
    "...KKKKKKKKKK...",
    "...KGGGGGGGGK...",
    "...KgggggggGK...",
    "...KKKKKKKKKK...",
    "...KRRRGGRRRK...",
    "...KRrrGGrrRK...",
    "...KRrrrrrrRK...",
    "...KRRRRRRRRK...",
    "...KKKKKKKKKK...",
    "....dddddddd....",
    "................",
    "................",
    "................",
]


# 道中の出店。赤白の縞の幌が最大の目印で、これがあると宝箱と一目で区別が付く。
# 床の上に建っているので下地は床色で塗りつぶす（背景が透けると通路に浮いて見える）。
SHOP = Palette(
    "shop",
    {
        "K": "#0E1220",  # 輪郭
        "f": "#3C3226",  # 床（下地）
        "A": "#C03A32",  # 幌 赤
        "a": "#8C2018",  # 幌 赤 影
        "W": "#E8DCC0",  # 幌 生成り
        "R": "#8A5A34",  # 木
        "r": "#5A3A20",  # 木 影
        "G": "#F0D28C",  # 並んでいる品
    },
)

TILE_SHOP = [
    "ffffffffffffffff",
    "fKKKKKKKKKKKKKKf",
    "fKAAWWAAWWAAWWKf",
    "fKAAWWAAWWAAWWKf",
    "fKaaWWaaWWaaWWKf",
    "fKKKKKKKKKKKKKKf",
    "ffKffffffffffKff",
    "ffKfGGfGGfGGfKff",
    "ffKfGGfGGfGGfKff",
    "ffKRRRRRRRRRRKff",
    "ffKrrrrrrrrrrKff",
    "ffKffffffffffKff",
    "ffKffffffffffKff",
    "ffKKffffffffKKff",
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
        from_ascii(TILE_SHOP, SHOP),
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

# 顔の作り方について。
#
# 最初の版は「肌の四角形の真ん中に細い目」で、生気が無く不気味に見えた。
# 24x32 で人の顔に見せる要点は次の 4 つ。
#
#   1. 目を縦に大きく取る。3px 幅 x 3 段（睫毛 / 虹彩＋光点 / 虹彩の影）。
#      **細い目が不気味さの正体**なので、ここを削ってはいけない
#   2. 目のまわりに肌を残す。目が髪に接すると穴が空いているように見える
#   3. 前髪と目のあいだに額を 1 段入れる。これが無いと能面になる
#   4. 口を描かない。この寸法では口は点にしかならず、点は表情ではなく汚れに見える
#
# 列の役割を固定してある。**x3..x6 と x17..x20 が髪、x7..x16 が顔と胴**。
# ここが揃っていないと HERO_LOOKS の差分（髪を短くする・肩当てを足す）が書けない。

HERO_DOWN = [
    "........................",
    "........KKKKKKKK........",
    "......KwwwwwwwwwwK......",
    "....KwwWWWwwwwwwwwwK....",
    "...KwwWWWwwwwwwwwwwwK...",
    "...KwwWWwwwwwwwwwwwwK...",
    "...KwwwWwwwwwwwwwwwwK...",
    "...KwwwwwwwwwwwwwwwwK...",
    "...KwhhhhhhhhhhhhhhwK...",
    "...KwhhSSSSSSSSSShhwK...",
    "...KwhhSKKSSSSKKShhwK...",
    "...KwhhSWESSSSEWShhwK...",
    "...KwhhSeESSSSEeShhwK...",
    "...KwhhSSSSSSSSSShhwK...",
    "...KwhhhSSSSSSSShhhwK...",
    "...KwhhhhSSSSSShhhhwK...",
    "...KwhhKBBbEEbBBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbEEEEbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBGGGGGGBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    ".....KBBbbbbbbbbBBK.....",
    "....KBBbbbbbbbbbbBBK....",
    "...KBBbbbbbbbbbbbbBBK...",
    "..KBbbeeeeeeeeeeeebbBK..",
    "..KKBBBBBBBBBBBBBBBBKK..",
    ".......KbbK..KbbK.......",
    ".......KbbK..KbbK.......",
    ".......KBBK..KBBK.......",
    ".......KKKK..KKKK.......",
]

# 背面。顔が無いぶん、髪の陰影だけで丸みを出す。
HERO_UP = [
    "........................",
    "........KKKKKKKK........",
    "......KwwwwwwwwwwK......",
    "....KwwWWWwwwwwwwwwK....",
    "...KwwWWWwwwwwwwwwwwK...",
    "...KwwWWwwwwwwwwwwwwK...",
    "...KwwwWwwwwwwwwwwwwK...",
    "...KwwwwwwwwwwwwwwwwK...",
    "...KwhhhhhhhhhhhhhhwK...",
    "...KwhhhhhhhhhhhhhhwK...",
    "...KwhhhhhhhhhhhhhhwK...",
    "...KwhhhhhHHHHhhhhhwK...",
    "...KwhhhhHHHHHHhhhhwK...",
    "...KwhhhhHHHHHHhhhhwK...",
    "...KwhhhhhHHHHhhhhhwK...",
    "...KwhhhhhhHHhhhhhhwK...",
    "...KwhhKBBbbbbbbBKhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbEEEEbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBGGGGGGBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    ".....KBBbbbbbbbbBBK.....",
    "....KBBbbbbbbbbbbBBK....",
    "...KBBbbbbbbbbbbbbBBK...",
    "..KBbbeeeeeeeeeeeebbBK..",
    "..KKBBBBBBBBBBBBBBBBKK..",
    ".......KbbK..KbbK.......",
    ".......KbbK..KbbK.......",
    ".......KBBK..KBBK.......",
    ".......KKKK..KKKK.......",
]

# 横向き（左を向く）。頭の輪郭は正面と共通にしてある（被り物の差分を
# 3 方向で使い回すため）。目は 3px 幅 1 つだけ。横顔で両目を描くと必ず破綻する。
HERO_SIDE = [
    "........................",
    "........KKKKKKKK........",
    "......KwwwwwwwwwwK......",
    "....KwwWWWwwwwwwwwwK....",
    "...KwwWWWwwwwwwwwwwwK...",
    "...KwwWWwwwwwwwwwwwwK...",
    "...KwwwWwwwwwwwwwwwwK...",
    "...KwwwwwwwwwwwwwwwwK...",
    "...KwhhhhhhhhhhhhhhwK...",
    "...KSSSSSSShhhhhhhhwK...",
    "...KSKKSSSShhhhhhhhwK...",
    "...KSWESSSShhhhhhhhwK...",
    "...KSeESSSShhhhhhhhwK...",
    "...KSSSSSSShhhhhhHHwK...",
    "...KsSSSSSShhhhhHHHwK...",
    "...KhsSSSSShhhhHHHHwK...",
    "...KwhhKBBbEEbBBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbEEEEbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBGGGGGGBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    "...KwhhKBbbbbbbBKhhwK...",
    ".....KBBbbbbbbbbBBK.....",
    "....KBBbbbbbbbbbbBBK....",
    "...KBBbbbbbbbbbbbbBBK...",
    "..KBbbeeeeeeeeeeeebbBK..",
    "..KKBBBBBBBBBBBBBBBBKK..",
    ".......KbbK..KbbK.......",
    ".......KbbK..KbbK.......",
    ".......KBBK..KBBK.......",
    ".......KKKK..KKKK.......",
]

# 裾。体形の差はここが一番読める。
SKIRT_WIDE = [
    (23, 5, "KBBbbbbbbbbBBK"),
    (24, 4, "KBBbbbbbbbbbbBBK"),
    (25, 3, "KBBbbbbbbbbbbbbBBK"),
    (26, 2, "KBbbeeeeeeeeeeeebbBK"),
    (27, 2, "KKBBBBBBBBBBBBBBBBKK"),
]

SKIRT_NARROW = [
    (23, 6, "KBBbbbbbbBBK"),
    (24, 5, "KBBbbbbbbbbBBK"),
    (25, 4, "KBBbbbbbbbbbbBBK"),
    (26, 4, "KBbbeeeeeeeebbBK"),
    (27, 4, "KKBBBBBBBBBBBBKK"),
]

# 職業ごとの姿。
#
# **差し色を変えただけでは全員が同じ人に見える。** 面積の大きい色と輪郭が
# 同じだからで、胸の 1px の線をいくら変えても意味がない。
# DQ が少ないドットで人を見分けられるのは、次の 3 つが人ごとに違うから。
#
#   1. 髪のシルエット（ボブ / 長髪 / ツインテール / 束ね髪）
#   2. 面積の大きい色（マントやローブが体の何割を占めるか）
#   3. 頭の形（帽子・フード・ベール）
#
# ここではその 3 つを差分として重ねる。
#
#   head  : 頭まわり（0..8 行）。3 方向で共通に使える
#   body  : 肩から胴（16..22 行）と、髪の外へ張り出す部分
#   face  : 正面と横で位置が違うぶん（面をかぶるなど）
#   hair  : 横の髪をどの行まで垂らすか。小さいほど短髪
#   skirt : 裾の広がり
#
# 差分の書式は (行, 開始列, 文字列)。空白 1 文字は「元のまま」を意味する。
HERO_LOOKS = {
    # せんし: 肩で切りそろえた髪 + 金の額当て + 蒼のマント。
    # 体の左右が丸ごと蒼になるので、遠目にも「蒼い人」で通る。
    "soldier": {
        "head": [(7, 3, "KGGGGGGGEEGGGGGGGK")],
        "body": [
            (16, 3, "KEEE"), (16, 17, "EEEK"),
            (17, 3, "KEEE"), (17, 17, "EEEK"),
            (18, 3, "KEee"), (18, 17, "eeEK"),
            (19, 3, "KEee"), (19, 17, "eeEK"),
            (20, 3, "KEee"), (20, 17, "eeEK"),
            (21, 3, "KEee"), (21, 17, "eeEK"),
            (22, 3, "KKee"), (22, 17, "eeKK"),
            (16, 7, "KGGGGGGGGK"),
            (17, 7, "KgGGGGGGgK"),
        ],
        "hair": 15,
        "skirt": SKIRT_NARROW,
    },
    # そうりょ: 頭から肩まで白いベール。頭部が白い塊になるのが目印。
    # 胸から裾へ翠の帯を垂らして、正面の中央に色を置く。
    "priest": {
        "head": [
            (3, 4, "WWWWWWWWWWWWWWWW"),
            (4, 3, "KWWWWWWWWWWWWWWWWK"),
            (5, 3, "KWWWWWWWWWWWWWWWWK"),
            (6, 3, "KWWWWWWWWWWWWWWWWK"),
            (7, 3, "KWWwwwwwwwwwwwwWWK"),
            (8, 3, "KWWW"), (8, 17, "WWWK"),
        ],
        "body": [
            (9, 3, "KWWW"), (9, 17, "WWWK"),
            (10, 3, "KWWW"), (10, 17, "WWWK"),
            (11, 3, "KWWW"), (11, 17, "WWWK"),
            (12, 3, "KWWW"), (12, 17, "WWWK"),
            (13, 3, "KWWW"), (13, 17, "WWWK"),
            (14, 3, "KWWW"), (14, 17, "WWWK"),
            (15, 3, "KWWW"), (15, 17, "WWWK"),
            (16, 3, "KWWW"), (16, 17, "WWWK"),
            (17, 3, "KWWW"), (17, 17, "WWWK"),
            (18, 3, "KWW"), (18, 18, "WWK"),
            (17, 10, "EEEE"),
            (18, 10, "EeeE"),
            (19, 10, "EEEE"),
            (21, 10, "EeeE"),
            (22, 10, "EEEE"),
        ],
        "hair": 22,
        "skirt": SKIRT_WIDE,
    },
    # まほうつかい: つば広の帽子で頭の形がいちばん違う。
    # 胴は桃のローブで丸ごと塗る（4 人でここだけ体の中央が明るい）。
    "mage": {
        "head": [
            (1, 8, "KbbbbbbK"),
            (2, 6, "KbbbbbbbbbbK"),
            (3, 4, "KbbbbbbbbbbbbbbK"),
            (4, 3, "KbEEEEEEEEEEEEEEbK"),
            (5, 0, "KKbbbbbbbbbbbbbbbbbbbbKK"),
            (6, 0, "KBBBBBBBBBBBBBBBBBBBBBBK"),
            (7, 4, "hhhhhhhhhhhhhhhh"),
        ],
        "body": [
            (17, 7, "KEEEEEEEEK"),
            (18, 7, "KEeeeeeeEK"),
            (19, 7, "KEEEEEEEEK"),
            (19, 3, "KEEE"), (19, 17, "EEEK"),
            (20, 3, "KEee"), (20, 17, "eeEK"),
            (21, 7, "KEEEEEEEEK"),
            (22, 7, "KEeeeeeeEK"),
        ],
        "hair": 22,
        "skirt": SKIRT_WIDE,
    },
    # とうぞく: ツインテールが唯一無二のシルエット。紅のフードで頭が赤くなる。
    # 体は細く、裾も短い。
    "thief": {
        "head": [
            (2, 6, "KEEEEEEEEEEK"),
            (3, 4, "KEEEEEEEEEEEEEEK"),
            (4, 3, "KEEEEEEEEEEEEEEEEK"),
            (5, 3, "KEeeeeeeeeeeeeeeEK"),
            (6, 3, "KEEEEEEEEEEEEEEEEK"),
            (7, 3, "KEEEEEEEEEEEEEEEEK"),
            (8, 3, "KE"), (8, 19, "EK"),
        ],
        "body": [
            # 左右へ落ちるツインテール。頭の外へ張り出すので、
            # 遠目でもこの人だけシルエットが違う。
            # 頭と地続きにする。あいだに輪郭線を残すと、
            # 髪ではなく耳当てが付いているように見えた。
            (8, 1, "KK"), (8, 21, "KK"),
            (9, 0, "KwWw"), (9, 20, "wWwK"),
            (10, 0, "Kwww"), (10, 20, "wwwK"),
            (11, 0, "Kwww"), (11, 20, "wwwK"),
            (12, 0, "Khww"), (12, 20, "wwhK"),
            (13, 0, "Khhw"), (13, 20, "whhK"),
            (14, 0, "Khhh"), (14, 20, "hhhK"),
            (15, 0, "Khhh"), (15, 20, "hhhK"),
            (16, 0, "KhhK"), (16, 20, "KhhK"),
            (17, 0, "KHhK"), (17, 20, "KhHK"),
            (18, 0, "KHHK"), (18, 20, "KHHK"),
            (19, 1, "KK"), (19, 21, "KK"),
            (16, 3, "KEE"), (16, 18, "EEK"),
            (17, 3, "KEe"), (17, 18, "eEK"),
        ],
        "hair": 16,
        "skirt": SKIRT_NARROW,
    },
    # せいきし: せんしの格上げ。翼の付いた額当てと白銀のマント。
    "paladin": {
        "head": [
            (5, 1, "GG"), (5, 21, "GG"),
            (6, 2, "Gg"), (6, 20, "gG"),
            (7, 3, "KGGGGGGGEEGGGGGGGK"),
        ],
        "body": [
            (16, 3, "KGWW"), (16, 17, "WWGK"),
            (17, 3, "KGWW"), (17, 17, "WWGK"),
            (18, 3, "KGWh"), (18, 17, "hWGK"),
            (19, 3, "KGWh"), (19, 17, "hWGK"),
            (20, 3, "KGWh"), (20, 17, "hWGK"),
            (21, 3, "KGWh"), (21, 17, "hWGK"),
            (22, 3, "KKgh"), (22, 17, "hgKK"),
            (16, 6, "GGGGGGGGGGGG"),
            (17, 7, "KgGGGGGGgK"),
        ],
        "hair": 20,
        "skirt": SKIRT_WIDE,
    },
    # にんじゃ: 口元の面と、右へ流した束ね髪。細身。
    "ninja": {
        "head": [(8, 3, "KeeeeeeeeeeeeeeeeK")],
        "body": [
            # 右へ流した束ね髪。頭と地続きにして、耳当てに見えないようにする。
            (5, 21, "KK"),
            (6, 20, "wWwK"),
            (7, 20, "wwwK"),
            (8, 20, "wwwK"),
            (9, 20, "whwK"),
            (10, 20, "whhK"),
            (11, 21, "hhK"),
            (12, 21, "hhK"),
            (13, 21, "HhK"),
            (14, 21, "HhK"),
            (15, 21, "HHK"),
            (16, 21, "KKK"),
            (19, 7, "KEEEEEEEEK"),
            (20, 7, "KeeeeeeeeK"),
        ],
        "face_down": [
            (13, 7, "BBBBBBBBBB"),
            (14, 8, "BBBBBBBB"),
            (15, 9, "BBBBBB"),
        ],
        "face_side": [
            (13, 4, "BBBBBBB"),
            (14, 4, "BBBBBBB"),
            (15, 5, "BBBBB"),
        ],
        "hair": 17,
        "skirt": SKIRT_NARROW,
    },
}


def _overlay(rows: list[str], patches) -> list[str]:
    """差分を重ねる。空白 1 文字は「元のまま」。"""
    out = list(rows)
    for y, x, chars in patches:
        row = out[y]
        if x + len(chars) > len(row):
            raise ValueError(f"差分が右にはみ出している（行 {y}, 列 {x}, {len(chars)} 文字）")
        merged = "".join(row[x + i] if c == " " else c for i, c in enumerate(chars))
        out[y] = row[:x] + merged + row[x + len(chars) :]
    return out


## 髪の列。ここを固定しているから「髪を短くする」が差分で書ける。
HAIR_COLUMNS = list(range(3, 7)) + list(range(17, 21))
HAIR_ROWS = range(8, 23)


def _cut_hair(rows: list[str], last_row: int) -> list[str]:
    """横の髪を last_row より下で消す。職業ごとの髪の長さを作る。"""
    out = []
    for y, row in enumerate(rows):
        if y not in HAIR_ROWS or y <= last_row:
            out.append(row)
            continue
        chars = list(row)
        for x in HAIR_COLUMNS:
            chars[x] = "."
        out.append("".join(chars))
    return out


def _hero_frames(job: str) -> tuple[list[str], list[str], list[str]]:
    look = HERO_LOOKS[job]
    head = look.get("head", [])
    body = look.get("body", [])
    skirt = look.get("skirt", SKIRT_WIDE)
    common = head + body + skirt

    # 髪を切ってから差分を重ねる。順番が逆だと、髪の列に置いたマントや
    # ツインテールまで一緒に消える。
    down = _overlay(_cut_hair(HERO_DOWN, look["hair"]), common + look.get("face_down", []))
    up = _overlay(_cut_hair(HERO_UP, look["hair"]), common)
    side = _overlay(_cut_hair(HERO_SIDE, look["hair"]), common + look.get("face_side", []))
    return down, up, side


# 生成器の外で描いた歩行シートの置き場。ここに candidate_hero_<職業>.png が
# あればそれを採用し、無ければ下の ASCII マップから起こす。
#
# ASCII マップは「16 色で人の形を作る」ための土台としては十分だが、
# 後期 SFC のドット絵にある密度（布の陰影・金具のハイライト・髪の束）までは
# 手で書ききれない。外で描いたものを持ち込めるようにしておく。
HERO_SOURCE_DIR = ROOT / "docs" / "chara_image"

## 取り込む絵に課す条件。ここを通らないものは採用しない。
## 「SFC らしさは技巧ではなく制約の徹底から出る」という前提を、
## 外から来た絵にも同じように当てはめる。
HERO_SHEET_SIZE = (CHAR_W * 3, CHAR_H * 4)
HERO_MAX_COLORS = 15


def _verify_hero_sheet(job: str, sheet: Canvas) -> None:
    """取り込んだシートが SFC の制約を守っているかを検算する。

    黙って通すと、色数もアルファもばらばらな絵が assets/ に混ざり、
    「なぜか 1 人だけ浮いている」の原因が追えなくなる。
    """
    if (sheet.w, sheet.h) != HERO_SHEET_SIZE:
        raise ValueError(
            "%s: シートは %dx%d でなければならない（%dx%d だった）"
            % (job, HERO_SHEET_SIZE[0], HERO_SHEET_SIZE[1], sheet.w, sheet.h)
        )

    alphas = {p[3] for p in sheet.px}
    if not alphas <= {0, 255}:
        raise ValueError("%s: アルファは 0 か 255 だけにする（%s があった）" % (job, sorted(alphas)))

    colors = {p[:3] for p in sheet.px if p[3] == 255}
    if len(colors) > HERO_MAX_COLORS:
        raise ValueError(
            "%s: 透明を除いて %d 色まで（%d 色あった）" % (job, HERO_MAX_COLORS, len(colors))
        )

    off = [c for c in colors if snes("#%02X%02X%02X" % c) != c]
    if off:
        raise ValueError(
            "%s: BGR555 に乗っていない色が %d 個ある（例 #%02X%02X%02X）"
            % (job, len(off), off[0][0], off[0][1], off[0][2])
        )


def _load_hero_sheet(job: str) -> Canvas | None:
    """外で描いた歩行シートを読む。無ければ None。"""
    path = HERO_SOURCE_DIR / f"candidate_hero_{job}.png"
    if not path.exists():
        return None
    sheet = load_png(path)
    _verify_hero_sheet(job, sheet)
    return sheet


def build_heroes() -> None:
    """職業ごとに 1 枚。歩行 3 フレーム x 4 方向を 72x128 のシートにまとめる。

    脚だけを 1px 持ち上げて歩きを作る。描き足さずに動きが出る、
    SFC 期の 3 フレーム歩行の定石。
    """
    # 幅が 1 文字ずれると from_ascii が右を透明で埋めて黙って左右にずれる。
    # 対称形が崩れる原因がこれだと気づきにくいので、ここで弾く。
    for name, rows in (("DOWN", HERO_DOWN), ("UP", HERO_UP), ("SIDE", HERO_SIDE)):
        if len(rows) != CHAR_H:
            raise ValueError(f"HERO_{name}: {CHAR_H} 行必要（{len(rows)} 行ある）")
        for i, row in enumerate(rows):
            if len(row) != CHAR_W:
                raise ValueError(f"HERO_{name} の行 {i} が {len(row)} 文字（{CHAR_W} 文字にする）")

    for job in HERO_ACCENTS:
        # 外で描いたシートがあればそれを使う。ASCII マップは土台として残す
        # （素材が無い環境でも生成が通り、差分もレビューできる状態を保つため）。
        imported = _load_hero_sheet(job)
        if imported is not None:
            imported.to_png(ASSETS / "sprites" / f"hero_{job}.png")
            imported.scaled(4).to_png(PREVIEW / f"hero_{job}.png")
            print(f"  取り込み: hero_{job}.png（{HERO_SOURCE_DIR.name}/candidate_hero_{job}.png）")
            continue

        palette = hero_palette(job)
        down_rows, up_rows, side_rows = _hero_frames(job)
        down = from_ascii(down_rows, palette, CHAR_W)
        up = from_ascii(up_rows, palette, CHAR_W)
        left = from_ascii(side_rows, palette, CHAR_W)
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
