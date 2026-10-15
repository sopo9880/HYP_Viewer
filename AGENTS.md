# HYP Viewer AI development rules

These instructions apply to EVERY AI-driven change, including Codex and ChatGPT work across conversations.

## Always ship all supported UI languages
- Each new or changed user-facing UI string must include Korean (ko), English (en), and Japanese (ja) translations **in the same PR**, without waiting for a separate user request.
- Define new keys in `lib/l10n/app_ko.arb`, `app_en.arb`, and `app_ja.arb`, and use Flutter `AppLocalizations.of(context)!` from widgets. Never add raw Korean string literals to Text, TextField decorations, tooltips or dialogs.
- Run `flutter gen-l10n`, `python3 scripts/check_l10n.py`, `flutter analyze --no-fatal-infos`, and `flutter test` before sending the PR. Let GitHub CI do these validations if Flutter is unavailable locally.
- Check localization for new settings, errors, dialog labels and accessibility text. Preserve interpolation placeholders across languages and keep UI labels short enough for Android.
- Never machine-translate user-generated titles, original comments, author names, work identifiers or external URLs.
- Existing HypText/HypI18n remains as a compatibility layer for older UI, but every new UI must use generated typed keys. Migrate old strings incrementally and remove that layer only after verifying full coverage.
- If any language pack is missing a key, CI MUST fail. Do not silently fall back to Korean as a substitute for proper translations.
- Update or extend automated tests for the three locales with every UI feature. Review translation semantics for important errors or warnings.

## Development workflow and release safety
- Preserve existing Android package identity, signing, on-device library data, offline CBZ files, and JSON backups.
- Never merge a PR, publish a release, or advance beyond v0.x merely because a commit was pushed.
- Development command updates an existing feature PR, checks workflow dispatch/results links, and stops; CI verification and merge require the user's separate confirmation.
