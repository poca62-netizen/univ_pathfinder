// Isolated browser QA entry. Synthetic records only; no authentication or DB writes.
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/admission_condition_store.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

void main() {
  final date = DateTime.utc(2026);
  const subjects = ['공통국어1', '공통수학1', '공통영어1', '한국사1', '통합사회1', '통합과학1'];
  final summary = CounselingSummary(
    grades: SummarySection([
      for (final term in [(2025, 1, 1), (2025, 1, 2), (2026, 2, 1)])
        for (final name in subjects)
          GradeRecord(
            id: '$term/$name',
            userId: 'synthetic',
            schoolYear: term.$2,
            semester: term.$3,
            subjectName: name,
            credit: 3,
            gradeRank: 1,
            calendarYear: term.$1,
            examKind: 'semesterSummary',
            sourceConfirmedAt: date,
            createdAt: date,
            updatedAt: date,
          ),
    ]),
    mockExams: SummarySection([
      if (const bool.fromEnvironment('MINIMUM_PREVIEW'))
        for (final month in [6, 9])
          for (final area in ['국어', '수학', '영어', '통합사회', '통합과학', '한국사'])
            MockExamRecord(
              id: '$month/$area',
              calendarYear: 2026,
              schoolYear: 2,
              examMonth: month,
              subject: area,
              institution: '교육청',
              gradeRank: month == 6 ? 1 : 4,
            ),
    ]),
    activities: SummarySection([
      SchoolRecordEvidence(
        id: 'synthetic',
        calendarYear: 2026,
        schoolYear: 2,
        category: '세특',
        evidence: '컴퓨터공학 분야 가상 활동',
        careerInterest: '컴퓨터공학',
        sourceLocation: '가상 자료',
        confirmedAt: date,
      ),
    ]),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PathfinderTheme.light,
      home: UniversityRecommendationScreen(
        loadSummary: () async => summary,
        conditionStore: const bool.fromEnvironment('MINIMUM_PREVIEW')
            ? AdmissionConditionStore('browser-qa-synthetic')
            : null,
        loadCatalog: const bool.fromEnvironment('MINIMUM_PREVIEW')
            ? () async => AdmissionCatalog(
                year: 2028,
                source: '가상 QA 자료',
                status: '가상 자료',
                tracks: [
                  for (final name in ['일반전형', '학과별전형'])
                    AdmissionTrack(
                      university: '가상검증대',
                      department: '',
                      type: '학생부교과',
                      name: name,
                      quota: '10명',
                      eligibility: '가상 지원자격',
                      recommendation: '학교장 추천',
                      recommender: '학교장',
                      selection: '교과',
                      minimum: name == '일반전형'
                          ? '국,수,영,통사/통과(상위 1과목) 중 2개 합 5 이내'
                          : '일반학과: 국,수,영,통사/통과(상위 1과목) 중 2개 합 5 이내\n별도학과: 없음',
                      section: '가상',
                    ),
                ],
              )
            : null,
      ),
    ),
  );
}
