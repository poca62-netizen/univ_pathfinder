import 'dart:js_interop';
import 'dart:typed_data';

@JS('univGradeOcrExtract')
external JSFunction? get _extractor;
@JS('univGradeOcrExtract')
external JSPromise<JSString> _extract(
  JSUint8Array bytes,
  JSString mime,
  JSBoolean forceOcr,
  JSFunction onProgress,
  JSBoolean enhanced,
);
@JS('univGradeOcrCancel')
external void _cancel();

bool get localOcrAvailable => _extractor != null;

Future<String> recognizeDocument(
  Uint8List bytes,
  String mime, {
  bool forceOcr = false,
  bool enhancedRecognition = false,
  void Function(String)? onProgress,
}) async {
  if (!localOcrAvailable) {
    throw StateError('인식 라이브러리를 불러오지 못했습니다. 페이지를 새로고침해 주세요.');
  }
  void progress(JSString value) => onProgress?.call(value.toDart);
  try {
    return (await _extract(
      bytes.toJS,
      mime.toJS,
      forceOcr.toJS,
      progress.toJS,
      enhancedRecognition.toJS,
    ).toDart).toDart;
  } catch (e) {
    final code = e.toString();
    final message = switch (code) {
      _ when code.contains('CANCELLED') => '인식을 취소했습니다.',
      _ when code.contains('BUSY') => '다른 파일을 인식 중입니다. 잠시 후 다시 시도해 주세요.',
      _ when code.contains('PASSWORD_PROTECTED') => '암호가 설정된 PDF는 인식할 수 없습니다.',
      _ when code.contains('TOO_MANY_PAGES') =>
        '한 번에 최대 20쪽까지 처리합니다. 필요한 쪽을 나눠 선택해 주세요.',
      _ when code.contains('INVALID_SIZE') =>
        mime == 'application/pdf'
            ? '빈 PDF이거나 20MB를 초과했습니다.'
            : '빈 이미지이거나 5MB를 초과했습니다.',
      _ when code.contains('INVALID_FILE') =>
        '파일 내용과 형식이 일치하지 않거나 지원하지 않는 파일입니다.',
      _ when code.contains('ASSETS_UNAVAILABLE') =>
        '로컬 인식 파일을 불러오지 못했습니다. 설치 상태를 확인해 주세요.',
      _ => '파일을 인식하지 못했습니다. 더 선명한 이미지나 잠금이 없는 PDF로 시도해 주세요.',
    };
    throw StateError(message);
  }
}

void cancelDocumentRecognition() {
  if (localOcrAvailable) _cancel();
}
