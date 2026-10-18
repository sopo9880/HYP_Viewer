#!/usr/bin/env python3
"""Apply HYP's approved icon after flutter create regenerates host projects.

CI does not check platform runners into Git: flutter create replaces their
default icons on each run. This script runs AFTER flutter create and BEFORE
flutter pub get and flutter build, across verify and release workflows.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from io import BytesIO
import hashlib

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDING_PARTS = ROOT / "assets" / "icons" / "hyp_brand"
BRANDING_SHA256 = "08679c28e4b8bda686577196f05f0903bbcf1bc86b7be6a06e5f5837adf2e03a"

TRAY = ROOT / "assets" / "icons" / "hyp_tray.ico"
ANDROID = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
ICON_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48),
              (64, 64), (128, 128), (256, 256)]


def apply(platform: str, *, root: Path = ROOT) -> list[Path]:
    source = root / "assets" / "icons" / "hyp_app_icon.jpg"
    parts = root / "assets" / "icons" / "hyp_brand"
    if source.is_file():
        # For downstream maintainers who want to replace the brand icon,
        # a direct replacement source takes precedence.
        image_source = source.read_bytes()
    else:
        files = [parts / f"part_{i:02d}.bin" for i in range(8)]
        if not all(p.is_file() for p in files):
            raise FileNotFoundError(
                f"Approved icon parts are missing from {parts}")
        image_source = b"".join(p.read_bytes() for p in files)
        if hashlib.sha256(image_source).hexdigest() != BRANDING_SHA256:
            raise ValueError("The approved HYP icon failed SHA-256 integrity")
    with Image.open(BytesIO(image_source)) as image:
        image = image.convert("RGB")
        if image.width < 192 or image.height < 192:
            raise ValueError("Branding image must be at least 192px square")
        if image.width != image.height:
            raise ValueError("App launcher icon must be square")
        created: list[Path] = []
        if platform == "android":
            for density, size in ANDROID.items():
                target = (root / "android" / "app" / "src" / "main" /
                          "res" / f"mipmap-{density}" / "ic_launcher.png")
                if not target.parent.is_dir():
                    raise FileNotFoundError(
                        f"Flutter Android project is not generated: {target}")
                image.resize((size, size), Image.Resampling.LANCZOS).save(
                    target, format="PNG", optimize=True)
                created.append(target)
        elif platform == "windows":
            target = root / "windows" / "runner" / "resources" / "app_icon.ico"
            if not target.parent.is_dir():
                raise FileNotFoundError(
                    f"Flutter Windows project is not generated: {target}")
            image.save(target, format="ICO", sizes=ICON_SIZES)
            created.append(target)
            tray = root / "assets" / "icons" / "hyp_tray.ico"
            image.save(tray, format="ICO", sizes=ICON_SIZES)
            created.append(tray)
        else:
            raise ValueError(f"Unknown platform: {platform}")
    for file in created:
        if file.stat().st_size == 0:
            raise RuntimeError(f"Generated icon is empty: {file}")
    print(f"Applied HYP icons for {platform}: " +
          ", ".join(str(p.relative_to(root)) for p in created))
    return created


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("android", "windows"),
                        required=True)
    args = parser.parse_args()
    apply(args.platform)
