# HYP Viewer 빌드 및 배포 가이드

이 문서는 HYP Viewer의 **Windows 설치 프로그램(Setup.exe)**과 **Android APK**를 빌드하고 GitHub Releases에 배포하는 방법을 설명해.

> **버전 정책:** 첫 릴리스는 **v0.1.0**이며, 사용자가 별도로 1.x 릴리스를 요청하기 전까지 모든 버전은 **v0.x.x**로 유지해. 자세한 규칙은 [버전 관리 정책](VERSIONING.md)을 참고해.

## 1. 개발용 설치 파일

GitHub Actions의 **Build and verify** 워크플로는 개발 브랜치나 Pull Request의 코드를 검사하고 다음 설치 파일을 빌드해.

| 플랫폼 | 개발용 결과물 | 주의사항 |
| --- | --- | --- |
| Android | 디버그 APK | 개발·설치 테스트용이며 정식 배포용이 아님 |
| Windows | Setup.exe | Windows에 설치할 수 있는 테스트용 설치 프로그램 |

개발용 APK의 디버그 서명은 정식 릴리스의 서명과 달라. **디버그 APK를 계속 업데이트할 수 있는 정식 APK로 취급하면 안 돼.**

빌드 결과물은 GitHub 저장소의 [Actions](https://github.com/sopo9880/HYP_Viewer/actions)에서 성공한 **Build and verify** 실행을 선택한 뒤, **Artifacts** 항목에서 다운로드할 수 있어.

### PC에서 직접 빌드하기

먼저 Flutter SDK와 필요한 Android SDK / Windows 빌드 도구를 설치해. 이후 프로젝트 폴더에서 다음 명령어를 실행하면 돼.

~~~bash
flutter create --platforms=android,windows --org com.sopo9880 --project-name hyp_viewer .
flutter pub get
flutter test
flutter run -d windows
~~~

Android의 `MainActivity`와 `AndroidManifest.xml`에는 YouTube 쇼츠 공유 메뉴를 받는 코드가 들어 있어. 기존 파일을 덮어쓸 수 있으므로 **`flutter create --overwrite`는 사용하지 마.**

## 2. Android 정식 APK 서명 키 설정

정식 APK를 배포하고 나중에 **기존 앱을 삭제하지 않고 업데이트**하려면, 모든 Android 릴리스에 **동일한 서명 키**를 사용해야 해.

서명 키는 처음 한 번 생성하고 반드시 안전한 장소에 백업해. 키를 분실하면 기존 앱을 동일한 방식으로 업데이트하기 어려워질 수 있어.

### 2-1. 서명 키 생성

본인 PC에서 PowerShell 또는 터미널을 열고 아래 명령어를 실행해.

~~~powershell
keytool -genkeypair -v -keystore upload-keystore.jks -alias hyp-viewer -keyalg RSA -keysize 3072 -validity 10000
~~~

실행 중 비밀번호와 인증서 정보를 입력하게 돼. 생성되는 `upload-keystore.jks`는 **비공개로 보관**하고 GitHub 저장소에 업로드하지 마.

> `keytool` 명령어를 찾지 못하면 Java JDK 설치 및 PATH 설정을 확인해.

### 2-2. 서명 키를 Base64로 변환

GitHub Actions Secrets에 등록하기 위해, `upload-keystore.jks`가 있는 폴더에서 아래 PowerShell 명령어를 실행해.

~~~powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
~~~

실행하면 **JKS 키 파일의 Base64 내용이 클립보드에 복사**돼. 이 내용도 민감한 정보니까 채팅이나 공개 게시물에 붙여넣지 마.

### 2-3. GitHub Actions Secrets 등록

[HYP_Viewer의 Actions Secrets 설정](https://github.com/sopo9880/HYP_Viewer/settings/secrets/actions)을 열어.

**Settings → Secrets and variables → Actions → New repository secret**

아래 네 가지 Secret을 각각 생성해.

| Secret 이름 | 입력할 값 |
| --- | --- |
| `HYP_ANDROID_KEYSTORE_BASE64` | 앞 단계에서 복사한 JKS 파일의 Base64 문자열 |
| `HYP_ANDROID_KEYSTORE_PASSWORD` | 키 저장소 생성 시 정한 비밀번호 |
| `HYP_ANDROID_KEY_ALIAS` | 키 별칭. 위 명령어대로 생성했다면 `hyp-viewer` |
| `HYP_ANDROID_KEY_PASSWORD` | 해당 키 별칭의 비밀번호 |

**네 항목 중 하나라도 빠지면 정식 Android APK는 빌드하지 않도록 구성했어.** 대신 디버그 서명의 APK를 정식 배포 파일로 올리는 일은 없게 했어.

키 파일은 GitHub 외부에도 별도로 백업해. Secret에 등록했다는 이유로 원본 키 파일을 삭제하면 안 돼.

## 3. 정식 v0.x.x 릴리스 발행

릴리스는 `main` 브랜치에 병합된 **검토 완료 코드**를 기준으로 발행돼.

1. 개발 PR의 Android 및 Windows CI가 모두 통과했는지 확인해.
2. `pubspec.yaml`의 `version`을 새 버전에 맞추고, `+` 뒤의 Android 빌드 번호도 업데이트할 때마다 늘려.
3. `.github/release-request.txt`에도 같은 버전의 태그를 적어.
4. 준비된 PR을 `main`에 병합하면 **Publish HYP Viewer 0.x Releases** 워크플로가 실행돼.
5. 워크플로가 버전 정책을 검사한 후 Windows `Setup.exe`를 빌드해. 서명 키가 준비돼 있으면 정식 Android APK도 빌드해.
6. 완료된 설치 파일과 체크섬 파일(`SHA256SUMS.txt`)이 [GitHub Releases](https://github.com/sopo9880/HYP_Viewer/releases)에 올라가.

첫 번째 릴리스는 다음과 같이 맞추면 돼.

| 항목 | v0.1.0 예시 |
| --- | --- |
| `pubspec.yaml` | `version: 0.1.0+1` |
| `.github/release-request.txt` | `v0.1.0` |
| Windows 설치 파일 | `HYP_Viewer_Setup_v0.1.0.exe` |
| Android 정식 APK | `HYP_Viewer_v0.1.0.apk` |

> **중요:** 네가 직접 요청하기 전까지 `v1.0.0` 이상의 릴리스는 허용하지 않아. 자동 릴리스 과정에서도 `0.x.x` 이외의 버전을 거부하도록 설정했어.

### Android 서명 키를 아직 등록하지 않았다면?

**Windows 설치 파일만 포함된 v0.1.0 릴리스**가 먼저 발행될 수 있어. 이때 정식 Android APK는 포함되지 않아.

이후 네 가지 Android Secrets를 모두 등록하고, **같은 `main` 커밋에서 릴리스 워크플로를 수동으로 다시 실행**하면 기존 버전의 릴리스에 정식 서명 APK를 첨부할 수 있도록 구성되어 있어. 기존 태그가 다른 커밋을 가리키면 덮어쓰지 않아.

## 4. Windows 설치 및 업데이트

Windows 설치 프로그램은 **Inno Setup**으로 만들어져.

- 사용자 계정 기준으로 설치하므로 일반적으로 관리자 권한이 필요하지 않아.
- 업데이트 후에도 기존 프로그램 식별자(`AppId`)가 유지돼.
- 앱 데이터 폴더와 프로그램 설치 폴더가 분리되어 있어, 일반적인 업데이트 때 **서재와 읽기 기록을 유지**하도록 설계했어.
- 현재 Windows 설치 파일에는 **Authenticode 코드 서명 인증서**가 없어. Windows SmartScreen에서 게시자를 확인할 수 없다는 경고가 나올 수 있어.

## 5. 앱 내부 업데이트 기능

HYP Viewer는 공개된 GitHub Releases에서 새 버전을 확인해.

1. 앱 실행 시 최대 **24시간에 한 번** 최신 릴리스를 확인해.
2. 현재보다 높은 버전이 있으면 업데이트를 안내해.
3. 사용자가 동의하면 운영체제에 맞는 APK 또는 Setup.exe를 임시 폴더에 다운로드해.
4. 설치 파일의 **SHA-256 값**을 GitHub의 릴리스 검증 정보 또는 `SHA256SUMS.txt`와 비교해.
5. 검증을 통과하면 **설치 여부를 다시 확인한 뒤** 운영체제의 설치 기능을 실행해.

Android에서는 시스템 설치 확인창에서 사용자가 직접 승인해야 해. Windows에서도 기존 앱 종료나 설치 확인이 필요할 수 있어.

**사용자 몰래 설치하거나 자동으로 컴퓨터를 재부팅하는 기능은 구현하지 않았어.**

## 6. 개인정보 및 콘텐츠 관련 주의사항

- JSON 백업에는 서재·즐겨찾기·작품 번호·읽기 진행도 등의 정보가 들어가지만, **다운로드한 CBZ 이미지 파일은 포함되지 않아.**
- Excel(`.xlsx`)은 **서재 내보내기 전용**이고, 앱 간 백업·복원은 JSON만 지원해.
- GitHub 토큰, YouTube API 키, 서명 키, 개인 서재 파일을 소스코드나 릴리스에 포함하면 안 돼.
- 본인에게 접근·저장 권한이 있는 이미지 소스만 연결해. 저작권자 허가가 없는 이미지 파일은 배포 프로그램에 포함하지 않아.

---

**관련 문서:** [버전 정책](VERSIONING.md) · [온라인 이미지 소스 연결](ONLINE_SOURCES.md) · [GitHub Releases](https://github.com/sopo9880/HYP_Viewer/releases)
