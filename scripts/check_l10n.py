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
        "searchAllFields", "searchResultMatches", "searchSeries", "searchTag",
        "searchLanguageChip", "settingsTapZonesNote", "settingsHeroUploadNote",
        "workInfoHeader", "workInfoProgress", "workInfoLanguage",
        "androidSecurityNotice", "tooltipSearchLanguage",
        "editionAliasTitles", "editionAliasHelp",
        "workSourceHistory", "workSourcesHelp", "workSourceInvalid",
        "workSourceCount", "onlineLinkedShelf", "searchProgress",
        "youtubeMoreVideos", "youtubeCommentsPartial",
        "readerFailedPage", "readerTooltipPrevious", "readerTooltipNext",
        "readingStatsSummary", "readingActivityDay",
        "readingSaveReportFailed",
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
    # Check unchanged legacy pages too. Previously only changed lines were
    # inspected, so whole panels could silently remain untranslated.
    # Only static HypText literals are checked here. Dynamic user-authored
    # titles are intentionally left verbatim; runtime messages require ARB.
    legacy_source = (ROOT / "lib" / "core" / "i18n.dart").read_text(encoding="utf-8")
    extra_source = (ROOT / "lib" / "core" / "i18n_extra.dart").read_text(encoding="utf-8")
    legacy_keys = set(re.findall(r"(?m)^\s*'([^']+)'\s*:\s*\[", legacy_source))
    legacy_keys.update(
        re.findall(r'(?m)^\s*"((?:[^"\\]|\\.)+)"\s*:\s*\[', extra_source)
    )
    static_text = re.compile(
        r"""HypText\s*\(\s*((?:(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")\s*)+)""",
        re.S,
    )
    quoted = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*" """.strip())
    missing_static = []
    for page in [ROOT / "lib" / "main.dart", *(ROOT / "lib" / "ui").glob("*.dart")]:
        content = page.read_text(encoding="utf-8")
        for item in static_text.finditer(content):
            literal = "".join(fragment[1:-1] for fragment in
                              quoted.findall(item.group(1)))
            suffix = content[item.end():].lstrip()
            # Expressions that embed variables or concatenate user data
            # need separate runtime treatment; don't mistake them for keys.
            if "$" in literal or suffix.startswith("+"):
                continue
            if re.search(r"[가-힣]", literal) and literal not in legacy_keys:
                missing_static.append(f"{page.relative_to(ROOT)}: {literal[:100]}")
    if missing_static:
        raise ValueError("Untranslated static UI labels:\n" +
                         "\n".join(missing_static[:35]))

    # Full-surface audit: old pages must not escape localization by using
    # Text('한국어'), a literal tooltip, or untranslated field labels.
    # Native-script choices ("한국어" in the language picker) are exempt.
    raw_label = re.compile(
        r"""(?:\bText\s*\(\s*|(?:tooltip|labelText|hintText|helperText)\s*:\s*)
        (?:const\s*)?(['"])([^'"\n]*[가-힣][^'"\n]*)\1""",
        re.X,
    )
    allowed_native = {"한국어"}
    untranslated_raw = []
    for page in [ROOT / "lib" / "main.dart",
                 *(ROOT / "lib" / "ui").glob("*.dart")]:
        source = page.read_text(encoding="utf-8")
        for match in raw_label.finditer(source):
            literal = match.group(2)
            if literal in allowed_native:
                continue
            line = source.count("\n", 0, match.start()) + 1
            untranslated_raw.append(
                f"{page.relative_to(ROOT)}:{line}: {literal[:110]}"
            )
    if untranslated_raw:
        raise ValueError("Untranslated UI text/tooltips/fields in existing pages:\n" +
                         "\n".join(untranslated_raw[:50]))

    # A translated locale must never reuse raw Korean fallback sentences.
    # Work titles and user library metadata are not part of these catalogues.
    for language in ("en", "ja"):
        leftover = [
            key for key, value in messages[language].items()
            if re.search(r"[가-힣]", value)
        ]
        if leftover:
            raise ValueError(
                f"{language}: Korean text leaked into ARB: {leftover[:30]}"
            )

    diff = None
    for base in ("origin/main", "main"):
        result = subprocess.run(
            ["git", "diff", "--unified=0", f"{base}...HEAD", "--", "lib"],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
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
