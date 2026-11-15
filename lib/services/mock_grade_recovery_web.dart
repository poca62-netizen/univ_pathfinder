import 'dart:js_interop';
import 'dart:typed_data';

@JS('univRecoverMockGrades')
external JSPromise<JSString> _recover(
  JSUint8Array bytes,
  JSString mime,
  JSString response,
  JSFunction progress,
);
Future<String?> recoverMockGrades(
  Uint8List bytes,
  String mime,
  String response, {
  void Function(String)? onProgress,
}) async {
  void progress(JSString message) => onProgress?.call(message.toDart);
  return (await _recover(
    bytes.toJS,
    mime.toJS,
    response.toJS,
    progress.toJS,
  ).toDart).toDart;
}
