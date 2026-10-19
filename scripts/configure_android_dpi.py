"""Patch generated Flutter Gradle build for app-local Android ByeDPI."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
gradle = root / "android/app/build.gradle.kts"
if not gradle.exists():
    sys.exit("Run flutter create --platforms=android first.")
source = gradle.read_text(encoding="utf-8")
if "android {\n" not in source:
    sys.exit("Unknown Android Gradle template")
cmake_line = 'path = file("src/main/cpp/CMakeLists.txt")'
if cmake_line not in source:
    source = source.replace("android {\n",
        """android {
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
""", 1)
webview_dependency = 'implementation("androidx.webkit:webkit:1.14.0")'
if webview_dependency not in source:
    source = source.rstrip() + "\n\ndependencies {\n    " + webview_dependency + "\n}\n"
gradle.write_text(source, encoding="utf-8")
# R8 must not rename JNI entrypoints in permanently signed release builds.
rules = root / "android/app/proguard-rules.pro"
keep = "-keep class com.sopo9880.hyp_viewer.DpiNativeBridge { *; }"
current = rules.read_text(encoding="utf-8") if rules.exists() else ""
if keep not in current:
    rules.write_text(current.rstrip() + "\n" + keep + "\n", encoding="utf-8")
print("Android native ByeDPI and WebView override configured.")
