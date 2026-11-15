import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/school_record_import.dart';
import 'package:univ_pathfinder/screens/school_record_review_screen.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/services/school_record_import_parser.dart';

Map<String, dynamic> line(double y, List<(String, double)> values) => {
  'text': values.map((v) => v.$1).join(' '),
  'words': [
    for (final v in values) {'text': v.$1, 'x': v.$2, 'y': y, 'w': 10, 'h': 10},
  ],
};
Map<String, dynamic> page(List<Map<String, dynamic>> lines, {int number = 1}) =>
    {
      'page': number,
      'width': 595,
      'height': 842,
      'method': 'pdf-text',
      'text': lines.map((l) => l['text']).join('\n'),
      'lines': lines,
    };
List<Map<String, dynamic>> narrative() => [
  line(120, [('[1학년]', 45)]),
  line(140, [('과목', 45), ('세부능력', 260), ('및', 300), ('특기사항', 320)]),
  line(160, [('과학탐구실험1:', 45), ('가상 실험을 설계하고 측정값을 비교함.', 160)]),
  line(180, [('체육1:', 45), ('가상 경기에서 협업하고 역할을 수행함.', 100)]),
  line(200, [('미술:', 45), ('가상 관찰 드로잉을 제작하고 수정함.', 100)]),
  line(220, [('진로와', 45), ('직업', 80), ('가상 진로 탐색 과정을 성찰함.', 120)]),
  line(680, [
    ('2026년', 45),
    ('1/12', 220),
    ('반', 300),
    ('7', 320),
    ('번호', 350),
    ('17', 380),
    ('이름', 430),
    ('가상식별자', 470),
  ]),
];

void main() {
  test('정성 근거는 제외 교과도 포함하고 하단 식별정보·미제공 안내는 제거', () {
    final parsed = SchoolRecordImportParser().parse([
      page(narrative()),
      page([
        line(120, [('[2학년]', 45)]),
        line(140, [('과목', 45), ('세부능력', 260), ('특기사항', 320)]),
        line(160, [('해당내용은 공공기관의 정보공개에 관한 법률에 따라 제공하지 않습니다.', 45)]),
      ], number: 2),
    ]);
    expect(parsed.evidence.length, 4);
    expect(
      parsed.evidence.map((e) => e.category),
      containsAll(['세특 · 체육1', '세특 · 미술', '세특 · 진로와 직업']),
    );
    expect(parsed.evidence.map((e) => e.text).join(), isNot(contains('가상식별자')));
    expect(parsed.evidence.every((e) => e.schoolYear == 1), isTrue);
    expect(parsed.warnings.join(), contains('미제공'));
    final preview = GradeImportParser().parse(
      jsonEncode({
        'pages': [page(narrative())],
      }),
      kind: StudentDocumentKind.schoolRecord,
      schoolYear: 1,
      semester: 1,
    );
    expect(
      preview.rawText,
      isEmpty,
    ); // Never offer full unredacted text in the review.
    expect(preview.schoolRecordImport!.evidence.length, 4);
    expect(preview.canStoreGrades, isFalse);
  });

  test('학기 종합 열 분리, 수강자수 등급 오인 방지 및 불명확한 소수점 차단', () {
    final parsed = SchoolRecordImportParser().parse([
      page([
        line(120, [('[2학년]', 45)]),
        line(180, [('석차', 425), ('수강', 455)]),
        line(190, [
          ('학기', 45),
          ('교과', 90),
          ('과목', 150),
          ('학점', 200),
          ('성취도', 280),
          ('성취도별', 340),
        ]),
        line(200, [('과목평균', 230), ('등급', 425)]),
        line(230, [
          ('1', 45),
          ('생명과학 실험', 145),
          ('4', 200),
          ('96/94.5', 230),
          ('A', 280),
          ('19', 455),
        ]),
        line(260, [
          ('영어', 145),
          ('3', 200),
          ('83/794', 230),
          ('A', 280),
          ('3', 425),
          ('200', 455),
        ]),
        line(290, [
          ('체육', 145),
          ('2', 200),
          ('90/80', 230),
          ('A', 280),
          ('1', 425),
        ]),
        line(310, [('이수학점 합계', 45)]),
      ]),
    ]);
    expect(parsed.grades.length, 2);
    expect(parsed.grades[0].grade.subjectName, '생명과학 실험');
    expect(parsed.grades[0].grade.semester, 1);
    expect(parsed.grades[0].grade.gradeRank, isNull);
    expect(parsed.grades[1].grade.gradeRank, 3);
    expect(parsed.grades[1].grade.subjectAverage, isNull);
    expect(parsed.warnings.join(), contains('소수점'));
  });

  testWidgets('원본 확인 필수, 수정 후 재확인, 실패 후 안정된 ID로 재시도', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final e = SchoolEvidenceCandidate(
      category: '세특 · 체육',
      text: '가상 활동에서 동료와 협업하며 문제를 해결함.',
      source: '1쪽 · 체육',
      schoolYear: 1,
      calendarYear: 2025,
    );
    var calls = 0;
    final ids = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolRecordReviewScreen(
          result: SchoolRecordImport(evidence: [e]),
          saveAllowed: true,
          loadGrades: () async => [],
          saveBatch: (g, es) async {
            calls++;
            ids.add(es.single.id);
            throw StateError('offline');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '선택한 1개 저장');
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final confirm = find.widgetWithText(
      CheckboxListTile,
      '선택한 모든 항목을 원본과 대조했고 개인정보를 제거했습니다.',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
    final field = find.byKey(const ValueKey('활동·교과 항목/0'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '세특 · 체육 수정');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(confirm).value, isFalse);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(ids.toSet().length, 1);
  });
}
