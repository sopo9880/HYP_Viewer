# HYP Viewer v0.5.2 — WEB/SERIES visual library and update APK cleanup

## Scope

- Preserve the existing HYP/WEB/SERIES three-mode navigation introduced in v0.5.1.
- WEB Home uses the real `HypHeroBanner` component with WEB-specific
  slides and up to three locally generated CBZ cover previews.
- SERIES Home uses the same hero component with SERIES-specific slides,
  grouped-series totals, recent-series covers and a last-saved-chapter shelf.
- WEB and SERIES libraries use `WebVisualLibrary` / `WebVisualCard`, which
  mirror the breakpoints, HYP colors, border radii and progress bars of
  `HypWorkGrid`. Title/author search, newest/title/progress sorting and
  incremental item pagination are included.
- A saved WEB CBZ's first image is scaled and written to a small preview in
  `web_viewer/covers/`. v0.5.0/v0.5.1 CBZs are lazily converted on first
  visible cover. Cover generation errors never discard valid downloads.
- SERIES parent cards prefer the existing local saved-chapter cover and
  otherwise use the public HTTPS cover URL found in its original DOM, falling
  back to the same HYP vector palette. Remote cover loads cannot access local
  HTTP URLs.
- Tapping a saved WEB or SERIES chapter opens the original GalleryReader
  with its existing page count and progress. No CBZ is copied or migrated to
  the original HYP library.

## Android APK cleanup (new)

- `UpdateApkCleanup` scans **only** direct regular files inside the app
  support `hyp_updates` directory. Name filter: `HYP_Viewer_v0.x.y.apk`
  plus its `.part` and `.metadata.json` companions.
- The cleanup does not enter nested folders, public Downloads, any HYP/WEB
  gallery, or arbitrary Android storage.
- On Android app launch, cleanup only runs if `PackageInfo.version` agrees
  with the built release version, and a pending-update marker does not point
  to a later version. This ensures a cancelled/not-yet-approved install can
  be retried from the verified APK.
- While `downloadingUpdate` is true, automatic/manual cleanup is blocked.
- Manual cleanup is available in the update/settings sections of HYP, WEB
  and SERIES on Android. It previews file count + bytes, requires user
  confirmation, and reports removed bytes, blocked cleanups, or failures.
- No user library data, CBZs, images, configuration, or signing material is
  deleted. Existing diagnostic logs are retained.
- Already installed versions need to be **v0.5.2 or newer** before this new
  automatic cleanup behavior is present.

## Validation

- `test/v052_visual_workspace_test.dart`: shared hero branding, cover-card
  grid, search, progress and mobile layout.
- `test/v052_update_apk_cleanup_test.dart`: old APK inventory, deletion of
  owned APK/partial/metadata files only, pending/newer update protection,
  active-transfer protection and fail-closed invalid markers.
- Existing `test/v0501_*.dart` regression suites remain unchanged.
- CI is the authority for automated checks; Android/Windows real-device
  functional tests are performed by the user after the official release.

Release integration: keep the existing GitHub main CI signing and immutable
artifact reuse pipeline. APKs must never be rebuilt by the release workflow.
