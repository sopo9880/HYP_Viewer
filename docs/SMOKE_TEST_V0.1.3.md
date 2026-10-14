# HYP Viewer v0.1.3 설치 후 이미지 호스트 검증

v0.1.2 Windows에서 발생한 오류:
`Failed host lookup: '2.gold-usergeneratedcontent.net'`.
이 숫자 호스트는 오래된 원본 JPG 재시도 경로로, 이미지 서버 접근 문제의
실제 원인이었던 WebP 요청 실패를 가릴 수 있어.

## 업데이트

- [ ] 먼저 서재를 JSON으로 백업해.
- [ ] v0.1.3 Windows Setup.exe 또는 정식 서명 Android APK를 기존 앱 위에
      업데이트 설치해. **앱을 삭제하지 마.**
- [ ] 서재, 즐겨찾기, 읽기 위치가 유지되는지 확인해.

## 이미지 확인

1. v0.1.2에서 오류가 났던 **같은 작품**을 다시 열어.
2. 첫 이미지가 로드되고 페이지 이동이 가능한지 확인해.
3. 실패하면 오류 메시지에서 실패한 서버가
   `w1.gold-usergeneratedcontent.net` 또는
   `w2.gold-usergeneratedcontent.net`인지 확인해.
   이전의 `2.gold-usergeneratedcontent.net` 같은 숫자 호스트
   재시도는 더 이상 사용하지 않아야 해.
4. **다시 시도**, **웹 리더로 열기** 버튼이 정상 동작하는지 확인해.
5. 하단 페이지 슬라이더가 화면 중앙에 겹치지 않는지 확인해.

## DNS 문제 확인 (Windows)

오류가 `WebP 이미지 서버 DNS 조회 실패`라면 PowerShell에서 다음
명령으로 연결 상태를 비교해봐.

```powershell
Resolve-DnsName w2.gold-usergeneratedcontent.net
Resolve-DnsName ltn.gold-usergeneratedcontent.net
```

- `ltn`은 되고 `w2`만 안 되면 특정 이미지 서버 또는 DNS 정책 문제일 수 있어.
- 둘 다 실패하면 DNS/네트워크 연결 상태를 먼저 점검해.
- DNS는 정상인데 HTTP 403/404가 뜨면 접근 허용 또는 이미지 URL 형식
  문제일 수 있어. HTTP 오류를 DNS 오류로 취급하지 않아.
- 임의 IP 입력, 사용자 DNS 설정 우회 또는 로그인/접근 제한 우회는
  앱에서 수행하지 않아.

**중요:** 테스트와 빌드 성공은 실제 도메인의 DNS 응답이나 이미지 로딩
성공을 보장하지 않아. 실제 환경에서 확인한 오류 메시지와 작업 순서를
알려주면 이후 0.x 버전에서 이어서 개선할 수 있어.
