# HYP Viewer v0.4.4 — Manual acceptance / compatibility checklist

> CI alone does not prove external API compatibility or user-device behavior.
> Run this smoke pass on an Android device and Windows after automated checks.

## Navigation and all ko/en/ja screens
- [ ] Change the app language from Korean to English and Japanese without
      restarting. Verify Home, Library, Favorites, Downloads, Reading History,
      Online Search, Reader, Settings and Information pages all update.
- [ ] Check each settings section including advanced JSON source, backup,
      Android security guidance, notification permissions, reader settings,
      update prompts and error/toast/help messages for untranslated Korean.
- [ ] Verify all modal dialogs, tooltips, status messages, empty/error states,
      grouping/edition prompts, import/export forms, and selection counts.
- [ ] Gallery titles, source metadata, original comments and user-authored
      labels must retain their original text even across language switches.
- [ ] Check language-specific ARB placeholders for multi-digit counts.

## Reader navigation and saved state
- [ ] Open a work with default entry chrome hidden, reveal with center tap or
      Space, confirm keyboard/touch and Android volume-key navigation.
- [ ] Change between one and two-page spread via toolbar, verify physical
      page / reading progress do not reset. In Android landscape, verify the
      display orientation setting. Webtoon mode must keep its priority.
- [ ] Save custom cover, disable automatic cover generation, close/reopen the
      app, and verify settings/cover/CBZ/last page persist.
- [ ] Exit/reenter library and verify hiding a completed edition does not
      delete sibling language editions or independent page positions.

## Other-language finding and grouping
- [ ] Find an original work, open the language-finder popup immediately,
      observe incremental candidate/progress updates, and cancel with Back.
- [ ] Select several distinct language versions at once; commit once, then
      verify they share one chapter stack inside its series.
- [ ] Tap stack cover (latest-read edition) versus title (language chooser).
- [ ] Deliberately select different chapter/series IDs and verify the entire
      batch is rejected without partial library writes.
- [ ] Verify matching title aliases, creator, circle, page counts and optional
      cover evidence never silently connect unrelated chapters.

## Online search, API outages and public links
- [ ] Search Pochi and another multilingual title with no language filter.
      Confirm results appear as categories finish, exact-title ranking,
      deduplication and multi-language aliases.
- [ ] Filter to Korean/Japanese/English, use explicit artist:/group:/tag:
      terms, and inspect results with missing language metadata.
- [ ] Disconnect network, switch search query, and verify cancellation,
      partial source warnings and that local library search still works.
- [ ] Use a public YouTube short, channel or playlist, then a community post;
      check title, description, public comment pagination and any partial flag.
- [ ] Where the optional personal YouTube Data API key is available, test
      multi-page public comments. Private, login-gated or age-restricted
      content must not be bypassed.
- [ ] Test an Instagram public post/reel and a blocked/private link. Public
      preview is never misrepresented as complete original captions/comments.

## Downloads / backup / release gates
- [ ] Verify Android foreground notification and Windows tray-download
      resumption after minimize/screen-lock on the v0.4.3.1 base.
- [ ] Import a legacy v0.x JSON backup, preserve reading progress, edition
      links, favorite flags, cover images, custom library group order and CBZ.
- [ ] Confirm Android/Windows CI targets build from the PR's exact head SHA.
- [ ] Do not merge PR #28 nor tag/publish v0.4.4 before the user requests CI
      verification and all required checks pass.
