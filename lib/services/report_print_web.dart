import 'dart:js_interop';

@JS('univPrintReport')
external JSBoolean? _printReport(JSString html);

/// 새 창에 인쇄용 문서를 열고 브라우저 인쇄 창을 띄운다. 팝업이 막히면 false.
bool printReportHtml(String html) {
  try {
    return _printReport(html.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
