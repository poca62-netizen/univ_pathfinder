import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';
import 'package:univ_pathfinder/services/snu_csat_conversion.dart';

void main() {
  MockExamRecord record(String subject, {int? grade, double? percentile}) =>
      MockExamRecord(
        id: subject,
        calendarYear: 2027,
        schoolYear: 3,
        examMonth: 6,
        subject: subject,
        gradeRank: grade,
        percentile: percentile,
      );

  final full = [
    record('국어', grade: 2, percentile: 90),
    record('수학', grade: 1, percentile: 95),
    record('영어', grade: 3),
    record('한국사', grade: 4),
    record('통합사회', grade: 2, percentile: 85),
    record('통합과학', grade: 1, percentile: 92),
  ];

  test('1단계 등급 환산과 계열별 2단계 백분위 환산(원문 15·16쪽 산식)', () {
    final s = snuCsatComponents(MockExamSession(full));
    // 9 + 10 + 8 + 7 + (9 + 10) / 2
    expect(s['1단계 등급 환산 (50점)'], closeTo(43.5, 1e-9));
    // (90·100 + 95·120 + 85·50 + 92·30) / 100 − 영어 3등급 2.0, × 60/300
    expect(s['2단계 수능 · 인문·사회과학·경영 등 (60점)'], closeTo(54.42, 1e-9));
    // 사회 30 · 과학 50
    expect(s['2단계 수능 · 자연과학·공과·의과·수의과 등 (60점)'], closeTo(54.7, 1e-9));
    // 사회 40 · 과학 40
    expect(s['2단계 수능 · 약학·첨단융합·치의학·간호 등 (60점)'], closeTo(54.56, 1e-9));
  });

  test('만점이면 1단계 50점, 2단계 60점', () {
    final s = snuCsatComponents(
      MockExamSession([
        for (final subject in ['국어', '수학', '통합사회', '통합과학'])
          record(subject, grade: 1, percentile: 100),
        record('영어', grade: 1),
        record('한국사', grade: 1),
      ]),
    );
    expect(s['1단계 등급 환산 (50점)'], 50);
    for (final key in s.keys.where((k) => k.startsWith('2단계'))) {
      expect(s[key], closeTo(60, 1e-9), reason: key);
    }
  });

  test('영어 9등급 감점 14점을 2단계 합산 점수에서 뺀다', () {
    final s = snuCsatComponents(
      MockExamSession([
        for (final subject in ['국어', '수학', '통합사회', '통합과학'])
          record(subject, grade: 1, percentile: 100),
        record('영어', grade: 9),
        record('한국사', grade: 1),
      ]),
    );
    expect(s['2단계 수능 · 인문·사회과학·경영 등 (60점)'], closeTo((300 - 14) * 0.2, 1e-9));
    expect(s['1단계 등급 환산 (50점)'], 42);
  });

  test('백분위가 없으면 1단계만, 한국사 등급이 없으면 2단계만 계산한다', () {
    final gradesOnly = snuCsatComponents(
      MockExamSession([
        for (final r in full) record(r.subject, grade: r.gradeRank),
      ]),
    );
    expect(gradesOnly.keys, ['1단계 등급 환산 (50점)']);

    final noHistory = snuCsatComponents(
      MockExamSession(full.where((r) => r.subject != '한국사').toList()),
    );
    expect(noHistory.keys.every((k) => k.startsWith('2단계')), isTrue);
    expect(noHistory.length, 3);
  });

  test('같은 영역이 두 건이거나 범위를 벗어난 값은 계산하지 않는다', () {
    expect(
      snuCsatComponents(
        MockExamSession([...full, record('국어', grade: 1, percentile: 99)]),
      ),
      isEmpty,
    );
    expect(
      snuCsatComponents(
        MockExamSession([
          ...full.where((r) => r.subject != '수학'),
          record('수학', grade: 1, percentile: 120),
        ]),
      ).keys,
      ['1단계 등급 환산 (50점)'],
    );
  });
}
