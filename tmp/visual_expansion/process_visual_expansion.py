from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(r"C:\LocalWork\Prj\RetroRogueRPG")
DOCS = ROOT / "docs" / "chara_image"
TMP = ROOT / "tmp" / "visual_expansion"

BACKGROUNDS = [
    ("dungeon_depths", "DUNGEON DEPTHS"),
    ("snowfield_ruins", "SNOWFIELD RUINS"),
    ("grassland_twilight", "GRASSLAND TWILIGHT"),
    ("volcanic_caldera", "VOLCANIC CALDERA"),
    ("drowned_wetland", "DROWNED WETLAND"),
    ("imperial_foundry", "IMPERIAL FOUNDRY"),
]

FX = [
    ("slash", "SLASH"),
    ("thrust", "THRUST"),
    ("gunshot", "GUNSHOT"),
    ("explosion", "EXPLOSION"),
    ("fire", "FIRE"),
    ("ice", "ICE"),
    ("bolt", "BOLT"),
    ("heal", "HEAL"),
    ("poison", "POISON"),
    ("sleep", "SLEEP"),
    ("buff", "BUFF"),
    ("debuff", "DEBUFF"),
]

PROPS = [
    ("beast_cage", "BEAST CAGE"),
    ("restraint_post", "RESTRAINT POST"),
    ("feed_trough", "FEED TROUGH"),
    ("pipe_valve", "PIPE VALVE"),
    ("specimen_vat", "SPECIMEN VAT"),
    ("command_pylon", "COMMAND PYLON"),
    ("supply_crate", "SUPPLY CRATE"),
    ("imperial_banner", "IMPERIAL BANNER"),
    ("chain_bundle", "CHAIN BUNDLE"),
    ("incubator_egg", "INCUBATOR EGG"),
    ("broken_harness", "BROKEN HARNESS"),
    ("furnace_vent", "FURNACE VENT"),
]


def sfc_channel(value: int) -> int:
    return (value >> 3) * 255 // 31


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in [
        Path(r"C:\Windows\Fonts\segoeuib.ttf"),
        Path(r"C:\Windows\Fonts\arialbd.ttf"),
    ]:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def quantize_rgb_sfc(image: Image.Image, colors: int = 15) -> Image.Image:
    rgb = image.convert("RGB")
    quantized = rgb.quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    output = Image.new("RGBA", quantized.size)
    output.putdata(
        [
            (sfc_channel(r), sfc_channel(g), sfc_channel(b), 255)
            for r, g, b in quantized.getdata()
        ]
    )
    return output


def quantize_rgba_sfc(image: Image.Image, colors: int = 15) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = list(rgba.getdata())
    visible = [(r, g, b) for r, g, b, a in pixels if a >= 128]
    if not visible:
        raise ValueError("image has no visible pixels")

    strip = Image.new("RGB", (len(visible), 1))
    strip.putdata(visible)
    quantized = strip.quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    mapped = iter(quantized.getdata())

    output_pixels = []
    for _r, _g, _b, alpha in pixels:
        if alpha < 128:
            output_pixels.append((0, 0, 0, 0))
            continue
        r, g, b = next(mapped)
        output_pixels.append(
            (sfc_channel(r), sfc_channel(g), sfc_channel(b), 255)
        )
    output = Image.new("RGBA", rgba.size)
    output.putdata(output_pixels)
    return output


