from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "素材"
XUANLAN = Image.open(SOURCE / "玄览LOGO.jpg").convert("RGB")
MITSURI = Image.open(SOURCE / "甘露寺蜜璃LOGO.jpg").convert("RGB")


def save_icon(source: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(
        path, format="PNG", optimize=True
    )


def icon_entries(prefix: str) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for idiom, points, scales in (
        ("iphone", 20, (2, 3)),
        ("iphone", 29, (1, 2, 3)),
        ("iphone", 40, (2, 3)),
        ("iphone", 60, (2, 3)),
        ("ipad", 20, (1, 2)),
        ("ipad", 29, (1, 2)),
        ("ipad", 40, (1, 2)),
        ("ipad", 76, (1, 2)),
        ("ipad", 83.5, (2,)),
    ):
        for scale in scales:
            pixels = round(points * scale)
            name = f"{prefix}-{points:g}x{points:g}@{scale}x.png"
            save_icon(
                MITSURI,
                ROOT / "ios/Runner/Assets.xcassets/MitsuriIcon.appiconset" / name,
                pixels,
            )
            entries.append(
                {
                    "size": f"{points:g}x{points:g}",
                    "idiom": idiom,
                    "filename": name,
                    "scale": f"{scale}x",
                }
            )
    save_icon(
        MITSURI,
        ROOT / "ios/Runner/Assets.xcassets/MitsuriIcon.appiconset/Icon-Mitsuri-1024.png",
        1024,
    )
    entries.append(
        {
            "size": "1024x1024",
            "idiom": "ios-marketing",
            "filename": "Icon-Mitsuri-1024.png",
            "scale": "1x",
        }
    )
    return entries


pixels = np.asarray(MITSURI)
near_white = (pixels.min(axis=2) >= 246) & (
    pixels.max(axis=2) - pixels.min(axis=2) <= 14
)
edge_background = np.zeros(near_white.shape, dtype=bool)
edge_background[[0, -1], :] = near_white[[0, -1], :]
edge_background[:, [0, -1]] |= near_white[:, [0, -1]]
edge_background = ndimage.binary_propagation(edge_background, mask=near_white)
transparent_logo = Image.fromarray(
    np.dstack((pixels, np.where(edge_background, 0, 255).astype(np.uint8))),
    mode="RGBA",
)


branding_dir = ROOT / "assets/branding"
branding_dir.mkdir(parents=True, exist_ok=True)
XUANLAN.save(branding_dir / "xuanlan-logo.jpg", format="JPEG", quality=94)
MITSURI.save(branding_dir / "mitsuri-logo.png", format="PNG", optimize=True)
transparent_logo.save(
    branding_dir / "mitsuri-logo-transparent.png", format="PNG", optimize=True
)
save_icon(MITSURI, ROOT / "web/icons/Icon-Mitsuri-192.png", 192)
save_icon(MITSURI, ROOT / "web/icons/Icon-Mitsuri-512.png", 512)

for density, size in (
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
):
    directory = ROOT / f"android/app/src/main/res/mipmap-{density}"
    save_icon(XUANLAN, directory / "ic_launcher.png", size)
    save_icon(MITSURI, directory / "ic_launcher_mitsuri.png", size)

for name, size in (("Icon-192.png", 192), ("Icon-512.png", 512)):
    save_icon(XUANLAN, ROOT / "web/icons" / name, size)
for name, size in (("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)):
    save_icon(XUANLAN, ROOT / "web/icons" / name, size)
save_icon(MITSURI, ROOT / "web/icons/Icon-Mitsuri-maskable-192.png", 192)
save_icon(MITSURI, ROOT / "web/icons/Icon-Mitsuri-maskable-512.png", 512)
save_icon(XUANLAN, ROOT / "web/favicon.png", 64)

primary_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
primary_json = json.loads((primary_set / "Contents.json").read_text(encoding="utf-8"))
for entry in primary_json["images"]:
    filename = entry.get("filename")
    if filename:
        points = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        save_icon(XUANLAN, primary_set / filename, round(points * scale))

alternate_set = ROOT / "ios/Runner/Assets.xcassets/MitsuriIcon.appiconset"
alternate_set.mkdir(parents=True, exist_ok=True)
contents = {
    "images": icon_entries("Icon-Mitsuri"),
    "info": {"author": "xcode", "version": 1},
}
(alternate_set / "Contents.json").write_text(
    json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)

MITSURI.resize((256, 256), Image.Resampling.LANCZOS).save(
    ROOT / "windows/runner/resources/app_icon_mitsuri.ico",
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
XUANLAN.resize((256, 256), Image.Resampling.LANCZOS).save(
    ROOT / "windows/runner/resources/app_icon.ico",
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
