import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:platform_ocr/platform_ocr.dart';

/// On-device OCR only. Nothing is ever sent to a remote OCR server.
class VisualOcrResult {
  final String text;
  final List<String> warnings;
  const VisualOcrResult(this.text, {this.warnings = const []});
}

class VisualOcr {
  const VisualOcr();

  Future<VisualOcrResult> analyze(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      return const VisualOcrResult('',
          warnings: ['이미지는 최대 16MB까지 분석할 수 있어.']);
    }
    if (Platform.isWindows) {
      try {
        final result = await PlatformOcr().recognizeText(
            OcrSource.memory(bytes));
        return VisualOcrResult(result.text.trim());
      } catch (error) {
        return VisualOcrResult('',
            warnings: ['Windows 로컬 OCR 실패: $error']);
      }
    }
    if (!Platform.isAndroid) {
      return const VisualOcrResult('',
          warnings: ['이 환경에서 로컬 OCR을 지원하지 않아.']);
    }
    final temporary = await getTemporaryDirectory();
    final file = File(temporary.path + Platform.pathSeparator +
        'hyp_ocr_' + DateTime.now().microsecondsSinceEpoch.toString() + '.png');
    final detected = <String>{};
    final warnings = <String>[];
    try {
      await file.writeAsBytes(bytes, flush: true);
      final image = InputImage.fromFilePath(file.path);
      // Japanese/Korean model dependencies are bundled by CI's
      // configure_android_ocr.py step for the generated Flutter project.
      for (final script in <TextRecognitionScript>[
        TextRecognitionScript.korean,
        TextRecognitionScript.japanese,
        TextRecognitionScript.latin,
      ]) {
        final engine = TextRecognizer(script: script);
        try {
          final result = await engine.processImage(image);
          if (result.text.trim().isNotEmpty) detected.add(result.text.trim());
        } catch (error) {
          warnings.add(script.name + ' OCR unavailable: ' + error.toString());
        } finally {
          await engine.close();
        }
      }
      return VisualOcrResult(detected.join('\n'), warnings: warnings);
    } catch (error) {
      return VisualOcrResult(detected.join('\n'),
          warnings: [...warnings, '로컬 OCR 실패: $error']);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
