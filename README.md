# HYP Viewer

Local-first **Windows setup.exe + Android APK** app for finding and organizing references from YouTube Shorts. No AI service, login, or cloud library required.

**Status:** experimental v0.1.0 release candidate. Android signing must be configured for a durable release APK.

## Features implemented in the MVP

- Share a Shorts URL from YouTube to the Android app, or paste a URL in Windows.
- Extract numeric work-reference candidates from text using deterministic rules (no LLM).
- Optional YouTube Data API request to load a video's description and sampled top-level comments. **Each user must supply their own API key** to use this automatic fetch; it is not embedded or saved in exports. Without a key, paste comment text directly.
- Inspect all candidate codes and the original text; manually enter the correct number when ambiguous.
- Local library with favorites, reading page, completion state and metadata.
- **JSON export/import** for Android-to-Android, Android-to-Windows and Windows-to-Windows library backup or merge.
- **Excel XLSX export only** to read and organize library information.
- Import user-owned CBZ/ZIP image archives per saved work; open a built-in full-screen reader with zoom, page swiping, horizontal/vertical navigation and progress saving.
- **Online reading (opt-in):** configure an authorized HTTPS image source manifest, use the work ID to load pages, and read without importing a file first.
- **Optional offline download:** press Download, review the consent dialog, and save a CBZ only if the source explicitly permits downloads. Progress and cancellation are included.
- Check public GitHub Releases, download a platform-specific installer, validate its SHA-256 digest, and request OS-approved installation (APK system installer or Windows Setup.exe).
- Windows Inno Setup installer and Android debug APK produced by the GitHub Actions verification workflow.

The reader supports either locally imported CBZ/ZIP files or an **explicitly configured, authorized HTTPS manifest server** that maps the numeric work ID to images. No arbitrary third-party scraper is included. The download button saves approved remote pages as CBZ files. No third-party imagery is bundled or distributed. JSON library backups preserve metadata and reading progress but do not contain locally saved CBZ files.

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

In the app, set an authorized image-source URL template such as https://gallery.example.org/galleries/{workId}.json and click the Save Source button. A compatible server returns a JSON page manifest with an explicit allowDownload flag. Each work card offers **온라인 읽기**, **다운로드**, **오프라인 읽기** and **CBZ/ZIP 연결**. See [online source setup](docs/ONLINE_SOURCES.md) for the exact schema, permissions, file limits and limitations.

## Official releases

The reviewed 0.x release request in `.github/release-request.txt` triggers Windows and (when persistently signed) Android installers from main. The owner has explicitly required **only 0.x versions** until a future instruction to release 1.x. See [release guide](docs/RELEASE_GUIDE.md) and [version policy](docs/VERSIONING.md). The public repository does not require personal GitHub tokens to check its Releases. The updater refuses to install files lacking SHA-256 verification; Android and Windows always ask before installation.

## Privacy & backups

Data lives on each user's device. Excel is never accepted as a restore file; app-to-app migration only accepts the versioned JSON format. API credentials, secrets, images, and device-specific paths are excluded from exported libraries.
