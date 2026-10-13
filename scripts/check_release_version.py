"""Validate a release request and reject every non-0.x version."""
import os
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
tag = (root / ".github" / "release-request.txt").read_text(encoding="utf-8").strip()
if not re.fullmatch(r"v0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
    sys.exit("Release rejected: only v0.MINOR.PATCH is authorized.")

pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
match = re.search(
    r"^version:\s*(0\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))\+([1-9][0-9]*)\s*$",
    pubspec,
    flags=re.MULTILINE,
)
if not match or "v" + match.group(1) != tag:
    sys.exit("Release request must match pubspec version and positive build number.")

print("Approved 0.x version:", tag, "Android build:", match.group(2))
if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write("tag=" + tag + "\nversion=" + match.group(1) + "\n")
