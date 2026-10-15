import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android background service uses declared dataSync foreground type', () async {
    final xml = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    expect(xml, contains('FOREGROUND_SERVICE_DATA_SYNC'));
    expect(xml, contains('FOREGROUND_SERVICE'));
    expect(xml, contains('IsolateHolderService'));
    expect(xml, contains('android:foregroundServiceType="dataSync"'));
    expect(xml, contains('POST_NOTIFICATIONS'));
  });
}
