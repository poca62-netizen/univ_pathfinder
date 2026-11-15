import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/grade_scope.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

void main() {
  test('제외 과목 직접 입력 차단 및 통합과학 유지', () {
    for (final subject in [
      '체육2(2)',
      '음악',
      '미술1',
      '과학 탐구 실험2',
      '교양교과',
      '운동과 건강',
    ]) {
      expect(GradeScope.isExcludedSubject(subject), isTrue);
      expect(
        GradeDraft(
          schoolYear: 1,
          semester: 1,
          subjectName: subject,
          credit: 2,
        ).isValid,
        isFalse,
      );
    }
    expect(
      GradeDraft(
        schoolYear: 1,
        semester: 1,
        subjectName: '통합과학2',
        credit: 4,
      ).isValid,
      isTrue,
    );
  });
  test('교양 구역은 임의 과목명도 제외하며 다음 보통교과 구역에서 재개', () {
    Map<String, dynamic> line(List<String> texts) => {
      'text': texts.join(' '),
      'words': [
        for (var i = 0; i < texts.length; i++)
          {'text': texts[i], 'x': i * 100, 'w': 10},
      ],
    };
    final input = jsonEncode({
      'pages': [
        {
          'page': 1,
          'method': 'text',
          'text': '성적 통지표',
          'lines': [
            line(['보통교과 및 전문교과']),
            line(['과목명', '학점', '원점수']),
            line(['국어', '4', '81']),
            line(['교양교과']),
            line(['과목명', '학점', '원점수']),
            line(['가상진로과목', '1', '90']),
            line(['보통교과 및 전문교과']),
            line(['과목명', '학점', '원점수']),
            line(['통합과학', '4', '83']),
            line(['체육·예술과목 / 과학탐구실험']),
            line(['과목명', '학점', '원점수']),
            line(['이름이잘못읽힌제외과목', '2', '77']),
          ],
        },
      ],
    });
    final result = GradeImportParser().parse(
      input,
      kind: StudentDocumentKind.finalExam,
      schoolYear: 1,
      semester: 1,
    );
    expect(result.result.subjects.map((r) => r.subjectName), ['국어', '통합과학']);
    expect(result.warnings.any((w) => w.contains('이름이잘못읽힌')), isFalse);
  });
  testWidgets('기존 제외 성적은 분석·요약과 미확인 건수에서 제외', (tester) async {
    GradeRecord record(String name, {bool confirmed = true}) => GradeRecord(
      id: name,
      userId: 'test',
      schoolYear: 1,
      semester: 1,
      subjectName: name,
      credit: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      sourceConfirmedAt: confirmed ? DateTime.utc(2026) : null,
    );
    final rows = [record('국어'), record('체육2'), record('음악', confirmed: false)];
    final summary = CounselingSummary(
      grades: SummarySection(rows),
      mockExams: SummarySection([]),
      activities: SummarySection([]),
    );
    expect(summary.confirmedGrades.map((r) => r.subjectName), ['국어']);
    expect(summary.unconfirmedGradeCount, 0);
    await tester.pumpWidget(
      MaterialApp(home: GradeAnalysisScreen(loadGrades: () async => rows)),
    );
    await tester.pumpAndSettle();
    expect(find.text('DB에 저장된 내 성적 1개'), findsOneWidget);
    expect(find.textContaining('체육2'), findsNothing);
    expect(find.textContaining('음악'), findsNothing);
  });
}
