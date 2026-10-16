#!/usr/bin/env python3
"""Patch the legacy flutter_inappwebview Android ProGuard default for AGP 9+.

The latest stable Android plugin (1.1.3) still references the removed
proguard-android.txt template. Patch only the resolved pub-cache dependency
after "flutter pub get", retaining R8 optimization instead of disabling its
validation. Do not edit the generated app Gradle project or user data.

Remove this workaround when a compatible stable plugin ships.
"""

import json
from pathlib import Path


def patch_gradle(gradle_file: Path) -> str:
    source = gradle_file.read_text(encoding="utf-8")
    legacy = "getDefaultProguardFile('proguard-android.txt')"
    supported = "getDefaultProguardFile('proguard-android-optimize.txt')"

    if legacy not in source:
        if supported not in source:
            raise RuntimeError(
                f"Unexpected WebView Gradle configuration: {gradle_file}"
            )
        return "already compatible"

    count = source.count(legacy)
    if count > 3:
        raise RuntimeError(
            f"Unexpected number of obsolete ProGuard references: {count}"
        )
    patched = source.replace(legacy, supported)
    gradle_file.write_text(patched, encoding="utf-8")
    return f"replaced {count} obsolete ProGuard reference(s)"


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    metadata_file = root / ".flutter-plugins-dependencies"
    if not metadata_file.is_file():
        raise RuntimeError(
            "Flutter plugin metadata not found; run flutter pub get first."
        )

    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    android_plugins = metadata.get("plugins", {}).get("android", [])
    selected = [
        item for item in android_plugins
        if item.get("name") == "flutter_inappwebview_android"
    ]
    if len(selected) != 1:
        raise RuntimeError(
            f"Expected one resolved Android WebView plugin; found {len(selected)}."
        )
    plugin_path = Path(selected[0]["path"])
    if not plugin_path.is_absolute():
        plugin_path = root / plugin_path
    gradle_file = plugin_path / "android" / "build.gradle"
    if not gradle_file.is_file():
        raise RuntimeError(f"Resolved Android plugin Gradle file missing: {gradle_file}")

    print(f"WebView Android AGP 9 compatibility: {patch_gradle(gradle_file)}")


if __name__ == "__main__":
    main()
