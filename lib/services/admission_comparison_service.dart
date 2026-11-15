import 'dart:math' as math;

import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';

class AcademicComparison {
  AcademicComparison({
    required this.university,
    required this.department,
    required this.track,
    required this.level,
    required this.reason,
    required this.history,
    required this.centralMetric,
    required this.mappingNote,
    this.optimistic,
    this.conservative,
    this.simpleAverage,
    this.weightedAverage,
  });
  final String university, department, track, reason;
  final AdmissionLikelihood level;
  final List<Map<String, dynamic>> history;
  final String centralMetric, mappingNote;
  final double? optimistic, conservative, simpleAverage, weightedAverage;
  String get id => '$university/$department/$track';
}

class AdmissionComparisonService {
  String compact(String s) =>
      s.replaceAll(RegExp(r'[\s·ㆍ・]'), '').toLowerCase();
  // Strict aliases prevent an elective or annual combined subject from filling a missing slot.
  String? subject(String name) => switch (compact(name)) {
    '공통국어1' || '공통국어' => '국어',
    '공통수학1' || '공통수학' => '수학',
    '공통영어1' || '공통영어' => '영어',
    '한국사1' || '한국사' => '한국사',
    '통합사회1' || '통합사회' => '사회',
    '통합과학1' || '통합과학' => '과학',
    _ => null,
  };

  List<AcademicComparison> compare({
    required Map<String, dynamic> data,
    required CounselingSummary summary,
    required Iterable<AdmissionTrack> tracks,
    required String interest,
    required bool Function(String, String) matches,
    bool cumulativeConfirmed = false,
  }) {
    final bridge = data['bridge'] as Map;
    final entries = (data['benchmarks'] as List).cast<Map>();
    final values = (bridge['nineGradeByRankSum'] as List)
        .map((v) => v is num ? v.toDouble() : double.nan)
        .toList();
    final core = <String, List<GradeRecord>>{};
    for (final r in summary.confirmedGrades) {
      if (r.calendarYear != bridge['calendarYear'] ||
          r.schoolYear != bridge['schoolYear'] ||
          r.semester != bridge['semester'] ||
          r.examKind != 'semesterSummary') {
        continue;
      }
      final key = subject(r.subjectName);
      if (key != null) core.putIfAbsent(key, () => []).add(r);
    }
    String? error;
    const requiredSubjects = ['국어', '수학', '영어', '한국사', '사회', '과학'];
    if (summary.grades.failed) {
      error = '성적 조회 실패로 비교하지 않았습니다.';
    }
    final missing = requiredSubjects
        .where((s) => !core.containsKey(s))
        .toList();
    if (missing.isNotEmpty) {
      error ??=
          '2025년 1학년 1학기 학기 종합 성적 중 ${missing.join("·")}이 없습니다. 중간·기말이나 다른 학기를 대신 사용하지 않습니다.';
    }
    if (core.values.any((v) => v.length != 1)) {
      error ??= '같은 기준 학기·과목의 기록이 중복되어 비교를 중단했습니다.';
    }
    final rows = core.values.expand((v) => v).toList();
    if (rows.any(
      (r) =>
          r.gradeRank == null ||
          r.gradeRank! < 1 ||
          r.gradeRank! > 5 ||
          !r.credit.isFinite ||
          r.credit <= 0,
    )) {
      error ??= '6개 공통과목의 유효한 1~5등급과 학점이 모두 필요합니다.';
    }
    if (values.length != 25 ||
        values.any((v) => !v.isFinite || v < 1 || v > 9) ||
        List.generate(
          math.max(0, values.length - 1),
          (i) => values[i] > values[i + 1],
        ).any((v) => v)) {
      error ??= '공개 비교표의 값·순서·범위를 검증하지 못했습니다.';
    }
    double? simple, weighted, low, high;
    if (error == null && rows.length == 6 && values.length == 25) {
      simple = rows.fold<double>(0, (s, r) => s + r.gradeRank!) / 6;
      weighted =
          rows.fold<double>(0, (s, r) => s + r.gradeRank! * r.credit) /
          rows.fold<double>(0, (s, r) => s + r.credit);
      // Enclose both averages with published table nodes; no extrapolation or invented probability interval.
      final lo = (math.min(simple, weighted) * 6 - 6 + 1e-8).floor().clamp(
        0,
        24,
      );
      final hi = (math.max(simple, weighted) * 6 - 6 - 1e-8).ceil().clamp(
        0,
        24,
      );
      low = values[lo];
      high = values[hi];
    } else {
      error ??= '비교표 형식 또는 기준 과목 수가 맞지 않습니다.';
    }
    if (cumulativeConfirmed) {
      final cumulative = _cumulative(summary, data['cumulativeBridge'] as Map?);
      error = cumulative.error;
      low = cumulative.low;
      high = cumulative.high;
      simple = null;
      weighted = cumulative.average;
    }
    return [
      for (final b in entries)
        if (matches(b['department'] as String, interest) &&
            tracks.any(
              (t) =>
                  t.university == b['university'] &&
                  t.name == b['track'] &&
                  t.type == b['type'],
            ))
          _one(b, error, low, high, simple, weighted, cumulativeConfirmed),
    ];
  }

