# Building and distributing HYP Viewer

## Development artifacts
The Build and verify workflow attempts to build an Android **debug APK** and
a Windows installer on pushes and PR updates. Debug APK signatures are only
for testing; **do not treat them as upgrade-safe official releases**.

Generate native project files locally with:

    flutter create --platforms=android,windows --org com.sopo9880 --project-name hyp_viewer .
    flutter pub get
    flutter test
    flutter run -d windows

The source-controlled Android MainActivity and AndroidManifest configure
the Shorts share target. Do not pass --overwrite to flutter create.

## Android release signing

One persistent signing key is required for Android APK updates.
Generate it locally using a trusted Java keytool:

    keytool -genkeypair -v -keystore upload-keystore.jks -alias hyp-viewer -keyalg RSA -keysize 3072 -validity 10000

Store secure backups outside GitHub. Generate base64 on your own Windows PC:

    [Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard

Add these under repo Settings > Secrets and variables > Actions:

- HYP_ANDROID_KEYSTORE_BASE64: base64 string for the JKS keystore
- HYP_ANDROID_KEYSTORE_PASSWORD: your store password
- HYP_ANDROID_KEY_ALIAS: your key alias, for example hyp-viewer
- HYP_ANDROID_KEY_PASSWORD: your key password

Never send the secret values in chat or commit them to source control.
Missing secrets never cause a debug-signed APK to be published. The Windows
installer can release independently while Android waits for key configuration.

## Official v0.x releases

See [VERSIONING.md](VERSIONING.md). Every automated release must remain within
v0.MINOR.PATCH until the owner explicitly requests a 1.x release.

1. Confirm Android and Windows CI checks pass on a reviewed PR.
2. Update pubspec.yaml and bump the +build integer for Android.
3. Update .github/release-request.txt to the matching v0.x tag.
4. Merge the PR into main, triggering Publish HYP Viewer 0.x Releases.
5. The workflow validates version consistency and builds Windows Setup.exe.
   It also builds a permanently signed Android APK if signing secrets exist.
6. GitHub Releases receives the built installers and SHA256SUMS.txt.
7. If Android signing secrets were missing, add them and rerun the same
   release workflow on the same main commit to attach the signed APK.


The Windows installer has a stable Inno Setup AppId and installs per user.
Flutter's application-support directory remains outside the app installation
directory, so an update is designed to retain the local library. A Windows
unsigned-publisher SmartScreen warning can appear until code signing is added.

The installed app checks public GitHub Releases at most once a day, and can
download a platform-appropriate APK or Setup.exe to a temporary directory after
explicit approval. It checks the GitHub release SHA-256 digest, or the packaged
SHA256SUMS.txt, before requesting the OS installer. There is a second prompt
before installation, and Android's system installer still requires user approval.
Silent installation and automatic reboot/restart are not implemented.

Images not owned or licensed by the user are not included in the project.
