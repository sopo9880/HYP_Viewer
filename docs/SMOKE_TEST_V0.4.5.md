# HYP Viewer v0.4.5 — Acceptance and data compatibility

This is a manual device checklist in addition to Flutter CI. No real Android
notification delivery or OEM-specific behavior can be established by unit tests.

## 1. Saved link finder cleanup
- [ ] Paste links/comments, select two verified candidates, save to shelf,
      switch to Library or Favorites: finder link, extracted candidates,
      code, title, author and comments are blank on returning Home.
- [ ] Enter a link and change tabs without saving: the draft is preserved.
- [ ] Save, then enter a *new* link or edit a comment before navigating:
      all newly edited input is retained.
- [ ] A saved API key and preferences are never wiped.
- [ ] A rejected/failed save does not arm the automatic wipe.

## 2. Final-page confirmation
- [ ] Open final page without pressing next: progress persists but an
      unfinished book does NOT become completed.
- [ ] Next (touch, mouse, keyboard, Android volume): see exactly one dialog
      with Complete + Exit / Exit Without Completing / Keep Reading.
- [ ] Keep Reading leaves the reader open; Exit Without Completing keeps
      the prior completion flag; Complete + Exit marks only the work as read.
- [ ] Next from the last unit of two-page spread and webtoon behaves the
      same as one-page mode, after its last image has displayed.
- [ ] Turn off the confirmation setting: previous last-image automatic
      completion behavior still works; JSON backup remains compatible.
- [ ] Final image load failure must not allow accidental completion.

## 3. Android volume hold
- [ ] With navigation OFF, volume buttons change device volume normally.
- [ ] With navigation ON, quick Down / Up changes page forward / backward.
- [ ] Hold for >500ms: repeat at 700/400/200ms intervals as configured;
      releasing the button stops without additional page turns.
- [ ] Hold at last page: it stops and does not open the completion dialog;
      after key release a fresh Down press can open that dialog.
- [ ] Close reader, background app, or force-stop: no repeat timer remains.
- [ ] Verify reader zoom, RTL, two-page, webtoon and OS accessibility keys.

## 4. Android foreground notification progress
- [ ] Approve a work download. Only ONE ongoing notification is shown.
- [ ] From the notification shade, inspect work ID, completed/total pages,
      percent and determinate progress bar. Progress must not jump backward.
- [ ] Pause/resume: notification switches text and progress remains stable.
- [ ] Queue two works: the next title/ID and count replace the first.
- [ ] Complete/fail/cancel: foreground notification closes and a result
      notification links back to Downloads. New work cancels stale results.
- [ ] Tap progress notification when app is already open and cold-started:
      both open Downloads without duplicating Android tasks.
- [ ] Disable Android 13+ notification permission, force-stop, switch networks,
      or enable battery limits: failures must not corrupt the resumable queue.

## 5. Korean / English / Japanese
- [ ] Home: Recently Read and actual 0..4 item count and collapse tooltip.
- [ ] Downloads: on-device saved work count, creator name, and page start.
- [ ] Library: Hide Finished / Show Finished buttons and any counts.
- [ ] Favorites: subtitle and creator information for each saved card.
- [ ] New confirmation dialog, volume hold speed labels and in-app controls.

## Compatibility and release gate
- [ ] Retain v0.4.4 library, favorite IDs, independent edition completion,
      reading positions, covers, CBZ, backup JSON and download checkpoints.
- [ ] CI must pass Android and Windows jobs at the exact PR HEAD before merge.
- [ ] After release, verify signed APK, Setup EXE, GitHub tag and SHA256SUMS.
