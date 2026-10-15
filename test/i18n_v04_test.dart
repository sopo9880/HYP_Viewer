import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/i18n.dart';

void main() {
  test('0.4 new UI labels translate in English and Japanese', () {
    expect(HypI18n.translate('링크로 작품 찾기', 'en'),
        'Find Works from Links');
    expect(HypI18n.translate('다른 언어판 찾기', 'ja'),
        '他の言語版を探す');
    expect(HypI18n.translate('실행 시 업데이트 알림', 'en'),
        'Update Alerts on Startup');
    expect(HypI18n.translate('회차순 (수동 순서)', 'ja'),
        '話数順（手動）');
    expect(HypI18n.translate('온라인 검색 실패: timeout', 'en'),
        'Online Search Failed: timeout');
    expect(HypI18n.translate('USER CREATED TITLE', 'en'),
        'USER CREATED TITLE');
  });
}
