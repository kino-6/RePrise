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

from sfc_art import (  # noqa: E402
    TRANSPARENT,
    Canvas,
    Palette,
    dither,
    from_ascii,
    load_png,
    mirrored,
    snes,
)

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
    "ranger": ("#98E070", "#40801C"),   # 若草（紅 x 蒼）
    "spellblade": ("#78B0F8", "#2048A8"),  # 群青（蒼 x 桃）
    "summoner": ("#F8B058", "#B05818"),    # 橙（桃 x 翠）
    "sage": ("#F8F0C0", "#A89020"),        # 生成り（翠 x 桃 の極み）
    "gunner": ("#C0C8D8", "#5A6478"),      # 鋼（紅 x 若草）
    "alchemist": ("#68E0D8", "#188078"),   # 青緑（桃 x 紅）
    "chronomancer": ("#C098F8", "#6030B0"),  # 藤（桃 x 紫）
    "beastmaster": ("#E09858", "#8A4818"),   # 鳶（若草 x 蒼）
    "jester": ("#F878A0", "#B02050"),        # 撫子（初期職の変わり種）
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


## タイルシートの寸法（16x16 を 9 枚、横一列）。取り込みの検算に使う。
TILESET_SIZE = (TILE * 9, TILE)

## 床と壁の色の隔たりの下限（RGB 空間の距離）。
##
## この 2 枚は「通れる／通れない」を伝える唯一の手がかりなので、
## 質感の良さより先に**離れて見えること**が要る。明度だけで測ると、
## 色相が違って明度が同じ組（草原の草と木立ちなど）を落としてしまうので距離で測る。
##
## 実測（この値を決めた根拠）:
##   いまの ASCII タイル  距離 65.9 … 読めている
##   雪原の候補           距離 138.4 … 読める
##   地下 / 草原 / 火山 / 湿地の候補  距離 3.3〜9.3 … どこを歩けるのか読めない
MIN_FLOOR_WALL_DISTANCE = 40.0


def _tile_mean(sheet: Canvas, index: int) -> tuple[float, float, float]:
    """タイル 1 枚の平均色。透明は数えない。"""
    px = [
        sheet.get(index * TILE + x, y)
        for y in range(TILE)
        for x in range(TILE)
        if sheet.get(index * TILE + x, y)[3]
    ]
    if not px:
        return (0.0, 0.0, 0.0)
    n = len(px)
    return (
        sum(p[0] for p in px) / n,
        sum(p[1] for p in px) / n,
        sum(p[2] for p in px) / n,
    )


def _tileset_readable(sheet: Canvas) -> tuple[bool, str]:
    """床と壁が見分けられるか。見分けられない絵は、綺麗でも採用しない。"""
    floor = _tile_mean(sheet, 0)
    wall = _tile_mean(sheet, 2)
    gap = math.dist(floor, wall)
    if gap >= MIN_FLOOR_WALL_DISTANCE:
        return True, ""
    return False, (
        "床と壁の色が近すぎる（距離 %.1f、%.1f 以上必要）。"
        "床 (%.0f,%.0f,%.0f) / 壁 (%.0f,%.0f,%.0f)。"
        % (gap, MIN_FLOOR_WALL_DISTANCE, floor[0], floor[1], floor[2], wall[0], wall[1], wall[2])
    )


# 床と壁を引き離すときの 1 段ぶん。壁の明るさをこの割合ずつ落とす。
_SEPARATE_STEP = 0.88
_SEPARATE_TRIES = 12


def separate_floor_wall(sheet: Canvas, name: str) -> Canvas:
    """床と壁が近すぎるなら、壁を暗くして引き離す。

    **却下せずに直す。** このリポジトリの取り込みは元々そういう作りで、
    BGR555 に乗っていない色は丸めて通す（実機に無い色は間違いではなく、
    まだ丸めていないだけ）。寸法・アルファ・色数のように直せないものだけ止める。
    床と壁の距離は**直せる**ので、止める側に置いていたのが誤りだった。

    草原や湿地は床（草）と壁（茂み）が同じ色相で、絵として正しくても
    数値では近くなる。色相を変えると絵が壊れるので、**明るさだけ**を落とす。
    見下ろし画面では壁が暗いほうが自然なので、絵の意図とも喧嘩しない。
    """
    floor = _tile_mean(sheet, 0)
    wall = _tile_mean(sheet, 2)
    if math.dist(floor, wall) >= MIN_FLOOR_WALL_DISTANCE:
        return sheet

    before = math.dist(floor, wall)
    down = 1.0
    up = 1.0
    for _ in range(_SEPARATE_TRIES):
        # **壁を暗くするだけでなく、床も同じだけ明るくする。**
        # 片側だけ動かすと絵全体が沈み、草原が夜の洞窟になった（実際そうなった）。
        # 両側へ開けば中間の明るさが保たれるので、元の絵の調子が残る。
        down *= _SEPARATE_STEP
        up /= _SEPARATE_STEP
        shifted = _scale_tiles(sheet, (2, 3), down)
        shifted = _scale_tiles(shifted, (0, 1), up)
        after = math.dist(_tile_mean(shifted, 0), _tile_mean(shifted, 2))
        if after >= MIN_FLOOR_WALL_DISTANCE:
            print(
                "    %s: 床を %.0f%% / 壁を %.0f%% にして引き離した（%.1f → %.1f）"
                % (name, up * 100, down * 100, before, after)
            )
            return shifted
    # ここまで暗くしても離れないなら、床と壁が同じ絵ということ。直せない。
    return sheet


