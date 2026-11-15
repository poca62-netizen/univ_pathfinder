import 'dart:typed_data';

bool get localOcrAvailable => false;

Future<String> recognizeDocument(
  Uint8List bytes,
  String mime, {
  bool forceOcr = false,
  bool enhancedRecognition = false,
  void Function(String)? onProgress,
}) => Future.error(UnsupportedError('파일 자동 인식은 현재 Chrome 등 웹 버전에서 지원합니다.'));

void cancelDocumentRecognition() {}