def alpha_crop(image: Image.Image, threshold: int = 16) -> Image.Image:
    rgba = image.convert("RGBA")
    mask = rgba.getchannel("A").point(lambda alpha: 255 if alpha >= threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("empty alpha subject")
    return rgba.crop(bbox)


def fit_subject(
    subject: Image.Image,
    cell_size: tuple[int, int],
    max_size: tuple[int, int],
    scale: float | None = None,
) -> Image.Image:
    max_w, max_h = max_size
    if scale is None:
        scale = min(max_w / subject.width, max_h / subject.height)
    size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    reduced = subject.resize(size, Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", cell_size, (0, 0, 0, 0))
    x = (cell_size[0] - size[0]) // 2
    y = (cell_size[1] - size[1]) // 2
    cell.alpha_composite(reduced, (x, y))
    return cell


def process_backgrounds() -> dict[str, Image.Image]:
    results: dict[str, Image.Image] = {}
    target_ratio = 512 / 176
    for asset_id, _label in BACKGROUNDS:
        source = Image.open(
            DOCS / f"candidate_battle_bg_{asset_id}_source.png"
        ).convert("RGB")
        ratio = source.width / source.height
        if ratio > target_ratio:
            crop_w = round(source.height * target_ratio)
            x0 = (source.width - crop_w) // 2
            source = source.crop((x0, 0, x0 + crop_w, source.height))
        elif ratio < target_ratio:
            crop_h = round(source.width / target_ratio)
            y0 = (source.height - crop_h) // 2
            source = source.crop((0, y0, source.width, y0 + crop_h))
        reduced = source.resize((512, 176), Image.Resampling.LANCZOS)
        final = quantize_rgb_sfc(reduced)
        final.save(DOCS / f"candidate_battle_bg_{asset_id}.png")
        results[asset_id] = final

    contact = Image.new("RGB", (1056, 660), (12, 13, 21))
    draw = ImageDraw.Draw(contact)
    label_font = font(21)
    for index, (asset_id, label) in enumerate(BACKGROUNDS):
        col, row = index % 2, index // 2
        x, y = 8 + col * 528, 36 + row * 218
        image = results[asset_id].convert("RGB")
        contact.paste(image, (x, y))
        draw.text((x, y - 28), label, fill=(222, 210, 186), font=label_font)
    contact.save(DOCS / "candidate_battle_backgrounds_6_contact.png")
    make_background_mockups(results)
    return results


def make_background_mockups(backgrounds: dict[str, Image.Image]) -> None:
    screenshot_path = ROOT / "docs" / "preview" / "screen_battle.png"
    screenshot = Image.open(screenshot_path).convert("RGBA")
    enemy = Image.open(ROOT / "assets" / "sprites" / "arcane_hound.png").convert("RGBA")
    top_ui = screenshot.crop((0, 0, 512, 30))
    lower_ui = screenshot.crop((0, 176, 512, 320))
    mockups = Image.new("RGB", (1024, 960), (8, 9, 15))
    for index, (asset_id, _label) in enumerate(BACKGROUNDS):
        frame = Image.new("RGBA", (512, 320), (0, 0, 0, 255))
        frame.alpha_composite(backgrounds[asset_id], (0, 0))
        enemy_x = (512 - enemy.width) // 2
        frame.alpha_composite(enemy, (enemy_x, 168 - enemy.height))
        frame.alpha_composite(top_ui, (0, 0))
        frame.alpha_composite(lower_ui, (0, 176))
        col, row = index % 2, index // 2
        mockups.paste(frame.convert("RGB"), (col * 512, row * 320))
    mockups.save(DOCS / "candidate_battle_backgrounds_game_mockup.png")


def process_fx() -> dict[str, Image.Image]:
    results: dict[str, Image.Image] = {}
    for asset_id, _label in FX:
        source = Image.open(TMP / "fx" / f"{asset_id}.png").convert("RGBA")
        frames: list[Image.Image] = []
        for index in range(4):
            x0 = round(index * source.width / 4)
            x1 = round((index + 1) * source.width / 4)
            frames.append(alpha_crop(source.crop((x0, 0, x1, source.height))))
        global_scale = min(
            30 / max(frame.width for frame in frames),
            30 / max(frame.height for frame in frames),
        )
        sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            cell = fit_subject(frame, (32, 32), (30, 30), global_scale)
            sheet.alpha_composite(cell, (index * 32, 0))
        final = quantize_rgba_sfc(sheet)
        validate_transparent(final, (128, 32), asset_id, frame_count=4)
        final.save(DOCS / f"candidate_fx_{asset_id}.png")
        results[asset_id] = final

        enlarged = final.resize((768, 192), Image.Resampling.NEAREST)
        preview = Image.new("RGBA", enlarged.size, (15, 15, 24, 255))
        preview.alpha_composite(enlarged)
        preview.convert("RGB").save(DOCS / f"candidate_fx_{asset_id}_preview.png")

    contact = Image.new("RGB", (1584, 656), (15, 15, 24))
    draw = ImageDraw.Draw(contact)
    label_font = font(21)
    for index, (asset_id, label) in enumerate(FX):
        col, row = index % 3, index // 3
        x, y = col * 528 + 8, row * 164 + 35
        enlarged = results[asset_id].resize((512, 128), Image.Resampling.NEAREST)
        card = Image.new("RGBA", enlarged.size, (15, 15, 24, 255))
        card.alpha_composite(enlarged)
        contact.paste(card.convert("RGB"), (x, y))
        draw.text((x, y - 27), label, fill=(222, 210, 186), font=label_font)
    contact.save(DOCS / "candidate_battle_fx_12_contact.png")
    return results


def process_props() -> dict[str, Image.Image]:
    unquantized = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
    for index, (asset_id, _label) in enumerate(PROPS):
        subject = alpha_crop(Image.open(TMP / "props" / f"{asset_id}.png"))
        cell = fit_subject(subject, (32, 32), (30, 30))
        x, y = (index % 4) * 32, (index // 4) * 32
        unquantized.alpha_composite(cell, (x, y))

    atlas = quantize_rgba_sfc(unquantized)
    validate_transparent(atlas, (128, 96), "imperial_props_atlas")
    atlas.save(DOCS / "candidate_imperial_props_12_atlas.png")

    results: dict[str, Image.Image] = {}
    for index, (asset_id, _label) in enumerate(PROPS):
        x, y = (index % 4) * 32, (index // 4) * 32
        prop = atlas.crop((x, y, x + 32, y + 32))
        validate_transparent(prop, (32, 32), asset_id)
        prop.save(DOCS / f"candidate_imperial_prop_{asset_id}.png")
        results[asset_id] = prop
        enlarged = prop.resize((256, 256), Image.Resampling.NEAREST)
        preview = Image.new("RGBA", enlarged.size, (15, 15, 24, 255))
        preview.alpha_composite(enlarged)
        preview.convert("RGB").save(
            DOCS / f"candidate_imperial_prop_{asset_id}_preview.png"
        )

    contact = Image.new("RGB", (1104, 876), (15, 15, 24))
    draw = ImageDraw.Draw(contact)
    label_font = font(19)
    for index, (asset_id, label) in enumerate(PROPS):
        col, row = index % 4, index // 4
        x, y = col * 276 + 10, row * 292 + 34
        enlarged = results[asset_id].resize((256, 256), Image.Resampling.NEAREST)
        card = Image.new("RGBA", enlarged.size, (15, 15, 24, 255))
        card.alpha_composite(enlarged)
        contact.paste(card.convert("RGB"), (x, y))
        draw.text((x, y - 27), label, fill=(222, 210, 186), font=label_font)
    contact.save(DOCS / "candidate_imperial_props_12_contact.png")
    make_prop_map_mockup(results)
    return results


def make_prop_map_mockup(props: dict[str, Image.Image]) -> None:
    tiles = Image.open(ROOT / "assets" / "tiles" / "dungeon.png").convert("RGBA")
    floor = tiles.crop((0, 0, 16, 16))
    wall = tiles.crop((32, 0, 48, 16))
    mockup = Image.new("RGBA", (512, 320), (0, 0, 0, 255))
    for y in range(0, 320, 16):
        for x in range(0, 512, 16):
            border = x in (0, 16, 480, 496) or y in (0, 16, 288, 304)
            mockup.alpha_composite(wall if border else floor, (x, y))

    positions = [
        (40, 48), (120, 48), (200, 48), (280, 48), (360, 48), (440, 48),
        (40, 208), (120, 208), (200, 208), (280, 208), (360, 208), (440, 208),
    ]
    for (asset_id, _label), position in zip(PROPS, positions):
        mockup.alpha_composite(props[asset_id], position)
    mockup.convert("RGB").save(DOCS / "candidate_imperial_props_map_mockup.png")


def validate_transparent(
    image: Image.Image,
    expected_size: tuple[int, int],
    asset_id: str,
    frame_count: int | None = None,
) -> None:
    if image.size != expected_size:
        raise AssertionError(f"{asset_id}: unexpected size {image.size}")
    pixels = list(image.getdata())
    alphas = sorted({alpha for _r, _g, _b, alpha in pixels})
    colors = {(r, g, b) for r, g, b, alpha in pixels if alpha == 255}
    bgr555 = all(
        channel == sfc_channel(channel)
        for color in colors
        for channel in color
    )
    corners = [
        image.getpixel((0, 0))[3],
        image.getpixel((image.width - 1, 0))[3],
        image.getpixel((0, image.height - 1))[3],
        image.getpixel((image.width - 1, image.height - 1))[3],
    ]
    frames_ok = True
    if frame_count is not None:
        frame_w = image.width // frame_count
        frames_ok = all(
            image.crop((index * frame_w, 0, (index + 1) * frame_w, image.height))
            .getchannel("A")
            .getbbox()
            is not None
            for index in range(frame_count)
        )
    passed = (
        len(colors) <= 15
        and alphas == [0, 255]
        and bgr555
        and all(alpha == 0 for alpha in corners)
        and frames_ok
    )
    print(
        f"{asset_id}: size={image.size} colors={len(colors)} alpha={alphas} "
        f"bgr555={bgr555} corners={corners} frames_ok={frames_ok} PASS={passed}"
    )
    if not passed:
        raise AssertionError(f"{asset_id}: validation failed")


def validate_background(image: Image.Image, asset_id: str) -> None:
    pixels = list(image.getdata())
    colors = {(r, g, b) for r, g, b, _alpha in pixels}
    alphas = sorted({_alpha for _r, _g, _b, _alpha in pixels})
    bgr555 = all(
        channel == sfc_channel(channel)
        for color in colors
        for channel in color
    )
    passed = (
        image.size == (512, 176)
        and len(colors) <= 15
        and alphas == [255]
        and bgr555
    )
    print(
        f"{asset_id}: size={image.size} colors={len(colors)} alpha={alphas} "
        f"bgr555={bgr555} PASS={passed}"
    )
    if not passed:
        raise AssertionError(f"{asset_id}: validation failed")


def main() -> None:
    backgrounds = process_backgrounds()
    for asset_id, _label in BACKGROUNDS:
        validate_background(backgrounds[asset_id], asset_id)
    process_fx()
    process_props()


if __name__ == "__main__":
    main()
