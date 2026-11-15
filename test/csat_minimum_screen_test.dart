import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/services/admission_condition_store.dart';

import 'university_recommendation_test.dart' as fixtures;
import 'csat_minimum_test.dart' as mocks;

void main() {
  testWidgets('전형별 기준 선택·시험 전환·확인 표시 복원', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final t = AdmissionTrack(
      university: '가상대',
      department: '',
      type: '학생부교과',
      name: '가상전형',
      quota: '10명',
      eligibility: '졸업예정자',
      recommendation: '학교장',
      recommender: '학교장',
      selection: '교과',
      minimum: '일반: 국,수,영,통사/통과(상위 1과목) 중 2개 합 5 이내\n별도: 없음',
      section: '가상',
    );
    final base = fixtures.summary();
    final summary = CounselingSummary(
      grades: base.grades,
      activities: base.activities,
      mockExams: SummarySection([
        ...mocks.mockGrades([4, 4, 4, 4, 4, 4]),
        ...mocks.mockGrades([1, 1, 1, 1, 1, 1], month: 6),
      ]),
    );
    final saved = <String, String>{};
    final store = AdmissionConditionStore(
      'fake',
      read: (k) async => saved[k],
      write: (k, v) async {
        saved[k] = v;
      },
    );
    Future<void> mount() async {
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityRecommendationScreen(
            loadSummary: () async => summary,
            loadCatalog: () async => fixtures.catalog([t]),
            loadTuition: () async => throw StateError('offline'),
            loadComparison: () async => throw StateError('offline'),
            conditionStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '약학');
      final generate = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      final tracks = find.text('전형 1개 · 지원조건');
      await tester.ensureVisible(tracks);
      await tester.tap(tracks);
      await tester.pumpAndSettle();
      final track = find.text('학생부교과 · 가상전형');
      await tester.ensureVisible(track);
      await tester.tap(track);
      await tester.pumpAndSettle();
    }

    await mount();
    expect(find.text('모의고사 대비 수능 최저: 원문 확인 필요'), findsOneWidget);
    final branch = find.widgetWithText(
      DropdownButtonFormField<String>,
      '실제 지원할 학과·계열의 최저 기준',
    );
    await tester.ensureVisible(branch);
    await tester.tap(branch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('일반').last);
    await tester.pumpAndSettle();
    expect(find.text('모의고사 대비 수능 최저: 미달 수준'), findsOneWidget);
    expect(find.textContaining('등급 합 3.0 개선 필요'), findsOneWidget);
    final exam = find.widgetWithText(
      DropdownButtonFormField<String>,
      '수능 최저 비교할 모의고사',
    );
    await tester.ensureVisible(exam);
    await tester.tap(exam);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026년 2학년 6월 · 교육청').last);
    await tester.pumpAndSettle();
    expect(find.text('모의고사 대비 수능 최저: 충족 수준'), findsOneWidget);
    final eligibility = find.widgetWithText(CheckboxListTile, '지원자격 · 확인 필요');
    await tester.ensureVisible(eligibility);
    await tester.tap(eligibility);
    await tester.pumpAndSettle();
    expect(find.text('지원자격 · 본인 확인'), findsOneWidget);
    expect(saved, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await mount();
    expect(find.text('지원자격 · 본인 확인'), findsOneWidget);
    expect(find.text('모의고사 대비 수능 최저: 원문 확인 필요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('저장 복원 실패 시 기존 표시를 덮어쓰지 않음', (tester) async {
    var writes = 0;
    final store = AdmissionConditionStore(
      'fake',
      read: (_) async => throw StateError('denied'),
      write: (_, _) async {
        writes++;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityRecommendationScreen(
          loadSummary: () async => fixtures.summary(),
          loadCatalog: () async => fixtures.catalog(),
          loadTuition: () async => throw StateError('offline'),
          loadComparison: () async => throw StateError('offline'),
          conditionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}
