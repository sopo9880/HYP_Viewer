import tempfile
import unittest
from pathlib import Path

from PIL import Image

from scripts.apply_app_icons import apply, ANDROID


class IconBuildTests(unittest.TestCase):
    def test_generated_android_icons_and_windows_ico(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "assets" / "icons"
            source.mkdir(parents=True)
            Image.new("RGB", (320, 320), (7, 17, 61)).save(
                source / "hyp_app_icon.jpg", format="JPEG")
            for density in ANDROID:
                (root / "android" / "app" / "src" / "main" /
                 "res" / f"mipmap-{density}").mkdir(parents=True)
            (root / "windows" / "runner" / "resources").mkdir(parents=True)
            android = apply("android", root=root)
            self.assertEqual(len(android), 5)
            for icon in android:
                density = icon.parent.name.removeprefix("mipmap-")
                with Image.open(icon) as png:
                    self.assertEqual(png.size, (ANDROID[density],)*2)
            windows = apply("windows", root=root)
            self.assertEqual(len(windows), 2)
            for icon in windows:
                with Image.open(icon) as ico:
                    self.assertEqual(ico.format, "ICO")
                    self.assertEqual(ico.size, (256, 256))

    def test_missing_source_aborts_instead_of_silent_flutter_default(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                apply("android", root=Path(directory))


if __name__ == "__main__":
    unittest.main()
