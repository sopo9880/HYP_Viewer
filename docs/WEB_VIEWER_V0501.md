# WEB Viewer v0.5.1: field feedback and compatibility notes

This release is based on the Android field-test screenshot of v0.5.0 and an
HTML example of a 105-page dynamic webtoon reader. It is an additive patch
within the existing 0.x version series.

## Site buttons
- A site's more menu supports Edit (name + HTTPS URL) and Delete.
- Delete requires an explicit confirmation dialog showing name and URL.
- Current Tab Save in the embedded browser saves the current loaded HTTPS
  page as a site button. Duplicate URLs do not create more buttons.
- Last Tab appears above the WEB site list. Browser Recent Tabs lists up to
  20 visited pages and allows reopening one. Page history is persisted in the
  WEB-only metadata file; common credential-bearing query parameters are
  dropped. The user-selected site list is separate from browser history.

## Download failures
- Individual failures can be removed, or all failure logs can be cleared.
- Clearing a failure log never deletes a saved CBZ or its reading progress.
- Failure records show a human-readable work title when available.
- Temporary archive folders are cleaned up after failed transfers.
- Transport failures (including connection resets) are retried twice after
  the initial request. HTTP 401/403/404 and non-image payloads are not retried
  or bypassed. An image's explicit no-referrer policy is respected.

## Dynamic webtoon HTML
- Prioritize images under the in-page reader container
  [data-theme-viewer-images] in order of data-theme-page.
- Prefer .theme-viewer-title for the work title.
- This specific example declares 105 page slots; those slots are NOT proof
  that the 105 image files can be downloaded.
- Some HTML includes placeholder image URLs with misleading extensions.
  Only images already verified as successfully displayed by the WebView
  are eligible for capture. No hidden APIs or authentication tokens are
  extracted. Do not try to bypass site access verification.
- Show loaded image count versus expected slot count and warn when incomplete.
  The user can return to the same live WebView, scroll and detect again.
- Earlier Kone image-view-wrapper detection remains intact.
- The original full HTML sample is not committed. Regression fixtures contain
  fabricated domains, non-secret paths and structural markers only.

## Verification and release
- PR CI: generated l10n, Flutter analyze, unit tests and Windows/Android builds.
- Main CI: signed APK built once; publisher reuses unchanged APK and EXE
  from matching successful CI workflow and verifies their source SHA and hash.
- Live Android browsing and access to third-party images need a real-device
  test after official release. Network/server denial can remain unresolved.
