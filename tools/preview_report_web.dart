// Isolated browser QA entry for the consulting report.
// Synthetic student only; no authentication or DB access. University data (results, catalog,
// tuition, bridge) comes from the real app bundle, so missing asset registrations show up here.
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/consulting_report_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

void main() {
  final date = DateTime.utc(2026);
  // 가상 학생: 5등급제 내신 대부분 2등급(일부 1·3), 2026 고2 9월 교육청 모의고사.
  const subjects = {
    '공통국어1': 2,
    '공통수학1': 2,
    '공통영어1': 1,
    '한국사1': 2,
    '통합사회1': 3,
    '통합과학1': 2,
  };
  const mock = {
    // 과목: (백분위, 등급)
    '국어': (88.0, 2),
    '수학': (84.0, 3),
    '영어': (null, 2),
    '통합사회': (82.0, 3),
    '통합과학': (90.0, 2),
    '한국사': (null, 3),
  };
  final summary = CounselingSummary(
    grades: SummarySection([
      for (final term in [(2025, 1, 1), (2025, 1, 2), (2026, 2, 1)])
        for (final e in subjects.entries)
          GradeRecord(
            id: '$term/${e.key}',
            userId: 'synthetic',
            schoolYear: term.$2,
            semester: term.$3,
            subjectName: e.key,
            credit: 3,
            gradeRank: e.value,
            calendarYear: term.$1,
            examKind: 'semesterSummary',
            sourceConfirmedAt: date,
            createdAt: date,
            updatedAt: date,
          ),
    ]),
    mockExams: SummarySection([
      for (final e in mock.entries)
        MockExamRecord(
          id: 'mock/${e.key}',
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          subject: e.key,
          institution: '교육청',
          percentile: e.value.$1,
          gradeRank: e.value.$2,
        ),
    ]),
    activities: SummarySection([
      SchoolRecordEvidence(
        id: 'a1',
        calendarYear: 2026,
        schoolYear: 2,
        category: '세특',
        evidence: '가상 활동: 정보 시간에 정렬 알고리즘을 비교·구현함.',
        careerInterest: '컴퓨터공학',
        sourceLocation: '가상 자료 1쪽',
        confirmedAt: date,
      ),
      SchoolRecordEvidence(
        id: 'a2',
        calendarYear: 2025,
        schoolYear: 1,
        category: '동아리',
        evidence: '가상 활동: 컴퓨터 동아리에서 웹 페이지를 만듦.',
        sourceLocation: '가상 자료 2쪽',
        confirmedAt: date,
      ),
    ]),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PathfinderTheme.light,
      home: ConsultingReportScreen(loadSummary: () async => summary),
    ),
  );
}
