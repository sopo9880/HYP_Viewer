# HYP Viewer

Local-first **Windows setup.exe + Android APK** app for finding and organizing references from YouTube Shorts. No AI service, login, or cloud library required.

**Status:** v0.1.5 next release candidate (not published yet). Earlier 0.x releases remain available. We follow **release → update → live test → next 0.x fix**. See [v0.1.5 smoke test](docs/SMOKE_TEST_V0.1.5.md).

## v0.1.5 changes in review

- Download images from the same built-in gallery reader after explicitly confirming storage rights. Stream pages to a CBZ archive with progress, pause (between images), resume and cancel; the previous CBZ is retained if a new download fails.
- Automatic first-page covers are opt-in (off by default for new works). Choose built-in designs, upload photos or crop any gallery page using drag/pinch/zoom.
- Android reader: optional physical volume +/- page navigation and optional landscape lock while a two-page spread is open. Normal system volume control is restored after closing.
- Administrator **in-app notices** with opt-in, a GitHub-authorized publishing action and plain-text feed. They do not generate background system push notifications. See [admin guide](docs/ADMIN_NOTICES.md).
- First-launch Android security help; device security is never disabled automatically, and the user opens system settings deliberately.
- Existing library JSON data, CBZ files and signing identities are preserved across 0.x updates.

## Features implemented in the MVP

- Share a Shorts URL from YouTube to the Android app, or paste a URL in Windows.
- Extract numeric work-reference candidates from text using deterministic rules (no LLM).
- **Keyless Shorts comment lookup (experimental):** fetch public YouTube watch-page metadata and sample comments using the website's public client configuration. No personal YouTube Data API key is required; changes to YouTube, consent screens and anti-bot controls can prevent access. The optional personal Data API key remains available as an advanced fallback. If fetching fails, paste comment text manually. See [technical notes](docs/YOUTUBE_PUBLIC_COMMENTS.md).
- Inspect all candidate codes and the original text; manually enter the correct number when ambiguous.
- Local library with favorites, reading page, completion state and metadata.
- **JSON export/import** for Android-to-Android, Android-to-Windows and Windows-to-Windows library backup or merge.
- **Excel XLSX export only** to read and organize library information.
- Import user-owned CBZ/ZIP image archives per saved work; open a built-in full-screen reader with zoom, page swiping, horizontal/vertical navigation and progress saving.
- **In-app online reading:** resolve metadata and images for a numbered Hitomi gallery, then display its pages in the existing Flutter reader with saved progress. As a fallback open a fixed external web reader URL: page 1 uses `#1-`; page N>=2 uses `#N-(N+1)`.
- **Optional offline download:** press Download, review the consent dialog, and save a CBZ only if the source explicitly permits downloads. Progress and cancellation are included.
- Check public GitHub Releases, download a platform-specific installer, validate its SHA-256 digest, and request OS-approved installation (APK system installer or Windows Setup.exe).
- Windows Inno Setup installer and Android debug APK produced by the GitHub Actions verification workflow.

The reader supports local CBZ/ZIP files and numbered Hitomi galleries, with optional external web-reader links. A **separate, user-authorized JSON manifest server** is still supported for explicitly permitted offline CBZ downloads. Built-in Hitomi image reading does not imply or enable bulk downloading. No third-party imagery is bundled. JSON backups preserve metadata and progress but do not contain saved image archives.

## Try the development builds

Open the [Build and verify Actions runs](https://github.com/sopo9880/HYP_Viewer/actions/workflows/verify.yml), select a successful run, then expand **Artifacts**. The Android debug APK is for temporary development testing and may require uninstall/reinstall when switching to a consistently signed official release. JSON-export your library first.

The Windows artifact is named `HYP_Viewer_Setup_v<version>.exe` (for this release: `HYP_Viewer_Setup_v0.1.1.exe`). It installs per user and keeps the local library outside the application folder.

## Build locally

Install Flutter and platform prerequisites, then run:

```sh
flutter create --platforms=android,windows --org com.sopo9880 --project-name hyp_viewer .
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Do not use `flutter create --overwrite`: native Android sharing files already live in the repository.

## Reading locally

Save a work number, then click **CBZ/ZIP 연결** on its library card. Select a comic archive containing PNG/JPEG/WebP/GIF/BMP pages (maximum 180 MB compressed, 1500 pages). Click **읽기** to open it again; your last page is retained. Files stay in app support storage, not in the installation directory.

## Online reading and optional downloads

For in-app reading, save a numeric work ID and select **앱 내 온라인 읽기**. The app resolves gallery metadata automatically. For the external browser, use **웹 리더 · 시작 페이지 선택**; this opens the fixed `https://hitomi.la/reader/{workId}.html#...` link, but browser progress is not synchronized. To enable **JSON 소스 다운로드**, optionally configure an authorized image-source URL template such as `https://gallery.example.org/galleries/{workId}.json`. Downloads are enabled only if that source explicitly returns `allowDownload: true`. See [online sources](docs/ONLINE_SOURCES.md).

## Official releases

The reviewed 0.x release request in `.github/release-request.txt` triggers Windows and (when persistently signed) Android installers from main. The owner has explicitly required **only 0.x versions** until a future instruction to release 1.x. See [release guide](docs/RELEASE_GUIDE.md) and [version policy](docs/VERSIONING.md). The public repository does not require personal GitHub tokens to check its Releases. The updater refuses to install files lacking SHA-256 verification; Android and Windows always ask before installation.

## Privacy & backups

Data lives on each user's device. Excel is never accepted as a restore file; app-to-app migration only accepts the versioned JSON format. API credentials, secrets, images, and device-specific paths are excluded from exported libraries.

### Current public image-host routing (v0.1.3)

The built-in online reader now attempts full-sized WebP images on only the
`w1` and `w2` public image hostnames. The previous numeric-subdomain
JPG fallback (`1.gold-usergeneratedcontent.net`,
`2.gold-usergeneratedcontent.net`) was obsolete and could obscure
WebP errors with `Failed host lookup`. If WebP itself fails, the reader
shows the actual failing host and error, plus Retry and Open in Web Reader.
A successful CI run **does not establish** that a user's DNS/network or
Hitomi's current image servers are reachable.
