# HYP Viewer v0.4.6 — two-phase development plan

Maintain the existing **0.x** version policy. Phase 1 is a development
commit, not an official release. Keep the current v0.4.5 version,
release-request, and Android build number until both phases are ready for
release. Merging/issuing a public release is a separate validated step.

## Phase 1 — Android download reliability and social share text

- Keep an Android foreground-service lease for the *entire* approved work
  queue (including metadata fetch between works). Nested per-work leases do
  not shut the foreground service down.
- Request Android 13+ notification visibility permission during a user-started
  transfer, not automatically at app startup. Downloads can continue if
  notifications are declined; the app surfaces that loss of visibility.
- Show indeterminate progress while resolving metadata and page-based progress
  once the number of pages is available.
- Keep page-level staging checkpoints, CBZ integrity and the persisted work
  queue intact. Restore pending jobs at fresh launch or foreground resume when
  no job is already executing. Never delete jobs on failed service startup.
- Normalize hexadecimal/decimal/named HTML references in Instagram shares;
  receive ACTION_SEND text even without a URL, preserve the original link,
  and prefill editable title/author fields when explicitly identifiable.
  Likes and comment counts are metadata, not gallery identifiers.

## Phase 2 — in-app source browser and image identification

- Android WebView and Windows WebView2 analysis of *actually available* public
  page metadata, rendered captions and displayed comments. Fall back to
  manual copying; do not bypass login restrictions or private data.
- Instagram posts/carousels/reels; YouTube videos/Shorts/community posts.
  Read the original page's images where available, otherwise offer screen
  capture. Sampling video frames requires lawful access to the media and a
  user-driven alternative when it is blocked.
- Accept Android image ACTION_SEND/SEND_MULTIPLE, plus Android/Windows local
  image selection. Use on-device OCR and local image embeddings against an
  opt-in local index; online reverse-image search is optional, consent-based.
- Combine caption, author, comment code, OCR and image evidence into ranked
  work candidates. Verify numbered works, distinguish approximate matches,
  and require user confirmation before saving.
- Preserve multilingual UI, backup/restore, library, saved settings and CBZ.

## Acceptance criteria for the two-phase release

1. Android analyzer, tests and debug APK + Windows installer on current head
   pass in GitHub Actions.
2. Real-device progress, notification permissions, Home, screen-off,
   multi-work queue, Wi-Fi offline/recovery, pause/resume and task relaunch
   tests pass. Force-stop is allowed to interrupt execution; checkpoints and
   queue must survive until a later explicit app launch.
3. Instagram/YouTube page/comment restrictions and local-only image search
   failures must be reported as such; never invent comments or work numbers.
4. Existing v0.4.5 user files/settings and backups must remain compatible.
