#!/usr/bin/env python3
"""Apply HYP's approved icon after flutter create regenerates host projects.

CI does not check platform runners into Git: flutter create replaces their
default icons on each run. This script runs AFTER flutter create and BEFORE
flutter pub get and flutter build, across verify and release workflows.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "icons" / "hyp_app_icon.jpg"
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
    if not source.is_file():
        raise FileNotFoundError(f"Approved icon is missing: {source}")
    with Image.open(source) as image:
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
