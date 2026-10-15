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
