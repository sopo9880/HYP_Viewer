# Screenshot-based online source discovery and Instagram comments

## Online image lookup

Home > Shorts finder > Find work by image opens two separate result views.
**Internet image search is the default**; **My library images** is secondary.
The user must explicitly select an image and press Search online.
This sends only that image to external providers. The app never uploads
private shelf data, offline archives or stored settings.

- ascii2d is attempted using the public search form without a key. Its
  HTML/CSRF form can change and automated search may be rate limited.
- Optionally, the user can enter a SauceNAO API key for structured results.
  It exists only inside the current inspector dialog and is not persisted.
- Results show source thumbnails, titles, artists, original external URLs
  and a similarity score only if the provider supplies one.
- If a **Hitomi URL directly contains a gallery ID**, the work ID is offered
  as a candidate. Otherwise the source title or artist is searched against
  the existing public online gallery metadata provider. Those candidates
  **do not prove** that the screenshot and gallery belong together.
- Import is always user-confirmed; images cannot establish a work ID in
  services that have never indexed that page.

My library indexing remains opt-in and uses stored covers plus up to three
pages per offline gallery. Screenshots, saved gallery images and fingerprint
index data are not uploaded during local search. A local fingerprint result
is only a similarity lead, not an identity guarantee.

## Instagram posts/reels

When one Instagram post/reel is shared or submitted for analysis, the
in-app WebView is preferred to the former public metadata-only preview.

- The page DOM is re-read after asynchronous rendering settles. Users may
  scroll, open/expand comments manually, then press **Re-read visible post
  and comments**. Captions and the already-rendered comment rows are shown
  in an expandable preview with a loaded-comment count.
- Public OG metadata remains a **fallback snippet**, not a full caption.
- If Instagram requires login or blocks the page, the app displays that
  limitation, and the user can paste copied post/comment text explicitly.
- There is no use of private GraphQL, login bypass, account cookies,
  automated comment pagination or private-account scraping. The official
  Meta API does not provide arbitrary public account comments.

## Test after CI

Verify Android and Windows build/test jobs, keyless and key-backed provider
returns, Instagram visible caption/visible-comment rows, restricted login
wall and manual paste, direct-vs-indirect numeric work IDs, 0.x backup and
saved-library integrity. Real-device validation is after release.
