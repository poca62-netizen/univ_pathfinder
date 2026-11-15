import 'dart:math' as math;

import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// Percentile-based 2028 regular-admission CSAT examples whose formulas are fully
/// stated in the university's own 2028 admission plan.
class _Scores {
  _Scores(this.session);
  final MockExamSession session;

  Iterable<MockExamRecord> _rows(String subject) =>
      session.records.where((r) => r.subject.trim() == subject);

  double? percentile(String subject) {
    final found = _rows(subject);
    if (found.length != 1) return null;
    final p = found.single.percentile;
    return p != null && p.isFinite && p >= 0 && p <= 100 ? p : null;
  }

  int? grade(String subject) {
    final found = _rows(subject);
    if (found.length != 1) return null;
    final g = found.single.gradeRank;
    return g != null && g >= 1 && g <= 9 ? g : null;
  }
}

/// 가톨릭대 2028 시행계획 문서 28–29쪽, 백분위 활용 정시 전형.
/// 원문은 총점 척도를 밝히지 않으므로 반영 비율을 그대로 적용한 100점 기준 값이다.
Map<String, double> catholicCsatComponents(MockExamSession session) {
  final s = _Scores(session);
  final korean = s.percentile('국어'), math_ = s.percentile('수학');
  final social = s.percentile('통합사회'), science = s.percentile('통합과학');
  final english = s.grade('영어'), history = s.grade('한국사');
  if (korean == null ||
      math_ == null ||
      social == null ||
      science == null ||
      english == null ||
      history == null) {
    return const {};
  }
  const englishPoints = [100.0, 98.0, 95.0, 85.0, 70.0, 50.0, 30.0, 10.0, 0.0];
  final historyDeduction = history <= 4 ? 0.0 : (history <= 6 ? 1.0 : 2.0);
  final high = math.max(korean, math_), low = math.min(korean, math_);
  final inquiry = math.max(social, science);
  final eng = englishPoints[english - 1];
  return {
    '일반전형Ⅰ (100점 기준)':
        high * .4 + low * .2 + eng * .2 + inquiry * .2 - historyDeduction,
    '일반전형Ⅱ (100점 기준)': high * .5 + eng * .2 + inquiry * .3 - historyDeduction,
  };
}

/// 인천대 2028 시행계획 문서 5·35–36쪽, 일반학생·기회균형·농어촌 정시 (1,000점).
/// 한국사는 반영하지 않는다.
Map<String, double> incheonCsatComponents(MockExamSession session) {
  final s = _Scores(session);
  final korean = s.percentile('국어'), math_ = s.percentile('수학');
  final social = s.percentile('통합사회'), science = s.percentile('통합과학');
  final english = s.grade('영어');
  if (korean == null ||
      math_ == null ||
      social == null ||
      science == null ||
      english == null) {
    return const {};
  }
  const englishPoints = [100.0, 98.0, 95.0, 85.0, 60.0, 50.0, 30.0, 10.0, 0.0];
  final inquiry = math.max(social, science) * 2.0;
  final eng = englishPoints[english - 1] * 2.0;
  return {
    '인문계열·패션산업학과 (1,000점)': korean * 3.5 + math_ * 2.5 + inquiry + eng,
    '자연계열·동북아국제통상물류학부 (1,000점)': korean * 2.5 + math_ * 3.5 + inquiry + eng,
  };
}

/// 상명대(서울) 2028 시행계획 문서 27–28쪽, 수능전형·농어촌학생전형.
/// 백분위 × 반영비율 × 10, 영어 등급 점수 × 비율 × 10, 계열에 맞는 탐구 5% 가산,
/// 한국사 등급별 가산점. 원문 규정대로 소수점 넷째 자리에서 반올림한다.
Map<String, double> sangmyungCsatComponents(MockExamSession session) {
  final s = _Scores(session);
  final korean = s.percentile('국어'), math_ = s.percentile('수학');
  final social = s.percentile('통합사회'), science = s.percentile('통합과학');
  final english = s.grade('영어'), history = s.grade('한국사');
  if (korean == null ||
      math_ == null ||
      social == null ||
      science == null ||
      english == null ||
      history == null) {
    return const {};
  }
  const englishPoints = [100.0, 98.0, 96.0, 94.0, 90.0, 80.0, 60.0, 40.0, 0.0];
  const historyBonus = [10.0, 9.8, 9.6, 9.4, 9.0, 8.0, 7.0, 6.0, 5.0];
  double round3(double v) => (v * 1000).round() / 1000;
  double total(double k, double m, {required bool humanities}) {
    final inquiry = math.max(
      social * .1 * 10 * (humanities ? 1.05 : 1),
      science * .1 * 10 * (humanities ? 1 : 1.05),
    );
    return round3(
      korean * k * 10 +
          math_ * m * 10 +
          englishPoints[english - 1] * .25 * 10 +
          inquiry +
          historyBonus[history - 1],
    );
  }

  return {
    '인문계열 (사회탐구 5% 가산)': total(.35, .30, humanities: true),
    '자연계열 (과학탐구 5% 가산)': total(.30, .35, humanities: false),
  };
}

