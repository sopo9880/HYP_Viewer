# Instagram comment capture in HYP Viewer v0.4.10

## Verified source structures

Two logged-in Instagram HTML captures provided during v0.4.9 debugging
showed distinct loaded-comment structures (not all comments on Instagram):

| User-opened page | Row hook | Rendered text comments | Notes |
| --- | --- | ---: | --- |
| Desktop dialog | `li._a9zj > div._a9zr` | 8 | image-only or empty rows omitted |
| Android/mobile | `div._ac6x[role=button]` | 9 | nested `span[dir=auto]` body spans |

These counts describe the supplied samples, **not** a guaranteed count for
other reels/posts or their total reply count. Instagram can alter its markup.

## Implementation

1. The user opens an Instagram post or Reel and, if required, logs in **inside
   the HYP Viewer WebView**. The standalone Instagram app has separate state.
2. Only mounted DOM in the open page is cloned. Scripts, images, video,
   form inputs and unrelated HTML attributes are removed. No cookies or tokens
   are read or written to files. The fragment is capped at 250,000 characters.
3. Dart `InstagramCommentHtmlParser` uses the same rules for Android and
   Windows: find comment rows, match an on-page author profile link, extract
   non-interactive leaf `span[dir=auto]` text, and exclude likes, timestamps,
   reply controls and image-only placeholders.
4. `SocialCommentAccumulator` deduplicates by **author + body**, up to
   200 comments per open post. Results can grow when the user scrolls the
   already-open public comment view.
5. `NumberExtractor` receives only collected comment **bodies**, not
   author names, like counts or raw HTML. A successful comment collection
   does not guarantee any numeric gallery candidate.
6. The UI shows collected comments with authors and separately shows the
   number of gallery candidates. Collector diagnostics expose DOM row and
   parsed comment counts to help diagnose future Instagram DOM changes.

## Safety and compatibility

- No hidden/private content, undocumented comment API requests or automatic
  login bypass. Users still expand/scroll visible comments themselves.
- No login cookie import from installed Instagram/Chrome. Authenticated
  WebView interaction is user-controlled.
- The already-working YouTube retrieval path is unchanged; legacy DOM
  snapshots without `commentHtml` still use the existing fallback.
- Existing library, settings and cached works remain untouched.
- Regression tests use **synthetic/anonymized structural fixtures**.
  Raw supplied Instagram page HTML is never committed to the repository.

## Manual device verification after release

- Android: log in inside WebView, open comments, tap Results, confirm count,
  usernames and comment text; scroll and verify incremental accumulation.
- Windows: open a post in a dialog, confirm comments also work in reels;
  use the read/refresh control and compare count against visible text rows.
- Confirm image-only comments are excluded and like counts/usernames do
  not turn into work-number candidates.
- Check an unrelated public post with no ID: it must show `comments > 0`
  with `work IDs = 0`.
