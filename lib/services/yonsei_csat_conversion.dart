import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// Yonsei Seoul 2028 plan, pp. 20 and 25. CSAT component after the Korean history deduction.
Map<String, double> yonseiCsatComponents(MockExamSession session) {
  double? score(String subject, double max) {
    final rows = session.records.where((r) => r.subject.trim() == subject);
    if (rows.length != 1) return null;
    final value = rows.single.standardScore;
    return value != null && value.isFinite && value >= 0 && value <= max
        ? value
        : null;
  }

  final korean = score('국어', 200);
  final math = score('수학', 200);
  final social = score('통합사회', 100);
  final science = score('통합과학', 100);
  final english = session.records.where((r) => r.subject.trim() == '영어');
  final history = session.records.where((r) => r.subject.trim() == '한국사');
  final grade = english.length == 1 ? english.single.gradeRank : null;
  final historyGrade = history.length == 1 ? history.single.gradeRank : null;
  if (korean == null ||
      math == null ||
      social == null ||
      science == null ||
      grade == null ||
      grade < 1 ||
      grade > 9 ||
      historyGrade == null ||
      historyGrade < 1 ||
      historyGrade > 9) {
    return const {};
  }
  const englishPoints = [100.0, 95.0, 87.5, 75.0, 60.0, 40.0, 25.0, 12.5, 5.0];
  final base = korean + math + social + science + englishPoints[grade - 1];
  final scienceType = base + math / 2 + science;
  const historyDeductions = [0.0, 0.0, 0.0, 0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  final deduction = historyDeductions[historyGrade - 1];
  return {
    '유형 Ⅰ 인문 (900점)': base + korean / 2 + social - deduction,
    '유형 Ⅱ 자연 (900점)': scienceType - deduction,
    '유형 Ⅱ 의예과 (850점)': scienceType * 850 / 900 - deduction,
    '유형 Ⅲ 통합 (900점)': base * 900 / 700 - deduction,
  };
}
