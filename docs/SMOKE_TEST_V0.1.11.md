# HYP Viewer v0.1.11 — QA and manual device checklist

## Import/Export from Android to Windows
1. Export with default flags **Library + Settings**. Confirm schema 2 has works, favorites, reading history, ReaderSettings fields such as languageCode, tapNavigation, webtoonMode, preloadPages=-1, autoDownloadOnSave, receiveAnnouncements, heroArtworkSource.
2. JSON exports exclude credentials, online image source URL templates, OS permissions and offline CBZ. The Excel export remains a non-restorable viewing report.
3. Optional "Include Cover & Banner Images" generates a larger Base64 export (max total image payload 22 MB / JSON file 40 MB), without embedding downloadable full-size galleries. Restore should reproduce stored custom previews and banner when present.
4. Import two different libraries (phone 100, PC 50, overlap 20): **① Add Works** yields 130 IDs, merges favorite/completed/collections, retains highest progress; current PC settings unchanged.
5. **② Replace Settings** keeps all PC library entries and replaces reader/home/language settings. Auto-download and admin notices are intentionally OFF until permission is renewed.
6. **③ Replace Works + Settings** requires the explicit "I understand replacement" checkbox, overwrites the PC shelf and preferences; previous disk snapshot is kept as .previous by LibraryStorage.
7. Import an older schema-1 JSON: "Add Works" enabled; destructive or settings modes disabled. Empty settings-only schema-2 export must not delete the user's shelf.
8. Invalid file, bad base64, path traversal in image fields and unknown schema must fail before modifying on-disk data.

## Shelf editing and batch deletion
9. Library: press Select (PC/Android) or long-press a work on Android. Tap cards to choose. Select All selects ONLY the currently filtered search results; Clear Selection returns to zero.
10. Choose 2+ cards, select Delete, see item count and deletion warning. Default checkbox OFF retains downloaded CBZ/custom cover files; ON deletes those files for selected IDs only. Cancellation must leave all entries alone.
11. Select just one card and press Edit Details; also use work card menu > Edit Work Details. Change title/author/comment without touching favorites and reading progress.
12. Correct an erroneous work ID such as 23172801 to 3172801. Use metadata verification and optionally Use Verified Title. If metadata service fails or cannot confirm, show an extra warning; users can still manually save.
13. If destination ID already exists, prompt Merge or Cancel. The merge keeps favorites, completed flags, maximum reading progress and union of collections; source CBZ and cover files remain under their OLD numeric IDs.
14. Verify selection on both narrow Android layout and Windows, and update v0.1.10 in place without removing app data.

## Known limits
- Changing a saved ID does NOT transfer an old local CBZ or cached cover to the new ID; this prevents displaying incorrect images for a corrected number.
- Cross-device JSON is not a CBZ archive. Base64 images are optional and limited for memory safety.
- Restoration of a valid v2 backup includes UI preferences but requires renewed consent for downloads and notifications; Android OS permissions always remain device-local.
