# HYP Viewer 관리자 공지 — 사용법과 한계

## 현재 제공하는 공지 기능

관리자는 GitHub에 로그인하여 **Actions → Publish administrator notice →
Run workflow**에서 제목과 본문을 입력해 공지를 발행할 수 있어.

- 워크플로: [Publish administrator notice](../.github/workflows/publish-announcement.yml)
- 공지 피드: `app-announcements` 브랜치의 `notices/feed.json`
- 읽기: `https://raw.githubusercontent.com/sopo9880/HYP_Viewer/app-announcements/notices/feed.json`
- 게시 절차: GitHub의 workflow_dispatch 권한을 가진 저장소 관리자만 실행 가능하며, 해당 워크플로는 `app-announcements` 브랜치만 수정해
- 앱은 공지 발행에 필요한 로그인 정보나 GitHub 토큰을 포함하지 않아
- 일반 사용자는 **설정 → 관리자 공지 수신 (동의)**를 켠 경우에만 앱 실행 중 약 15분마다, 앱 재실행 시 최신 공지를 확인해
- 사용자 ID나 기기 식별자를 서버로 보내지 않아. 로컬에는 마지막 확인한 공지 ID만 남겨
- 설정을 꺼도 **공지 목록 확인** 버튼으로 기존 공지를 수동 열람할 수 있어

## v0.4.8 다국어 공지 입력

공지 워크플로의 기본 제목과 본문은 한국어 그대로 유지하면서, 선택적으로
**English title/body** 및 **日本語 title/body**를 입력할 수 있어.
각 언어는 제목과 본문을 함께 입력해야 하고, 비워두면 해당 언어의 번역은 생략돼.

피드 형식은 기존 `schemaVersion: 1`을 유지하고, 다음 필드를 선택적으로 추가해.
기존 공지와 예전 버전 앱은 영향을 받지 않아.

~~~json
{
  "id": "notice_example_20261017",
  "title": "새 기능 안내",
  "message": "새 기능이 공개됐어.",
  "publishedAt": "2026-10-17T09:00:00Z",
  "translations": {
    "en": {"title": "New feature", "message": "A new feature is available."},
    "ja": {"title": "新機能のお知らせ", "message": "新機能を公開しました。"}
  }
}
~~~

새 앱은 현재 설정된 앱 언어의 번역이 있으면 해당 제목·본문을 표시해.
**기존 한국어 공지에 번역이 없다면 자동 번역하지 않아.** 영어·일본어
화면에서는 한국어 원문을 무작정 섞는 대신 해당 공지가 한국어로만 제공된다는
안내를 표시해. 앱 언어를 한국어로 변경하면 원문을 확인할 수 있어.
이 기능은 공지 발행자의 번역 입력을 지원하는 것이지 임의 자동 번역이 아니야.

## 주의: 앱 종료 상태 푸시는 아직 미지원

지금 기능은 앱 내(in-app) 공지야. Windows 알림 센터나 Android OS에서
**앱이 완전히 종료되어 있어도 울리는 원격 푸시 알림은 아냐.**
이 기능까지 원한다면 Firebase Cloud Messaging(FCM) 등 전송 서버를
별도 연결하고, 관리자 인증·수신 동의·토큰 저장/폐기·사용자 탈퇴 처리와
스팸 방지 정책을 구축해야 해. GitHub 계정 없이 임의 사용자가 전송
버튼을 호출할 수 있는 공개 API는 만들지 않아.

## 공개 범위와 운영

공지 본문은 모든 인터넷 이용자가 읽을 수 있어. 개인정보, API 키, 암호,
사적인 URL을 넣지 말아야 해. 본문은 앱의 일반 텍스트로만 표시해
임의 HTML/코드가 실행되지 않아. 최근 30개까지만 보관하고,
게시 권한은 GitHub 저장소 관리자에게만 허용해.

공지를 발행하려면 먼저 이 워크플로가 `main`에 병합되어 있어야 해.
실제 발행 검증은 관리자 본인이 GitHub Actions 실행 결과를 보고 확인해 줘.
