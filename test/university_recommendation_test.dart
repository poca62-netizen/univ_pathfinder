import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';

AdmissionTrack track(
  String university, {
  String department = '',
  String name = '일반전형',
  String type = '학생부종합',
}) => AdmissionTrack(
  university: university,
  department: department,
  type: type,
  name: name,
  quota: '10명',
  eligibility: '고교 졸업(예정)자',
  recommendation: 'X',
  recommender: '',
  selection: '서류 100%',
  minimum: '없음',
  section: '서울',
);
AdmissionCatalog catalog([List<AdmissionTrack>? rows]) => AdmissionCatalog(
  year: 2028,
  source: '전형 자료.html',
  status: '공식 원문 대조 전',
  tracks:
      rows ??
      [
        track('서울대'),
        track('연세대(서울)'),
        track('가상분야대', department: '약학과'),
        track('서울대', name: '지역균형전형'),
        track('가상특별대', name: '농어촌전형'),
      ],
);
CounselingSummary summary({
  bool enabled = true,
  bool confirmed = true,
  bool failed = false,
}) => CounselingSummary(
  grades: SummarySection([
    GradeRecord(
      id: 'g',
      userId: 'fake',
      schoolYear: 2,
      semester: 1,
      subjectName: '생명과학',
      credit: 3,
      gradeRank: 2,
      calendarYear: 2026,
      examKind: 'semesterSummary',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      sourceConfirmedAt: confirmed ? DateTime.utc(2026) : null,
    ),
  ], failed: failed),
  mockExams: SummarySection([]),
  activities: SummarySection([
    SchoolRecordEvidence(
      id: 'e',
      calendarYear: 2026,
      schoolYear: 2,
      category: '세특',
      evidence: '약학 관련 실험을 수행함.',
      sourceLocation: '3쪽',
      confirmedAt: DateTime.utc(2026),
      careerEvidenceEnabled: enabled,
    ),
  ]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = UniversityRecommendationService();
  test('번들 전형 자산 로드', () async {
    final data = await service.loadCatalog();
    expect(data.year, 2028);
    expect(data.tracks.length, 1045);
  });
  test('대학 중복 없이 요청 개수, 분야 일치가 기본 대학 순서보다 우선', () {
    final result = service.recommend(
      catalog: catalog(),
      summary: summary(),
      interest: '약학',
      count: 2,
    );
    expect(result.candidates.map((c) => c.name), ['가상분야대', '서울대']);
    expect(result.total, 3);
    expect(result.candidates.last.tracks.length, 2);
    expect(result.evidence.single.sourceLocation, '3쪽');
    final changed = service.recommend(
      catalog: catalog(),
      summary: summary(),
      interest: '생명과학',
      count: 1,
      priority: '연세대(서울),서울대',
    );
    expect(changed.candidates.single.name, '연세대(서울)');
    expect(changed.candidates.single.departmentMatch, isFalse);
  });
  test('실패·미확인 성적·비활성 생기부·다른 연도·빈 관심 분야 차단', () {
    for (final s in [
      summary(failed: true),
      summary(confirmed: false),
      summary(enabled: false),
    ]) {
      final result = service.recommend(
        catalog: catalog(),
        summary: s,
        interest: '약학',
        count: 5,
      );
      expect(result.candidates, isEmpty);
      expect(result.issues, isNotEmpty);
    }
    expect(
      service
          .recommend(
            catalog: catalog(),
            summary: summary(),
            interest: '약학',
            count: 5,
            targetYear: 2029,
          )
          .issues,
      isNotEmpty,
    );
    expect(
      service
          .recommend(
            catalog: catalog(),
            summary: summary(),
            interest: ' ',
            count: 5,
          )
          .candidates,
      isEmpty,
    );
    expect(
      service
          .recommend(
            catalog: catalog(),
            summary: summary(),
            interest: '약학',
            count: 0,
          )
          .issues,
      isNotEmpty,
    );
  });
  test('특별자격 기본 제외·전형 필터·부족한 개수 유지', () {
    final rows = catalog([
      track('가상교과대', type: '학생부교과'),
      track('가상종합대'),
      track('가상특별대', name: '농어촌전형'),
    ]);
    expect(
      service
          .recommend(
            catalog: rows,
            summary: summary(),
            interest: '공학',
            count: 10,
            type: '학생부교과',
          )
          .candidates
          .single
          .name,
      '가상교과대',
    );
    final result = service.recommend(
      catalog: rows,
      summary: summary(),
      interest: '공학',
      count: 10,
      includeSpecial: true,
    );
    expect(result.candidates.length, 3);
  });
  test('진로 분야 표현과 학과 접미사를 처리하고 AI 부분 일치를 피한다', () {
    expect(service.matches('언론홍보영상학부', '미디어학과'), isTrue);
    expect(service.matches('상담심리학과', '심리전공'), isTrue);
    expect(service.matches('첨단컴퓨팅학부', 'AI'), isTrue);
    expect(service.matches('AI 프로젝트', '인공지능전공'), isTrue);
    expect(service.matches('painting', 'AI'), isFalse);
    expect(service.matches('치의학과', '의학과'), isFalse);
  });

  test('생명과학을 의학으로 추정하지 않고 의학·한의·치의·수의 구분', () {
    expect(service.matches('의예과', '생명과학'), isFalse);
    expect(service.matches('의예과', '의학'), isTrue);
    for (final major in ['한의예과', '치의학과', '수의예과']) {
      expect(service.matches(major, '의학'), isFalse);
    }
  });
  test('제공 파일에서 데이터만 수입, 수도권 55개 대학과 필드 보존', () {
    final data = jsonDecode(
      File('assets/data/admissions_2028.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final parsed = AdmissionCatalog.fromJson(data);
    expect(parsed.tracks.length, 1045);
    expect(parsed.tracks.map((t) => t.university).toSet().length, 55);
    expect(parsed.tracks.any((t) => t.university == '부산대'), isFalse);
    expect(parsed.tracks.any((t) => t.university == '서울교대'), isTrue);
    expect(data.keys.toSet(), {'year', 'source', 'status', 'rows'});
    expect(
      (data['rows'] as List).every(
        (r) =>
            !(r as Map).keys.any((k) => ['author', 'maker', '제작자'].contains(k)),
      ),
      isTrue,
    );
    expect(
      parsed.tracks
          .where((t) => t.university == '서울대' && t.name == '일반전형')
          .first
          .selection,
      contains('서류 50%'),
    );
  });
  testWidgets('관심 분야·개수 선택 후 결과와 부족 수 표시, 조건 변경 시 이전 결과 제거', (tester) async {
    final service = UniversityRecommendationService();
    final comparison = await tester.runAsync(service.loadComparison);
    final tuition = await tester.runAsync(service.loadTuition);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityRecommendationScreen(
          loadSummary: () async => summary(),
          loadCatalog: () async => catalog(),
          loadComparison: () async => comparison!,
          loadTuition: () async => tuition!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '약학');
    final button = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('지원 검토 대학 3개 / 조건에 맞는 3개'), findsOneWidget);
    expect(find.text('조건에 맞는 대학이 10개보다 적어 3개만 표시합니다.'), findsOneWidget);
    final countField = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField<int>,
    );
    await tester.ensureVisible(countField);
    await tester.tap(countField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2개').last);
    await tester.pumpAndSettle();
    final two = find.widgetWithText(FilledButton, '등록 자료로 2개 대학 보기');
    await tester.ensureVisible(two);
    await tester.tap(two);
    await tester.pumpAndSettle();
    expect(find.text('지원 검토 대학 2개 / 조건에 맞는 3개'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(TextField, '관심 학과·분야'));
    await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '교육');
    await tester.pump();
    expect(find.text('지원 검토 대학 3개 / 조건에 맞는 3개'), findsNothing);
    expect(find.text('지원 검토 대학 2개 / 조건에 맞는 3개'), findsNothing);
  });
}
