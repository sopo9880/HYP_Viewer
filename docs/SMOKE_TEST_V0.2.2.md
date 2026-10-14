# HYP Viewer v0.2.2 — acceptance and manual checks

1. Auto grouping: different works originating in one Shorts share the SAME
   originalComment with "1편 / 2편 / 3편". They must still detect correct
   per-work episode numbers from titles or source-ID-specific comment lines.
2. Auto grouping must never propose merging unrelated series just because
   they share a Shorts ID or a single artist/circle.
3. Two separate Shorts with the same normalized series title can be suggested
   together. Identical titles without explicit chapter numbers receive a
   review recommendation, not automatic merging.
4. Existing grouped series can be offered new ungrouped works. Its prior
   members, group order, progress, favorite state and CBZ stay unchanged.
5. Auto wizard shows all proposed groups; expand for each work's title, ID
   and cover (when available), and an explanation/rule score. Toggle whole
   groups or individual works. New groups need >=2 included works. Existing
   groups allow >=1 newcomer. Edit title and reorder with arrows. Cancel
   leaves the library untouched; Confirm persists only selected chapters.
6. Reader physical taps: from page 3 of 5, left side -> 2 and right side -> 4,
   even in RTL or two-page spreads. Middle toggles top and bottom controls.
   On webtoon, side tap jumps to neighboring page and middle toggles chrome,
   with regular scroll and Ctrl+wheel preserved.
7. Reader setting defaults to checked on clean install. A stored false remains
   false on upgrade. Keyboard and browser/platform gestures stay functional.
8. Number extraction: broad 6-9 digit contiguous groups only within one
   line first; keep legitimate mnemonic "4036년 3월55일", "271만59".
   Explicit chapter markers separate regions even if two episodes are in one
   long line; chapter labels never become digits in gallery IDs.
9. Metadata verification: deduplicate, fetch in <=24 ID batches with at
   most 3 simultaneous metadata requests. The UI shows progress and unknown
   status. A 404/410 is not-found; a 429/503 is unavailable, not not-found.
10. Cross-line fallback only when first-pass candidates are ALL confirmed
    absent, or the line pass has no candidates. Only combine adjacent lines
    inside one paragraph/comment; never across blank-line comment boundary.
    Show that fallback was used, and require final manual selection.
11. Full Flutter tests, Android debug and Windows CI on PR. After merge,
    signed Android release APK, Windows Setup.exe and SHA256SUMS exist in
    the official v0.2.2 release. Upgrade the previous signed v0.2.1 APK
    without deleting the library; verify external gallery sites on hardware.
