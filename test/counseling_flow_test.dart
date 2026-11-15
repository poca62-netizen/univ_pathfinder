import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';

import 'university_recommendation_test.dart' as fixtures;

import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';

void main() {
  setUp(() => CounselingSession.instance.clear());
  tearDown(() => CounselingSession.instance.clear());

  testWidgets('내신 자료는 학년 학기 시험 구분 순서로 등록한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CounselingDocumentsScreen()),
    );
    expect(find.text('내신 중간고사'), findsNothing);
    await tester.tap(find.text('내신 성적표'));
    await tester.pumpAndSettle();
    final year = tester.getTopLeft(find.text('고등학교 학년')).dy;
    final semester = tester.getTopLeft(find.text('학기')).dy;
    final exam = tester.getTopLeft(find.text('시험 구분')).dy;
    expect(year < semester && semester < exam, isTrue);
    expect(find.text('중간고사'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('자료 목록에서 모의고사 종류를 유지하고 등록 화면으로 이동', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CounselingDocumentsScreen()),
    );
    await tester.tap(find.text('모의고사'));
    await tester.pumpAndSettle();
    expect(find.text('모의고사 시행 월'), findsOneWidget);
    expect(find.text('학기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('분야 필터 변경과 비교 화면 이동에도 선택을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversitySearchScreen(
          loadCatalog: () async => fixtures.catalog(),
          loadTuition: () async => const TuitionCatalog(
            source: '공시',
            sourceUrl: '',
            note: '',
            rows: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(CheckboxListTile, '서울대'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, '서울대'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('학생부교과'),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('학생부교과'));
    await tester.pumpAndSettle();
    expect(CounselingSession.instance.catalogSelection.length, 1);
    await tester.tap(find.text('선택한 1개 대학 비교'));
    await tester.pumpAndSettle();
    expect(find.text('관심 대학 1/10개'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '서울대'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
