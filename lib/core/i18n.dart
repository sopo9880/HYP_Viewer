import 'package:flutter/material.dart';

/// Device-local UI language. Persisted with ReaderSettings; no account or
/// network service is involved. Korean remains the default for old installs.
abstract final class HypLanguage {
  static final ValueNotifier<String> selected = ValueNotifier<String>('ko');
  static const supported = <String>{'ko', 'en', 'ja'};
}

/// Translation keys are the existing Korean UI strings, so old code and
/// existing backups do not need rewriting. Unrecognized gallery metadata
/// and user-authored titles are intentionally returned unchanged.
abstract final class HypI18n {
  static const Map<String, List<String>> _labels = {
    '홈': ['Home', 'ホーム'],
    '서재': ['Library', '本棚'],
    '내 서재': ['My Library', 'マイ本棚'],
    '즐겨찾기': ['Favorites', 'お気に入り'],
    '다운로드': ['Downloads', 'ダウンロード'],
    '열람 기록': ['Reading History', '閲覧履歴'],
    '설정': ['Settings', '設定'],
    '업데이트': ['Updates', 'アップデート'],
    '관리자 공지': ['Admin Notices', '管理者のお知らせ'],
    '관리자 공지 확인': ['Check Notices', 'お知らせを確認'],
    '추가 메뉴': ['More options', 'その他のメニュー'],
    '알림 닫기': ['Dismiss notification', '通知を閉じる'],
    '오프라인 보관함': ['Offline Storage', 'オフライン保存'],
    '좋아하는 이야기를,\n더 가까이': ['Your favorite stories,\ncloser than ever', 'お気に入りの物語を、\nもっと身近に'],
    'JSON 백업': ['JSON Backup', 'JSONバックアップ'],
    'JSON 서재 가져오기': ['Import Library JSON', '本棚JSONを読み込む'],
    'JSON 내보내기': ['Export JSON', 'JSONを書き出す'],
    'JSON 가져오기': ['Import JSON', 'JSONを読み込む'],
    'Excel 내보내기': ['Export Excel', 'Excelを書き出す'],
    '앱 업데이트': ['App Updates', 'アプリの更新'],
    '업데이트 확인': ['Check for Updates', '更新を確認'],
    '확인': ['OK', '確認'],
    '취소': ['Cancel', 'キャンセル'],
    '알겠어': ['Got it', '了解'],
    '나중에': ['Later', '後で'],
    '저장': ['Save', '保存'],
    '전체 보기': ['View All', 'すべて表示'],
    '더보기': ['See More', 'もっと見る'],
    '작품 제목, 작가, 번호, 목록으로 검색하세요...': ['Search titles, creators, IDs, and collections...', 'タイトル・作者・番号・コレクションで検索...'],
    '추가한 작품과 읽기 진행도를 관리하세요.': ['Manage saved works and reading progress.', '保存した作品と読書の進捗を管理します。'],
    '하트를 누른 작품만 모아 보여줘.': ['Only show works you favorited.', 'お気に入りにした作品だけを表示します。'],
    '최근 읽기 화면을 연 순서대로 표시해.': ['Shows works by most recent reading activity.', '最近読んだ順に作品を表示します。'],
    '최근 본 작품': ['Recently Read', '最近読んだ作品'],
    '최근 열람한 작품을 이어서 감상하세요.': ['Continue where you left off.', '前回の続きから読みましょう。'],
    '추천 작품': ['Suggested Works', 'おすすめ作品'],
    '즐겨찾기한 작품 중 다시 살펴볼 작품이야.': ['Rediscover your favorite works.', 'お気に入りの作品をもう一度。'],
    '아직 열람 기록이 없어': ['No reading history yet', 'まだ閲覧履歴がありません'],
    '서재에 작품을 추가하고 읽기를 시작하면 여기에 표시돼.': ['Add a work and start reading to see it here.', '作品を追加して読むと、ここに表示されます。'],
    '아직 추천할 서재 작품이 없어': ['No suggested works yet', 'おすすめ作品はまだありません'],
    '임의 추천 대신 실제 즐겨찾기한 작품만 표시해.': ['Shows actual favorites, not random picks.', 'ランダムではなく、お気に入りの作品を表示します。'],
    '내 서재 보기': ['Open Library', '本棚を開く'],
    '검색 결과': ['Search Results', '検索結果'],
    '홈에서 번호를 찾아 저장하거나 서재에서 작품을 열어봐.': ['Find a work number on Home or open a saved work.', 'ホームで作品番号を探すか、保存した作品を開いてください。'],
    '작품 다운로드 중': ['Downloading Work', '作品をダウンロード中'],
    '계속': ['Resume', '再開'],
    '일시정지': ['Pause', '一時停止'],
    '다운로드한 작품이 없어': ['No Offline Works', 'ダウンロード済みの作品がありません'],
    '서재에서 다운로드하거나 CBZ/ZIP을 연결하면 이곳에 표시돼.': ['Download from the library or import CBZ/ZIP files.', '本棚からダウンロードするかCBZ/ZIPを読み込んでください。'],
    '표지를 바꿀 작품 선택': ['Select Work to Edit Cover', '表紙を変更する作品を選択'],
    '작품 번호 또는 제목': ['Work ID or title', '作品番号またはタイトル'],
    '쇼츠 작품 번호 찾기': ['Find Works from Shorts', 'ショート動画から作品を探す'],
    'Shorts 링크만 붙여넣으면 공개 설명란·댓글에서 번호를 찾아봐. API 키는 필요 없어.': ['Paste a Shorts URL to scan public descriptions and comments. No API key required.', 'ショート動画のURLで公開概要欄・コメントから番号を探します。APIキーは不要です。'],
    'YouTube Shorts 링크 또는 작품 번호 입력': ['Enter a Shorts URL or work ID', 'ショート動画のURLまたは作品番号を入力'],
    '개인 YouTube Data API 키 (고급 · 선택)': ['Personal YouTube Data API key (optional)', '個人用YouTube Data APIキー（任意）'],
    'API 키 숨기기': ['Hide API key', 'APIキーを隠す'],
    'API 키 보기': ['Show API key', 'APIキーを表示'],
    '작품 찾기': ['Find Work', '作品を探す'],
    '고급 설정 · 내 YouTube Data API 키 사용 (선택)': ['Advanced · Use your YouTube Data API key (optional)', '詳細設定・YouTube Data APIキーを使用（任意）'],
    '후보를 누르면 번호가 입력돼. 아래에서 확인 후 저장해줘.': ['Tap a candidate to fill its ID. Confirm before saving.', '候補をタップして番号を入力。確認してから保存してください。'],
    '기본 조회는 API 키 없이 YouTube 공개 페이지에서 댓글을 읽어. 유튜브 제한으로 실패할 수도 있어. 이때는 직접 댓글을 복사해 붙여넣어줘.': ['Comments are read from public YouTube pages without an API key. If access is blocked, paste the comments manually.', '通常はAPIキーなしで公開コメントを取得します。取得できない場合はコメントをコピーして貼り付けてください。'],
    '설명란 · 댓글 자동 조회': ['Fetch Description & Comments', '概要欄とコメントを取得'],
    '유튜브 열고 댓글 복사': ['Open YouTube & Copy Comments', 'YouTubeでコメントをコピー'],
    '댓글·번호 입력 접기': ['Hide Details', '詳細を閉じる'],
    '댓글 직접 입력 · 번호 확정': ['Enter Comments / Work ID', 'コメント・作品番号を入力'],
    '설명란 / 댓글 원문': ['Description / Original Comments', '概要欄・コメント原文'],
    '댓글 내용을 붙여넣으면 숫자 후보를 추출할 수 있어.': ['Paste comments to extract candidate IDs.', 'コメントを貼り付けて番号候補を抽出します。'],
    '원문에서 번호 추출': ['Extract IDs', '番号を抽出'],
    '추출된 후보 · 여러 작품은 체크 후 함께 저장해줘': ['Found candidates · select multiple to save together', '抽出した候補・複数選択してまとめて保存'],
    '추출된 모든 숫자가 실제 작품 번호는 아니야. 선택된 번호를 확인하고 저장해줘.': ['Not all detected numbers are valid work IDs. Verify before saving.', '抽出された番号はすべて作品番号とは限りません。確認して保存してください。'],
    '확정 작품 번호 *': ['Confirmed Work ID *', '確定した作品番号 *'],
    '작품명 (선택)': ['Title (optional)', '作品名（任意）'],
    '비워두면 작품 번호로 실제 제목을 조회해': ['Leave blank to look up the title by ID', '空欄の場合は番号から作品名を取得します'],
    '작가 (선택)': ['Creator (optional)', '作者（任意）'],
    '확정한 작품을 서재에 저장': ['Save Work to Library', '作品を本棚に保存'],
    '후보 번호는 자동 검증된 작품 번호가 아니야. 원문을 보고 직접 확인한 뒤 저장해줘.': ['Candidate IDs are not verified. Check the source before saving.', '候補番号は未検証です。原文を確認してから保存してください。'],
    '좋아하는 이야기를,\n언제 어디서나': ['Your favorite stories,\nanytime, anywhere', 'お気に入りの物語を、\nいつでもどこでも'],
    '내 서재 속 이야기를,\n한 곳에서': ['All your stories,\nin one library', 'お気に入りの物語を、\nひとつの本棚に'],
    '읽던 이야기의\n다음 페이지까지': ['Pick up right\nwhere you left off', '続きのページへ、\nいつでも'],
    '웹의 이미지 작품과 내가 가진 파일을\n더 편리하게 감상하세요.': ['Read online image works and your own files\nin one convenient viewer.', 'オンライン作品や手持ちのファイルを\n快適に楽しめます。'],
    '즐겨찾기와 작품 번호, 기록을\n내 기기에서 관리하세요.': ['Manage favorites, work IDs and reading history\non your device.', 'お気に入り・作品番号・閲覧履歴を\n端末で管理できます。'],
    '오프라인으로 저장한 작품은\n인터넷 없이 이어서 읽으세요.': ['Read downloaded works\nwithout an internet connection.', '保存した作品は\nオフラインでも読めます。'],
    '이전 소개': ['Previous Slide', '前の紹介'],
    '다음 소개': ['Next Slide', '次の紹介'],
    '서재 열기': ['Open Library', '本棚を開く'],
    '다운로드 보기': ['View Downloads', 'ダウンロードを見る'],
    '오프라인 읽기': ['Read Offline', 'オフラインで読む'],
    '앱 내 온라인 읽기': ['Read Online in App', 'アプリでオンライン閲覧'],
    '웹 리더 · 시작 페이지 선택': ['Web Reader · Choose Page', 'Webビューアー・開始ページ選択'],
    '온라인 작품 오프라인 저장': ['Download for Offline Reading', '作品をオフライン保存'],
    '추가 JSON 소스 다운로드': ['Download from JSON Source', 'JSONソースからダウンロード'],
    '오프라인 파일 삭제': ['Delete Offline Files', 'オフラインファイルを削除'],
    'CBZ/ZIP 연결': ['Import CBZ/ZIP', 'CBZ/ZIPを読み込む'],
    '표지 선택': ['Choose Cover', '表紙を選択'],
    '즐겨찾기 해제': ['Remove Favorite', 'お気に入り解除'],
    '원본 쇼츠': ['Original Shorts', '元のショート動画'],
    '서재에서 작품 삭제': ['Remove Work from Library', '本棚から作品を削除'],
    '완독': ['Finished', '読了'],
    '작품 메뉴': ['Work Menu', '作品メニュー'],
    '페이지를 서재 표지로 지정했어.': ['Page set as library cover.', 'ページを表紙に設定しました。'],
    '페이지를 불러오지 못했어.': ['Unable to load page.', 'ページを読み込めません。'],
    '다시 시도': ['Retry', '再試行'],
    '웹 리더로 열기': ['Open in Web Reader', 'Webビューアーで開く'],
    '이미지를 불러오는 중…': ['Loading image…', '画像を読み込み中…'],
    '이전 페이지 (PageUp)': ['Previous Page (PageUp)', '前のページ (PageUp)'],
    '다음 페이지 (PageDown / Space)': ['Next Page (PageDown / Space)', '次のページ (PageDown / Space)'],
    '온라인 이미지를 CBZ로 저장': ['Save Online Images as CBZ', 'オンライン画像をCBZとして保存'],
    '현재 페이지를 서재 표지로 지정': ['Use Current Page as Cover', '現在のページを表紙にする'],
    '페이지 도구 숨기기': ['Hide Page Controls', 'ページ操作を隠す'],
    '페이지 도구 표시': ['Show Page Controls', 'ページ操作を表示'],
    '현재 페이지를 웹 리더로 열기': ['Open Page in Web Reader', '現在のページをWebで開く'],
    '가로 넘기기': ['Horizontal Paging', '横方向にページ送り'],
    '세로 넘기기': ['Vertical Paging', '縦方向にページ送り'],
    '뷰어 조작, 기본 표지, 추가 다운로드 소스와 앱 데이터를 관리해.': ['Manage reading controls, covers, downloads and app data.', '閲覧操作・表紙・ダウンロード・アプリデータを管理します。'],
    '홈 배너 일러스트': ['Home Banner Artwork', 'ホームバナーの画像'],
    '첫 화면의 "좋아하는 이야기를, 언제 어디서나" 배경 일러스트를 직접 설정할 수 있어.': ['Choose custom artwork for the home introduction banner.', 'ホームの紹介バナーに好きな画像を設定できます。'],
    '일러스트 업로드': ['Upload Artwork', '画像をアップロード'],
    '일러스트 교체': ['Replace Artwork', '画像を変更'],
    '기본 배경으로 되돌리기': ['Restore Default Background', '標準の背景に戻す'],
    'PNG · JPG · WebP (최대 12MB). 이미지 자체는 이 기기에 저장되며 서재 JSON 백업에는 포함되지 않아.': ['PNG, JPG or WebP (up to 12 MB). Stored only on this device, not in JSON backups.', 'PNG・JPG・WebP（最大12MB）。端末内に保存され、JSONバックアップには含まれません。'],
    '이미지 뷰어 설정': ['Image Viewer Settings', '画像ビューアー設定'],
    '읽기 방향을 정하면 화면 스와이프와 방향키도 함께 적용돼.': ['Reading direction also changes swipe and arrow-key behavior.', '読む方向はスワイプと方向キーにも適用されます。'],
    '다음 페이지로 넘기는 방향': ['Direction to Next Page', '次のページに進む方向'],
    '왼쪽으로 넘기기 (→ 다음 페이지)': ['Swipe Left (→ Next Page)', '左にスワイプ（→ 次のページ）'],
    '오른쪽으로 넘기기 (← 다음 페이지)': ['Swipe Right (← Next Page)', '右にスワイプ（← 次のページ）'],
    '서재 추가 후 작품 자동 열기': ['Open Work after Adding', '保存後に作品を自動で開く'],
    '기본값은 끔. 켜면 한 작품을 저장한 직후 뷰어를 열어. 여러 작품을 한 번에 저장하면 서재로 이동해.': ['Off by default. When enabled, saving one work opens the reader. Saving multiple works opens the library.', '初期設定はオフ。オンにすると1作品の保存後にビューアーを開きます。複数作品は本棚へ移動します。'],
    '2쪽 모아보기': ['Two-Page Spread', '見開き表示'],
    '1-2, 3-4처럼 두 페이지를 한 화면에 표시': ['Show two pages side by side', '2ページずつ並べて表示'],
    '세로로 페이지 넘기기': ['Vertical Scrolling', '縦スクロール'],
    '뷰어 오른쪽 위의 가로/세로 전환 버튼과 같은 설정이야. 종료 후에도 유지돼. 2쪽 모아보기는 가로로 표시돼.': ['Same as the top-right orientation button. Saved across launches; spreads remain horizontal.', '右上の縦横切替と同じ設定です。再起動後も保持され、見開きは横表示です。'],
    '뷰어 오른쪽 위 아이콘 구성': ['Top-Right Reader Buttons', 'ビューアー右上のボタン'],
    '각 버튼을 표시하거나 숨길 수 있어. 기본값은 모두 표시야.': ['Show or hide individual buttons; all are shown by default.', 'ボタンごとに表示を切り替えられます。初期設定はすべて表示です。'],
    '다운로드 버튼 표시': ['Show Download Button', 'ダウンロードボタンを表示'],
    '온라인 이미지 저장 버튼': ['Download online images', 'オンライン画像の保存ボタン'],
    '표지 지정 버튼 표시': ['Show Set Cover Button', '表紙設定ボタンを表示'],
    '현재 페이지를 표지로 등록하는 버튼': ['Use current page as cover', '現在のページを表紙にするボタン'],
    '페이지 도구 버튼 표시': ['Show Page Controls Button', 'ページ操作ボタンを表示'],
    '하단 페이지 바 표시/숨기기 버튼': ['Toggle bottom progress bar', '下部のページバーの表示切替'],
    '웹 리더 버튼 표시': ['Show Web Reader Button', 'Webビューアーボタンを表示'],
    '현재 페이지를 브라우저에서 열기': ['Open current page in browser', '現在のページをブラウザで開く'],
    '가로/세로 전환 버튼 표시': ['Show Orientation Button', '縦横切替ボタンを表示'],
    '뷰어 오른쪽 위 전환 버튼': ['Top-right orientation button', '右上の縦横切替ボタン'],
    '앞뒤 미리 로딩 페이지': ['Page Preloading', 'ページ先読み'],
    '끄기': ['Off', 'オフ'],
    '1장씩': ['1 Page', '1ページ'],
    '2장씩 (추천)': ['2 Pages (Recommended)', '2ページ（おすすめ）'],
    '3장씩': ['3 Pages', '3ページ'],
    '키보드(뷰어): ← / →, PageUp / PageDown, Space, Home / End, Esc(닫기). 서재의 작품 메뉴에서 표지 선택 가능.': ['Reader keys: ←/→, PageUp/PageDown, Space, Home/End, Esc. Covers can be edited from a work menu.', 'ビューアーのキー: ←/→、PageUp/PageDown、Space、Home/End、Esc。表紙は作品メニューで変更できます。'],
    '표지 자동 설정 및 편집': ['Automatic Covers & Editing', '表紙の自動設定と編集'],
    '새 작품의 첫 페이지를 자동 표지로 사용': ['Use First Page as New Cover', '新しい作品の1ページ目を表紙にする'],
    '끄면 새 작품은 기본 디자인 표지로 시작해. 기존에 직접 지정한 표지는 바뀌지 않아.': ['When off, new works use built-in covers. Existing custom covers stay unchanged.', 'オフの場合は標準の表紙を使用します。既存の表紙は変更されません。'],
    '서재 작품 표지 편집 · 이미지 업로드 및 자르기': ['Edit Work Covers · Upload & Crop', '作品の表紙を編集・アップロードと切り抜き'],
    '이미지를 선택하거나 작품 페이지를 불러온 뒤, 미리보기 영역에서 드래그·확대·축소하여 표지를 만들 수 있어.': ['Choose an image or page, then drag and zoom to crop a cover.', '画像またはページを選び、ドラッグや拡大縮小で表紙を編集します。'],
    'Android 뷰어 동작': ['Android Reader Controls', 'Androidビューアー操作'],
    '볼륨키로 페이지 넘기기': ['Turn Pages with Volume Keys', '音量キーでページを送る'],
    '뷰어가 열려 있을 때 볼륨+는 이전, 볼륨−는 다음 페이지. 소리 조절은 일시적으로 대신 사용돼.': ['In the reader, Volume+ goes back and Volume− advances instead of changing sound.', 'ビューアーでは音量＋で前、音量−で次のページへ進みます。'],
    '2쪽 보기에서 가로 화면 고정': ['Lock Landscape for Spreads', '見開き時に横画面を固定'],
    'Android에서 2쪽 모아보기일 때만 가로 방향으로 열어. 끄면 휴대폰을 돌려 자유롭게 회전할 수 있어.': ['Lock to landscape only for two-page spreads; otherwise allow rotation.', 'Androidの見開き時のみ横画面に固定します。オフなら自由に回転できます。'],
    '관리자 공지 수신 (동의)': ['Receive Admin Notices (Opt-in)', '管理者のお知らせを受信'],
    '앱 실행 중이나 재실행 시 공개 공지를 확인해. 앱을 종료한 상태의 시스템 푸시 알림은 아직 지원하지 않아.': ['Check public notices while open or on launch. Background push is not supported.', 'アプリ起動中または起動時にお知らせを確認します。バックグラウンド通知には未対応です。'],
    '공지 목록 확인': ['View Notices', 'お知らせ一覧を確認'],
    'Android 설치 및 보안 위험 자동 차단 안내': ['Android Installation & Security Guidance', 'Androidのインストールとセキュリティ案内'],
    '기본 웹 리더 (주소 고정)': ['Default Web Reader', '標準Webビューアー'],
    '기본 온라인 읽기는 이미지 메타데이터를 이용해 앱 안에서 열어. 작품 메뉴의 웹 리더를 선택하면 브라우저에서 고정 링크를 열 수 있어. 1페이지는 #1-, 2페이지부터는 #2-3 형식이야.': ['Online works open inside the app. The work menu can open a fixed web URL (#1- for page one, #2-3 for page two).', 'オンライン作品はアプリ内で開きます。作品メニューから固定URLのWebビューアーも使用できます。'],
    '앱 안에서 읽는 경우에는 페이지 진행도가 저장돼. 외부 브라우저에서 넘긴 페이지는 자동 기록되지 않아.': ['In-app reading saves progress. Reading in an external browser does not.', 'アプリ内で読むと進捗が保存されます。外部ブラウザでは記録されません。'],
    '추가 JSON 이미지 소스 (선택)': ['Additional JSON Image Source (optional)', '追加のJSON画像ソース（任意）'],
    '자체 보유하거나 이용 허가된 JSON 이미지 서버를 통해 오프라인 저장하려는 경우에만 설정해줘. 기본 온라인 읽기나 웹 리더에 필요하지 않아.': ['Use only with JSON image servers you own or are allowed to download from. Not required for regular reading.', '所有または許可されたJSON画像サーバーで保存する場合のみ設定してください。通常の閲覧には不要です。'],
    '추가 JSON 소스 URL 패턴': ['Additional JSON Source URL Pattern', '追加JSONソースのURLパターン'],
    '추가 JSON 소스로 다운로드할 때만 사용하는 고급 설정이야.': ['Advanced setting for JSON downloads only.', 'JSONダウンロード専用の詳細設定です。'],
    '소스 설정 저장': ['Save Source Settings', 'ソース設定を保存'],
    '서재 데이터': ['Library Data', '本棚のデータ'],
    'JSON은 백업·기기 이전용, Excel은 확인용이야.': ['JSON is for backups/transfers; Excel is for viewing.', 'JSONはバックアップ・移行用、Excelは確認用です。'],
    '최신 0.x 업데이트 · GitHub Releases': ['Latest 0.x updates · GitHub Releases', '最新0.x版・GitHub Releases'],
    '한국어': ['Korean', '韓国語'],
    '영어': ['English', '英語'],
    '일본어': ['Japanese', '日本語'],
    '언어': ['Language', '言語'],
    '앱 언어': ['App Language', 'アプリの言語'],
    '언어를 바꾸면 메뉴와 버튼에 즉시 적용되고 다음 실행에도 유지돼.': ['Language changes apply immediately and persist across launches.', '言語の変更はすぐに反映され、再起動後も保持されます。'],
    '현재 버전': ['Current Version', '現在のバージョン'],
    '번호만 입력하면 바로 서재에 저장해. Shorts 링크는 댓글에서 후보를 찾아줘.': ['Enter an ID to save directly to the library. Shorts URLs scan comments for candidates.', '番号だけで本棚に保存できます。ショート動画のURLからはコメントを検索します。'],
    '서재 표지 선택': ['Choose Library Cover', '本棚の表紙を選択'],
    '기본 디자인 6종, 작품 내 원하는 페이지, 내 사진 중에서 표지를 선택할 수 있어.': ['Choose from six presets, any work page, or your own photo.', '6種類の標準デザイン、作品のページ、自分の写真から選べます。'],
    '자동: 작품 첫 페이지': ['Auto: First Page', '自動：作品の1ページ目'],
    '열람하면서 첫 페이지 미리보기를 생성해': ['Generate the first-page thumbnail as you read.', '閲覧時に1ページ目のサムネイルを作成します。'],
    '기본 표지 디자인': ['Built-in Cover Designs', '標準の表紙'],
    '내 이미지 업로드': ['Upload My Image', '画像をアップロード'],
    '사진 파일을 선택한 뒤 드래그·확대해서 자르기': ['Drag and zoom to crop a photo', '画像をドラッグ・拡大して切り抜き'],
    '작품 내 페이지 선택': ['Choose a Work Page', '作品内のページを選択'],
    '이미지 한 장을 축소해 저장 (네트워크 필요)': ['Resize and save one page (internet required)', 'ページを縮小して保存（通信が必要）'],
    '표지로 사용할 페이지 번호': ['Cover Page Number', '表紙にするページ番号'],
    '선택한 페이지 번호는 JSON 백업에 저장돼. 썸네일 이미지 파일은 기기 내부에 저장되므로 다른 기기로 옮기면 다시 생성해야 해.': ['The page number is backed up; image thumbnails stay on this device.', 'ページ番号はバックアップされますが画像データは端末内のみです。'],
    '표지 적용': ['Apply Cover', '表紙を適用'],
    '표지 자르기': ['Crop Cover', '表紙を切り抜く'],
    '위치 및 확대 초기화': ['Reset Position & Zoom', '位置と拡大率をリセット'],
    '저장 중…': ['Saving…', '保存中…'],
    '이 영역 저장': ['Save This Crop', 'この範囲を保存'],
    '서재에서 삭제': ['Remove from Library', '本棚から削除'],
    '로컬 파일도 함께 삭제': ['Also Delete Local Files', 'ローカルファイルも削除'],
    '파일 삭제': ['Delete Files', 'ファイルを削除'],
    '다운로드한 CBZ와 기기 내 표지 미리보기까지 삭제. 선택하지 않으면 파일은 남아서 작품 재등록 시 다시 사용할 수 있어.': ['Also delete saved CBZs and local covers. Unchecked files remain available for reimport.', '保存したCBZと表紙画像も削除します。未選択なら再登録時に利用できます。'],
    '서재 목록에서 제거하면 이 작품의 즐겨찾기와 읽기 기록도 함께 제거돼. 다른 작품은 유지돼.': ['Removes this work, favorites and reading history. Other works remain.', 'この作品のお気に入りと閲覧履歴も削除します。他の作品には影響しません。'],
    'CBZ 이미지만 삭제할까? 서재 기록·즐겨찾기·표지는 그대로 유지돼.': ['Delete only CBZ images? Library records, favorites and covers stay.', 'CBZ画像のみ削除しますか？本棚・お気に入り・表紙は保持されます。'],
  };

