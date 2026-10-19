"""Offline CI checks for the pinned Android DPI integration."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/prepare_android_byedpi.py"
spec = importlib.util.spec_from_file_location("android_byedpi_stage", SCRIPT)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class AndroidDpiIntegrationTest(unittest.TestCase):
    def test_source_is_pinned_and_licensed(self):
        self.assertEqual(len(engine.REVISION), 40)
        self.assertEqual(engine.UPSTREAM, "https://github.com/hufrea/byedpi.git")
        self.assertIn("proxy.c", engine.FILES)
        self.assertIn("main.c", engine.FILES)
        self.assertTrue(engine.ASSET.exists())
        license_text = engine.ASSET.read_text(encoding="utf-8")
        self.assertIn("MIT License", license_text)

    def test_generated_gradle_configuration_is_idempotent(self):
        gradle = ROOT / "android/app/build.gradle.kts"
        config = ROOT / "scripts/configure_android_dpi.py"
        self.assertTrue(gradle.exists())
        self.assertTrue(config.exists())
        text = gradle.read_text(encoding="utf-8")
        self.assertEqual(text.count('path = file("src/main/cpp/CMakeLists.txt")'), 1)
        self.assertEqual(text.count('implementation("androidx.webkit:webkit:1.14.0")'), 1)
        rules = (ROOT / "android/app/proguard-rules.pro").read_text(encoding="utf-8")
        self.assertIn("DpiNativeBridge", rules)

    def test_native_sources_are_present(self):
        for name in engine.FILES:
            self.assertTrue((engine.TARGET / name).is_file(), name)


if __name__ == "__main__":
    unittest.main()
