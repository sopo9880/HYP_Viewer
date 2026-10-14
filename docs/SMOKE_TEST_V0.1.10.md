# HYP Viewer v0.1.10 device smoke test

1. Install v0.1.10 over v0.1.9, keep app ID and signing. Back up the library to JSON before testing.
2. Android Recents: launch HYP, share multiple Shorts from YouTube when HYP is foreground/background, then return via recent-apps. Only one HYP task should be present. Save works; clear Recents and cold-launch. Previously saved library, favorites, reading progress and covers should persist.
3. Simulate a corrupted primary JSON with an intact .previous backup in a test environment. Startup restores contents; with both corrupt files, saving is blocked rather than replacing it with an empty shelf.
4. Reader: enable tap page turns. Left/right halves act like physical swipe directions, and top/bottom halves when vertical paging is active. Verify both normal and RTL reading.
5. Preload field accepts -1 or 0..1500. -1 warms images through a temporary disk cache and does not keep every image in RAM. Close the viewer and verify the cache directory is removed. Low-disk-space conditions must not corrupt the library.
6. Switch to Webtoon mode: all pages stack vertically without fixed-height slides and scroll continuously; app remembers reading position.
7. Settings > auto download on save: defaults to off. When enabled, explicit content-rights opt-in appears. New works enqueue sequentially and existing offline CBZ files are skipped.
8. Library > Download All: requires a one-time rights confirmation. Verify queued count, status, per-work errors, and Cancel stopping the active transfer and queued work. Remote access restrictions must not be bypassed.
9. Home > Random Library Covers: cycle across all three banner slides every eight seconds and change the cover each time. Manual slide arrows still work. When no cached covers exist, fall back to native art.
10. Reboot Android and reinstall-update without app data removal, ensuring settings and library survive.

Limitations: Downloads only run while HYP is active. Auto/bulk download requires permission for the specific content, and servers may reject access. -1 loading may use significant disk/network data (up to the validated gallery size); the UI maintains bounded memory and concurrency.
