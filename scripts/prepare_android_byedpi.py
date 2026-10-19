"""Stage pinned MIT ByeDPI C sources for Android NDK, never an unverified APK."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/hufrea/byedpi.git"
REVISION = "ba532298de7b28cfe854aea83d061369d13ca290"
FILES = (
    "main.c", "conev.c", "proxy.c", "desync.c", "mpool.c",
    "extend.c", "packets.c", "params.h", "error.h", "conev.h",
    "proxy.h", "desync.h", "mpool.h", "extend.h", "packets.h",
    "kavl.h", "win_service.h",
)
TARGET = ROOT / "android/app/src/main/cpp/byedpi"
ASSET = ROOT / "android/app/src/main/assets/licenses/ByeDPI-MIT.txt"


def stage(source):
    missing = [name for name in FILES if not (source / name).is_file()]
    if missing or not (source / "LICENSE").is_file():
        raise RuntimeError("Incomplete pinned ByeDPI checkout: " + str(missing))
    if TARGET.exists():
        shutil.rmtree(TARGET)
    TARGET.mkdir(parents=True)
    for name in FILES:
        shutil.copyfile(source / name, TARGET / name)
    shutil.copyfile(source / "LICENSE", TARGET / "LICENSE")
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / "LICENSE", ASSET)


def main():
    with tempfile.TemporaryDirectory(prefix="hyp-dpi-") as temp:
        checkout = Path(temp) / "upstream"
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        subprocess.run(["git", "-C", str(checkout), "remote", "add",
                        "origin", UPSTREAM], check=True)
        subprocess.run(["git", "-C", str(checkout), "fetch", "--depth=1",
                        "origin", REVISION], check=True)
        subprocess.run(["git", "-C", str(checkout), "checkout",
                        "-q", "--detach", "FETCH_HEAD"], check=True)
        actual = subprocess.check_output(["git", "-C", str(checkout),
                                          "rev-parse", "HEAD"],
                                         text=True).strip()
        if actual != REVISION:
            raise RuntimeError("Unverified ByeDPI source revision")
        stage(checkout)
        print("Pinned ByeDPI MIT source: " + actual)


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        sys.exit("Android DPI engine staging failed: " + str(error))
