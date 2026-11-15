import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

MockExamRecord mockGrade(
  String subject,
  int? grade, {
  int month = 9,
  int year = 2026,
  int schoolYear = 2,
  String? institution = '교육청',
  String? elective,
}) => MockExamRecord(
  id: '$subject/$month',
  calendarYear: year,
  schoolYear: schoolYear,
  examMonth: month,
  subject: subject,
  institution: institution,
  gradeRank: grade,
  elective: elective,
);
List<MockExamRecord> mockGrades(List<int?> grades, {int month = 9}) => [
  for (var i = 0; i < grades.length; i++)
    mockGrade(
      ['국어', '수학', '영어', '통합사회', '통합과학', '한국사'][i],
      grades[i],
      month: month,
    ),
];

void main() {
  final service = CsatMinimumService();
  const sum = '국,수,영,통사/통과(상위 1과목) 중 2개 합 5 이내';
  MinimumResult evaluate(String text, List<int?> grades) =>
      service.evaluate(text, MockExamSession(mockGrades(grades)));
  test('같은 시험 내 유리한 영역 조합과 등급 합 부족분', () {
    final met = evaluate(sum, [4, 4, 2, 3, 5, 4]);
    expect(met.status, MinimumStatus.met);
    expect(met.details.join(), contains('등급 합 5'));
    final below = evaluate(sum, [4, 4, 3, 4, 5, 4]);
    expect(below.status, MinimumStatus.below);
    expect(below.shortfall, 2);
    expect(below.details.first, contains('영어 3등급'));
  });
  test('필수 수학을 제외한 유리한 조합을 선택하지 않음', () {
    const forced = '국,수,영,통사/통과(상위 1과목) 중 수학 포함 3개 합 5 이내';
    final r = evaluate(forced, [1, 5, 1, 1, 1, 1]);
    expect(r.status, MinimumStatus.below);
    expect(r.details.first, contains('수학 5등급'));
    expect(
      evaluate('국,수,영,통과 중 3개 합 5 이내(수학 필수 포함)', [1, 5, 1, 1, 1, 1]).status,
      MinimumStatus.below,
    );
  });
  test('각 등급 규칙은 합계 규칙과 구분', () {
    const each = '국,수,영,통사/통과(상위 1과목) 중 3개 영역 각 3등급 이내 및 한국사 4등급 이내';
    expect(evaluate(each, [1, 1, 4, 4, 5, 3]).status, MinimumStatus.below);
    expect(evaluate(each, [3, 3, 3, 5, 5, 4]).status, MinimumStatus.met);
    expect(evaluate(each, [3, 3, 3, 5, 5, 5]).reason, contains('한국사 5 → 4등급'));
  });
  test('통사·통과 상위는 한 영역, 별도 나열은 두 영역', () {
    const best = '국,수,영,통사/통과(상위 1과목) 중 3개 합 4 이내';
    const separate = '국,수,영,통사,통과 중 3개 합 4 이내';
    expect(evaluate(best, [5, 5, 2, 1, 1, 1]).status, MinimumStatus.below);
    expect(evaluate(separate, [5, 5, 2, 1, 1, 1]).status, MinimumStatus.met);
  });
  test('탐구 평균 소수점 유지와 한국사·영어 별도 제한', () {
    const avg = '국,수,영,통사/통과(2과목 평균) 중 탐구 포함 3개 합 5 이내';
    final r = evaluate(avg, [1, 1, 5, 3, 4, 1]);
    expect(r.status, MinimumStatus.below);
    expect(r.shortfall, 0.5);
    expect(r.details.join(), contains('3.5등급'));
    const extras = '국,수,통사,통과 중 2개 합 5 이내, 영어 3등급 이내, 한국사 4등급 이내';
    expect(evaluate(extras, [1, 2, 4, 4, 5, 5]).reason, contains('영어 4 → 3등급'));
    expect(
      evaluate(extras, [1, 2, 4, 4, 5, 5]).reason,
      contains('한국사 5 → 4등급'),
    );
  });
  test('시험 시기·학년·기관별로 분리하고 최고 성적을 합치지 않음', () {
    final records = [
      ...mockGrades([1, 9, 9, 9, 9, 1], month: 6),
      ...mockGrades([9, 1, 9, 9, 9, 1]),
    ];
    final sessions = service.sessions(records);
    expect(sessions, hasLength(2));
    expect(sessions.first.first.examMonth, 9);
    for (final s in sessions) {
      expect(service.evaluate(sum, s).status, MinimumStatus.below);
    }
    expect(
      service.evaluate(sum, MockExamSession(records)).status,
      MinimumStatus.insufficient,
    );
    expect(
      service.sessions([
        mockGrade('국어', 1),
        mockGrade('수학', 1, institution: '평가원'),
        mockGrade('국어', 1, schoolYear: 1),
      ]),
      hasLength(3),
    );
  });
  test('누락·중복·등급 없음·범위 밖은 부족', () {
    for (final records in [
      mockGrades([1, 1]),
      mockGrades([1, 1, 1, 1, null]),
      mockGrades([1, 1, 1, 1, 10]),
      [
        ...mockGrades([1, 1, 1, 1, 1]),
        mockGrade('영어', 1),
      ],
    ]) {
      expect(
        service.evaluate(sum, MockExamSession(records)).status,
        MinimumStatus.insufficient,
      );
    }
    expect(
      service.evaluate(sum, null, failed: true).reason,
      contains('조회에 실패'),
    );
    expect(service.evaluate(sum, null).status, MinimumStatus.insufficient);
  });
  test('기관 미상·2028과 다른 학년·옛 선택탐구를 대신 사용하지 않음', () {
    expect(
      service
          .evaluate(
            sum,
            MockExamSession([mockGrade('국어', 1, institution: null)]),
          )
          .reason,
      contains('시행기관'),
    );
    expect(
      service
          .evaluate(
            sum,
            MockExamSession([mockGrade('국어', 1, year: 2025, schoolYear: 3)]),
          )
          .reason,
      contains('2028'),
    );
    final records = mockGrades([1, 1, 1]);
    records.addAll([mockGrade('생활과 윤리', 1), mockGrade('생명과학Ⅰ', 1)]);
    expect(
      service.evaluate(sum, MockExamSession(records)).reason,
      contains('통합사회'),
    );
  });
  test('지원하지 않는 수식·예외·주석을 무시하지 않음', () {
    for (final rule in [
      '$sum (영어 2등급은 1등급으로 반영)',
      '$sum ※ 탐구 반영 과목 수 미기재',
      '국,수,영,탐(사회 또는 과학) 중 2개 합 6 이내',
      '국,수,영,통사/통과 중 2개 합 6 이내',
      '국,수,영 중 0개 합 5 이내',
      '국,국,영 중 2개 합 5 이내',
      '국,수,영 중 2개 합 5 이내 또는 영어 1등급',
      '국,수,영 중 2개 합 5',
    ]) {
      expect(
        service.evaluate(rule, null).status,
        MinimumStatus.manual,
        reason: rule,
      );
    }
    final branches = service.branches('인문: $sum\n자연: 없음');
    expect(branches, hasLength(2));
    expect(branches.first.label, '인문');
    expect(service.branches('인문: $sum\n※ 탐구 반영 과목 수 미기재'), hasLength(1));
    expect(
      service.evaluate('없음', null, failed: true).status,
      MinimumStatus.none,
    );
  });
  test('실제 번들에서 지원하는 단일 조건의 수록 범위', () {
    final data = jsonDecode(
      File('assets/data/admissions_2028.json').readAsStringSync(),
    ) as Map;
    final rows = (data['rows'] as List)
        .where((r) => ['학생부교과', '학생부종합'].contains(r['type']))
        .toList();
    final supported = rows.where((r) {
      final branches = service.branches(r['minimum']);
      return branches.length == 1 &&
          service.parse(branches.single.text) != null;
    }).length;
    expect(supported, greaterThan(30));
  });
}
