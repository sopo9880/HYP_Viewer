# HYP Viewer v0.2.1 smoke tests

1. Library: Added, published (site metadata), daily/weekly/monthly/yearly popularity, local reads, title, ID each sort correctly. Missing dates/ranks remain last; offline status clearly reported.
2. Sorting remote metadata: bounded requests, failures reported, no invented view counts. JSON round-trip preserves popularity period and cached dates.
3. Library group cards: single group occupies one grid cell next to regular books; stacked covers and member count are visible. Tap opens member grid, Back returns, manage rename/order/ungroup survives restart.
4. Chapter order: explicit episode number precedes uploaded date, then numeric ID. Existing manual groupOrder stays stable.
5. Cover artwork uses contain (no crop), title/footer area unchanged in work and group cards. Explicit user-cropped covers stay as saved.
6. PC Space hides header/footer controls; Space restores. Side 30% taps turn, middle 40% toggles UI without changing page; RTL respects reading direction.
7. Android center tap toggles chrome and side taps turn. Two-finger pinch and desktop wheel zoom work without accidental page turning while zoomed; webtoon scroll remains functional.
8. Last page: visible successfully decoded page sets completed=true and percentage reaches 100. A prefetched last page not currently visible must not count.
9. Data saver: thumbnail host receives request before full WebP. 404 fallback to full image; rate-limit cooldown still applies. Disabled saver never requests thumbnails.
10. Foreground priority: while whole-work background cache warms, distant page jump starts with reserved network capacity. Current and nearby pages are pre-decoded.
11. Cache reused between online reader sessions for the same work and quality. Old caches pruned; offline CBZ, covers and JSON never removed by pruner.
12. Check Windows Setup.exe, permanently signed Android APK, SHA256SUMS, old-version upgrades and actual external site behavior on real hardware.
