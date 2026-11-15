import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';
import 'package:univ_pathfinder/services/percentile_csat_conversions.dart';

MockExamRecord _r(String subject, {int? grade, double? percentile}) =>
    MockExamRecord(
      id: subject,
      calendarYear: 2027,
      schoolYear: 3,
      examMonth: 6,
      subject: subject,
      gradeRank: grade,
      percentile: percentile,
    );

MockExamSession _session({int english = 3, int history = 6}) =>
    MockExamSession([
      _r('국어', grade: 2, percentile: 90),
      _r('수학', grade: 3, percentile: 80),
      _r('통합사회', grade: 2, percentile: 85),
      _r('통합과학', grade: 4, percentile: 70),
      _r('영어', grade: english),
      _r('한국사', grade: history),
    ]);

void main() {
  group('가톨릭대 (문서 28–29쪽)', () {
    test('우수 영역 순 40·20%, 영어 환산 20%, 탐구 상위 1과목 20%, 한국사 감점', () {
      final s = catholicCsatComponents(_session());
      // 90·.4 + 80·.2 + 영어 3등급 95·.2 + 85·.2 − 한국사 6등급 1
      expect(s['일반전형Ⅰ (100점 기준)'], closeTo(87, 1e-9));
      // 90·.5 + 95·.2 + 85·.3 − 1
      expect(s['일반전형Ⅱ (100점 기준)'], closeTo(88.5, 1e-9));
    });

    test('한국사 1~4등급 0, 5~6등급 −1, 7~9등급 −2', () {
      double first(int history) => catholicCsatComponents(
        _session(history: history),
      )['일반전형Ⅰ (100점 기준)']!;
      expect(first(4) - first(5), closeTo(1, 1e-9));
      expect(first(4) - first(7), closeTo(2, 1e-9));
      expect(first(1), first(4));
    });

    test('영어 등급별 환산점수 100·98·95·85·70·50·30·10·0', () {
      final base = catholicCsatComponents(
        _session(english: 1),
      )['일반전형Ⅰ (100점 기준)']!;
      const points = [100, 98, 95, 85, 70, 50, 30, 10, 0];
      for (var g = 1; g <= 9; g++) {
        final v = catholicCsatComponents(
          _session(english: g),
        )['일반전형Ⅰ (100점 기준)']!;
        expect(
          base - v,
          closeTo((100 - points[g - 1]) * .2, 1e-9),
          reason: '$g등급',
        );
      }
    });
  });

  group('인천대 (문서 5·35–36쪽)', () {
    test('인문·자연 계열 산식과 2028 영어 점수표', () {
      final s = incheonCsatComponents(_session(english: 4));
      // 90·3.5 + 80·2.5 + 85·2 + 영어 4등급 85·2
      expect(s['인문계열·패션산업학과 (1,000점)'], closeTo(855, 1e-9));
      // 90·2.5 + 80·3.5 + 85·2 + 85·2
      expect(s['자연계열·동북아국제통상물류학부 (1,000점)'], closeTo(845, 1e-9));
    });

    test('만점 1,000점, 한국사 등급은 영향이 없다', () {
      final perfect = MockExamSession([
        for (final subject in ['국어', '수학', '통합사회', '통합과학'])
          _r(subject, grade: 1, percentile: 100),
        _r('영어', grade: 1),
      ]);
      expect(
        incheonCsatComponents(perfect).values,
        everyElement(closeTo(1000, 1e-9)),
      );
      expect(
        incheonCsatComponents(_session(history: 1)),
        incheonCsatComponents(_session(history: 9)),
      );
    });

    test('2028 변경 후 영어 5등급은 60점(변경 전 70점이 아님)', () {
      final four = incheonCsatComponents(_session(english: 4)).values.first;
      final five = incheonCsatComponents(_session(english: 5)).values.first;
      expect(four - five, closeTo((85 - 60) * 2, 1e-9));
    });
  });

  group('상명대(서울) (문서 27–28쪽)', () {
    MockExamSession example({
      required double korean,
      required double math,
      required double social,
      required double science,
    }) => MockExamSession([
      _r('국어', percentile: korean),
      _r('수학', percentile: math),
      _r('통합사회', percentile: social),
      _r('통합과학', percentile: science),
      _r('영어', grade: 1),
      _r('한국사', grade: 1),
    ]);

    test('원문 예시 1: 사회탐구 반영 인문 지원자 929.300점', () {
      // 국90·수88·영1·통합사회86(5% 가산)·한국사1, 통합과학은 더 낮게 둔다.
      final s = sangmyungCsatComponents(
        example(korean: 90, math: 88, social: 86, science: 50),
      );
      expect(s['인문계열 (사회탐구 5% 가산)'], closeTo(929.3, 1e-9));
    });

    test('원문 예시 2: 과학탐구 반영 자연 지원자 929.300점', () {
      final s = sangmyungCsatComponents(
        example(korean: 88, math: 90, social: 50, science: 86),
      );
      expect(s['자연계열 (과학탐구 5% 가산)'], closeTo(929.3, 1e-9));
    });

    test('계열이 맞지 않는 탐구는 가산 없이 비교해 높은 쪽을 쓴다', () {
      // 인문: 사회 80×1.05=84 vs 과학 86 → 86 반영
      final s = sangmyungCsatComponents(
        example(korean: 90, math: 88, social: 80, science: 86),
      );
      expect(s['인문계열 (사회탐구 5% 가산)'], closeTo(315 + 264 + 250 + 86 + 10, 1e-9));
    });
  });

  group('동덕여대 (문서 37–38쪽)', () {
    test('일반·약학 산식과 한국사 가산점', () {
      final s = dongdukCsatComponents(_session(english: 3, history: 6));
      // (90·.35 + 80·.25 + 영어 3등급 96·.2 + 85·.2)·10 + 한국사 6등급 2.0
      expect(s['일반 모집단위 (1,000점 + 한국사 가산)'], closeTo(877 + 2, 1e-9));
      // (90·.25 + 80·.35 + 96·.2 + 통합과학 70·.2)·10 + 2.0
      expect(s['약학과 (1,000점 + 한국사 가산)'], closeTo(837 + 2, 1e-9));
    });

    test('한국사 1~4등급 3점, 9등급 0.5점', () {
      double bonusOf(int h) =>
          dongdukCsatComponents(_session(history: h))['약학과 (1,000점 + 한국사 가산)']!;
      expect(bonusOf(1), bonusOf(4));
      expect(bonusOf(4) - bonusOf(9), closeTo(2.5, 1e-9));
    });
  });

  group('명지대·삼육대·경기대', () {
    test('명지대 900점 + 계열 탐구 10% 가산 + 한국사 가산', () {
      final s = myongjiCsatComponents(_session(english: 3, history: 6));
      // (90·.35 + 80·.25 + 96·.2 + 사회 85·1.1·.2)·9 + 6등급 2.0
      expect(s['인문사회계열(경영대학 외) (900점)'], closeTo(806.6, 1e-9));
      expect(s['경영대학 (900점)'], closeTo(802.1, 1e-9));
      // 자연: 과학 70·1.1=77 < 사회 85 → 85 반영
      expect(s['자연공학계열 (900점)'], closeTo(782.3, 1e-9));
    });

    test('삼육대 우수 4개 영역 순 35/25/25/15, 약학 고정 비율', () {
      final s = sahmyookCsatComponents(_session(english: 3, history: 6));
      // 영어 3등급 92 → 92·.35 + 90·.25 + 85·.25 + 80·.15
      expect(s['인문·자연계열 (우수 4개 영역 순, 100점 기준)'], closeTo(87.95, 1e-9));
      // 90·.25 + 80·.35 + 92·.25 + 통합과학 70·.15
      expect(s['약학과 (100점 기준)'], closeTo(84, 1e-9));
    });

    test('경기대 반영 비율과 한국사 감점(6·7등급 0.5, 8·9등급 1)', () {
      final s = kyonggiCsatComponents(_session(english: 3, history: 6));
      expect(s['인문·사회과학·예술체육·관광문화대학 (100점 기준)'], closeTo(87.45, 1e-9));
      expect(s['소프트웨어경영·융합과학·창의공과대학 (100점 기준)'], closeTo(86.45, 1e-9));
      final h5 = kyonggiCsatComponents(_session(history: 5)).values.first;
      final h8 = kyonggiCsatComponents(_session(history: 8)).values.first;
      expect(h5 - h8, closeTo(1, 1e-9));
    });
  });

  test('필요한 영역이 빠지거나 중복되면 계산하지 않는다', () {
    final noPercentile = MockExamSession([
      for (final r in _session().records) _r(r.subject, grade: r.gradeRank),
    ]);
    expect(catholicCsatComponents(noPercentile), isEmpty);
    expect(incheonCsatComponents(noPercentile), isEmpty);
    expect(sangmyungCsatComponents(noPercentile), isEmpty);
    expect(dongdukCsatComponents(noPercentile), isEmpty);
    expect(myongjiCsatComponents(noPercentile), isEmpty);
    expect(sahmyookCsatComponents(noPercentile), isEmpty);
    expect(kyonggiCsatComponents(noPercentile), isEmpty);
    final duplicate = MockExamSession([
      ..._session().records,
      _r('국어', grade: 1, percentile: 99),
    ]);
    expect(catholicCsatComponents(duplicate), isEmpty);
    expect(incheonCsatComponents(duplicate), isEmpty);
  });
}
