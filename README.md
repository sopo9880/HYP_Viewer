# HYP Viewer

Local-first **Windows setup.exe + Android APK** app for finding and organizing references from YouTube Shorts. No AI service, login, or cloud library required.

**Status:** v0.1.0 is published. This feature branch contains unreleased changes intended for the next 0.x update; it is not a new release yet.

## Features implemented in the MVP

- Share a Shorts URL from YouTube to the Android app, or paste a URL in Windows.
- Extract numeric work-reference candidates from text using deterministic rules (no LLM).
- **Keyless Shorts comment lookup (experimental on this branch):** fetch public YouTube watch-page metadata and sample comments using the website's public client configuration. No personal YouTube Data API key is required; changes to YouTube, consent screens and anti-bot controls can prevent access. The optional personal Data API key remains available as an advanced fallback. If fetching fails, paste comment text manually. See [technical notes](docs/YOUTUBE_PUBLIC_COMMENTS.md).
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

The Windows artifact contains `HYP_Viewer_Setup_v0.1.0.exe`. It installs per user and keeps the local library outside the application folder.

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
