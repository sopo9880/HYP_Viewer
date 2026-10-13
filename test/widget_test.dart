import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/main.dart';

void main() {
  testWidgets('main window shows the library and Shorts entry', (tester) async {
    await tester.pumpWidget(const HypViewerApp());
    await tester.pump();
    expect(find.text('HYP Viewer'), findsOneWidget);
    expect(find.textContaining('쇼츠 작품 번호 찾기'), findsOneWidget);
  });
}
