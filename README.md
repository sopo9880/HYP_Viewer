# HYP Viewer

Local-first **Windows setup.exe + Android APK** app for finding and organizing references from YouTube Shorts. No AI service, login, or cloud library required.

**Status:** experimental MVP. The development PR contains source code and an automated build workflow; there is no official stable release yet.

## Features implemented in the MVP

- Share a Shorts URL from YouTube to the Android app, or paste a URL in Windows.
- Extract numeric work-reference candidates from text using deterministic rules (no LLM).
- Optional YouTube Data API request to load a video's description and sampled top-level comments. **Each user must supply their own API key** to use this automatic fetch; it is not embedded or saved in exports. Without a key, paste comment text directly.
- Inspect all candidate codes and the original text; manually enter the correct number when ambiguous.
- Local library with favorites, reading page, completion state and metadata.
- **JSON export/import** for Android-to-Android, Android-to-Windows and Windows-to-Windows library backup or merge.
- **Excel XLSX export only** to read and organize library information.
- Check public GitHub Releases for a newer version and open the release page.
- Windows Inno Setup installer and Android debug APK produced by the GitHub Actions verification workflow.

The current MVP is **not yet a full gallery-image reader**. No scraped, copyrighted, or explicit imagery is bundled or distributed. Reading arbitrary remote image galleries and in-app silent auto-installation remain future work.

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

## Official releases

The tag-triggered workflow creates Windows and Android installers **after a persistent Android signing key has been configured** as GitHub Actions Secrets. Follow [the release guide](docs/RELEASE_GUIDE.md) and preserve the signing key. The public repository does not require personal GitHub tokens to check its Releases.

## Privacy & backups

Data lives on each user's device. Excel is never accepted as a restore file; app-to-app migration only accepts the versioned JSON format. API credentials, secrets, images, and device-specific paths are excluded from exported libraries.
