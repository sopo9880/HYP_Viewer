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
Missing secrets cause the official release workflow to stop. There is no
fallback to a randomly generated debug certificate.

## Official release

1. Merge a passing PR into main.
2. Increase version and build number in pubspec.yaml.
3. Create a matching annotated Git tag, such as v0.1.1, on that commit.
4. Push tag. GitHub Actions attempts the signed APK and Windows installer.
5. Both builds must pass before a release is published with SHA256SUMS.txt.

The Windows installer has a stable Inno Setup AppId and installs per user.
Flutter's application-support directory remains outside the app installation
directory, so an update is designed to retain the local library. A Windows
unsigned-publisher SmartScreen warning can appear until code signing is added.

The installed app currently checks public GitHub Releases and offers to open
the release page for user-approved installation. Fully automatic downloading
and silent installation are not implemented.

Images not owned or licensed by the user are not included in the project.
