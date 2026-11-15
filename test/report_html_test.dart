import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/report_html.dart';

void main() {
  test('리포트 텍스트의 줄 형식을 제목·목록·안내로 바꾸고 HTML을 이스케이프한다', () {
    final html = reportHtml(
      '진학 컨설팅 리포트 (2026-11-15 작성)\n'
      '※ 합격을 보장하지 않습니다.\n'
      '\n'
      '[학생부교과 1건] 안정 1\n'
      '〈안정〉\n'
      '- 가대 · 컴퓨터공학과 | 지역균형 | 신뢰도 높음\n'
      '  70%컷 평균 <2.80> & 50%컷\n',
    );
    expect(html, contains('<title>진학 컨설팅 리포트 (2026-11-15 작성)</title>'));
    expect(html, contains('<p class="notice">※ 합격을 보장하지 않습니다.</p>'));
    expect(html, contains('<h2>[학생부교과 1건] 안정 1</h2>'));
    expect(html, contains('<h3>〈안정〉</h3>'));
    expect(html, contains('<li><strong>가대 · 컴퓨터공학과'));
    expect(html, contains('&lt;2.80&gt; &amp; 50%컷'));
    expect(html, isNot(contains('<2.80>')));
    expect(html, contains('@media print'));
  });
}
