"""Configure bundled Japanese/Korean ML Kit OCR models for generated Android.

Flutter regenerates android/app/build.gradle.kts in GitHub Actions.
The patch is idempotent and does not alter signing or the library files.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
path = root / "android" / "app" / "build.gradle.kts"
if not path.exists():
    sys.exit("Missing Android Kotlin Gradle file; run flutter create first.")
content = path.read_text(encoding="utf-8")
if 'com.google.mlkit:text-recognition-korean' in content:
    print("Android OCR models already configured.")
    sys.exit(0)
if "plugins {" not in content or "android {" not in content:
    sys.exit("Unexpected Android Flutter Gradle template.")
models = """dependencies {
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}
"""
path.write_text(content.rstrip() + "\n\n" + models, encoding="utf-8")
print("Bundled ML Kit Korean and Japanese offline OCR models.")
