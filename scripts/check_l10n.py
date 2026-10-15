#!/usr/bin/env python3
"""Fail the PR when a newly introduced UI label skips i18n or ARB keys differ.

During the incremental migration, unchanged legacy HypText literals remain
allowed. Only ADDED lines in the PR diff are checked for new raw UI strings.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
L10N = ROOT / "lib" / "l10n"
LANGUAGES = ("ko", "en", "ja")

def check():
    messages = {}
    for language in LANGUAGES:
        path = L10N / f"app_{language}.arb"
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("@@locale") != language:
            raise ValueError(f"Wrong locale in {path}")
        messages[language] = {
            k: v for k, v in data.items()
            if not k.startswith("@") and isinstance(v, str)
        }
    reference = set(messages["ko"])
    for language in LANGUAGES[1:]:
        missing = reference - set(messages[language])
        extra = set(messages[language]) - reference
        if missing or extra:
            raise ValueError(f"{language}: missing={sorted(missing)} extra={sorted(extra)}")
    if not reference:
        raise ValueError("No translations found")
    # These sections used to silently remain Korean even when ARB passed.
    # Treat them as required, not merely optional strings.
    required = {
        *(f"settings{part}" for part in (
            "General", "Hero", "Viewer", "Cover", "Android",
            "Notices", "Web", "Source", "Backup", "Updates")),
        *(f"insights{letter}" for letter in "ABCDEFGHIJKL"),
        "insightsTitle", "insightsSubtitle",
        "editionCoverPercent", "legacyCompletionReview",
        "youtubeChooseVideos", "searchFetchedUnique",
    }
    if required - reference:
        raise ValueError(f"Missing core UI localization keys: {sorted(required - reference)}")

    placeholder = re.compile(r"(?<!\{)\{([A-Za-z_]\w*)\}(?!\})")
    for key in reference:
        translations = [messages[lang][key] for lang in LANGUAGES]
        if any(not item.strip() for item in translations):
            raise ValueError(f"Blank translation: {key}")
        expected = set(placeholder.findall(translations[0]))
        if any(set(placeholder.findall(item)) != expected for item in translations[1:]):
            raise ValueError(f"Placeholder mismatch: {key}")
    diff = None
    for base in ("origin/main", "main"):
        result = subprocess.run(
            ["git", "diff", "--unified=0", f"{base}...HEAD", "--", "lib"],
            capture_output=True, text=True)
        if result.returncode == 0:
            diff = result.stdout
            break
    if diff is None:
        print("No baseline branch locally; skipping added-line lint, ARB verified.")
        return
    raw = re.compile(
        r"""(?:\bText\s*\(\s*|(?:labelText|helperText|hintText|tooltip)\s*:\s*)(?:const\s*)?['"][^'"\n]*[가-힣]"""
    )
    errors = []
    path = ""
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        if not line.startswith("+") or line.startswith("+++"):
            continue
        if path.endswith(".dart") and not path.startswith("lib/l10n/"):
            # Language names must remain in their native script regardless
            # of the currently selected locale.
            native = ("Text('한국어')", 'Text("한국어")')
            if any(part in line for part in native):
                continue
            if raw.search(line[1:]):
                errors.append(f"{path}: {line[1:].strip()}")
    if errors:
        raise ValueError("Unlocalized new UI strings:\n" + "\n".join(errors))
    print(f"All {len(reference)} keys match across ko/en/ja.")

if __name__ == "__main__":
    try:
        check()
    except (ValueError, FileNotFoundError) as error:
        print(f"Localization CI failure: {error}", file=sys.stderr)
        sys.exit(1)
