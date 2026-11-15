import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// Seoul National University 2028 plan, regular (나군) admission, pp. 15–16 and 18.
/// Stage 1: grade points (1등급 10 … 9등급 2) for 국어·수학·영어·한국사, plus the
/// average of 통합사회·통합과학 grade points (max 50).
/// Stage 2: percentile sum with unit-group weights minus the English deduction,
/// then × 60/300 (max 60). 교과역량평가·면접 are not included.
Map<String, double> snuCsatComponents(MockExamSession session) {
  Iterable<MockExamRecord> rows(String subject) =>
      session.records.where((r) => r.subject.trim() == subject);
  int? grade(String subject) {
    final found = rows(subject);
    if (found.length != 1) return null;
    final g = found.single.gradeRank;
    return g != null && g >= 1 && g <= 9 ? g : null;
  }

  double? percentile(String subject) {
    final found = rows(subject);
    if (found.length != 1) return null;
    final p = found.single.percentile;
    return p != null && p.isFinite && p >= 0 && p <= 100 ? p : null;
  }

  double points(int g) => (11 - g).toDouble();
  final result = <String, double>{};

  final gk = grade('국어'), gm = grade('수학'), ge = grade('영어');
  final gh = grade('한국사'), gs = grade('통합사회'), gc = grade('통합과학');
  if ([gk, gm, ge, gh, gs, gc].every((g) => g != null)) {
    result['1단계 등급 환산 (50점)'] =
        points(gk!) +
        points(gm!) +
        points(ge!) +
        points(gh!) +
        (points(gs!) + points(gc!)) / 2;
  }

  final pk = percentile('국어'), pm = percentile('수학');
  final ps = percentile('통합사회'), pc = percentile('통합과학');
  if (pk != null && pm != null && ps != null && pc != null && ge != null) {
    const englishDeduction = [0.0, 0.5, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0];
    double stage2(double social, double science) =>
        (pk * 100 + pm * 120 + ps * social + pc * science) / 100 -
        englishDeduction[ge - 1];
    result['2단계 수능 · 인문·사회과학·경영 등 (60점)'] = stage2(50, 30) * 60 / 300;
    result['2단계 수능 · 자연과학·공과·의과·수의과 등 (60점)'] =
        stage2(30, 50) * 60 / 300;
    result['2단계 수능 · 약학·첨단융합·치의학·간호 등 (60점)'] =
        stage2(40, 40) * 60 / 300;
  }
  return result;
}
