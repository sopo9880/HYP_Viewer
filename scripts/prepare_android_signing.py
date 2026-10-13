"""Configure Android release signing using repository Actions secrets.

Fail closed: an official release must not be signed with an ephemeral debug key.
"""
import base64
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
gradle = root / "android" / "app" / "build.gradle.kts"
keystore = root / "android" / "app" / "upload-keystore.jks"
properties_file = root / "android" / "key.properties"
secrets = [
    "HYP_ANDROID_KEYSTORE_BASE64",
    "HYP_ANDROID_KEYSTORE_PASSWORD",
    "HYP_ANDROID_KEY_ALIAS",
    "HYP_ANDROID_KEY_PASSWORD",
]
if any(not os.environ.get(name) for name in secrets):
    sys.exit("Missing Android signing secrets: refusing an official release.")
if not gradle.exists():
    sys.exit("Android build script missing; run flutter create first.")

raw = gradle.read_text(encoding="utf-8")
needle = 'signingConfig = signingConfigs.getByName("debug")'
if raw.count(needle) != 1 or "    buildTypes {" not in raw:
    sys.exit("Unknown Flutter Gradle template: cannot safely patch release signing.")

def escape_properties(value: str) -> str:
    return (value.replace("\\", "\\\\").replace("\r", "\\r")
                 .replace("\n", "\\n").replace("=", "\\=").replace(":", "\\:"))

keystore.write_bytes(base64.b64decode(os.environ[secrets[0]], validate=True))
values = {
    "storeFile": "upload-keystore.jks",
    "storePassword": os.environ[secrets[1]],
    "keyAlias": os.environ[secrets[2]],
    "keyPassword": os.environ[secrets[3]],
}
properties_file.write_text(
    "".join(k + "=" + escape_properties(v) + "\n" for k, v in values.items()),
    encoding="utf-8"
)

config = """
    signingConfigs {
        create("release") {
            val props = Properties().apply {
                load(rootProject.file("key.properties").inputStream())
            }
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
        }
    }

"""
if "import java.util.Properties" not in raw:
    raw = "import java.util.Properties\n\n" + raw

raw = raw.replace("    buildTypes {", config + "    buildTypes {", 1)
raw = raw.replace(needle, 'signingConfig = signingConfigs.getByName("release")', 1)
gradle.write_text(raw, encoding="utf-8")
print("Persistent Android signing configured.")
