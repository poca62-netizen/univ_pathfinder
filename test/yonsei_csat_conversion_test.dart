import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';
import 'package:univ_pathfinder/services/yonsei_csat_conversion.dart';

void main() {
  MockExamRecord record(String subject, {double? score, int? grade}) =>
      MockExamRecord(
        id: subject,
        calendarYear: 2027,
        schoolYear: 3,
        examMonth: 6,
        subject: subject,
        standardScore: score,
        gradeRank: grade,
      );

  final subjects = [
    record('국어', score: 120),
    record('수학', score: 140),
    record('통합사회', score: 70),
    record('통합과학', score: 80),
    record('영어', grade: 3),
  ];

  test('한국사 감점은 유형별 배점으로 환산한 뒤 적용한다', () {
    final scores = yonseiCsatComponents(
      MockExamSession([...subjects, record('한국사', grade: 7)]),
    );
    expect(
      scores.values,
      orderedEquals([
        closeTo(626.9, 0.0001),
        closeTo(646.9, 0.0001),
        closeTo(647.5 * 850 / 900 - 0.6, 0.0001),
        closeTo(497.5 * 900 / 700 - 0.6, 0.0001),
      ]),
    );
  });

  test('한국사 미등록 또는 중복이면 점수를 계산하지 않는다', () {
    expect(yonseiCsatComponents(MockExamSession(subjects)), isEmpty);
    expect(
      yonseiCsatComponents(
        MockExamSession([
          ...subjects,
          record('한국사', grade: 1),
          record('한국사', grade: 2),
        ]),
      ),
      isEmpty,
    );
  });
}
