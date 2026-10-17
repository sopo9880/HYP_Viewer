"""Configure bundled Japanese/Korean ML Kit OCR models for generated Android.

Flutter regenerates android/app/build.gradle.kts in GitHub Actions.
The patch is idempotent and does not alter signing or user library files.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
app = root / "android" / "app"
gradle = app / "build.gradle.kts"
rules = app / "proguard-rules.pro"
if not gradle.exists():
    sys.exit("Missing Android Kotlin Gradle file; run flutter create first.")

content = gradle.read_text(encoding="utf-8")
if "plugins {" not in content or "android {" not in content:
    sys.exit("Unexpected Android Flutter Gradle template.")

models = """dependencies {
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}
"""
if 'com.google.mlkit:text-recognition-korean' not in content:
    content = content.rstrip() + "\n\n" + models

# R8 must not require language packs that this app never instantiates.
# The Flutter plugin references these optional recognizer classes, but the
# app only enables Latin, Korean and Japanese. Keep release shrinking active.
proguard_rules = """# Optional ML Kit scripts not bundled by HYP Viewer.
# The app only requests Latin, Korean and Japanese recognizers.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
"""
rule_ref = 'proguardFiles("proguard-rules.pro")'
if rule_ref not in content:
    signing = 'signingConfig = signingConfigs.getByName("debug")'
    if content.count(signing) != 1:
        sys.exit("Unexpected release build type in generated Android Gradle file.")
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if signing in line:
            indentation = line[:len(line) - len(line.lstrip())]
            lines.insert(i + 1, indentation + rule_ref)
            break
    content = "\n".join(lines) + "\n"

gradle.write_text(content, encoding="utf-8")
if rules.exists() and rules.read_text(encoding="utf-8") != proguard_rules:
    sys.exit("Refusing to overwrite preexisting Android ProGuard rules.")
rules.write_text(proguard_rules, encoding="utf-8")
print("Bundled ML Kit Korean/Japanese OCR and guarded optional-script R8 references.")
