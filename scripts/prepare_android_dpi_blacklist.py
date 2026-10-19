"""Stage a SHA-256-verified official GoodbyeDPI host list into Android assets.

The Russian blacklist is used only with user-selected blacklist presets.
Download during CI, never at runtime; do not package or auto-execute Windows
GoodbyeDPI binaries on Android.
"""
import hashlib
import io
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from zipfile import ZipFile

from prepare_goodbyedpi import ASSET, BLACKLIST, SHA256, SOURCE, MAX_ARCHIVE, MAX_BLACKLIST_FILE

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "android/app/src/main/assets/dpi/russia-blacklist.txt"
LICENSE_DEST = ROOT / "android/app/src/main/assets/licenses/GoodbyeDPI-Apache.txt"

def main():
    req = Request(SOURCE, headers={"User-Agent": "HYPViewer-Android-Blacklist/0.4"})
    with urlopen(req, timeout=45) as handle:
        blob = handle.read(MAX_ARCHIVE + 1)
    if len(blob) > MAX_ARCHIVE or hashlib.sha256(blob).hexdigest() != SHA256:
        raise RuntimeError("Official GoodbyeDPI source archive SHA-256 verification failed")
    with ZipFile(io.BytesIO(blob)) as zipped:
        entries = [n for n in zipped.namelist()
                   if n.replace("\\", "/").endswith("/" + BLACKLIST)]
        if len(entries) != 1:
            raise RuntimeError("Expected one official blacklist, got " + str(entries))
        info = zipped.getinfo(entries[0])
        if info.file_size > MAX_BLACKLIST_FILE:
            raise RuntimeError("Official blacklist exceeds safety limit")
        content = zipped.read(info)
        license_entries = [n for n in zipped.namelist()
                           if n.replace("\\", "/").endswith("/LICENSE-goodbyedpi.txt")]
        if len(license_entries) != 1:
            raise RuntimeError("Official GoodbyeDPI license missing")
        license_text = zipped.read(license_entries[0])
    if not content or len(content) > MAX_BLACKLIST_FILE:
        raise RuntimeError("Empty/oversized official blacklist")
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_bytes(content)
    LICENSE_DEST.parent.mkdir(parents=True, exist_ok=True)
    LICENSE_DEST.write_bytes(license_text)
    print("Verified GoodbyeDPI blacklist for Android: " +
          str(len(content)) + " bytes from " + ASSET)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.exit("Android blacklist staging failed: " + str(e))
