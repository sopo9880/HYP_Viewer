# YouTube Shorts comments without a personal API key

The app now has a best-effort anonymous reader in `lib/core/youtube_public.dart`.

## What the app does

1. Parse a public YouTube Shorts/watch link to extract its 11-character video ID.
2. GET the public watch page and parse the embedded player data and web-client
   configuration (including YouTube's publicly embedded Innertube key).
3. Find the comments-section continuation in the initial watch-page data;
   otherwise request an initial public web-client "next" response for the ID.
4. Fetch up to three continuation pages and up to 100 sampled public comments.
   Support both legacy commentRenderer and newer commentEntityPayload mutations.
5. Feed the description and the sampled comments into the existing deterministic
   numeric work-ID extractor. The user still confirms ambiguous matches.

There is **no user-supplied Google/YouTube Data API v3 key** required for the
default path. The web-client key is dynamically read from YouTube's own public
page and is never bundled or persisted in the app. The official Data API path
remains an optional advanced fallback when the user provides their own key.

## Important limitations

- This mechanism accesses YouTube's publicly reachable web-client endpoints,
  which are undocumented, may change, and can be rate-limited or blocked.
- Private, age-restricted, login-gated, consent-gated or disabled-comment videos
  are not supported; no authentication or restriction bypass is implemented.
- The app does not claim to fetch every comment (up to 100 sampled comments).
- Errors must be shown to the user, with a fallback to manually copying comments.
- The GitHub automated tests use mocked public pages and responses. A passing CI
  run does **not** prove YouTube's live endpoints currently work on every
  Android device, Windows PC, network or region.

## Validation before calling the feature production-ready

- Test on a public Shorts video known to have many top-level comments.
- Test a video with comments disabled, an invalid URL, and one that requires
  sign-in. Confirm no misleading "success" is shown.
- Verify title/description, comments, numeric candidates and library storage
  both on Android and Windows.
- Confirm that no personal API key is requested on the default path.
- Check the user's jurisdiction, content rights and the platform's current terms.
