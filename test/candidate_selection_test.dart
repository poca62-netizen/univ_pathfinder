import 'package:flutter/material.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';

import 'university_recommendation_test.dart' as fixtures;

void main() {
  final session = CounselingSession.instance;
  setUp(session.clear);
  tearDown(session.clear);
  for (final width in [1200.0, 390.0]) {
    testWidgets('후보 선택·비교·돌아오기·저장 연결 ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? saved;
      final comparison = await tester.runAsync(
        UniversityRecommendationService().loadComparison,
      );
      final store = UniversitySelectionStore(
        'alice',
        read: (_) async => saved,
        write: (_, raw) async {
          saved = raw;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: UniversityRecommendationScreen(
            selectionStore: store,
            loadSummary: () async => fixtures.summary(),
            loadCatalog: () async => fixtures.catalog([fixtures.track('서울대')]),
            loadComparison: () async => comparison!,
            loadTuition: () async => const TuitionCatalog(
              source: '검증용 공시',
              sourceUrl: '',
              note: '',
              rows: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '공학');
      final generate = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      final add = find.text('관심 대학에 추가');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(session.catalogSelection, {'서울대'});
      final compare = find.text('선택한 1개 대학 모집정보 비교');
      await tester.ensureVisible(compare);
      await tester.tap(compare);
      await tester.pumpAndSettle();
      expect(find.byType(UniversitySearchScreen), findsOneWidget);
      expect(find.text('관심 대학 1/10개'), findsOneWidget);
      final remove = find
          .descendant(
            of: find.widgetWithText(InputChip, '서울대'),
            matching: find.byType(Icon),
          )
          .last;
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(session.catalogSelection, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('관심 대학에 추가'));
      await tester.tap(find.text('관심 대학에 추가'));
      await tester.pumpAndSettle();
      final save = find.text('관심 대학 목록 저장 · 변경 있음');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(await store.load(), {'서울대'});
      expect(tester.takeException(), isNull);
    });
  }
}
