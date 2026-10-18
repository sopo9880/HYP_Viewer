# HYP Viewer v0.4.12 – Windows tray and readable work titles

## v0.4.11 observed defects

- User confirmed tray left-click (hide/show) and X (quit) work correctly.
- On Windows, right-click shows *no context menu*.
- The released right-click callback refreshed native menu items but did not
  call the tray plugin's explicit pop-up operation.
- Long work titles were truncated in grids, search, verification and dialogs.

## 0.4.12 behavior

**Windows tray:** Reuse the already configured native context menu, explicitly
pop it up on right-click, and log errors instead of silently ignoring them.
Do not alter the working left click, double click, X-close or download flow.

**Titles:** A shared measured-width widget shows a normal ellipsis only when a
title genuinely overflows. Tapping the title scrolls all the way to the end,
pauses, then returns to the start once. It never bubbles to an enclosing
card's reader action. Short titles remain static. Tooltips and semantics keep
the full title. Verified work-number candidates are an exception: overflowing
verified titles repeat automatically while mounted. Reduced Motion preference
suppresses animation, and text editing / already fully selectable text stays
unchanged.

**Navigation:** A book cover opens the offline/online reader; a series cover
opens its chapter grid; a language-edition cover resumes the reading edition.
The language chooser remains a separate, discoverable target, not the title.
List selection, checkboxes, reorder arrows and card action menus continue to
work. In selection mode a title tap still selects the work.

**Surfaces:** Home recent cards, shelf, favorite cards, series and language
groups, online search results, candidate number checks, online/visual match
results, auto group wizard, library/edition selectors, reading insights,
gallery reader app bar, YouTube video selector and other relevant popups.
Text inside a tappable fallback cover remains static so cover interaction
remains reader-opening; the separate card title provides full-title access.

## Manual post-release smoke tests

1. Windows tray right-click must show a menu; test each menu action, while
   left-click and X keep working under both hide-to-tray and exit modes.
2. Click a long book title: reveal entire title without opening reader.
   Click cover: open reader. Short titles must not animate.
3. Group cover -> chapter list; language stack cover -> reader; tap language
   chooser label -> edition selector; tap title -> scrolling only.
4. Verify gallery numbers. Long verified candidate titles scroll repeatedly,
   short ones do not. Leaving the candidate view stops the motion.
5. Test long title in online search, visual results, rankings, group editor,
   recent works, and reader bar on both Windows and Android.
6. Verify selection mode and checkbox/list selection are unchanged.
7. Enable system Reduce Motion and confirm animated titles become static.
8. Confirm library JSON, downloaded CBZ, reading history and settings remain
   intact; v0.4.12 adds no persistent schema fields.

CI tests Flutter logic and compiles Windows/Android. Actual Windows shell
menu display still needs real-EXE verification.
