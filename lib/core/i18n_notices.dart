/// Localized app-generated notification text, including dynamic status
/// messages that cannot be represented by static ARB/HypText keys.
/// User-authored titles and server-supplied error details remain unmodified.
abstract final class HypNoticeTranslations {
  static const Map<String, List<String>> _exact = {
    "승인된 작품을 오프라인으로 다운로드 중": ["Downloading approved works for offline reading", "許可済みの作品をオフライン保存中"],
    "다운로드를 준비 중이야.": ["Preparing your download.", "ダウンロードを準備しています。"],
    "번호를 찾지 못했어. 댓글을 확인하고 직접 입력해줘.": ["No work ID found. Check the comments or enter one manually.", "作品番号が見つかりませんでした。コメントを確認するか手動で入力してください。"],
    "공유 내용을 받았어. 링크에서 작품 번호를 찾을게.": ["Share received. Looking for work IDs in the link.", "共有を受信しました。リンクから作品番号を検索します。"],
    "홈 배너 첫 번째 화면에 일러스트를 설정했어.": ["Updated the first home banner image.", "ホームの最初のバナー画像を更新しました。"],
    "홈 배너를 기본 디자인으로 되돌렸어.": ["Restored the default home banner.", "ホームバナーを標準デザインに戻しました。"],
    "이 기기에서는 보안 설정 화면을 열 수 없어.": ["Security settings are unavailable on this device.", "この端末ではセキュリティ設定を開けません。"],
    "온라인 이미지 소스 설정을 저장했어.": ["Saved the online image source settings.", "オンライン画像ソース設定を保存しました。"],
    "본문·댓글·이미지 OCR 결과를 Finder로 가져왔어. 후보를 확인하거나 수동으로 번호를 입력해줘.": ["Imported available details to Finder. Review candidates or enter an ID manually.", "Finderに情報を取り込みました。候補を確認するか番号を手動で入力してください。"],
    "Instagram 게시물·릴스 또는 YouTube 영상·게시물 링크를 입력해줘.": ["Enter an Instagram post/reel or YouTube video/post link.", "Instagramの投稿・リール、またはYouTube動画・投稿のリンクを入力してください。"],
    "분석할 링크나 공유 텍스트를 입력해줘.": ["Paste a link or shared text to analyze.", "解析するリンクまたは共有テキストを入力してください。"],
    "공유 텍스트를 분석했지만 작품 번호는 없었어. 게시물 링크나 댓글을 추가해서 다시 분석해줘.": ["No work ID was found in the shared text. Add the post link or comments and retry.", "共有テキストに作品番号が見つかりませんでした。投稿リンクやコメントを追加して再解析してください。"],
    "번호가 없어. 공개 설명·본문에 없을 수 있으니 댓글을 직접 붙여넣어줘.": ["No IDs found in public descriptions. Try pasting the comments manually.", "公開説明文に番号が見つかりません。コメントを手動で貼り付けてください。"],
    "같은 작품의 다른 언어판으로 묶었어.": ["Linked editions of the same work.", "同じ作品の他言語版をまとめました。"],
    "선택한 언어판만 묶음에서 분리했어.": ["Removed only the selected language edition from the stack.", "選択した言語版のみをまとめから解除しました。"],
    "번호는 숫자 1~12자리로 입력해줘.": ["Enter a numeric work ID containing 1–12 digits.", "作品番号を1〜12桁の数字で入力してください。"],
    "번호를 변경했어. 기존 CBZ·표지는 원래 번호에 보존했어.": ["Work ID changed; existing CBZ and cover remain under the previous ID.", "作品番号を変更しました。既存のCBZと表紙は元の番号のまま保持しました。"],
    "작품 정보를 수정했어.": ["Updated work details.", "作品情報を更新しました。"],
    "묶음은 서로 다른 작품 2개 이상과 이름이 필요해.": ["A group needs a name and at least two different works.", "グループには名前と異なる作品が2件以上必要です。"],
    "작품을 삭제하지 않고 묶음만 해제했어.": ["Ungrouped works without deleting them.", "作品を削除せずグループだけ解除しました。"],
    "완독 처리했어.": ["Marked as finished.", "読了に設定しました。"],
    "완독 표시를 해제했어.": ["Removed the finished mark.", "読了設定を解除しました。"],
    "보관된 원본 링크가 없어.": ["No saved source link is available.", "保存済みの元リンクがありません。"],
    "유효한 HTTPS 링크를 입력해줘.": ["Enter a valid HTTPS link.", "有効なHTTPSリンクを入力してください。"],
    "웹에서 본문·댓글을 복사해 앱에 붙여넣을 수 있어.": ["You can copy captions and comments from the web into the app.", "Webから本文やコメントをコピーしてアプリに貼り付けられます。"],
    "이전에 저장된 서재 백업(.previous)이 없어.": ["No previous library backup (.previous) is available.", "以前の本棚バックアップ（.previous）がありません。"],
    "JSON 복원이 완료됐어.": ["JSON restore completed.", "JSONの復元が完了しました。"],
    "보이는 영역을 작품 표지로 저장했어.": ["Saved the visible area as the work cover.", "表示領域を作品の表紙に保存しました。"],
    "웹 리더를 열었어. 브라우저에서 넘긴 페이지는 앱에 자동 저장되지 않아.": ["Opened the web reader. Browser page changes are not saved to the app.", "Webリーダーを開きました。ブラウザでのページ移動はアプリに保存されません。"],
    "시작 페이지는 1~1000000 사이의 숫자로 입력해줘.": ["Enter a start page between 1 and 1,000,000.", "開始ページを1〜100万の数字で入力してください。"],
    "알림 권한이 꺼져 있어 진행률이 알림창에 표시되지 않아. 다운로드는 계속 시도할게. Android 설정에서 알림을 허용해줘.": ["Notifications are disabled. Downloads continue, but progress may not appear. Enable notifications in Android settings.", "通知が無効のため進捗が表示されません。保存は続行します。Androidの設定で通知を許可してください。"],
    "알림 권한이 없어 진행률이 알림창에 표시되지 않을 수 있어. 앱 알림을 허용해줘. 다운로드는 계속 시도할게.": ["Notification permission is off. Transfers continue but progress may be hidden. Enable app notifications.", "通知が許可されていません。保存は続きますが進捗が表示されない場合があります。通知を許可してください。"],
    "이미 서재에서 삭제된 작품이야.": ["This work has already been removed from your library.", "この作品は既に本棚から削除されています。"],
    "오프라인 이미지를 삭제했어. 서재 기록은 유지했어.": ["Deleted offline images. Library records are preserved.", "オフライン画像を削除しました。本棚の記録は保持します。"],
    "온라인 소스 URL 패턴을 먼저 설정해줘.": ["Configure the online source URL pattern first.", "先にオンラインソースのURLパターンを設定してください。"],
    "선택한 파일의 경로를 읽지 못했어.": ["Unable to read the selected file path.", "選択したファイルのパスを読み取れません。"],
    "기기 보안 설정을 열지 못했어. 설정에서 직접 확인한 뒤 업데이트를 다시 시도해줘.": ["Unable to open device security settings. Check them manually, then retry the update.", "端末のセキュリティ設定を開けません。手動で確認してから更新を再試行してください。"],
    "Android 설치 화면을 열었어. 승인 후 앱 버전이 변경되면 설치를 확인할게.": ["Opened the Android installer. Approve installation; the app will verify the new version.", "Androidのインストール画面を開きました。承認後に新しいバージョンを確認します。"],
    "현재 더 새로운 릴리스가 없어.": ["You already have the latest release.", "これより新しいリリースはありません。"],
    "설치 파일을 내려받는 중이야.": ["Downloading the installer.", "インストーラーをダウンロード中です。"],
    "온라인 소스 설정을 읽지 못했어: ": ["Unable to read online source settings: ", "オンラインソース設定を読み取れません: "],
    "앱 내 온라인 읽기 실패: ": ["Unable to open in-app reader: ", "アプリ内閲覧に失敗: "],
    "백그라운드 다운로드 시작 실패: ": ["Unable to start background download: ", "バックグラウンド保存を開始できません: "],
    "저장된 다운로드 복구 실패: ": ["Unable to restore pending downloads: ", "保存済みのダウンロードを復元できません: "],
    "본문 확인 · 댓글 미로딩": ["Caption found · Comments not loaded", "本文取得済み・コメント未読み込み"],
    "누적 수집된 댓글": ["Comments collected in this session", "このセッションで収集したコメント"],
    "수집된 내용": ["Collected content", "収集した内容"],
    "인스타그램 화면에서 댓글을 직접 펼치고 스크롤한 뒤 다시 읽어줘.": ["Expand comments in Instagram, scroll, then reread the visible comments.", "Instagramでコメントを開いてスクロールし、表示中のコメントを再読込してください。"],
    "기존 댓글을 유지하면서 새 댓글을 기다리는 중": ["Keeping collected comments; waiting for new comments", "収集したコメントを保持し、新しいコメントを待っています"],
    "댓글 영역 감지 · 댓글을 펼친 후 다시 읽어줘": ["Comment area detected · Expand comments and reread", "コメント欄を検出しました・コメントを開いて再読込してください"],
    "읽은 본문이 없어.": ["No caption was loaded.", "本文を取得できませんでした。"],
    "화면에서 보이는 본문·댓글 다시 읽기": ["Reread visible caption and comments", "表示中の本文とコメントを再読込"],
    "후보를 Finder로 전달": ["Send candidates to Finder", "候補をFinderに送る"],
  };
  static const Map<String, List<String>> _prefixes = {
    "온라인 소스 설정을 읽지 못했어: ": ["Unable to read online source settings: ", "オンラインソース設定を読み取れません: "],
    "백그라운드 다운로드 시작 실패: ": ["Unable to start background download: ", "バックグラウンド保存を開始できません: "],
    "앱 내 온라인 읽기 실패: ": ["Unable to open in-app reader: ", "アプリ内閲覧に失敗: "],
    "저장된 다운로드 복구 실패: ": ["Pending download restore failed: ", "保留中のダウンロード復元に失敗: "],
    "선택 삭제 실패: ": ["Bulk removal failed: ", "一括削除に失敗: "],
    "페이지 저장 실패: ": ["Page save failed: ", "ページ保存に失敗: "],
  };
  static final List<(RegExp, String, String)> _formats = [
    (RegExp(r'^후보 (\d+)개 발견\. 확인 후 저장해줘\.$'), "Found {1} candidates. Review before saving.", "候補{1}件を発見しました。確認してから保存してください。"),
    (RegExp(r'^v([0-9.]+) 업데이트가 실제 앱 버전으로 확인됐어\.$'), "Update v{1} was verified as installed.", "更新v{1}のインストールを確認しました。"),
    (RegExp(r'^작품 (\d+)개를 서재에 저장했어\.$'), "Saved {1} works to the library.", "{1}作品を本棚に保存しました。"),
    (RegExp(r'^작품 (\d+)개를 서재에 저장했어\. 제목을 찾지 못한 (\d+)개는 임시 이름으로 저장했어\.$'), "Saved {1} works. {2} titles were unavailable and received temporary names.", "{1}作品を保存しました。うち{2}作品は仮のタイトルで保存しました。"),
    (RegExp(r'^작품 (\d+) 다운로드 실패: ([\s\S]+)$'), "Work {1} download failed: {2}", "作品{1}のダウンロードに失敗: {2}"),
    (RegExp(r'^백그라운드 다운로드 시작 실패: ([\s\S]+)\. 작업은 저장되어 있으니 앱으로 돌아와 다시 시도해줘\.$'), "Background download could not start: {1}. Your queue is saved; retry after returning to the app.", "バックグラウンド保存を開始できません: {1}。キューは保存されています。アプリに戻って再試行してください。"),
    (RegExp(r'^앱 내 온라인 읽기 실패: ([\s\S]+) / 작품 메뉴의 웹 리더로 열기를 이용할 수 있어\.$'), "In-app reading failed: {1}. Try Open in Web Reader from the work menu.", "アプリ内閲覧に失敗: {1}。作品メニューのWebリーダーを試してください。"),
    (RegExp(r'^기존 서재 읽기 실패: ([\s\S]+) / 데이터 보호를 위해 새 서재 저장을 잠갔어\. 원본과 \.previous 파일을 확인해줘\.$'), "Library load failed: {1}. New saves are blocked to protect your data. Check the original and .previous files.", "本棚の読み込みに失敗: {1}。データ保護のため新規保存を停止しました。元ファイルと.previousを確認してください。"),
    (RegExp(r'^작품 (\d+)개를 서재에 저장했어\. 제목을 찾지 못한 (\d+)개는 임시 이름으로 저장했어\.$'), "Saved {1} works; {2} had temporary names.", "{1}作品を保存しました。{2}作品は仮の名前です。"),
    (RegExp(r'^(\d+)개 CBZ를 선택한 폴더로 내보냈어\. (\d+)개는 실패했어\.$'), "Exported {1} CBZ files. {2} failed.", "{1}件のCBZを出力しました。{2}件は失敗しました。"),
    (RegExp(r'^분석된 후보 (\d+)개\. 일부 링크는 원문을 읽지 못했어: [\s\S]+$'), "Found {1} candidates. Some sources were incomplete; manually paste missing comments.", "候補{1}件を検出しました。一部ソースが不完全です。コメントを手動で貼り付けてください。"),
    (RegExp(r'^읽기 실패: ([\s\S]+) / CBZ 또는 ZIP 파일을 먼저 연결해줘\.$'), "Reader failed: {1}. Connect a CBZ or ZIP file first.", "閲覧に失敗: {1}。先にCBZかZIPファイルを登録してください。"),
    (RegExp(r'^다운로드 대기: (\d+)개 작품\. 백그라운드에서도 순서대로 다운로드해\.$'), "{1} works queued for background download.", "{1}作品をバックグラウンド保存キューに追加しました。"),
  ];

  static String? translate(String text, String language) {
    if (language == 'ko') return text;
    final index = language == 'ja' ? 1 : 0;
    final matchExact = _exact[text];
    if (matchExact != null) return matchExact[index];
    for (final entry in _formats) {
      final match = entry.$1.firstMatch(text);
      if (match == null) continue;
      var result = language == 'ja' ? entry.$3 : entry.$2;
      for (var i = 1; i <= match.groupCount; i++) {
        result = result.replaceAll(
          '{' + i.toString() + '}', match.group(i) ?? '');
      }
      return result;
    }
    for (final entry in _prefixes.entries) {
      if (text.startsWith(entry.key)) {
        return entry.value[index] + text.substring(entry.key.length);
      }
    }
    return null;
  }
}
