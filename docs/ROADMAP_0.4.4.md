# HYP Viewer release plan (0.x)

## v0.4.3.1 — Background downloads only

- Android: user-triggered, foreground-service-backed downloads show an
  ongoing notification while running. Screen lock and leaving the app do not
  deliberately cancel active jobs. Android power management, force-stop,
  reboot, and platform time limits can still suspend or terminate execution.
- Windows: active downloads survive minimizing the window. Closing the window
  while transferring hides it to the tray; users can restore or explicitly exit.
- Preserve authorized pending work IDs and the source class in a durable
  per-install queue. On a new launch, resume approved unfinished jobs.
- Keep complete pages on disk across connection failures and app termination;
  rebuild CBZ and replace an older offline copy only after validation.
- Include the separate JSON image-source entry point and update-installer
  downloads in background execution protections.
- Never bypass download restrictions, protected content, HTTPS limits or
  a user's explicit cancellation. No automatic installation.
- v0.4.3.1 is the GitHub tag and the Windows installer version.
  Flutter/Android use valid pubspec 0.4.3+21 (Android build code 21); the
  app exposes its complete release identity as v0.4.3.1.

## v0.4.4 — Planned, NOT implemented by the hotfix

1. Audit EVERY view, settings panel, dialog, error, notification, tooltip,
   reader/navigation screen and dynamic message against ko/en/ja language
   packs. Include runtime-path tests, not just ARB key parity.
2. Finish previously partial multilingual edition discovery/matching,
   cover evidence and safe clustering without collapsing unrelated chapters.
3. Document and improve publicly accessible YouTube post/comment coverage,
   Instagram preview completeness and bounded retrieval. Never pretend
   restricted or private comments are retrievable without authorization.
4. Audit search completeness, pagination, failures and all previously agreed
   v0.4.3 functionality on real Windows and Android devices.
5. Preserve existing 0.x library JSON, saved CBZ, covers, edition associations
   and read progress while validating changes.

Do not merge v0.4.4 scope into the v0.4.3.1 hotfix release.

## v0.4.4 — Two-step implementation contract

The user requested **two distinct development turns**. Stop after the first
phase PR and its initial CI URL; do not merge or publish a version before the
separate verification/phase-2 instructions.

### Phase 1 (this stacked PR; review/CI pending)

- Reader starts with toolbar and bottom bar hidden by default; saved
  setting can restore visible-on-entry behavior. Center tap/Space toggles UI.
- Replace the obsolete toolbar visibility icon with a live two-page spread
  toggle, retaining the current physical page and user preference.
- A language-edition discovery modal opens immediately, displays candidates
  as they arrive and cancels network work on Back/Cancel. Allow multiple
  checked editions in one atomically validated library write.
- Edition stack cover opens the most recently visited language edition;
  its title opens the existing language chooser.
- Unified online search emits partial results as each category returns;
  changing the query cancels superseded HTTP requests.
- Add ko/en/ja strings for the newly introduced controls, with focused
  regression tests. **This is NOT the full-screen translation audit.**

### Phase 2 (implemented on development branch; CI and device QA pending)

- Examine **every** dashboard page, panel, reader control, dialog, error,
  tooltip, accessibility string and dynamic status message for ko/en/ja,
  and add runtime language-switch tests.
- Complete the previously agreed five v0.4.3 implementation workstreams:
  multilingual original/translation discovery, cover/matching safeguards,
  public YouTube and Instagram retrieval within authorization constraints,
  safe reader/cache behavior and compatibility/regression coverage.
- Investigate incorrect search relevance, field syntax, multilingual recall,
  page boundaries and mirror failures; fix underlying algorithms and add
  realistic comparisons. Streaming display alone is insufficient.
- Rebase/retarget onto released v0.4.3.1 when available, run all checks on
  the final SHA, then use the normal verification, merge and release process.
- Preserve prior JSON backups, user grouping decisions, offline CBZ,
  custom covers and independent reading positions; retain the 0.x policy.


### Phase-2 code changes (not a release declaration)

1. Whole-app ko/en/ja static UI audit extends to every existing reader,
   dashboard, settings, backup and online-content view, including Text,
   tooltips and input decorations. Validate ARB placeholder parity and add
   real language-notifier widget tests. Numeric work/status messages now have
   bounded full-message translation rules rather than untranslated suffixes.
2. Fix phase-1 multi-edition atomic linking parser and misplaced test helper.
   Cross-series conflicts cannot silently merge chapters; legitimate English
   or Korean words in a work title are no longer stripped as translation
   markers. Language codes have the same canonical mapping in local search,
   remote search and edition selection. Preserve saved metadata and reading
   progress when linking versions.
3. Expand original/translation alias discovery across title and creator,
   studio and series fields within fixed network budgets; deduplicate
   metadata by work ID across fields, rank exact title matches above broad
   tag/category matches, and exclude only known conflicting language tags
   when the provider ignores a language filter. Each category continues to
   render incrementally without waiting for others.
4. The optional user-provided YouTube API key now pages through up to five
   comment pages, de-duplicating public comments. Anonymous public-page
   fetching allows up to 10 pages / 300 comments, without bypassing login,
   age restrictions or access limits. When the public comments transport
   changes, preserve publicly visible title/description and explicitly
   flag incomplete results. Instagram metadata remains a PUBLIC PREVIEW,
   not an assertion that captions/comments were retrieved completely.
5. Review and extend test coverage for serialization, language grouping,
   metadata matching, streaming online search, public-source fallback,
   dynamic locale switching, reader navigation and safe user-data handling.

**Release gates:** PR #27 for v0.4.3.1 remains separate. PR #28 is stacked on
#27 and stays a draft until its HEAD passes all Android/Windows checks and
the user issues the verification/merge command. The formal v0.4.4 version
bump, signed APK, EXE installer and release artifacts are intentionally NOT
published from this development branch. Test on real devices as specified in
docs/SMOKE_TEST_V0.4.4.md, and confirm v0.x JSON, offline CBZ, covers and
reading history survive an update.
