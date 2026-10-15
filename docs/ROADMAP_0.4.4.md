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

### Phase 2 (NOT started; requires a separate user request)

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
