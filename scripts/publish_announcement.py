"""Validate and publish a plain-text app announcement in the separate feed branch.

Only invoked through the repository's manually dispatched Actions workflow.
No client tokens or private authentication information are present in the app.
"""
import datetime as dt
import hashlib
import json
import os
import pathlib
import re

title = os.environ.get("NOTICE_TITLE", "").strip()
message = os.environ.get("NOTICE_MESSAGE", "").strip()
if not (1 <= len(title) <= 120) or "\n" in title:
    raise SystemExit("Invalid title (1..120 characters, single line)")
if not (1 <= len(message) <= 2000):
    raise SystemExit("Invalid message length")
identifier = (
    "notice_" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S") +
    "_" + hashlib.sha256((title + message).encode("utf-8")).hexdigest()[:8]
)
assert re.fullmatch(r"[a-zA-Z0-9_-]{5,80}", identifier)
path = pathlib.Path("notices/feed.json")
feed = json.loads(path.read_text(encoding="utf-8"))
if feed.get("schemaVersion") != 1 or not isinstance(feed.get("announcements"), list):
    raise SystemExit("Unsupported notice feed schema")
feed["announcements"].insert(0, {
    "id": identifier,
    "title": title,
    "message": message,
    "publishedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
})
feed["announcements"] = feed["announcements"][:30]
temporary = path.with_suffix(".json.tmp")
temporary.write_text(
    json.dumps(feed, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
os.replace(temporary, path)
print("Published notice ID:", identifier)
