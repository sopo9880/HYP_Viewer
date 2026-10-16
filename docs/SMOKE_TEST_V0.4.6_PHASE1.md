# v0.4.6 phase-one manual Android smoke tests

Automated CI can check Kotlin/Dart builds but **cannot validate Samsung One UI
notification rendering or device background lifecycle**.

1. Use a test device and back up the v0.4.5 user library and settings.
   Android debug APK signing may differ from the production key.
2. Android 13+: start an approved download and observe the notification
   permission prompt. Grant, then repeat with permission denied. The latter
   should show an in-app warning and retain jobs.
3. During remote metadata fetch, observe "Preparing work" (indeterminate).
   After metadata resolves, observe X/Y pages and the percentage/progress bar
   in both the collapsed and expanded notification drawer.
4. Queue at least three distinct works, press Home, and verify page counts
   continue to advance across work boundaries. Repeat with the screen locked.
5. Turn Wi-Fi off and back on, return to the app, and verify stored jobs
   resume without deleting already staged pages. Repeat after app process
   restart. Force-stop does not guarantee immediate automatic restart.
6. Verify cancel/pause/resume, completed/failed notifications, notification
   navigation into Downloads and handling of denied notification permission.
7. Send only '만화방 on Instagram: "&#xb9cc;&#xd654;"' as ACTION_SEND
   text/plain; Finder must show the decoded caption instead of discarding it.
8. Send an Instagram URL and encoded caption containing '작가 : 八木戸マト'.
   The source link and editable title/author fields should be preserved.
9. Confirm existing offline CBZ, reading progress, language groups, backup
   restore and library content remain intact.

This checklist is **not marked done** until real-device evidence is recorded.