  static String translate(String text, String language) {
    if (language == 'ko') return text;
    final entry = _labels[text];
    if (entry != null) return entry[language == 'ja' ? 1 : 0];
    final version = RegExp(r'^현재 버전: (.+)$').firstMatch(text);
    if (version != null) {
      return (language == 'ja' ? '現在のバージョン: ' : 'Current Version: ') +
          version.group(1)!;
    }
    final count = RegExp(r'^발견된 번호 후보: (\d+)개$').firstMatch(text);
    if (count != null) {
      return language == 'ja'
          ? '見つかった番号候補: ${count.group(1)}件'
          : 'Candidate IDs found: ${count.group(1)}';
    }
    final selected = RegExp(r'^선택한 작품 (\d+)개 한 번에 저장$').firstMatch(text);
    if (selected != null) {
      return language == 'ja'
          ? '選択した${selected.group(1)}作品を保存'
          : 'Save ${selected.group(1)} Selected Works';
    }
    final saved = RegExp(r'^작품 (\d+)개를 서재에 저장했어[.]').firstMatch(text);
    if (saved != null) {
      return language == 'ja'
          ? '${saved.group(1)}作品を本棚に保存しました。'
          : 'Saved ${saved.group(1)} works to your library.';
    }
    return text;
  }

  static String t(BuildContext context, String text) {
    // Register a dependency on MaterialApp's locale for immediate rebuilds,
    // but use the explicit app preference (not the device's system language).
    Localizations.maybeLocaleOf(context);
    return translate(text, HypLanguage.selected.value);
  }
}

/// Const-friendly translated text with standard Flutter text semantics.
/// All user-provided titles and numbers are preserved without translation.
class HypText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;
  final TextDirection? textDirection;

  const HypText(this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: HypLanguage.selected,
    builder: (context, language, _) => Text(
      HypI18n.translate(data, language),
      style: style,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
      softWrap: softWrap,
      textDirection: textDirection,
    ),
  );
}
