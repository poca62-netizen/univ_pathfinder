/// 리포트 복사용 텍스트를 인쇄용 HTML 문서로 바꾼다(브라우저 인쇄 → PDF 저장용).
/// 텍스트의 줄 형식만 해석한다: 첫 줄 제목, "[…]" 절 제목, "〈…〉" 단계 제목, "- " 항목, "※"·"•" 안내.
String reportHtml(String text) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final lines = text.split('\n');
  final title = lines.isEmpty ? '진학 컨설팅 리포트' : lines.first.trim();
  final body = StringBuffer();
  var inList = false;
  void closeList() {
    if (inList) body.writeln('</ul>');
    inList = false;
  }

  for (final raw in lines.skip(1)) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      closeList();
      continue;
    }
    if (line.startsWith('[')) {
      closeList();
      body.writeln('<h2>${esc(line)}</h2>');
    } else if (line.startsWith('〈')) {
      closeList();
      body.writeln('<h3>${esc(line)}</h3>');
    } else if (line.startsWith('- ')) {
      if (!inList) body.writeln('<ul>');
      inList = true;
      body.writeln('<li><strong>${esc(line.substring(2))}</strong>');
    } else if (line.startsWith('  ') && inList) {
      body.writeln('<div class="detail">${esc(line.trim())}</div>');
    } else {
      closeList();
      final cls = line.startsWith('※') ? ' class="notice"' : '';
      body.writeln('<p$cls>${esc(line)}</p>');
    }
  }
  closeList();
  return '''<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<title>${esc(title)}</title>
<style>
body{font-family:"Malgun Gothic","Apple SD Gothic Neo",sans-serif;font-size:11pt;line-height:1.55;color:#111;margin:24px;max-width:900px}
h1{font-size:17pt;margin:0 0 8px}h2{font-size:13pt;margin:20px 0 6px;border-bottom:1px solid #999;padding-bottom:2px}
h3{font-size:11.5pt;margin:12px 0 4px}ul{margin:4px 0 8px;padding-left:18px}li{margin:4px 0;break-inside:avoid}
.detail{font-size:9.5pt;color:#333}.notice{border:1px solid #bbb;padding:6px 8px;font-size:10pt}p{margin:4px 0}
@media print{body{margin:0}h2{break-after:avoid}}
</style></head><body>
<h1>${esc(title)}</h1>
$body</body></html>
''';
}