/// 동덕여대 2028 시행계획 문서 37–38쪽. 백분위 × 반영비율(1,000점) + 한국사 가산점.
Map<String, double> dongdukCsatComponents(MockExamSession session) {
  final s = _Scores(session);
  final korean = s.percentile('국어'), math_ = s.percentile('수학');
  final social = s.percentile('통합사회'), science = s.percentile('통합과학');
  final english = s.grade('영어'), history = s.grade('한국사');
  if (korean == null ||
      math_ == null ||
      social == null ||
      science == null ||
      english == null ||
      history == null) {
    return const {};
  }
  const englishPoints = [100.0, 99.0, 96.0, 85.0, 70.0, 55.0, 40.0, 20.0, 0.0];
  const historyBonus = [3.0, 3.0, 3.0, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5];
  final eng = englishPoints[english - 1];
  final bonus = historyBonus[history - 1];
  return {
    '일반 모집단위 (1,000점 + 한국사 가산)':
        (math.max(korean, math_) * .35 +
                math.min(korean, math_) * .25 +
                eng * .2 +
                math.max(social, science) * .2) *
            10 +
        bonus,
    '약학과 (1,000점 + 한국사 가산)':
        (korean * .25 + math_ * .35 + eng * .2 + science * .2) * 10 + bonus,
  };
}

/// Shared input check for the formulas below: all four percentiles plus English/Korean history grades.
({double k, double m, double s, double c, int e, int h})? _percentileInputs(
  MockExamSession session,
) {
  final x = _Scores(session);
  final k = x.percentile('국어'), m = x.percentile('수학');
  final s = x.percentile('통합사회'), c = x.percentile('통합과학');
  final e = x.grade('영어'), h = x.grade('한국사');
  if (k == null ||
      m == null ||
      s == null ||
      c == null ||
      e == null ||
      h == null) {
    return null;
  }
  return (k: k, m: m, s: s, c: c, e: e, h: h);
}

/// 명지대 2028 시행계획 문서 40쪽. 백분위, 총점 900점(일반·농어촌전형).
/// 탐구는 계열에 맞는 탐구 백분위 반영 점수에 10% 가산 후 상위 1과목, 한국사 가산점은 총점 환산 후 더한다.
Map<String, double> myongjiCsatComponents(MockExamSession session) {
  final v = _percentileInputs(session);
  if (v == null) return const {};
  const englishPoints = [100.0, 98.0, 96.0, 90.0, 80.0, 60.0, 40.0, 20.0, 0.0];
  const historyBonus = [3.0, 2.8, 2.6, 2.4, 2.2, 2.0, 1.8, 1.6, 1.4];
  double total(double k, double m, {required bool humanities}) {
    final inquiry = math.max(
      v.s * (humanities ? 1.1 : 1),
      v.c * (humanities ? 1 : 1.1),
    );
    return (v.k * k + v.m * m + englishPoints[v.e - 1] * .2 + inquiry * .2) *
            9 +
        historyBonus[v.h - 1];
  }

  return {
    '인문사회계열(경영대학 외) (900점)': total(.35, .25, humanities: true),
    '경영대학 (900점)': total(.30, .30, humanities: true),
    '자연공학계열 (900점)': total(.25, .35, humanities: false),
  };
}

/// 삼육대 2028 시행계획 문서 8쪽. 백분위, 한국사 미반영.
/// 원문에 총점 척도가 없어 반영 비율 그대로의 100점 기준 값이다.
Map<String, double> sahmyookCsatComponents(MockExamSession session) {
  final v = _percentileInputs(session);
  if (v == null) return const {};
  const englishPoints = [98.0, 95.0, 92.0, 87.0, 82.0, 70.0, 50.0, 40.0, 30.0];
  final eng = englishPoints[v.e - 1];
  final ranked = [v.k, v.m, eng, math.max(v.s, v.c)]
    ..sort((a, b) => b.compareTo(a));
  return {
    '인문·자연계열 (우수 4개 영역 순, 100점 기준)':
        ranked[0] * .35 + ranked[1] * .25 + ranked[2] * .25 + ranked[3] * .15,
    '약학과 (100점 기준)': v.k * .25 + v.m * .35 + eng * .25 + v.c * .15,
  };
}

/// 경기대 2028 시행계획 문서 30쪽. 백분위, 탐구 상위 1과목, 한국사 등급별 감점.
/// 원문에 총점 척도가 없어 반영 비율 그대로의 100점 기준 값이다.
Map<String, double> kyonggiCsatComponents(MockExamSession session) {
  final v = _percentileInputs(session);
  if (v == null) return const {};
  const englishPoints = [100.0, 99.0, 96.0, 92.0, 80.0, 70.0, 60.0, 50.0, 0.0];
  const historyDeduction = [0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0];
  final eng = englishPoints[v.e - 1];
  final inquiry = math.max(v.s, v.c);
  final deduction = historyDeduction[v.h - 1];
  return {
    '인문·사회과학·예술체육·관광문화대학 (100점 기준)':
        v.k * .40 + v.m * .25 + eng * .20 + inquiry * .15 - deduction,
    '소프트웨어경영·융합과학·창의공과대학 (100점 기준)':
        v.k * .30 + v.m * .35 + eng * .20 + inquiry * .15 - deduction,
  };
}