  AcademicComparison _one(
    Map b,
    String? error,
    double? low,
    double? high,
    double? simple,
    double? weighted,
    bool cumulative,
  ) {
    final history = (b['history'] as List)
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    var level = AdmissionLikelihood.insufficient;
    var reason = error ?? '';
    final valid =
        b['mixedMetrics'] != true &&
        history.length >= 2 &&
        history.map((h) => h['year']).toSet().length == history.length &&
        history.every(
          (h) =>
              (h['quota'] == null || (h['quota'] is num && h['quota'] > 3)) &&
              (h['centralMetric'] == null ||
                  h['centralMetric'] == b['centralMetric']) &&
              h['central'] is num &&
              h['cut70'] is num &&
              (h['central'] as num).isFinite &&
              (h['cut70'] as num).isFinite &&
              (h['central'] as num) >= 1 &&
              (h['cut70'] as num) <= 9 &&
              (h['central'] as num) <= (h['cut70'] as num),
        );
    if (error == null && valid && low != null && high != null) {
      final central = history
          .map((h) => (h['central'] as num).toDouble())
          .reduce(math.min);
      final cut = history
          .map((h) => (h['cut70'] as num).toDouble())
          .reduce(math.max);
      if (high < central) {
        level = AdmissionLikelihood.strong;
        reason = '보수적인 공개표 대응값도 두 해 ${b["centralMetric"]}보다 유리합니다.';
      } else if (low > cut) {
        level = AdmissionLikelihood.weak;
        reason = '낙관적인 공개표 대응값도 두 해 70%컷보다 불리합니다. 불합격 확정을 뜻하지 않습니다.';
      } else {
        level = AdmissionLikelihood.medium;
        reason =
            '공개표 대응구간이 두 해 ${b["centralMetric"]}~70%컷 범위와 겹치거나 연도별 판단이 달라집니다.';
      }
      reason +=
          ' ${cumulative ? "고2 1학기까지 3학기 누적 학점평균" : "고1 1학기"} 공개표를 사용한 낮은 신뢰도의 근사 비교이며 2028 대학 환산점수·합격확률이 아닙니다.';
    } else if (error == null) {
      reason = '입결 누락·지표 역전·연도 부족·지표 불일치 또는 소수 모집(3명 이하)으로 비교를 보류했습니다.';
    }
    return AcademicComparison(
      university: b['university'] as String,
      department: b['department'] as String,
      track: b['track'] as String,
      level: level,
      reason: reason,
      history: history,
      centralMetric: b['centralMetric'] as String,
      mappingNote:
          b['mappingNote'] as String? ?? '과거 입결 학과의 2028 모집 여부·반영 방식은 확인 전입니다.',
      optimistic: low,
      conservative: high,
      simpleAverage: simple,
      weightedAverage: weighted,
    );
  }

  ({String? error, double? average, double? low, double? high}) _cumulative(
    CounselingSummary summary,
    Map? bridge,
  ) {
    ({String? error, double? average, double? low, double? high}) fail(
      String message,
    ) => (error: message, average: null, low: null, high: null);
    if (summary.grades.failed || bridge == null) {
      return fail('누적 성적 또는 공개 누적 비교표를 불러오지 못했습니다.');
    }
    final rows = summary.confirmedGrades
        .where(
          (r) =>
              r.examKind == 'semesterSummary' &&
              r.gradeRank != null &&
              ((r.calendarYear == 2025 &&
                      r.schoolYear == 1 &&
                      [1, 2].contains(r.semester)) ||
                  (r.calendarYear == 2026 &&
                      r.schoolYear == 2 &&
                      r.semester == 1)),
        )
        .toList();
    final keys = <String>{};
    for (final r in rows) {
      if (!keys.add(
        '${r.schoolYear}/${r.semester}/${compact(r.subjectName)}',
      )) {
        return fail('누적 성적에 같은 학기·과목이 중복되었습니다.');
      }
      if (r.gradeRank! < 1 ||
          r.gradeRank! > 5 ||
          !r.credit.isFinite ||
          r.credit <= 0) {
        return fail('누적 성적의 등급·학점을 확인하세요.');
      }
    }
    for (final term in [(1, 1), (1, 2), (2, 1)]) {
      if (rows
              .where((r) => r.schoolYear == term.$1 && r.semester == term.$2)
              .length <
          6) {
        return fail('2025년 고1 두 학기와 2026년 고2 1학기의 석차등급 과목이 각각 6개 이상 필요합니다.');
      }
    }
    final nodes = (bridge['nodes'] as List).cast<List>();
    if (nodes.length < 2 ||
        nodes.any(
          (n) =>
              n.length != 2 ||
              n.any((v) => v is! num || !v.isFinite) ||
              (n[0] as num) < 1 ||
              (n[0] as num) > 5 ||
              (n[1] as num) < 1 ||
              (n[1] as num) > 9,
        ) ||
        nodes.first[0] != 1 ||
        nodes.last[0] != 5 ||
        List.generate(
          nodes.length - 1,
          (i) =>
              nodes[i][0] >= nodes[i + 1][0] || nodes[i][1] > nodes[i + 1][1],
        ).any((v) => v)) {
      return fail('누적 비교표 형식 오류로 비교하지 않았습니다.');
    }
    final avg =
        rows.fold<double>(0, (s, r) => s + r.gradeRank! * r.credit) /
        rows.fold<double>(0, (s, r) => s + r.credit);
    final lower = nodes.lastWhere((n) => n[0] <= avg + 1e-8);
    final upper = nodes.firstWhere((n) => n[0] >= avg - 1e-8);
    return (
      error: null,
      average: avg,
      low: (lower[1] as num).toDouble(),
      high: (upper[1] as num).toDouble(),
    );
  }
}
