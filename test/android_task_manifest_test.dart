import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android SEND and launcher reuse a single recent task', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest, contains('android:documentLaunchMode="never"'));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.category.LAUNCHER'));
  });
}
