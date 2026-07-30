from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "chara_image"
TMP = ROOT / "tmp" / "imperial_assets"

SOLDIERS = [
    "rifleman", "lancer", "officer", "magus", "medic", "sapper",
]
MACHINES = [
    "clockwork_hound", "sentry_orb", "boiler_automaton",
    "siege_walker", "iron_cavalier", "ash_revenant",
]
BOSSES = [
    "land_dreadnought", "iron_margrave", "aetheric_war_engine",
]


def q5(value: int) -> int:
    n = max(0, min(31, round(value * 31 / 255)))
    return (n << 3) | (n >> 2)


def bgr555(color: tuple[int, int, int]) -> tuple[int, int, int]:
    return tuple(q5(value) for value in color)


def quantize(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    visible = [(r, g, b) for r, g, b, a in rgba.getdata() if a >= 128]
    sample = Image.new("RGB", (len(visible), 1))
    sample.putdata(visible)
    indexed = sample.quantize(
        colors=15,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    raw = indexed.getpalette()
    palette = []
    for index in sorted(set(indexed.getdata())):
        base = index * 3
        palette.append(bgr555(tuple(raw[base : base + 3])))
    palette = list(dict.fromkeys(palette))
    for required in (
        bgr555(min(visible, key=sum)),
        bgr555(max(visible, key=sum)),
    ):
        if required in palette:
            continue
        if len(palette) < 15:
            palette.append(required)
        else:
            palette[0 if sum(required) < 200 else -1] = required

    output = Image.new("RGBA", rgba.size)
    result = []
    for r, g, b, a in rgba.getdata():
        if a < 128:
            result.append((0, 0, 0, 0))
            continue
        nearest = min(
            palette,
            key=lambda c: (r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2,
        )
        result.append((*nearest, 255))
    output.putdata(result)
    return output


def paths(name: str, boss: bool) -> tuple[Path, Path, Path]:
    kind = "boss" if boss else "enemy"
    stem = f"candidate_imperial_{kind}_{name}"
    transparent = TMP / f"{stem}_source_transparent.png"
    return transparent, DOCS / f"{stem}.png", DOCS / f"{stem}_preview.png"


def process(name: str, boss: bool) -> Image.Image:
    size = (64, 64) if boss else (48, 48)
    transparent, final_path, preview_path = paths(name, boss)
    source = Image.open(transparent).convert("RGBA")
    bbox = source.getchannel("A").point(lambda a: 255 if a >= 72 else 0).getbbox()
    if bbox is None:
        raise RuntimeError(f"No subject: {name}")
    subject = source.crop(bbox)
    scale = min((size[0] - 2) / subject.width, (size[1] - 2) / subject.height)
    target = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(target, Image.Resampling.LANCZOS)
    alpha = subject.getchannel("A").point(lambda a: 255 if a >= 72 else 0)
    rgb = ImageEnhance.Contrast(subject.convert("RGB")).enhance(1.08)
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=0.65, percent=130, threshold=2))
    subject = rgb.convert("RGBA")
    subject.putalpha(alpha)

    canvas = Image.new("RGBA", size)
    canvas.alpha_composite(
        subject,
        ((size[0] - subject.width) // 2, size[1] - 1 - subject.height),
    )
    canvas = quantize(canvas)
    canvas.save(final_path)

    factor = 6 if boss else 8
    preview_size = (size[0] * factor, size[1] * factor)
    preview = Image.new("RGBA", preview_size, (18, 17, 25, 255))
    preview.alpha_composite(canvas.resize(preview_size, Image.Resampling.NEAREST))
    preview.save(preview_path)
    return canvas


def make_contact(
    filename: str,
    names: list[str],
    images: dict[str, Image.Image],
    columns: int,
    factor: int,
) -> None:
    cell = 64
    rows = (len(names) + columns - 1) // columns
    output = Image.new(
        "RGBA",
        (columns * cell * factor, rows * cell * factor),
        (18, 17, 25, 255),
    )
    for index, name in enumerate(names):
        image = images[name]
        slot = Image.new("RGBA", (cell, cell))
        slot.alpha_composite(
            image,
            ((cell - image.width) // 2, cell - image.height),
        )
        slot = slot.resize((cell * factor, cell * factor), Image.Resampling.NEAREST)
        output.alpha_composite(
            slot,
            (
                (index % columns) * cell * factor,
                (index // columns) * cell * factor,
            ),
        )
    output.save(DOCS / filename)


def make_actual_mockup(
    filename: str,
    names: list[str],
    images: dict[str, Image.Image],
) -> None:
    output = Image.new("RGBA", (512, 320), (14, 18, 32, 255))
    draw = ImageDraw.Draw(output)
    draw.rectangle((0, 112, 511, 179), fill=(10, 13, 24, 255))
    draw.line((0, 178, 511, 178), fill=(41, 41, 74, 255))
    centers = [round(512 * (i + 1) / (len(names) + 1)) for i in range(len(names))]
    for center, name in zip(centers, names):
        image = images[name]
        output.alpha_composite(image, (center - image.width // 2, 166 - image.height))
    draw.rectangle((8, 188, 504, 264), fill=(16, 24, 57, 255), outline=(8, 8, 16, 255), width=2)
    draw.rectangle((11, 191, 501, 261), outline=(205, 213, 222, 255))
    draw.rectangle((8, 270, 504, 312), fill=(16, 24, 57, 255), outline=(8, 8, 16, 255), width=2)
    draw.rectangle((11, 273, 501, 309), outline=(139, 148, 172, 255))
    output.save(DOCS / filename)


def validate(images: dict[str, Image.Image]) -> None:
    for name, image in images.items():
        pixels = list(image.getdata())
        colors = {(r, g, b) for r, g, b, a in pixels if a}
        alphas = {a for _, _, _, a in pixels}
        corners = [
            image.getpixel((0, 0))[3],
            image.getpixel((image.width - 1, 0))[3],
            image.getpixel((0, image.height - 1))[3],
            image.getpixel((image.width - 1, image.height - 1))[3],
        ]
        passed = (
            len(colors) <= 15
            and alphas <= {0, 255}
            and not any(corners)
            and all(bgr555(color) == color for color in colors)
        )
        print(
            f"{name:22} {image.width}x{image.height} "
            f"colors={len(colors):2} alpha={sorted(alphas)} PASS={passed}"
        )
        if not passed:
            raise RuntimeError(name)


def main() -> None:
    images = {}
    for name in SOLDIERS + MACHINES:
        images[name] = process(name, False)
    for name in BOSSES:
        images[name] = process(name, True)

    make_contact(
        "candidate_imperial_soldiers_6_contact.png",
        SOLDIERS,
        images,
        columns=3,
        factor=6,
    )
    make_contact(
        "candidate_imperial_machines_6_contact.png",
        MACHINES,
        images,
        columns=3,
        factor=6,
    )
    make_contact(
        "candidate_imperial_enemies_12_contact.png",
        SOLDIERS + MACHINES,
        images,
        columns=4,
        factor=5,
    )
    make_contact(
        "candidate_imperial_bosses_3_contact.png",
        BOSSES,
        images,
        columns=3,
        factor=6,
    )
    make_contact(
        "candidate_imperial_all_15_contact.png",
        SOLDIERS + MACHINES + BOSSES,
        images,
        columns=5,
        factor=4,
    )
    make_actual_mockup(
        "candidate_imperial_actual_scale_mockup.png",
        ["rifleman", "lancer", "clockwork_hound", "siege_walker"],
        images,
    )
    make_actual_mockup(
        "candidate_imperial_bosses_actual_scale_mockup.png",
        BOSSES,
        images,
    )
    validate(images)


if __name__ == "__main__":
    main()
