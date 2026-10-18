#!/usr/bin/env python3
"""Bundle the original, pinned GoodbyeDPI for HYP Viewer Windows installers.

This is a build-time operation, not a first-run user download. Fail closed if
the publisher changes the release bytes, the architecture, or license files.
The app's own installer and uninstaller then manage these bundled files.
"""
from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path
from urllib.request import Request, urlopen
from zipfile import ZipFile

TAG = "0.2.3rc3"
ASSET = "goodbyedpi-0.2.3rc3-2.zip"
SOURCE = f"https://github.com/ValdikSS/GoodbyeDPI/releases/download/{TAG}/{ASSET}"
SHA256 = "37f96b32d050dadcc930a639eba68e1ccd57ed5c04a5f77dfca908f01905a4c5"
MAX_ARCHIVE = 5 * 1024 * 1024
MAX_UNPACKED_FILE = 2 * 1024 * 1024
TOOLS = ("goodbyedpi.exe", "WinDivert.dll", "WinDivert64.sys")
LICENSES = ("LICENSE-goodbyedpi.txt", "LICENSE-windivert.txt",
            "LICENSE-getline.txt", "LICENSE-uthash.txt")
BLACKLIST = "russia-blacklist.txt"


def _single_member(zipped: ZipFile, suffix: str) -> str:
    matches = [n for n in zipped.namelist()
               if n.replace("\\", "/").lower().endswith(suffix.lower())
               and not n.endswith("/")]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one official release entry: {suffix}, got {matches}")
    return matches[0]


def unpack_verified(contents: bytes, dest: Path, *, expected_sha256: str = SHA256) -> list[Path]:
    if len(contents) > MAX_ARCHIVE:
        raise ValueError("GoodbyeDPI archive is larger than the safety limit")
    if hashlib.sha256(contents).hexdigest() != expected_sha256:
        raise ValueError("GoodbyeDPI SHA-256 mismatch; cannot package unverified binary")
    dest.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    with ZipFile(io.BytesIO(contents)) as zipped:
        for name in TOOLS:
            member = _single_member(zipped, f"/x86_64/{name}")
            item = zipped.getinfo(member)
            if item.file_size < 1000 or item.file_size > MAX_UNPACKED_FILE:
                raise ValueError("Executable size outside expected limits")
            data = zipped.read(member)
            output = dest / name
            output.write_bytes(data)
            created.append(output)
        for name in (*LICENSES, BLACKLIST):
            member = _single_member(zipped, "/" + name)
            item = zipped.getinfo(member)
            if item.file_size > MAX_UNPACKED_FILE:
                raise ValueError("Release notice/list exceeds safety limit")
            output = dest / name
            output.write_bytes(zipped.read(member))
            created.append(output)
    supervisor = Path(__file__).parent / "windows_dpi_supervisor.ps1"
    if not supervisor.is_file():
        raise FileNotFoundError("Bundled DPI supervisor script is missing")
    dest_script = dest / "hyp_dpi_supervisor.ps1"
    dest_script.write_bytes(supervisor.read_bytes())
    created.append(dest_script)
    notice = dest / "HYP_GOODBYEDPI_NOTICES.txt"
    notice.write_text(
        "Third-party utility: GoodbyeDPI " + TAG +
        "\nCopyright: GoodbyeDPI contributors; Apache-2.0 license\n" +
        "WinDivert: see LICENSE-windivert.txt\n" +
        "Upstream: https://github.com/ValdikSS/GoodbyeDPI\n" +
        "Original asset: " + SOURCE +
        "\nSHA256: " + SHA256 +
        "\nThis optional mode requires administrator consent and can affect network traffic system-wide.\n" +
        "Third-party license texts and blacklist are copied unchanged.\n",
        encoding="utf-8",
    )
    created.append(notice)
    return created


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", default="build/windows/x64/runner/Release/tools")
    args = parser.parse_args()
    # Download on GitHub Actions only. The installed application NEVER does
    # this and cannot silently change its GoodbyeDPI engine.
    request = Request(SOURCE, headers={"User-Agent": "HYPViewer-ReleaseBuild/0.4"})
    with urlopen(request, timeout=45) as response:
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > MAX_ARCHIVE:
            raise ValueError("Unexpected oversized release archive")
        data = response.read(MAX_ARCHIVE + 1)
    created = unpack_verified(data, Path(args.destination))
    print("Packaged verified GoodbyeDPI files: " + ", ".join(x.name for x in created))


if __name__ == "__main__":
    main()
