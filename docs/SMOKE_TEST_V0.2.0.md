# HYP Viewer v0.2.0 validation (18-point rollout)

1. Simulate gallery HTTP 503/429 while webtoon scrolls; ensure no unbounded burst, global cooldown and limited retry, and retry/web-reader fallback for visible page.
2. In 120-page gallery with preload set to 0, jump to page 85 using slider and verify no transient reset to 1; duplicate requests must be coalesced, jump committed only on gesture end.
3. Test left/right swipe direction and reversed mode. Vertical paging must ALWAYS advance top-to-bottom, including slider, button and arrow navigation.
4. New installation default preload -1, existing saved 2 stays 2. -1 warms entire work with disk budget and queue priority; do not hold all pages in RAM.
5. Data saver toggle switches to 1 concurrent request and at most one nearby page while enabled; saved -1 remains and resumes on disable.
6. On Android press system Back: reader -> invoking page; Library/Settings/Downloads/Favorites/History -> Home; first Back on Home shows warning, second within 2s exits; dialogs/drawer/selection close first.
7. Android bottom order Favorites, Library, Home, Downloads, Settings. Desktop sidebar unaffected.
8. Verify tall cover aspect 0.68, title and page progress percentage, and visible cover image crop on 360px mobile display.
9. Home Recent collapses and displays <=4, state persists; recommendation section removed.
10. Android top-right updates action invokes release check; top-right overflow contains exactly Settings, Reading History, Backup Settings. Backup deep link expands correct settings section.
11. All settings panels are collapsible and preserve expanded state when leaving and returning, plus across restart through ReaderSettingsStorage.
12. Library sort Added/Newest, Local Read Count, Title, Numeric ID; toggle direction. Remote view counts MUST NEVER be inferred or fabricated.
13. Work card menu removes "CBZ/ZIP bind" and "JSON source download"; has Work Info, Intro Shorts, favorites and reading actions. Work Info displays actual metadata, local reading and explicit unavailable views.
14. Library selection -> Group selection: users name a group; individual reading/bookmarks preserved, chapter order editable. Auto wizard proposes only ungrouped numbered works with reliable shared Shorts IDs or titles and requires explicit confirmation.
15. Ungroup only removes membership; no changes to individual works, files or favorite state. Rename and reordering persist.
16. Downloads selection supports folder export of existing offline CBZs. Android uses system ACTION_OPEN_DOCUMENT_TREE; only selected app-private CBZ paths can be copied; original CBZ remains. Windows avoids file-name collisions.
17. JSON v2 exports and restores with reader settings, group membership and optional previews; old v1 backup still imports. Android v0.1.11 package updates with same durable signature.
18. Confirm real Android firmware, external gallery throttling, device SAF providers and offline CBZ exports manually before claiming guaranteed device compatibility.

User-facing limitations: External view counts are not part of verified galleryinfo metadata and are shown as unavailable. "Popular" library sort refers to local opening count and is labelled as such, not external site popularity. Whole preloading is opportunistic within a temporary disk budget and can be interrupted by low storage or server limits.
