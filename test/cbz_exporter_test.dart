import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/cbz_exporter.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  test('export names are deterministic and cannot contain path traversal', () {
    final work = WorkEntry.create(
      workId: '3172801',
      title: '../../Unsafe:Part/1? / A',
    );
    final name = SelectedCbzExporter.safeName(work);
    expect(name.startsWith('3172801_'), true);
    expect(name.endsWith('.cbz'), true);
    expect(name.contains('/'), false);
    expect(name.contains('..'), false);
    expect(name.contains(':'), false);
  });
}
