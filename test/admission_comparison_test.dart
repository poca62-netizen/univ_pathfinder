import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:univ_pathfinder/services/admission_comparison_service.dart';

import 'university_recommendation_test.dart' as fixtures;

CounselingSummary profile(
  List<int?> ranks, {
  int year = 2025,
  String kind = 'semesterSummary',
  bool confirmed = true,
  bool duplicate = false,
  bool failed = false,
  List<double>? credits,
}) {
  const names = ['공통국어1', '공통수학1', '공통영어1', '한국사1', '통합사회1', '통합과학1'];
  final records = [
    for (var i = 0; i < ranks.length; i++)
      GradeRecord(
        id: 'g$i',
        userId: 'fake',
        schoolYear: 1,
        semester: 1,
        subjectName: names[i],
        credit: credits?[i] ?? 3,
        gradeRank: ranks[i],
        calendarYear: year,
        examKind: kind,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        sourceConfirmedAt: confirmed ? DateTime.utc(2026) : null,
      ),
  ];
  return CounselingSummary(
    grades: SummarySection([
      ...records,
      if (duplicate) records.first,
    ], failed: failed),
    mockExams: SummarySection([]),
    activities: fixtures.summary().activities,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = UniversityRecommendationService();
  final engine = AdmissionComparisonService();
  final data = jsonDecode(
    File('assets/data/admission_comparison.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final track = fixtures.track('홍익대(서울)', name: '학교장추천자전형', type: '학생부교과');
  List<AcademicComparison> run(
    CounselingSummary s, {
    Map<String, dynamic>? source,
    String interest = '컴퓨터공학',
  }) => engine.compare(
    data: source ?? data,
    summary: s,
    tracks: [track],
    interest: interest,
    matches: service.matches,
  );
  test('공개 자료 번들·2024/2025 결과 연도와 평균 지표 보존', () async {
    final bundled = await service.loadComparison();
    expect(bundled['benchmarks'], hasLength(199));
    expect(
      (bundled['benchmarks'] as List).map((b) => b['university']).toSet(),
      hasLength(5),
    );
    final first = (bundled['benchmarks'] as List).firstWhere(
      (b) => b['university'] == '홍익대(서울)' && b['department'] == '컴퓨터공학과',
    ) as Map;
    expect(first['centralMetric'], '등록자 평균');
    expect((first['history'] as List).map((v) => v['year']), [2024, 2025]);
    expect((first['history'] as List).first['central'], 1.92);
  });
  test('실제 입결 대비 강·중·약, 최종 합격 여부와 구분', () {
    expect(
      run(profile([1, 1, 1, 1, 1, 1])).single.level,
      AdmissionLikelihood.strong,
    );
    expect(
      run(profile([2, 1, 1, 1, 1, 1], credits: [4, 3, 3, 3, 3, 3]))
          .single
          .level,
      AdmissionLikelihood.medium,
    );
    expect(
      run(profile([2, 2, 2, 2, 2, 2])).single.level,
      AdmissionLikelihood.weak,
    );
    final result = service.recommend(
      catalog: fixtures.catalog([track]),
      summary: profile([1, 1, 1, 1, 1, 1]),
      interest: '컴퓨터공학',
      count: 1,
      comparisonData: data,
    );
    expect(
      result.candidates.single.comparisons.single.level,
      AdmissionLikelihood.strong,
    );
    expect(
      result.candidates.single.assessment.level,
      AdmissionLikelihood.insufficient,
    );
  });
  test('누적 비교는 세 학기 완비 후 학점평균에만 공식 누적표 적용', () {
    final base = profile([1, 1, 1, 1, 1, 1]);
    final records = [
      for (final term in [(2025, 1, 1), (2025, 1, 2), (2026, 2, 1)])
        for (final g in base.confirmedGrades)
          GradeRecord.fromJson({
            ...g.toMap(),
            'id': '${term.$1}/${term.$3}/${g.id}',
            'user_id': 'fake',
            'calendar_year': term.$1,
            'school_year': term.$2,
            'semester': term.$3,
          }),
    ];
    AcademicComparison cumulative(
      List<GradeRecord> grades, {
      Map<String, dynamic>? source,
    }) => engine
        .compare(
          data: source ?? data,
          summary: CounselingSummary(
            grades: SummarySection(grades),
            mockExams: base.mockExams,
            activities: base.activities,
          ),
          tracks: [track],
          interest: '컴퓨터공학',
          matches: service.matches,
          cumulativeConfirmed: true,
        )
        .single;
    final c = cumulative(records);
    expect(c.weightedAverage, 1);
    expect(c.simpleAverage, isNull);
    expect(c.optimistic, 1.28);
    expect(c.conservative, 1.28);
    expect(c.level, AdmissionLikelihood.strong);
    expect(
      cumulative(records.take(12).toList()).level,
      AdmissionLikelihood.insufficient,
    );
    expect(
      cumulative([...records, records.first]).level,
      AdmissionLikelihood.insufficient,
    );
    final broken = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    (broken['cumulativeBridge'] as Map)['nodes'] = [
      [1, double.infinity],
      [5, 9],
    ];
    expect(
      cumulative(records, source: broken).level,
      AdmissionLikelihood.insufficient,
    );
  });
  test('소수 모집·연도별 지표 혼재는 강으로 표시하지 않음', () {
    for (final mutation in ['quota', 'mixedMetrics', 'centralMetric']) {
      final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
      final b = (copy['benchmarks'] as List).firstWhere(
        (b) => b['university'] == '홍익대(서울)' && b['department'] == '컴퓨터공학과',
      ) as Map;
      if (mutation == 'mixedMetrics') {
        b['mixedMetrics'] = true;
      } else {
        (b['history'] as List).first[mutation] = mutation == 'quota'
            ? 3
            : '50%컷';
      }
      expect(
        run(profile([1, 1, 1, 1, 1, 1]), source: copy).single.level,
        AdmissionLikelihood.insufficient,
      );
    }
  });
  test('다른 연도·중간기말·미확인·누락·중복·등급공란·잘못된 값 차단', () {
    for (final s in [
      profile([1, 1, 1, 1, 1, 1], year: 2026),
      profile([1, 1, 1, 1, 1, 1], kind: 'midterm'),
      profile([1, 1, 1, 1, 1, 1], confirmed: false),
      profile([1, 1, 1, 1, 1]),
      profile([1, 1, 1, 1, 1, 1], duplicate: true),
      profile([1, 1, 1, 1, 1, null]),
      profile([1, 1, 1, 1, 1, 6]),
      profile([1, 1, 1, 1, 1, 1], failed: true),
      profile([1, 1, 1, 1, 1, 1], credits: [3, 3, 3, 3, 3, 0]),
    ]) {
      expect(run(s).single.level, AdmissionLikelihood.insufficient);
    }
  });
  test('학종·다른 학과·다른 전형으로 입결을 옮기지 않음', () {
    expect(run(profile([1, 1, 1, 1, 1, 1]), interest: '생명과학'), isEmpty);
    final r = engine.compare(
      data: data,
      summary: profile([1, 1, 1, 1, 1, 1]),
      tracks: [fixtures.track('홍익대(서울)', name: '학교생활우수자전형')],
      interest: '컴퓨터공학',
      matches: service.matches,
    );
    expect(r, isEmpty);
  });
  test('평균과 학점평균의 표 노드 범위 사용, 외삽하지 않음', () {
    final c = run(profile([2, 1, 1, 1, 1, 1], credits: [4, 3, 3, 3, 3, 3]))
        .single;
    expect(c.optimistic, 1.84);
    expect(c.conservative, 2.14);
    final last = run(profile([5, 5, 5, 5, 5, 5])).single;
    expect(last.optimistic, 8.89);
    expect(last.conservative, 8.89);
  });
  test('연도 부족 또는 지표 역전이면 비교 보류', () {
    final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    final b = (copy['benchmarks'] as List).firstWhere(
      (b) => b['university'] == '홍익대(서울)' && b['department'] == '컴퓨터공학과',
    ) as Map;
    (b['history'] as List)[0]['central'] = 4.0;
    expect(
      run(profile([1, 1, 1, 1, 1, 1]), source: copy).single.level,
      AdmissionLikelihood.insufficient,
    );
    b['history'] = [(b['history'] as List).last];
    expect(
      run(profile([1, 1, 1, 1, 1, 1]), source: copy).single.level,
      AdmissionLikelihood.insufficient,
    );
  });
  test('실제 2028 카탈로그의 5개 대학 전형에 각각 연결', () async {
    final catalog = await service.loadCatalog();
    for (final b in (data['benchmarks'] as List).cast<Map>()) {
      final result = service.recommend(
        catalog: catalog,
        summary: profile([1, 1, 1, 1, 1, 1]),
        interest: b['department'] as String,
        count: 55,
        comparisonData: data,
      );
      final matched = result.candidates.singleWhere(
        (c) => c.name == b['university'],
      );
      expect(
        matched.comparisons.any((c) => c.department == b['department']),
        isTrue,
      );
      expect(matched.assessment.level, AdmissionLikelihood.insufficient);
    }
  });
  test('비교표 숫자·순서 오류는 중으로 분류하지 않음', () {
    final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    (copy['bridge'] as Map)['nineGradeByRankSum'] = [
      for (var i = 0; i < 25; i++) 99,
    ];
    expect(
      run(profile([1, 1, 1, 1, 1, 1]), source: copy).single.level,
      AdmissionLikelihood.insufficient,
    );
  });
  testWidgets('등록 성적으로 학업 강과 최종 자료 부족을 함께 표시', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityRecommendationScreen(
          loadSummary: () async => profile([1, 1, 1, 1, 1, 1]),
          loadCatalog: () async => fixtures.catalog([track]),
          loadComparison: () async => data,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '컴퓨터공학');
    final button = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final label = find.text('과거 입결 대비 학업 비교: 강');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    expect(label, findsOneWidget);
    expect(find.text('학업 비교(참고): 강'), findsOneWidget);
    expect(find.text('최종 합격 판단: 미검증'), findsOneWidget);
    expect(find.textContaining('근거 신뢰도 낮음'), findsOneWidget);
  });
  test('비교 지원 대학 필터 후 요청 개수 적용', () async {
    final result = service.recommend(
      catalog: await service.loadCatalog(),
      summary: profile([1, 1, 1, 1, 1, 1]),
      interest: '경영',
      count: 2,
      comparisonData: data,
      comparisonOnly: true,
    );
    expect(result.total, greaterThanOrEqualTo(3));
    expect(result.candidates.length, 2);
    expect(result.candidates.every((c) => c.comparisons.isNotEmpty), isTrue);
  });
}
