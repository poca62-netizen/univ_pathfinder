import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/services/admission_comparison_service.dart';

class UniversityCandidate {
  UniversityCandidate(
    this.name,
    this.tracks,
    this.departmentMatch,
    this.readiness, {
    this.comparisons = const [],
  });
  final String name;
  final List<AdmissionTrack> tracks;
  final bool departmentMatch;
  final int readiness;
  final List<AcademicComparison> comparisons;
  AdmissionAssessment get assessment => AdmissionAssessment.unavailable;
}

class UniversityRecommendation {
  UniversityRecommendation({
    required this.candidates,
    required this.total,
    required this.issues,
    required this.evidence,
  });
  final List<UniversityCandidate> candidates;
  final int total;
  final List<String> issues;
  final List<SchoolRecordEvidence> evidence;
}

class UniversityRecommendationService {
  Future<Map<String, dynamic>> loadComparison() async => jsonDecode(
    await rootBundle.loadString('assets/data/admission_comparison.json'),
  ) as Map<String, dynamic>;
  Future<TuitionCatalog> loadTuition() async => TuitionCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/tuition.json'))
        as Map<String, dynamic>,
  );
  static const defaultPriority =
      '서울대,연세대(서울),고려대(서울),서강대,성균관대,한양대(서울),중앙대,경희대,서울시립대,이화여대,한국외대(서울),건국대(서울),동국대(서울),홍익대(서울),아주대,인하대';

  Future<AdmissionCatalog> loadCatalog() async => AdmissionCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/admissions_2028.json'))
        as Map<String, dynamic>,
  );

  String _compact(String s) =>
      s.replaceAll(RegExp(r'[\s·ㆍ・]'), '').toLowerCase();
  bool matches(String text, String interest) {
    final q = _compact(interest);
    if (q.isEmpty) return false;
    final field = q == '의학과'
        ? '의학'
        : q.replaceFirst(RegExp(r'(학과|학부|전공)$'), '');
    if (['의학', '의대'].contains(field) && RegExp('치의|한의|수의').hasMatch(text)) {
      return false;
    }
    final terms = <String>{q};
    if (field.isNotEmpty) terms.add(field);
    // Field synonyms only; never infer that life science means medicine.
    const synonyms = {
      '의학': ['의예', '의학과'],
      '의대': ['의예', '의학과'],
      '치의학': ['치의예', '치의학'],
      '한의학': ['한의예', '한의학'],
      '약학': ['약학'],
      '수의학': ['수의예', '수의학'],
      '교육': ['초등교육', '교육학'],
      '간호': ['간호'],
      '인공지능': ['인공지능', 'ai', '첨단컴퓨팅'],
      '소프트웨어': ['소프트웨어', '컴퓨터공학', '컴퓨터과학'],
      '건축': ['건축학', '건축공학'],
      '심리': ['심리학', '상담심리'],
      '미디어': ['미디어', '언론정보', '언론홍보', '커뮤니케이션'],
      '환경공학': ['환경공학', '환경시스템공학'],
      '반도체': ['반도체', '반도체설계'],
      '데이터과학': ['데이터과학', '데이터사이언스', '데이터공학'],
    };
    terms.addAll(synonyms[field == 'ai' ? '인공지능' : field] ?? []);
    final normalized = _compact(text);
    return terms.any(
      (term) => term == 'ai'
          ? RegExp(r'(^|[^a-z])ai([^a-z]|$)').hasMatch(text.toLowerCase())
          : normalized.contains(term),
    );
  }

  UniversityRecommendation recommend({
    required AdmissionCatalog catalog,
    required CounselingSummary summary,
    required String interest,
    required int count,
    String type = '전체',
    bool includeSpecial = false,
    String priority = defaultPriority,
    int targetYear = 2028,
    Map<String, dynamic>? comparisonData,
    bool comparisonOnly = false,
    bool cumulativeConfirmed = false,
  }) {
    final issues = <String>[];
    final activities = summary.activities.failed
        ? <SchoolRecordEvidence>[]
        : summary.activitiesFor(null);
    final linked = activities
        .where(
          (e) => matches(
            '${e.category} ${e.evidence} ${e.careerInterest ?? ""}',
            interest,
          ),
        )
        .toList();
    if (targetYear != catalog.year) {
      issues.add('${catalog.year}학년도 자료만 있습니다. 선택한 입학연도 자료를 먼저 확보하세요.');
    }
    if (summary.grades.failed || summary.activities.failed) {
      issues.add('성적 또는 생기부 조회에 실패했습니다. 다시 조회하세요.');
    }
    if (!summary.grades.failed && summary.confirmedGrades.isEmpty) {
      issues.add(
        summary.unconfirmedGradeCount > 0
            ? '등록한 내신 성적을 원본과 대조해 확인해 주세요.'
            : '대학 추천 분석을 시작하려면 내신 성적표를 업로드해 주세요.',
      );
    }
    if (!summary.activities.failed && activities.isEmpty) {
      issues.add('상담 활용이 켜진 생기부 근거를 먼저 등록하세요.');
    }
    if (interest.trim().isEmpty) issues.add('관심 학과·분야를 입력하세요.');
    if (count < 1 || count > 100) issues.add('대학 개수는 1~100개로 선택하세요.');
    if (issues.isNotEmpty) {
      return UniversityRecommendation(
        candidates: [],
        total: 0,
        issues: issues,
        evidence: linked,
      );
    }

    final hasRank = summary.confirmedGrades.any(
      (g) => g.examKind == 'semesterSummary' && g.gradeRank != null,
    );
    final groups = <String, List<AdmissionTrack>>{};
    for (final t in catalog.tracks) {
      if (!['학생부교과', '학생부종합'].contains(t.type)) continue;
      if (type != '전체' && t.type != type) continue;
      if (!includeSpecial && t.requiresSpecialEligibility) continue;
      if (t.department.isNotEmpty && !matches(t.department, interest)) continue;
      groups.putIfAbsent(t.university, () => []).add(t);
    }
    int readiness(AdmissionTrack t) =>
        t.type == '학생부종합' ? (linked.isNotEmpty ? 2 : 1) : (hasRank ? 2 : 1);
    final order = priority
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    int pos(String name) {
      final i = order.indexOf(name);
      return i < 0 ? order.length : i;
    }

    final candidates =
        [
          for (final entry in groups.entries)
            UniversityCandidate(
              entry.key,
              entry.value..sort((a, b) {
                final match = (b.department.isNotEmpty ? 1 : 0).compareTo(
                  a.department.isNotEmpty ? 1 : 0,
                );
                return match != 0
                    ? match
                    : readiness(b).compareTo(readiness(a));
              }),
              entry.value.any((t) => t.department.isNotEmpty),
              entry.value.map(readiness).reduce((a, b) => a > b ? a : b),
              comparisons: comparisonData == null
                  ? []
                  : AdmissionComparisonService().compare(
                      cumulativeConfirmed: cumulativeConfirmed,
                      data: comparisonData,
                      summary: summary,
                      tracks: entry.value,
                      interest: interest,
                      matches: matches,
                    ),
            ),
        ]..sort((a, b) {
          final field = (b.departmentMatch ? 1 : 0).compareTo(
            a.departmentMatch ? 1 : 0,
          );
          if (field != 0) return field;
          final historical = (b.comparisons.isNotEmpty ? 1 : 0).compareTo(
            a.comparisons.isNotEmpty ? 1 : 0,
          );
          if (historical != 0) return historical;
          final ready = b.readiness.compareTo(a.readiness);
          if (ready != 0) return ready;
          final preferred = pos(a.name).compareTo(pos(b.name));
          return preferred != 0 ? preferred : a.name.compareTo(b.name);
        });
    final visible = candidates
        .where((c) => !comparisonOnly || c.comparisons.isNotEmpty)
        .toList();
    return UniversityRecommendation(
      candidates: visible.take(count).toList(),
      total: visible.length,
      issues: [],
      evidence: linked,
    );
  }
}