def _scale_tiles(sheet: Canvas, indices: tuple, factor: float) -> Canvas:
    """指定したタイルだけ明るさを変えた複製を返す。"""
    out = Canvas(sheet.w, sheet.h)
    for y in range(sheet.h):
        for x in range(sheet.w):
            px = sheet.get(x, y)
            if px[3] and (x // TILE) in indices:
                # snes() は #RRGGBB を取るので、ここでは 5bit へ直に丸める
                # （31 段階に落として戻す。実機に無い色を作らないため）。
                px = tuple(
                    (min(int(c * factor), 255) >> 3) * 255 // 31 for c in px[:3]
                ) + (px[3],)
            out.set(x, y, px)
    return out


## 場所ごとのタイル。既定（dungeon）は assets/tiles/dungeon.png に、
## それ以外は名前のまま置く。無い場所は単に生成されないので、
## ゲーム側は「あれば使う」で拾えばよい。
BIOMES = ["dungeon", "grassland", "snowfield", "volcano", "wetland"]

# 町は探索用タイルの建物を引き継ぐが、地面だけは別の密度にする。
#
# 元の T_GROUND_ALT は枝、泥、溶岩の亀裂など「危険な場所を歩く」ための絵で、
# 5x5 の広場へ並べると人物より先に目へ入った。町用シートでは最初の9枚を
# 保ったまま床2枚を低密度版へ替え、末尾に街路4変種・広場4変種を足す。
# 変種は座標で選ぶので乱数を使わず、16pxごとの露骨な反復だけを崩せる。
TOWN_ROAD_FIRST = 9
TOWN_PLAZA_FIRST = 13
TOWN_VARIANTS = 4
TOWN_TILESET_TILES = TOWN_PLAZA_FIRST + TOWN_VARIANTS
TOWN_TILESET_SIZE = (TILE * TOWN_TILESET_TILES, TILE)

# すべて BGR555 上の色。通常地面と街路・広場は色相を共有し、
# 明暗差だけで「計画された場所」と読ませる。雪だけは明るい地色を守る。
TOWN_SURFACE_COLORS = {
    "dungeon": {
        "ground": ("#31315A", "#181831", "#393973"),
        "road": ("#181831", "#080810", "#31315A"),
        "plaza": ("#393973", "#31315A", "#5A5A94"),
    },
    "grassland": {
        "ground": ("#314A29", "#182918", "#525A31"),
        "road": ("#312918", "#182918", "#5A3929"),
        "plaza": ("#525A31", "#314A29", "#73736A"),
    },
    "wetland": {
        "ground": ("#293929", "#203941", "#526A39"),
        # 青緑にすると水路＝通行不能に見えたため、苔の暗い土色へ寄せる。
        "road": ("#293121", "#182918", "#526A39"),
        "plaza": ("#526A39", "#293929", "#52837B"),
    },
    "snowfield": {
        "ground": ("#B4C5C5", "#94A4AC", "#DEDED5"),
        "road": ("#94A4AC", "#6A7B8B", "#B4C5C5"),
        "plaza": ("#DEDED5", "#B4C5C5", "#94A4AC"),
    },
    "volcano": {
        "ground": ("#202039", "#181829", "#39395A"),
        "road": ("#39395A", "#202039", "#5A5A7B"),
        "plaza": ("#292941", "#202039", "#5A5A7B"),
    },
}


def _town_rgba(hex_color: str) -> tuple[int, int, int, int]:
    r, g, b = snes(hex_color)
    return (r, g, b, 255)


def _town_surface(
    colors: tuple[str, str, str], kind: str, variant: int = 0
) -> Canvas:
    """人物の輪郭と競合しない、低密度な16x16地面を作る。"""
    base, dark, light = (_town_rgba(color) for color in colors)
    tile = Canvas(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            tile.set(x, y, base)

    # 位置をずらすだけに留め、1タイル内の非ベース画素は12px以下にする。
    # 大きな石目や亀裂を描かないことが、キャラの足を読ませるうえで重要。
    ox = (variant * 3) % 7
    oy = (variant * 5) % 7
    if kind == "ground":
        marks = [
            (2 + ox, 3 + oy, dark), (11 - ox // 2, 5, light),
            (5, 12 - oy // 2, dark), (13 - ox // 3, 13, light),
        ]
    elif kind == "road":
        marks = [
            (1 + ox, 4, dark), (2 + ox, 4, dark), (3 + ox, 4, light),
            (10 - ox // 2, 11, dark), (11 - ox // 2, 11, dark),
            (12 - ox // 2, 11, light), (5, 14 - oy // 2, dark),
            (6, 14 - oy // 2, light),
        ]
    else:  # plaza
        marks = [
            (2 + ox, 2, dark), (3 + ox, 2, dark), (2 + ox, 3, light),
            (12 - ox // 2, 7 + oy // 2, dark),
            (13 - ox // 2, 7 + oy // 2, light),
            (6, 13 - oy // 2, dark), (7, 13 - oy // 2, dark),
            (8, 13 - oy // 2, light),
        ]
    for x, y, color in marks:
        tile.set(x, y, color)
    return tile


def _verify_town_tileset(name: str, sheet: Canvas) -> None:
    """町床が再び探索用の高密度テクスチャへ戻るのを止める。"""
    if (sheet.w, sheet.h) != TOWN_TILESET_SIZE:
        raise ValueError(
            f"town_{name}: {TOWN_TILESET_SIZE[0]}x{TOWN_TILESET_SIZE[1]} 必須"
        )
    surface_indices = [0, 1] + list(
        range(TOWN_ROAD_FIRST, TOWN_PLAZA_FIRST + TOWN_VARIANTS)
    )
    for index in surface_indices:
        counts: dict = {}
        for y in range(TILE):
            for x in range(TILE):
                color = sheet.get(index * TILE + x, y)
                counts[color] = counts.get(color, 0) + 1
        detail = TILE * TILE - max(counts.values())
        if detail > 12:
            raise ValueError(
                f"town_{name}: 地面{index}の模様が密すぎる（非ベース{detail}px）"
            )

    means = {
        "ground": _tile_mean(sheet, 0),
        "road": _tile_mean(sheet, TOWN_ROAD_FIRST),
        "plaza": _tile_mean(sheet, TOWN_PLAZA_FIRST),
    }
    for a, b in (("ground", "road"), ("ground", "plaza"), ("road", "plaza")):
        gap = math.dist(means[a], means[b])
        if not 8.0 <= gap <= 110.0:
            raise ValueError(
                f"town_{name}: {a}/{b}の色差{gap:.1f}が範囲外（8〜110）"
            )


def build_town_tilesets() -> None:
    """5生物相の建物を保ち、町専用の静かな床を加えたシートを作る。"""
    for name in BIOMES:
        source_path = ASSETS / "tiles" / f"{name}.png"
        if not source_path.exists():
            source_path = ASSETS / "tiles" / "dungeon.png"
        source = load_png(source_path)
        out = Canvas(*TOWN_TILESET_SIZE)
        out.blit(source, 0, 0)

        colors = TOWN_SURFACE_COLORS[name]
        out.blit(_town_surface(colors["ground"], "ground"), 0, 0)
        # 無計画な装飾床も同じ地色の疎な変種へ抑える。
        out.blit(_town_surface(colors["ground"], "ground", 2), TILE, 0)
        for variant in range(TOWN_VARIANTS):
            out.blit(
                _town_surface(colors["road"], "road", variant),
                (TOWN_ROAD_FIRST + variant) * TILE,
                0,
            )
            out.blit(
                _town_surface(colors["plaza"], "plaza", variant),
                (TOWN_PLAZA_FIRST + variant) * TILE,
                0,
            )
        _verify_town_tileset(name, out)
        out.to_png(ASSETS / "tiles" / f"town_{name}.png")
        out.scaled(4).to_png(PREVIEW / f"town_tiles_{name}.png")
        print(
            f"  町床: town_{name}.png"
            "（通常 / 街路4変種 / 広場4変種、各タイル模様12px以下）"
        )


def build_biomes() -> None:
    """既定以外の場所のタイルを書き出す。条件に落ちたものは見送る。"""
    for name in BIOMES:
        if name == "dungeon":
            continue  # 既定は build_tileset が面倒をみる
        sheet = _load_sheet(f"candidate_tiles_{name}", TILESET_SIZE)
        if sheet is None:
            continue
        sheet = separate_floor_wall(sheet, name)
        readable, reason = _tileset_readable(sheet)
        if not readable:
            print(f"  見送り: candidate_tiles_{name}.png — {reason}")
            continue
        sheet.to_png(ASSETS / "tiles" / f"{name}.png")
        sheet.scaled(6).to_png(PREVIEW / f"tiles_{name}.png")
        print(f"  取り込み: {name}.png（chara_image/candidate_tiles_{name}.png）")


def build_tileset() -> None:
    """9 枚を横一列に並べた 144x16 のタイルシート。

    外で描いたものがあればそれを採用する。並び順（床・ひび割れ床・壁・天面・
    階段・扉・宝箱・虚空・出店）は DungeonMap の enum と一致させること。
    """
    imported = _load_sheet("candidate_tiles_dungeon", TILESET_SIZE)
    if imported is not None:
        imported = separate_floor_wall(imported, "dungeon")
        readable, reason = _tileset_readable(imported)
        if readable:
            imported.to_png(ASSETS / "tiles" / "dungeon.png")
            imported.scaled(6).to_png(PREVIEW / "dungeon.png")
            print("  取り込み: dungeon.png（chara_image/candidate_tiles_dungeon.png）")
            return
        # 採用しない。ここで黙って通すと、綺麗だが遊べない地形が出来上がる。
        print("  見送り: candidate_tiles_dungeon.png — " + reason)

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
# ワールドマップのタイル（16x16 x 9）
#
# 並び順は WorldMap の enum と一致させること。
#   0 海 / 1 草原 / 2 森 / 3 丘 / 4 山 / 5 門 / 6 町 / 7 洞 / 8 城
#
# ここで一番大事なのは**通れる地形と通れない地形が一目で分かること**。
# ダンジョンタイルで学んだのと同じ問題で、明度だけ変えても見分けが付かない。
# 海と山（通れない）は寒色で暗く、草原・森・丘（通れる）は暖色寄りで明るく置く。
# --------------------------------------------------------------------------

# SFC の 1 サブパレットは透明を除き 15 色まで。9 枚を 1 枚のシートに載せるので、
# 海・草原・森・丘・山・建物の全部をこの 15 色で賄う。
#
# 色の割り振りに意図がある。**通れない地形（海・山）は寒色、通れる地形
# （草原・森・丘）は暖色寄り**にして、明度ではなく色相で見分けさせる。
# ダンジョンタイルが読めなかったのは、明度だけ変えて色相を揃えたせいだった。
WORLD = Palette(
    "world",
    {
        "K": "#0E1220",  # 輪郭・洞の口・最暗部
        # 海（通れない・寒色）
        "S": "#1A3A6E",
        "s": "#122A52",  # 山の影も兼ねる（どちらも通れない側）
        "W": "#3A6AA8",  # 波
        # 草原（通れる・黄緑）
        "G": "#5C9A3A",
        "H": "#7CBE52",  # 草の光。森の光も兼ねる
        # 森（通れる・濃い緑）
        "F": "#2E6A38",
        "f": "#1E4A26",
        # 丘（通れる・土）
        "N": "#8A6A3A",
        "n": "#6A4E28",  # 丘の影。真っ黒だと帯が強すぎて模様に見える
        "M": "#A88A52",
        # 山（通れない・灰と雪）
        "R": "#5A5A6A",
        "P": "#C8CCD8",  # 雪。建物の光にも使う
        # 建物
        "A": "#C03A32",  # 屋根 赤
        "Y": "#E8C860",  # 灯り
    },
)

TILE_WORLD_SEA = [
    "SsSsSsSsSsSsSsSs",
    "sSsSsSsSsSsSsSsS",
    "SsSsWWsSsSsSsSsS",
    "sSsSsSsSsSWWsSsS",
    "SsSsSsSsSsSsSsSs",
    "sSsSsSsSsSsSsSsS",
    "SsWWsSsSsSsSsSsS",
    "sSsSsSsSsSsWWsSs",
    "SsSsSsSsSsSsSsSs",
    "sSsSsSsSsSsSsSsS",
    "SsSsSsWWsSsSsSsS",
    "sSsSsSsSsSsSsSsS",
    "SsSsSsSsSsSsWWsS",
    "sSsSsSsSsSsSsSsS",
    "SsWWsSsSsSsSsSsS",
    "sSsSsSsSsSsSsSsS",
]

TILE_WORLD_PLAIN = [
    "GGGGGGGGGGGGGGGG",
    "GGHGGGGGGGGHGGGG",
    "GGGGGGGFGGGGGGGG",
    "GFGGGGGGGGGGGFGG",
    "GGGGGHGGGGGGGGGG",
    "GGGGGGGGGGFGGGGG",
    "GGFGGGGGGGGGGGHG",
    "GGGGGGGHGGGGGGGG",
    "GGGGGFGGGGGGGFGG",
    "GHGGGGGGGGGGGGGG",
    "GGGGGGGGGFGGGGGG",
    "GGGGFGGGGGGGHGGG",
    "GGGGGGGHGGGGGGGG",
    "GFGGGGGGGGFGGGGG",
    "GGGGGGGGGGGGGGGG",
    "GGGGHGGGGGGGGFGG",
]

TILE_WORLD_FOREST = [
    "FfFFFFFfFFFFFFfF",
    "FFHFFFFFFFHFFFFF",
    "FHHHFFFHFFHHHFFF",
    "HHHHHFFHHFHHHHHF",
    "FfHfFFHHHHFfHfFF",
    "FFfFFFHHHHFFfFFF",
    "FFfFFFFfHfFFfFFF",
    "fFFFfFFFfFFFFFfF",
    "FFFHFFFFFFFFHFFF",
    "FFHHHFFFfFFHHHFF",
    "FHHHHHFFFFHHHHHF",
    "FfHfFFFHFFfHfFFF",
    "FFfFFFFHHHFFfFFF",
    "FFfFFFFfHfFFfFFF",
    "fFFFfFFFfFFFFFfF",
    "FFFFFFFFFFFFFFFF",
]

TILE_WORLD_HILL = [
    "NNNNNNNNNNNNNNNN",
    "NNNMMNNNNNNNNNNN",
    "NNMMMMNNNNMMNNNN",
    "NMMMMMMNNMMMMNNN",
    "MMMMMMMMMMMMMMNN",
    "NnnnnnnnNnnnnnNN",
    "NNnNNNnNNNnNNnNN",
    "NNNNNNNNNNNNNNNN",
    "NNNNNNNNMMNNNNNN",
    "NNNMMNNMMMMNNNNN",
    "NNMMMMMMMMMMNNNN",
    "NMMMMMMMMMMMMMNN",
    "NnnnnnnnnnnnnnNN",
    "NNnNNNnNNNnNNNNN",
    "NNNNNNNNNNNNNNNN",
    "NNNNNNNNNNNNNNNN",
]

TILE_WORLD_MOUNTAIN = [
    "ssssssssssssssss",
    "sssssssPssssssss",
    "ssssssPPPsssssss",
    "sssssPPPPPssssss",
    "ssssRPPPPPRsssss",
    "sssRRRPPPRRRssss",
    "ssRRRRRPRRRRRsss",
    "sRRRRRRRRRRRRRss",
    "RRRRRRRRRRRRRRRs",
    "RRRRRsssssRRRRRR",
    "RRRRsssssssRRRRR",
    "RRRsssssssssRRRR",
    "RRsssssssssssRRR",
    "ssssssssssssssss",
    "ssssssssssssssss",
    "ssssssssssssssss",
]

# 門 — 砦から着く場所。石の枠に灯りを 2 つ。必ず草原の上に立つ。
TILE_WORLD_GATE = [
    "GGGGGGGGGGGGGGGG",
    "GGGKKKKKKKKKKGGG",
    "GGKRRRRRRRRRRKGG",
    "GKRRPPRRRRPPRRKG",
    "GKRYRRRRRRRRYRKG",
    "GKRRRRRRRRRRRRKG",
    "GKRRRKKKKKKRRRKG",
    "GKRRKKKKKKKKRRKG",
    "GKRRKKKKKKKKRRKG",
    "GKRRKKKKKKKKRRKG",
    "GKRRKKKKKKKKRRKG",
    "GKRPKKKKKKKKPRKG",
    "GKKKKKKKKKKKKKKG",
    "GGGGGKKKKKKGGGGG",
    "GGGGGGGGGGGGGGGG",
    "GGGGGGGGGGGGGGGG",
]

# 町 — 赤い屋根 2 つ。どこにあっても「安全」と読めるよう明るく。
TILE_WORLD_TOWN = [
    "GGGGGGGGGGGGGGGG",
    "GGGGGAAGGGGGGGGG",
    "GGGGAAAAGGGGGGGG",
    "GGGAAAAAAGGAAGGG",
    "GGKKKKKKKKAAAAGG",
    "GGKRRRRRKKKKKKKG",
    "GGKRYYRRKKRRRRKG",
    "GGKRYYRRKKRYYRKG",
    "GGKRRRRRKKRYYRKG",
    "GGKKKKKKKKRRRRKG",
    "GGGGGGGGGGKKKKKG",
    "GGGGGGGGGGGGGGGG",
    "GGGGAAAAGGGGGGGG",
    "GGGKKKKKKGGGGGGG",
    "GGGKRRRRKGGGGGGG",
    "GGGKRYYRKGGGGGGG",
]

# 洞 — 岩に空いた口。寄り道の目印なので町より小さく暗く。
TILE_WORLD_CAVE = [
    "NNNNNNNNNNNNNNNN",
    "NNNNNMMMMNNNNNNN",
    "NNNMMMMMMMNNNNNN",
    "NNMMMMMMMMMNNNNN",
    "NMMMKKKKKMMMNNNN",
    "NMMKKKKKKKMMMNNN",
    "NMMKKKKKKKKMMNNN",
    "NMMKKKKKKKKMMNNN",
    "NNNKKKKKKKKNNNNN",
    "NNNKKKKKKKKNNNNN",
    "NNNKKKKKKKKNNNNN",
    "NNNNKKKKKKNNNNNN",
    "NNNNNKKKKNNNNNNN",
    "NNNNNNNNNNNNNNNN",
    "NNNNNNNNNNNNNNNN",
    "NNNNNNNNNNNNNNNN",
]

# 城 — 終点。主が居る。狭間を持つ塔で、他のどれとも間違えない形にする。
TILE_WORLD_CASTLE = [
    "NNNNNNNNNNNNNNNN",
    "NRKRKNNRKRKNNNNN",
    "NRRRRNNRRRRNNNNN",
    "NRPPRNNRPPRNNNNN",
    "NRRRRKKRRRRNNNNN",
    "NRYRRKKRRYRNNNNN",
    "NRRRRKKRRRRKRKRK",
    "NKRKRKKRKRKKRRRR",
    "NRRRRRRRRRRRPPRR",
    "NRPPPPPPPPPRRRRR",
    "NRRKKKKKKRRRRYRR",
    "NRRKKKKKKRRKRKRK",
    "NRRKKKKKKRRRRRRR",
    "NPPKKKKKKPPRPPRR",
    "NKKKKKKKKKKKRRRR",
    "NNNNKKKKNNNNKKKK",
]


def world_texture(a: str, b: str, step: int, fleck: str = "", spots: tuple = ()) -> Canvas:
    """ディザ 2 色 + 斑点で地形の質感を作る。

    草原や森のように「形」がある地形は ASCII で描くが、雪原・砂漠・沼・溶岩は
    一面の質感なので手続きのほうが短く、粒の細かさも揃う。
    """
    c = Canvas(TILE, TILE)
    dither(c, 0, 0, TILE, TILE, WORLD.get(a), WORLD.get(b), step)
    if fleck:
        for x, y in spots:
            c.set(x, y, WORLD.get(fleck))
    return c


def build_world_tileset() -> None:
    """ワールドマップのタイル 14 枚（224x16）。

    外で描いたものがあれば採ることも考えたが、判定条件（床と壁の色距離）は
    ダンジョン用に作ったもので、ワールドには 5 種類の地形がある。
    ここは自前で描いたものを使い、差し替えは後で条件を作ってから考える。
    """
    tiles = [
        from_ascii(TILE_WORLD_SEA, WORLD),
        from_ascii(TILE_WORLD_PLAIN, WORLD),
        from_ascii(TILE_WORLD_FOREST, WORLD),
        from_ascii(TILE_WORLD_HILL, WORLD),
        from_ascii(TILE_WORLD_MOUNTAIN, WORLD),
        from_ascii(TILE_WORLD_GATE, WORLD),
        from_ascii(TILE_WORLD_TOWN, WORLD),
        from_ascii(TILE_WORLD_CAVE, WORLD),
        from_ascii(TILE_WORLD_CASTLE, WORLD),
        # 9 雪原 — 明るい白。通れるが遭遇が重い
        world_texture("P", "M", 5, "R", ((3, 6), (11, 2), (7, 12), (13, 9))),
        # 10 砂漠 — 乾いた土。丘より明るく、風紋を入れる
        world_texture("M", "N", 4, "P", ((2, 4), (6, 4), (10, 11), (14, 11))),
        # 11 沼 — 濃い緑に水たまり。歩けるが重い
        world_texture("f", "F", 3, "S", ((4, 5), (5, 5), (10, 9), (11, 9), (7, 13))),
        # 12 溶岩 — 通れない。赤は世界でここだけなので、遠目でも危険と読める
        world_texture("A", "K", 3, "Y", ((3, 3), (8, 7), (12, 12), (5, 10))),
        # 13 街道 — 地域をまたいでも同じ土色。本筋と枝道を地図から読めるようにする
        world_texture("N", "n", 4, "M", ((2, 3), (7, 8), (12, 4), (14, 13))),
    ]
    sheet = Canvas(TILE * len(tiles), TILE)
    for i, t in enumerate(tiles):
        sheet.blit(t, i * TILE, 0)
    sheet.to_png(ASSETS / "tiles" / "world.png")
    sheet.scaled(6).to_png(PREVIEW / "tiles_world.png")
    _report_world_contrast(tiles)


def _report_world_contrast(tiles: list[Canvas]) -> None:
    """通れる地形と通れない地形が見分けられるかを測って出す。

    ダンジョンタイルで「床と壁が見分けられない」を経験しているので、
    ここは黙って通さずに数字を出す。海・山（通れない）と草原・森・丘（通れる）
    の代表色が近すぎたら、目で見る前に分かる。
    """
    names = ["海", "草原", "森", "丘", "山", "", "", "", "", "雪原", "砂漠", "沼", "溶岩", "街道"]
    index = [0, 1, 2, 3, 4, 9, 10, 11, 12, 13]
    blocked = {0, 4, 12}
    means = {i: _mean_rgb(tiles[i]) for i in index}
    worst = None
    for i in index:
        for j in index:
            if j <= i:
                continue
            if (i in blocked) == (j in blocked):
                continue  # 同じ側どうしは見分けが付かなくてよい
            gap = math.dist(means[i], means[j])
            if worst is None or gap < worst[0]:
                worst = (gap, names[i], names[j])
    if worst is not None:
        mark = "OK" if worst[0] >= MIN_FLOOR_WALL_DISTANCE else "近い"
        print(
            "  ワールド地形の見分け: %s %s と %s が %.1f（基準 %.0f）"
            % (mark, worst[1], worst[2], worst[0], MIN_FLOOR_WALL_DISTANCE)
        )


def _mean_rgb(c: Canvas) -> tuple[float, float, float]:
    total = [0.0, 0.0, 0.0]
    count = 0
    for y in range(c.h):
        for x in range(c.w):
            px = c.get(x, y)
            if px == TRANSPARENT:
                continue
            total[0] += px[0]
            total[1] += px[1]
            total[2] += px[2]
            count += 1
    if count == 0:
        return (0.0, 0.0, 0.0)
    return (total[0] / count, total[1] / count, total[2] / count)


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
# 職業ごとの差分。**職業名から定番記号を足さない**（`AGENTS.md` の美術基準）。
#
# 遊び人に二股帽、銃士に制帽、錬金術師に白衣、魔獣使いに獣耳 ―― これらは禁止。
# 名前から連想したものを足した時点で、この作品の人ではなくなる。
# 代わりに黒い漆・象牙・骨、有機的な角や襟へ**役割を翻訳する**
# （対応表は `docs/character_art_direction.md`）。
#
# 差分は**輪郭で作る**。色だけ変えると同じ人に見える。24x32 では
# 頭飾り・襟・肩・裾のうち 2〜3 個を大きな輪郭として残す。
# 似すぎている組は `_report_hero_similarity()` が測って出す。
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
    # 差分を書いていない職業は、素の姿で起こす（外で描いた絵がある職業は
    # そちらが優先されるので、ここに届くのは素材が無いときだけ）。
    look = HERO_LOOKS.get(job, {"hair": 20, "skirt": SKIRT_WIDE})
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
MAX_COLORS = 15


def _verify_sheet(label: str, sheet: Canvas, size: tuple[int, int]) -> None:
    """取り込んだ絵が SFC の制約を守っているかを検算する。

    黙って通すと、色数もアルファもばらばらな絵が assets/ に混ざり、
    「なぜか 1 枚だけ浮いている」の原因が追えなくなる。
    SFC らしさは技巧ではなく制約の徹底から出るので、外から来た絵にも同じ条件を課す。
    """
    if (sheet.w, sheet.h) != size:
        raise ValueError(
            "%s: %dx%d でなければならない（%dx%d だった）"
            % (label, size[0], size[1], sheet.w, sheet.h)
        )

    alphas = {p[3] for p in sheet.px}
    if not alphas <= {0, 255}:
        raise ValueError("%s: アルファは 0 か 255 だけにする（%s があった）" % (label, sorted(alphas)))

    colors = {p[:3] for p in sheet.px if p[3] == 255}
    if len(colors) > MAX_COLORS:
        raise ValueError(
            "%s: 透明を除いて %d 色まで（%d 色あった）" % (label, MAX_COLORS, len(colors))
        )


def _quantize(sheet: Canvas) -> tuple[Canvas, int]:
    """すべての色を BGR555 へ丸める。丸めた色数を返す。

    ここは弾かずに直す。実機に無い色は「間違い」ではなく「まだ丸めていない」
    だけで、丸めても各チャンネル 8 段階ぶんしか動かない（目には分からない）。
    寸法・アルファ・色数のように**直せない違反**だけを例外にする。
    """
    moved: set = set()
    out = Canvas(sheet.w, sheet.h)
    for i, p in enumerate(sheet.px):
        if p[3] == 0:
            out.px[i] = TRANSPARENT
            continue
        rgb = snes("#%02X%02X%02X" % (p[0], p[1], p[2]))
        if rgb != p[:3]:
            moved.add(p[:3])
        out.px[i] = (rgb[0], rgb[1], rgb[2], 255)
    return out, len(moved)


def _load_sheet(stem: str, size: tuple[int, int]) -> Canvas | None:
    """外で描いた絵を読む。無ければ None（＝ ASCII マップから起こす方に落ちる）。"""
    path = HERO_SOURCE_DIR / f"{stem}.png"
    if not path.exists():
        return None
    sheet = load_png(path)
    sheet, moved = _quantize(sheet)
    _verify_sheet(stem, sheet, size)
    if moved:
        print(f"    {stem}: {moved} 色を BGR555 へ丸めた")
    return sheet


## 町の人。**主人公の絵を借りない。**
##
## 借りていたときは、町の中に自分と同じ姿が 4 人立っていた。
## 24x32 の 1 コマだけなので歩行はしないが、町に居るのは立ち止まっている人。
NPC_ROLES = [
    "innkeeper",
    "merchant",
    "elder",
    "scout",
    "guard",
    # 町の用途と輪郭が一目で分かれる追加 NPC。
    "healer",
    "blacksmith",
    "miner",
    "ferryman",
    "farmer",
    "beastkeeper",
    "mechanic",
    "scribe",
    "refugee",
    "pilgrim",
    "performer",
    "imperial_officer",
]

# NPC の候補は同じ 24x32 でも、実際には幅14〜18px・高さ29〜30pxの
# 細長い立ち絵だった。基準にする `hero_mage` は幅22px・高さ27pxで、
# 町へ並べると NPC だけ別の縮尺に見える。候補原画の輪郭は残しつつ、
# **ゲームへ出す直前に偶数寸法のフィールドキャラ規格へ翻訳する。**
#
# 暖かな茶革へ戻さず、黒い漆・象牙・一系統の差し色という作品の語彙へ揃える。
NPC_ACCENTS = {
    "innkeeper": ("#58D8B8", "#187860"),
    "merchant": ("#E878C8", "#903060"),
    "elder": ("#C098F8", "#603878"),
    "scout": ("#58B8D8", "#286878"),
    "guard": ("#F06868", "#903038"),
    "healer": ("#58E0C0", "#187860"),
    "blacksmith": ("#F08050", "#983828"),
    "miner": ("#B890F0", "#604878"),
    "ferryman": ("#68C8E8", "#286878"),
    "farmer": ("#88D878", "#487038"),
    "beastkeeper": ("#D87858", "#783828"),
    "mechanic": ("#58D8D8", "#287878"),
    "scribe": ("#A890E8", "#504070"),
    "refugee": ("#D85868", "#783040"),
    "pilgrim": ("#D0A0F0", "#684878"),
    "performer": ("#F070B0", "#903058"),
    "imperial_officer": ("#E85050", "#882028"),
}

NPC_TARGET_H = 28
NPC_MIN_W = 20
NPC_MAX_W = 22


def _rgba(hex_color: str) -> tuple[int, int, int, int]:
    rgb = snes(hex_color)
    return (rgb[0], rgb[1], rgb[2], 255)


NPC_K = _rgba("#0E0A16")
NPC_DARK = _rgba("#241C38")
NPC_MID = _rgba("#403650")
NPC_IVORY_SHADOW = _rgba("#A8B0C0")
NPC_IVORY = _rgba("#E8DCC8")
NPC_WHITE = _rgba("#F8F0E0")


def _opaque_bbox(sheet: Canvas) -> tuple[int, int, int, int]:
    points = [
        (x, y)
        for y in range(sheet.h)
        for x in range(sheet.w)
        if sheet.get(x, y) != TRANSPARENT
    ]
    if not points:
        raise ValueError("人物が透明だけになっている")
    return (
        min(x for x, _y in points),
        min(y for _x, y in points),
        max(x for x, _y in points),
        max(y for _x, y in points),
    )


def _field_width(source_w: int, scale: float) -> int:
    """24pxセル内の実体幅を、中央合わせしやすい20pxか22pxへ丸める。"""
    wanted = max(NPC_MIN_W, min(NPC_MAX_W, round(source_w * scale)))
    return wanted if wanted % 2 == 0 else min(wanted + 1, NPC_MAX_W)


def _resample_index(index: int, source_size: int, target_size: int) -> int:
    """最近傍変換で両端を必ず拾う。最終行を落として接地を崩さない。"""
    if source_size <= 1 or target_size <= 1:
        return 0
    return (
        index * (source_size - 1) + (target_size - 1) // 2
    ) // (target_size - 1)


def _npc_palette_color(
    color: tuple[int, int, int, int],
    low: float,
    high: float,
    accent: tuple[tuple[int, int, int, int], tuple[int, int, int, int]],
) -> tuple[int, int, int, int]:
    """候補の明暗配置を、黒・象牙・差し色1系統へ写す。

    元の RGB をそのまま明るくすると、茶色い農民・軍服・革装備という
    候補側の癖まで強調される。ここでは**形と陰影だけを借りる**。
    """
    r, g, b, _a = color
    luminance = r * 0.2126 + g * 0.7152 + b * 0.0722
    level = (luminance - low) / max(high - low, 1.0)
    saturation = (max(r, g, b) - min(r, g, b)) / float(max(max(r, g, b), 1))
    accent_light, accent_dark = accent
    if level < 0.14:
        return NPC_K
    if level < 0.31:
        return NPC_DARK
    if level < 0.49:
        return accent_dark if saturation >= 0.16 else NPC_MID
    if level < 0.67:
        return accent_light if saturation >= 0.20 else NPC_IVORY_SHADOW
    if level < 0.84:
        return NPC_IVORY_SHADOW
    if level < 0.94:
        return NPC_IVORY
    return NPC_WHITE


def _prepare_npc(role: str, source: Canvas) -> Canvas:
    """細長い候補を、`hero_mage` と同じ接地・頭身・明暗へ正規化する。"""
    x0, y0, x1, y1 = _opaque_bbox(source)
    source_w = x1 - x0 + 1
    source_h = y1 - y0 + 1
    target_w = _field_width(source_w, 1.25)
    target_x = (CHAR_W - target_w) // 2
    target_y = CHAR_H - NPC_TARGET_H

    opaque = [px for px in source.px if px != TRANSPARENT]
    lightness = sorted(
        px[0] * 0.2126 + px[1] * 0.7152 + px[2] * 0.0722
        for px in opaque
    )
    # 端の1色に引っ張られないよう、5〜95百分位を階調の両端にする。
    low = lightness[int((len(lightness) - 1) * 0.05)]
    high = lightness[int((len(lightness) - 1) * 0.95)]
    bright, dark = NPC_ACCENTS[role]
    accent = (_rgba(bright), _rgba(dark))

    out = Canvas(CHAR_W, CHAR_H)
    for dy in range(NPC_TARGET_H):
        sy = y0 + _resample_index(dy, source_h, NPC_TARGET_H)
        for dx in range(target_w):
            sx = x0 + _resample_index(dx, source_w, target_w)
            color = source.get(sx, sy)
            if color == TRANSPARENT:
                continue
            out.set(
                target_x + dx,
                target_y + dy,
                _npc_palette_color(color, low, high, accent),
            )
    return out


def _verify_npc_runtime_style(role: str, sheet: Canvas) -> None:
    """寸法だけ同じで別規格の人物が、再び町へ混ざるのを止める。"""
    x0, y0, x1, y1 = _opaque_bbox(sheet)
    width, height = x1 - x0 + 1, y1 - y0 + 1
    drawn = [px for px in sheet.px if px != TRANSPARENT]
    fill = len(drawn) / float(max(width * height, 1))
    bright = sum(max(px[:3]) >= 200 for px in drawn) / float(len(drawn))
    if width not in (NPC_MIN_W, NPC_MAX_W):
        raise ValueError(f"npc_{role}: 実画面幅が規格外（{width}px）")
    if height != NPC_TARGET_H or y1 != CHAR_H - 1:
        raise ValueError(
            f"npc_{role}: 高さ・接地が規格外（上{y0} 下{y1} 高さ{height}）"
        )
    if fill < 0.40:
        raise ValueError(f"npc_{role}: 輪郭が細すぎる（充填率 {fill:.2f}）")
    if bright < 0.05:
        raise ValueError(f"npc_{role}: 象牙の明部が足りない（{bright:.2f}）")


def _prepare_hero_sheet(job: str, source: Canvas) -> Canvas:
    """魔法使いを基準に、12コマすべての頭身と接地だけを揃える。

    職業候補は一枚ごとの絵としては成立しているため、NPCのような再配色はしない。
    ただし中身は幅16〜21px・高さ29〜30pxが大半で、魔法使いだけ幅22px・
    高さ27pxだった。全員を20pxか22px×28pxへ揃え、各コマを中央・下端へ写して
    元候補に混ざっていた1pxの上下揺れも取り除く。
    """
    out = Canvas(*HERO_SHEET_SIZE)
    for direction in range(4):
        for frame in range(3):
            ox, oy = frame * CHAR_W, direction * CHAR_H
            points = [
                (x, y)
                for y in range(CHAR_H)
                for x in range(CHAR_W)
                if source.get(ox + x, oy + y) != TRANSPARENT
            ]
            if not points:
                continue
            x0 = min(x for x, _y in points)
            y0 = min(y for _x, y in points)
            x1 = max(x for x, _y in points)
            y1 = max(y for _x, y in points)
            source_w, source_h = x1 - x0 + 1, y1 - y0 + 1
            target_w = _field_width(source_w, 1.20)
            target_x = (CHAR_W - target_w) // 2
            target_y = CHAR_H - NPC_TARGET_H
            dx0, dy0 = frame * CHAR_W + target_x, direction * CHAR_H + target_y
            for dy in range(NPC_TARGET_H):
                sy = y0 + _resample_index(dy, source_h, NPC_TARGET_H)
                for dx in range(target_w):
                    sx = x0 + _resample_index(dx, source_w, target_w)
                    color = source.get(ox + sx, oy + sy)
                    if color != TRANSPARENT:
                        out.set(dx0 + dx, dy0 + dy, color)
    return _evenize_hero_sheet(out)


def _hero_frame_colors(
    sheet: Canvas, ox: int, oy: int
) -> tuple[tuple[int, int, int, int], ...]:
    """候補自身のパレットから、輪郭・差し色・明部を選ぶ。"""
    colors = {
        sheet.get(ox + x, oy + y)
        for y in range(CHAR_H)
        for x in range(CHAR_W)
        if sheet.get(ox + x, oy + y) != TRANSPARENT
    }
    if not colors:
        return (NPC_K, NPC_MID, NPC_IVORY)

    def luminance(color) -> float:
        return color[0] * 0.2126 + color[1] * 0.7152 + color[2] * 0.0722

    ink = min(colors, key=luminance)
    ordered = sorted(colors, key=luminance)
    # 最明色は顔や髪の照りであることが多い。得物へ長く引くと白い棒に見えるため、
    # 中明度を金属の地色として使い、最明色は候補原画の中にだけ残す。
    mid = ordered[int((len(ordered) - 1) * 0.58)]

    # 彩度だけで選ぶと暗い輪郭色になるため、明度も少し加味する。
    def accent_score(color) -> float:
        hi, lo = max(color[:3]), min(color[:3])
        return (hi - lo) * 2.0 + luminance(color) * 0.25

    accent = max(colors, key=accent_score)
    return ink, accent, mid


def _hero_feature_points(job: str, direction: int) -> list[tuple[int, int, int]]:
    """実画面で職を読むための、外形に効く得物だけを返す。

    0=輪郭、1=差し色、2=明部。名前から記号を足すのではなく、
    戦闘時の役割を「盾で面を作る／長い得物で軸を作る」へ翻訳する。
    候補原画の描き込みは変えず、透明部へ足す輪郭を主に使う。
    """
    if job == "gunner":
        # 正面は左肩に立てた長銃、横は進行方向へ伸びる銃身。
        if direction in (0, 3):
            side = 1 if direction == 0 else 22
            inner = side + 1 if direction == 0 else side - 1
            points = [(side, y, 0) for y in range(8, 20)]
            points += [(inner, y, 2) for y in range(10, 18)]
            points += [
                (side, 7, 1), (inner, 19, 1),
                (inner + (1 if direction == 0 else -1), 20, 1),
                (inner + (2 if direction == 0 else -2), 21, 0),
            ]
            if direction == 0:
                # 胴の前を斜めに横切る機関部。輪郭だけでなく実画面でも銃と読ませる。
                for i in range(13):
                    points.append((6 + i, 21 - i // 2, 0))
                    if i % 2 == 0:
                        points.append((6 + i, 20 - i // 2, 2))
            return points
        points = [(x, 14, 0) for x in range(1, 11)]
        points += [(x, 15, 2) for x in range(2, 9, 2)]
        points += [(9, 16, 1), (10, 17, 1), (11, 18, 0)]
        return points

    if job == "paladin":
        # 大盾を片側へ寄せ、spellblade の細い得物と面積で分ける。
        left = direction == 0
        rows = {
            17: range(2, 5), 18: range(1, 6), 19: range(1, 6),
            20: range(1, 6), 21: range(1, 6), 22: range(1, 6),
            23: range(2, 5), 24: range(3, 4),
        }
        points = []
        for y, xs in rows.items():
            for x in xs:
                px = x if left else CHAR_W - 1 - x
                edge = x in (min(xs), max(xs)) or y in (17, 24)
                points.append((px, y, 0 if edge else (2 if (x + y) % 4 == 0 else 1)))
        return points

    if job == "spellblade":
        # 細身の刃を盾と反対側へ。正面・背面は縦、横は前方へ通す。
        if direction in (0, 3):
            side = 22 if direction == 0 else 1
            inner = side - 1 if direction == 0 else side + 1
            return (
                [(side, y, 0) for y in range(7, 19)]
                + [(inner, y, 2) for y in range(8, 17)]
                + [(inner, 19, 1), (inner - (1 if direction == 0 else -1), 20, 0)]
            )
        return (
            [(x, 11, 0) for x in range(1, 12)]
            + [(x, 12, 2) for x in range(2, 10)]
            + [(10, 13, 1), (11, 14, 0)]
        )

    if job == "ranger":
        # 左右へ張らず、縦長の弓弧と弦の負の空間で読む。
        left = direction != 0
        arc = [
            (3, 7), (2, 8), (2, 9), (1, 10), (1, 11), (1, 12),
            (1, 13), (1, 14), (1, 15), (1, 16), (1, 17), (1, 18),
            (1, 19), (1, 20), (2, 21), (2, 22), (3, 23), (3, 24),
            (4, 25),
        ]
        string = [(4, y) for y in range(9, 24)]
        points = []
        for x, y in arc:
            points.append((x if left else CHAR_W - 1 - x, y, 2))
        for x, y in string:
            points.append((x if left else CHAR_W - 1 - x, y, 0))
        return points

    if job == "sage":
        # 細い杖を右端へ通し、beastmaster の広い外套から離す。
        right = direction in (1, 2)
        x = 22 if right else 1
        inner = x - 1 if right else x + 1
        points = [(x, y, 2) for y in range(7, 28)]
        points += [(inner, y, 0) for y in range(10, 25, 3)]
        points += [
            (inner, 6, 0),
            (inner - (1 if right else -1), 5, 0),
            (x, 4, 2),
        ]
        return points

    if job == "chronomancer":
        # 骨の円環。歯車にはせず、欠けた弧を肩の外へ一つだけ置く。
        left = direction != 3
        arc = [
            (3, 7, 0), (2, 8, 0), (1, 9, 0), (1, 10, 0),
            (1, 12, 2), (1, 13, 0), (1, 14, 0), (2, 15, 0),
            (3, 16, 1), (4, 16, 0),
            (5, 15, 0), (5, 13, 2),
        ]
        return [
            (x if left else CHAR_W - 1 - x, y, tone)
            for x, y, tone in arc
        ]

    if job == "jester":
        # 道化帽ではなく、割れた仮面から片側だけ伸びる有機的な髪・角。
        right = direction != 3
        spikes = [
            (20, 6, 0), (21, 7, 2), (22, 8, 0),
            (21, 10, 0), (22, 11, 1), (21, 12, 0),
            (20, 14, 0), (22, 15, 0),
        ]
        return [
            (x if right else CHAR_W - 1 - x, y, tone)
            for x, y, tone in spikes
        ]
    return []


def _hero_feature_erase(job: str, direction: int) -> list[tuple[int, int]]:
    """得物と同じくらい重要な負の空間。密な候補の裾を役割別に切る。"""
    if job == "gunner":
        # 長銃に対して裾は直線的に絞る。獣使い・賢者の広い外套と分ける。
        if direction in (0, 3):
            points = [
                (x, y)
                for y in range(23, 29)
                for x in ([2, 3, 4, 19, 20, 21] if direction == 0 else [2, 3, 20, 21])
            ]
            # 正面の右輪郭も削り、左の長銃へ重心を寄せる。
            if direction == 0:
                points += [(x, y) for y in range(8, 22) for x in (19, 20, 21)]
            return points
        return [(x, y) for y in range(23, 28) for x in range(2, 6)]
    if job == "paladin":
        # 盾と反対側の裾を切り、左右非対称の一枚絵として読む。
        cut = range(18, 22) if direction == 0 else range(2, 6)
        points = [(x, y) for y in range(22, 28) for x in cut]
        if direction == 0:
            points += [(x, y) for y in range(9, 22) for x in (20, 21)]
        return points
    if job == "ranger":
        # 弓側に空間を残し、忍者の一体化した黒い外套から離す。
        cut = range(18, 22) if direction == 0 else range(2, 6)
        points = [(x, y) for y in range(19, 26) for x in cut]
        if direction == 0:
            # 身体と弓のあいだに1pxの空間を通し、輪郭を一体化させない。
            points += [(x, y) for y in range(10, 20) for x in (19, 20)]
        return points
    if job == "sage" and direction == 0:
        # 杖の反対側を落として縦軸を強め、獣使いの左右へ広い外套と分ける。
        return [(x, y) for y in range(8, 22) for x in (19, 20, 21)]
    if job == "chronomancer":
        # 円環の内側を空ける。塗りつぶした円盤では役割が読めない。
        left = direction != 3
        xs = (2, 3, 4) if left else (19, 20, 21)
        return [(x, y) for y in range(10, 15) for x in xs]
    if job == "jester":
        # 反対側を短く切り、忍者の左右均等な頭巾と分ける。
        left = direction != 3
        xs = (2, 3, 4) if left else (19, 20, 21)
        return [(x, y) for y in range(8, 16) for x in xs]
    return []


def _evenize_hero_sheet(sheet: Canvas) -> Canvas:
    """得物追加後の各コマを、拡大縮小せず偶数幅へ戻す。"""
    out = Canvas(sheet.w, sheet.h)
    out.blit(sheet, 0, 0)
    for direction in range(4):
        for frame in range(3):
            ox, oy = frame * CHAR_W, direction * CHAR_H
            points = [
                (x, y)
                for y in range(CHAR_H)
                for x in range(CHAR_W)
                if out.get(ox + x, oy + y) != TRANSPARENT
            ]
            if not points:
                continue
            x0, x1 = min(x for x, _y in points), max(x for x, _y in points)
            width = x1 - x0 + 1
            target_width = max(NPC_MIN_W, width + width % 2)
            target_width = min(target_width, NPC_MAX_W)
            if width == target_width:
                continue
            # 端の既存画素に必要なぶんだけ接続する。再拡大しないので密度を保てる。
            while width < target_width:
                grow_left = x0 > 1 and (x1 >= 22 or width % 2 == 1)
                edge_x = x0 if grow_left else x1
                target_x = edge_x - 1 if grow_left else edge_x + 1
                edge_rows = [
                    y
                    for y in range(CHAR_H)
                    if out.get(ox + edge_x, oy + y) != TRANSPARENT
                ]
                target_y = edge_rows[len(edge_rows) // 2]
                color = out.get(ox + edge_x, oy + target_y)
                out.set(ox + target_x, oy + target_y, color)
                x0 = min(x0, target_x)
                x1 = max(x1, target_x)
                width = x1 - x0 + 1
    return out


def _differentiate_hero(job: str, sheet: Canvas) -> Canvas:
    """候補原画へ、職の役割を示す最小限の得物シルエットを統合する。"""
    if job not in {
        "gunner", "paladin", "ranger", "sage", "chronomancer", "jester"
    }:
        return sheet
    out = Canvas(sheet.w, sheet.h)
    out.blit(sheet, 0, 0)
    for direction in range(4):
        base_points = _hero_feature_points(job, direction)
        for frame in range(3):
            ox, oy = frame * CHAR_W, direction * CHAR_H
            colors = _hero_frame_colors(sheet, ox, oy)
            mirror_side = direction == 2
            for x, y in _hero_feature_erase(job, direction):
                px = CHAR_W - 1 - x if mirror_side else x
                out.set(ox + px, oy + y, TRANSPARENT)
            for x, y, tone in base_points:
                px = CHAR_W - 1 - x if mirror_side else x
                # 偶数20/22px規格の内側だけを使う。セル端まで広げない。
                if 1 <= px <= 22 and 4 <= y <= 31:
                    out.set(ox + px, oy + y, colors[tone])
    # 得物を足した結果が21px幅になっても、拡大で原画を崩さず1pxだけ補う。
    return _evenize_hero_sheet(out)


def _verify_hero_runtime_style(job: str, sheet: Canvas) -> None:
    """全12コマがフィールド上の共通規格に入っているかを見る。"""
    for direction in range(4):
        for motion in range(3):
            frame = Canvas(CHAR_W, CHAR_H)
            ox, oy = motion * CHAR_W, direction * CHAR_H
            for y in range(CHAR_H):
                for x in range(CHAR_W):
                    frame.set(x, y, sheet.get(ox + x, oy + y))
            x0, y0, x1, y1 = _opaque_bbox(frame)
            width, height = x1 - x0 + 1, y1 - y0 + 1
            label = f"向き{direction}/コマ{motion}"
            if width not in (NPC_MIN_W, NPC_MAX_W):
                raise ValueError(
                    f"hero_{job}: {label}の実画面幅が規格外（{width}px）"
                )
            if height != NPC_TARGET_H or y1 != CHAR_H - 1:
                raise ValueError(
                    f"hero_{job}: {label}の高さ・接地が規格外"
                    f"（上{y0} 下{y1} 高さ{height}）"
                )


## 職業どうしのシルエットが重なりすぎている、とみなす基準。
##
## **前はここで平均色を測っていた。名前と中身が食い違っていた。**
## 「いまはシルエットで分ける方針」と書きながら、実際に計算していたのは
## 平均色の距離と塗り面積の差で、輪郭は一度も見ていなかった。
## そのせいで tasks.md には「ninja–thief が最悪（2.6）」と載っていたが、
## それは色の距離で、輪郭で測ると 105 組中 13 番目でしかない。
## 逆に paladin–spellblade と alchemist–summoner を見逃していた。
## **間違った組を描き直させる指標は、無いより悪い。**
##
## 生の重なり具合（IoU）では駄目だった ―― 15 職すべて人型なので
## 0.64〜0.85 に固まって差が出ない。**共通の胴体を差し引いて、
## 帽子・武器・外套といった「出っ張り」だけを比べる。**
## そうすると 0.16〜0.51 に広がり、順位が意味を持つ。
##
## 基準はその中央値（0.31）の約 1.4 倍。ここを超えると、
## 並べたときに輪郭の特徴が半分近く同じ場所にある。
MAX_HERO_FEATURE_IOU = 0.44

## 何割の職に塗られていれば「共通の胴体」とみなすか。
COMMON_BODY_SHARE = 0.8


def _silhouette(c: Canvas) -> list[bool]:
    """最初の 1 コマ（下向き・立ち）の輪郭。塗ってあるかどうかだけを見る。

    **色は見ない。** 並んだ 2 人を見分けているのは、まず輪郭だから。
    """
    return [
        c.get(x, y) != TRANSPARENT
        for y in range(CHAR_H)
        for x in range(CHAR_W)
    ]


def _report_hero_similarity(sheets: dict, baselines: dict | None = None) -> None:
    """職業の絵が似すぎている組を出す。

    **描き換えるのはこちらの仕事ではない**（docs/chara_image/ は外の領分）。
    だが似ていることは測れるので、気づける形にしておく。
    目で 15 枚を見比べるのは現実的でなく、実際にとうぞくと忍者が
    ほぼ同じ絵のまま通っていた。
    """
    names = sorted(sheets)
    if len(names) < 2:
        return
    marks = {name: _silhouette(sheets[name]) for name in names}
    # 共通胴体の判定元は、得物を足す前の正規化済み候補に固定する。
    # 成果物から毎回求めると、5職を直しただけで無関係な別の組の core が動き、
    # Gate の標的が生成のたびに入れ替わっていた。
    core_source = baselines if baselines is not None else sheets
    core_marks = {name: _silhouette(core_source[name]) for name in names}
    size = CHAR_W * CHAR_H

    # 共通の胴体。ほとんどの職で塗られている画素は、描き分けに寄与しない。
    need = COMMON_BODY_SHARE * len(names)
    core = [
        sum(core_marks[name][i] for name in names) >= need
        for i in range(size)
    ]
    feature = {
        name: [marks[name][i] and not core[i] for i in range(size)]
        for name in names
    }

    pairs = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            fa, fb = feature[a], feature[b]
            both = sum(1 for x, y in zip(fa, fb) if x and y)
            either = sum(1 for x, y in zip(fa, fb) if x or y)
            iou = both / float(max(either, 1))
            if iou >= MAX_HERO_FEATURE_IOU:
                # 色も添える。**判定には使わない**が、輪郭が近いうえに色まで
                # 近ければ、並べたときの見分けにくさは桁が違う。
                gap = math.dist(_mean_rgb(sheets[a]), _mean_rgb(sheets[b]))
                pairs.append((iou, gap, a, b))

    thin = [n for n in names if sum(feature[n]) < size * 0.06]
    if thin:
        # 出っ張りが無い職は、どの相手とも見分けにくい。組では出てこない。
        print(
            "  職業の描き分け: 特徴の少ない職 %s（胴体だけで、帽子や得物の輪郭が無い）"
            % "、".join(sorted(thin))
        )

    if not pairs:
        print("  職業の描き分け: OK（輪郭が重なりすぎている組は無い）")
        return
    pairs.sort(reverse=True)
    print(
        "  職業の描き分け: 輪郭が近い %d 組（共通の胴体を除いた重なり、基準 %.2f 未満）"
        % (len(pairs), MAX_HERO_FEATURE_IOU)
    )
    for iou, gap, a, b in pairs:
        print("    %-13s %-13s 重なり %.3f（色の距離 %.1f）" % (a, b, iou, gap))
    raise ValueError(
        "職業の輪郭が近すぎる組が %d 組ある（基準 %.2f 未満へ描き分ける）"
        % (len(pairs), MAX_HERO_FEATURE_IOU)
    )


def _ink_ratio(c: Canvas) -> float:
    """透明でない画素の割合。シルエットの太さの目安。"""
    drawn = sum(1 for px in c.px if px[3])
    return drawn / float(max(len(c.px), 1))


## 戦闘背景。512x176 で、戦場（空と地面）をそのまま覆う。
##
## 生物相ごとに 1 枚。**欠けていても落ちない** ―― ゲーム側は
## 「あれば使う、無ければ階調背景」で拾う。
BATTLE_BACKGROUNDS = [
    "grassland_twilight", "drowned_wetland", "snowfield_ruins",
    "volcanic_caldera", "dungeon_depths", "imperial_foundry",
]

BATTLE_BG_SIZE = (512, 176)


## 戦闘エフェクト。32x32 の 4 コマを横に並べた 128x32。
##
## 技の系統（斬・突・魔法）と属性（炎・氷・雷・毒）で選ぶ。
## **欠けていても落ちない** ―― 無ければ従来の点滅と数字だけになる。
BATTLE_FX = [
    "slash", "thrust", "fire", "ice", "bolt", "poison",
    "sleep", "buff", "debuff", "explosion", "gunshot", "heal",
]

FX_SIZE = (128, 32)


def build_battle_fx() -> None:
    for name in BATTLE_FX:
        sheet = _load_sheet(f"candidate_fx_{name}", FX_SIZE)
        if sheet is None:
            continue
        sheet.to_png(ASSETS / "effects" / f"fx_{name}.png")
    print(f"  取り込み: 戦闘エフェクト {len(BATTLE_FX)} 種")


def build_battle_backgrounds() -> None:
    for name in BATTLE_BACKGROUNDS:
        sheet = _load_sheet(f"candidate_battle_bg_{name}", BATTLE_BG_SIZE)
        if sheet is None:
            continue
        sheet.to_png(ASSETS / "backgrounds" / f"battle_bg_{name}.png")
        print(f"  取り込み: battle_bg_{name}.png")


def build_npcs() -> None:
    contact = Canvas(CHAR_W * 6, CHAR_H * 3)
    made = 0
    for i, role in enumerate(NPC_ROLES):
        sheet = _load_sheet(f"candidate_npc_{role}", (24, 32))
        if sheet is None:
            continue
        sheet = _prepare_npc(role, sheet)
        _verify_sheet(f"npc_{role}", sheet, (24, 32))
        _verify_npc_runtime_style(role, sheet)
        sheet.to_png(ASSETS / "sprites" / f"npc_{role}.png")
        sheet.scaled(4).to_png(PREVIEW / f"npc_{role}.png")
        contact.blit(sheet, (i % 6) * CHAR_W, (i // 6) * CHAR_H)
        made += 1
        print(f"  取り込み: npc_{role}.png")
    contact.scaled(4).to_png(PREVIEW / "npc_runtime_contact.png")
    print(
        "  NPC実画面規格: %d種（幅%dまたは%d / 高さ%d / 下端接地）"
        % (made, NPC_MIN_W, NPC_MAX_W, NPC_TARGET_H)
    )


# 非戦闘イベント用の 4 コマ演出と、画面全体を覆う 8 コマ遷移。
# 候補画像を正寸の横一列アトラスにしておき、再生側はフレーム幅だけを知ればよい。
EVENT_EFFECTS = [
    "world_gate",
    "seal_break",
    "chronicle_echo",
    "imperial_alarm",
]
TRANSITIONS = [
    "pixel_dissolve",
    "iris_gate",
    "page_turn",
    "gear_shutter",
]
EVENT_EFFECT_SIZE = (48 * 4, 48)
TRANSITION_SIZE = (64 * 8, 40)


def build_event_effects() -> None:
    for effect in EVENT_EFFECTS:
        sheet = _load_sheet(f"candidate_event_fx_{effect}", EVENT_EFFECT_SIZE)
        if sheet is None:
            continue
        sheet.to_png(ASSETS / "effects" / f"event_{effect}.png")
        sheet.scaled(4).to_png(PREVIEW / f"event_fx_{effect}.png")
        print(f"  取り込み: event_{effect}.png")


def _transition_frame(sheet: Canvas, index: int) -> Canvas:
    """8 コマのアトラスから 64x40 の 1 コマを取り出す。"""
    frame = Canvas(64, 40)
    for y in range(frame.h):
        for x in range(frame.w):
            frame.set(x, y, sheet.get(index * frame.w + x, y))
    return frame


def _edge_intro(frame: Canvas, fraction: float) -> Canvas:
    """外周側から絵を半分だけ見せる導入コマ。

    アイリス／シャッターの元絵は最初のコマですでに画面の 4 割前後を覆う。
    そのまま再生すると「突然部品が出た」ように見えるため、左右上下を一組に
    した帯を外から入れる。対称の組を崩さないので輪郭は歪まない。
    """
    opaque = {
        (x, y) for y in range(frame.h) for x in range(frame.w)
        if frame.get(x, y)[3] != 0
    }
    target = max(1, int(len(opaque) * fraction))
    groups: list[set[tuple[int, int]]] = []
    seen: set[tuple[int, int]] = set()
    for x, y in sorted(opaque):
        if (x, y) in seen:
            continue
        orbit = {
            p for p in {
                (x, y), (frame.w - 1 - x, y),
                (x, frame.h - 1 - y),
                (frame.w - 1 - x, frame.h - 1 - y),
            } if p in opaque
        }
        seen.update(orbit)
        groups.append(orbit)
    groups.sort(key=lambda g: min(
        min(x, frame.w - 1 - x, y, frame.h - 1 - y) for x, y in g
    ))

    keep: set[tuple[int, int]] = set()
    for group in groups:
        keep.update(group)
        if len(keep) >= target:
            break
    out = Canvas(frame.w, frame.h)
    for x, y in keep:
        out.set(x, y, frame.get(x, y))
    return out


def _right_intro(frame: Canvas, fraction: float) -> Canvas:
    """右から入るページを途中まで見せる。"""
    opaque = [
        (x, y) for y in range(frame.h) for x in range(frame.w)
        if frame.get(x, y)[3] != 0
    ]
    opaque.sort(key=lambda p: (-p[0], p[1]))
    out = Canvas(frame.w, frame.h)
    for x, y in opaque[:max(1, int(len(opaque) * fraction))]:
        out.set(x, y, frame.get(x, y))
    return out


def _dissolve_between(base: Canvas, filled: Canvas, fraction: float) -> Canvas:
    """角形の千鳥順で、base と filled の中間を作る。

    Web のマイクロトランジションにある staggered grid を、連続的な拡縮ではなく
    4x4 画素の離散セルへ翻訳したもの。乱数は使わず生成結果を固定する。
    """
    out = Canvas(base.w, base.h)
    out.blit(base, 0, 0)
    limit = int(max(0.0, min(1.0, fraction)) * 16)
    for y in range(filled.h):
        for x in range(filled.w):
            if out.get(x, y)[3] != 0 or filled.get(x, y)[3] == 0:
                continue
            # 4x4 セルごとの固定順。隣のセルが同時に出ないよう位相をずらす。
            rank = ((x // 4) * 5 + (y // 4) * 3) % 16
            if rank < limit:
                out.set(x, y, filled.get(x, y))
    return out


def _solid_last(frame: Canvas) -> Canvas:
    """最後のコマを完全に覆う。色は元絵の最多色だけを使い、色数を増やさない。"""
    counts: dict[tuple[int, int, int, int], int] = {}
    for color in frame.px:
        if color[3] != 0:
            counts[color] = counts.get(color, 0) + 1
    fill = max(counts, key=counts.get) if counts else snes("#080C18") + (255,)
    out = Canvas(frame.w, frame.h)
    for i, color in enumerate(frame.px):
        out.px[i] = color if color[3] != 0 else fill
    return out


def _prepare_transition_sheet(name: str, sheet: Canvas) -> Canvas:
    """導入 0% → 終端 100% を保証し、状態ごとの拍へ並べ直す。

    原画は読み取り専用のまま残す。生成物だけを整えることで、同じ入力から
    常に同じアセットを再生成できる。
    """
    src = [_transition_frame(sheet, i) for i in range(8)]
    blank = Canvas(64, 40)
    if name in {"iris_gate", "gear_shutter"}:
        frames = [
            blank, _edge_intro(src[0], 0.5), src[0], src[1],
            src[2], src[3], src[4], _solid_last(src[7]),
        ]
    elif name == "page_turn":
        frames = [
            blank, src[0], _right_intro(src[1], 0.5), src[1],
            src[2], src[3], src[4], _solid_last(src[7]),
        ]
    else:
        frames = [
            blank, src[0], src[1], src[2], src[3], src[4],
            _dissolve_between(src[4], src[5], 0.55), _solid_last(src[7]),
        ]

    # 覆いは増えるだけ。原画側に小さな穴の戻りがあっても前コマで埋め、
    # 再生中のちらつきを防ぐ。
    for i in range(1, len(frames)):
        for p, color in enumerate(frames[i - 1].px):
            if color[3] != 0 and frames[i].px[p][3] == 0:
                frames[i].px[p] = color

    out = Canvas(TRANSITION_SIZE[0], TRANSITION_SIZE[1])
    for i, frame in enumerate(frames):
        out.blit(frame, i * frame.w, 0)

    coverage = [
        sum(p[3] != 0 for p in frame.px) / len(frame.px) for frame in frames
    ]
    if coverage[0] != 0.0 or coverage[-1] != 1.0:
        raise ValueError(f"{name}: 遷移は透明から全面覆いまで必要（{coverage}）")
    if any(a > b for a, b in zip(coverage, coverage[1:])):
        raise ValueError(f"{name}: 覆い率が途中で戻っている（{coverage}）")
    print("    %s: 覆い率 %s" % (
        name, " → ".join(f"{round(value * 100):d}%" for value in coverage)
    ))
    return out


def build_transitions() -> None:
    for transition in TRANSITIONS:
        sheet = _load_sheet(f"candidate_transition_{transition}", TRANSITION_SIZE)
        if sheet is None:
            continue
        sheet = _prepare_transition_sheet(transition, sheet)
        _verify_sheet(f"transition_{transition}", sheet, TRANSITION_SIZE)
        sheet.to_png(ASSETS / "transitions" / f"{transition}.png")
        sheet.scaled(2).to_png(PREVIEW / f"transition_{transition}.png")
        print(f"  取り込み: transition/{transition}.png")


def build_heroes() -> None:
    made: dict = {}
    baselines: dict = {}
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
        imported = _load_sheet(f"candidate_hero_{job}", HERO_SHEET_SIZE)
        if imported is not None:
            imported = _prepare_hero_sheet(job, imported)
            baselines[job] = imported
            imported = _differentiate_hero(job, imported)
            _verify_sheet(f"hero_{job}", imported, HERO_SHEET_SIZE)
            _verify_hero_runtime_style(job, imported)
            imported.to_png(ASSETS / "sprites" / f"hero_{job}.png")
            made[job] = imported
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
        baselines[job] = sheet
        sheet.to_png(ASSETS / "sprites" / f"hero_{job}.png")
        made[job] = sheet
        sheet.scaled(4).to_png(PREVIEW / f"hero_{job}.png")
    contact = Canvas(CHAR_W * 5, CHAR_H * 3)
    for i, job in enumerate(HERO_ACCENTS):
        frame = Canvas(CHAR_W, CHAR_H)
        for y in range(CHAR_H):
            for x in range(CHAR_W):
                frame.set(x, y, made[job].get(x, y))
        contact.blit(frame, (i % 5) * CHAR_W, (i // 5) * CHAR_H)
    contact.scaled(4).to_png(PREVIEW / "hero_runtime_contact.png")
    _report_hero_similarity(made, baselines)

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


## 敵の絵の上限。これを超えるものは戦闘画面に収まらない。
MONSTER_MAX = (64, 64)

## 外で描いた絵しか持たない敵。ASCII の下絵は用意していないので、
## 素材が無ければその敵は生成されない（data/monsters.json 側で使わなければよい）。
IMPORTED_MONSTERS = [
    "arcane_hound", "lantern_mimic", "plague_moth", "crystal_drake",
    "ruin_automaton", "ember_wraith", "frost_stalker", "mire_oracle",
    "fungal_knight", "void_scribe", "chain_ogre", "shattered_seraph",
    # 帝国。深い階の主役になる一団で、機械と兵科で揃えてある。
    "lancer", "rifleman", "officer", "medic", "magus", "sapper",
    "clockwork_hound", "boiler_automaton", "sentry_orb", "ash_revenant",
    "iron_cavalier", "siege_walker",
]

## 主。名前は candidate_boss_<ID>.png / candidate_imperial_boss_<ID>.png で探す。
IMPORTED_BOSSES = [
    "thorn_crowned_king", "crucible_colossus", "frostbound_oracle",
    "iron_margrave", "land_dreadnought", "aetheric_war_engine",
]


def _load_monster_sheet(name: str) -> Canvas | None:
    """外で描いた敵の絵を読む。無ければ None（＝ ASCII マップから起こす）。

    敵は 1 体ずつ寸法が違う（ゲルは 48x40、主は 64x64）ので、
    寸法は候補のものをそのまま受け取り、上限だけを見る。
    """
    # 素材の名前は置いた側の都合で揺れる。探す順だけ決めて、あるものを拾う。
    stems = (
        f"candidate_enemy_{name}_refined",
        f"candidate_enemy_{name}",
        f"candidate_imperial_enemy_{name}",
        f"candidate_boss_{name}",
        f"candidate_imperial_boss_{name}",
    )
    for stem in stems:
        path = HERO_SOURCE_DIR / f"{stem}.png"
        if not path.exists():
            continue
        sheet, moved = _quantize(load_png(path))
        if sheet.w > MONSTER_MAX[0] or sheet.h > MONSTER_MAX[1]:
            raise ValueError(
                "%s: %dx%d は大きすぎる（上限 %dx%d）"
                % (stem, sheet.w, sheet.h, MONSTER_MAX[0], MONSTER_MAX[1])
            )
        _verify_sheet(stem, sheet, (sheet.w, sheet.h))
        if moved:
            print(f"    {stem}: {moved} 色を BGR555 へ丸めた")
        print(f"  取り込み: {name}.png（chara_image/{stem}.png）")
        return sheet
    return None


## 外で描いた絵だけで成り立つ敵を書き出す。
def build_imported_monsters() -> None:
    for name in IMPORTED_MONSTERS:
        sheet = _load_monster_sheet(name)
        if sheet is not None:
            sheet.to_png(ASSETS / "sprites" / f"{name}.png")
            sheet.scaled(4).to_png(PREVIEW / f"{name}.png")
    for name in IMPORTED_BOSSES:
        path = HERO_SOURCE_DIR / f"candidate_boss_{name}.png"
        if not path.exists():
            path = HERO_SOURCE_DIR / f"candidate_imperial_boss_{name}.png"
        if not path.exists():
            continue
        sheet, moved = _quantize(load_png(path))
        _verify_sheet(f"candidate_boss_{name}", sheet, (sheet.w, sheet.h))
        if sheet.w > MONSTER_MAX[0] or sheet.h > MONSTER_MAX[1]:
            raise ValueError("candidate_boss_%s: %dx%d は大きすぎる" % (name, sheet.w, sheet.h))
        if moved:
            print(f"    candidate_boss_{name}: {moved} 色を BGR555 へ丸めた")
        sheet.to_png(ASSETS / "sprites" / f"{name}.png")
        sheet.scaled(4).to_png(PREVIEW / f"{name}.png")
        print(f"  取り込み: {name}.png（chara_image/candidate_boss_{name}.png）")


def _emit_monster(name: str, half: Canvas) -> None:
    # 外で描いた絵があればそれを使う（鏡像で綴じる必要が無い）。
    imported = _load_monster_sheet(name)
    if imported is not None:
        imported.to_png(ASSETS / "sprites" / f"{name}.png")
        imported.scaled(4).to_png(PREVIEW / f"{name}.png")
        return

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
    # 版の刻印を先に更新する。**手で上げる番号は当てにしない**ので、
    # 生成を回すたびに git の commit を写しておく（tools/stamp_version.py）。
    try:
        import stamp_version
        stamp_version.main()
    except Exception as exc:  # 刻印に失敗しても絵の生成は続ける
        print(f"  版の刻印を飛ばした: {exc}")
    build_tileset()
    build_world_tileset()
    build_biomes()
    build_town_tilesets()
    build_battle_fx()
    build_battle_backgrounds()
    build_npcs()
    build_event_effects()
    build_transitions()
    build_heroes()
    build_blob("gel", GEL, width=24, height=40)
    build_monster("bat", BAT_HALF, BAT, width=24)
    build_monster("skull", SKULL_HALF, BONE, width=24)
    build_monster("shade", SHADE_HALF, SHADE, width=24)
    build_monster("golem", GOLEM_HALF, GOLEM, width=24)
    build_monster("warden", WARDEN_HALF, WARDEN, width=32)
    build_imported_monsters()
    build_window()
    build_cursor()
    print("生成完了:")
    for p in sorted(ASSETS.rglob("*.png")):
        print(f"  {p.relative_to(ROOT)}")


def _run_broken_hero_gate() -> None:
    """輪郭Gateの違反fixture。同じ輪郭を2職へ入れ、終了コード1にする。"""
    baselines: dict = {}
    for job in HERO_ACCENTS:
        source = _load_sheet(f"candidate_hero_{job}", HERO_SHEET_SIZE)
        if source is None:
            raise ValueError(f"違反fixtureに必要な hero_{job} が無い")
        baselines[job] = _prepare_hero_sheet(job, source)
    broken = dict(baselines)
    broken["spellblade"] = baselines["paladin"]
    _report_hero_similarity(broken, baselines)
    raise RuntimeError("違反fixtureを輪郭Gateが見逃した")


if __name__ == "__main__":
    if "--broken-hero-gate" in sys.argv:
        _run_broken_hero_gate()
    else:
        main()
