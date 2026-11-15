import 'dart:js_interop';
import 'dart:typed_data';

@JS('univCropOcrTable')
external JSPromise<JSUint8Array> _crop(
  JSUint8Array bytes,
  JSString mime,
  JSNumber top,
  JSNumber bottom,
);
Future<Uint8List?> cropOcrTable(
  Uint8List bytes,
  String mime,
  double top,
  double bottom,
) async {
  try {
    return (await _crop(
      bytes.toJS,
      mime.toJS,
      top.toJS,
      bottom.toJS,
    ).toDart).toDart;
  } catch (_) {
    return null;
  }
}
