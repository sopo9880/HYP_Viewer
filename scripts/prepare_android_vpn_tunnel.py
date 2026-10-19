"""Build pinned hev-socks5-tunnel JNI via Android NDK.

The VPN uses a separate local SOCKS5 ByeDPI worker and a tun2socks bridge.
Everything is compiled into the APK at CI time. No downloaded binaries,
dynamic remotes, root, or VPN activation without an Android permission dialog.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/heiher/hev-socks5-tunnel.git"
REV = "780b396b0fc3d0355fc0614e221e3446933669c4"
MAIN = ROOT / "android/app/src/main"
JNI = MAIN / "jni"
DEST = MAIN / "jniLibs"
CLASS = MAIN / "java/hev/htproxy/TProxyService.java"
LICENSE = MAIN / "assets/licenses/hev-socks5-tunnel-MIT.txt"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
NDK = "27.2.12479018"


def build():
    android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not android_home:
        raise RuntimeError("Android SDK path is missing")
    ndk_build = Path(android_home) / "ndk" / NDK / "ndk-build"
    if not ndk_build.is_file():
        raise RuntimeError("Pinned Android NDK not found: " + str(ndk_build))
    with tempfile.TemporaryDirectory(prefix="hyp-hev-") as temp:
        sources = Path(temp) / "source"
        subprocess.run(["git", "init", "-q", str(sources)], check=True)
        subprocess.run(["git", "-C", str(sources), "remote", "add", "origin", UPSTREAM], check=True)
        subprocess.run(["git", "-C", str(sources), "fetch", "--depth=1", "origin", REV], check=True)
        subprocess.run(["git", "-C", str(sources), "checkout", "-q", "--detach", "FETCH_HEAD"], check=True)
        actual = subprocess.check_output(
            ["git", "-C", str(sources), "rev-parse", "HEAD"], text=True).strip()
        if actual != REV:
            raise RuntimeError("hev-socks5-tunnel revision mismatch: " + actual)
        subprocess.run(["git", "-C", str(sources), "submodule", "update",
                        "--init", "--recursive", "--depth", "1"], check=True)
        for path in ("Android.mk", "src/hev-jni.c", "LICENSE",
                     "third-part/yaml/Android.mk", "third-part/lwip/Android.mk",
                     "third-part/hev-task-system/Android.mk",
                     "android/hev/htproxy/TProxyService.java"):
            if not (sources / path).is_file():
                raise RuntimeError("Incomplete pinned tunnel source: " + path)
        JNI.mkdir(parents=True, exist_ok=True)
        build_dir = Path(temp) / "obj"
        subprocess.run([
            str(ndk_build),
            "NDK_PROJECT_PATH=" + str(JNI),
            "APP_BUILD_SCRIPT=" + str(sources / "Android.mk"),
            "NDK_LIBS_OUT=" + str(DEST),
            "NDK_OUT=" + str(build_dir),
            "APP_ABI=" + " ".join(ABIS),
            "APP_PLATFORM=android-29",
            "APP_MODULES=hev-socks5-tunnel",
            "APP_CFLAGS=-DANDROID",
            "-j2",
        ], cwd=str(sources), check=True)
        for abi in ABIS:
            output = DEST / abi / "libhev-socks5-tunnel.so"
            if not output.is_file() or output.stat().st_size <= 2048:
                raise RuntimeError("Missing verified tun2socks JNI output: " + str(output))
        CLASS.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sources / "android/hev/htproxy/TProxyService.java", CLASS)
        LICENSE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sources / "LICENSE", LICENSE)
        print("Built pinned hev-socks5-tunnel for: " + ", ".join(ABIS))


if __name__ == "__main__":
    try:
        build()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        sys.exit("Pinned Android VPN tunnel build failed: " + str(error))
