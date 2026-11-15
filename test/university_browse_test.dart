import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/favorites_settings_screen.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';

import 'university_recommendation_test.dart' as fixtures;

const tuition = TuitionCatalog(
  source: '공시 자료',
  sourceUrl: 'https://example.org',
  note: '연간 평균',
  rows: [],
);

void main() {
  setUp(() => CounselingSession.instance.clear());
  tearDown(() => CounselingSession.instance.clear());

  testWidgets('설정의 관심 대학은 실제 선택과 함께 갱신한다', (tester) async {
    CounselingSession.instance.toggleCatalogUniversity('서울대');
    await tester.pumpWidget(const MaterialApp(home: FavoritesSettingsScreen()));
    expect(find.text('서울대'), findsOneWidget);
    expect(find.textContaining('가상대학교'), findsNothing);
    await tester.tap(find.byTooltip('선택 해제'));
    await tester.pump();
    expect(find.text('서울대'), findsNothing);
    expect(CounselingSession.instance.catalogSelection, isEmpty);
  });

  test('실제 대학 선택 한도·중복 해제·로그아웃 초기화', () {
    final session = CounselingSession.instance;
    for (var i = 0; i < 10; i++) {
      expect(session.toggleCatalogUniversity('대학$i'), isTrue);
    }
    expect(session.toggleCatalogUniversity('대학10'), isFalse);
    expect(session.catalogSelection.length, 10);
    expect(session.toggleCatalogUniversity('대학0'), isTrue);
    expect(session.toggleCatalogUniversity('대학10'), isTrue);
    session.clear();
    expect(session.catalogSelection, isEmpty);
  });

  testWidgets('실제 번들 로드·대학 검색·선택·비교 전환', (tester) async {
    final service = UniversityRecommendationService();
    final data = await tester.runAsync(service.loadCatalog);
    final fees = await tester.runAsync(service.loadTuition);
    expect(data!.tracks.map((r) => r.university).toSet().length, 55);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversitySearchScreen(
          loadCatalog: () async => data,
          loadTuition: () async => fees!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '서울대');
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
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '서울대'));
    await tester.pumpAndSettle();
    expect(CounselingSession.instance.catalogSelection, {'서울대'});
    await tester.tap(find.text('선택한 1개 대학 비교'));
    await tester.pumpAndSettle();
    expect(find.text('관심 대학 1/10개'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('609.2만원'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('609.2만원'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('모바일 필터·실패 구분·재조회 및 선택 유지', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: UniversitySearchScreen(
          loadCatalog: () async {
            if (fail) throw StateError('offline');
            return fixtures.catalog();
          },
          loadTuition: () async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('전형 자료를 불러오지 못했습니다.'), findsOneWidget);
    fail = false;
    await tester.scrollUntilVisible(
      find.text('자료 다시 불러오기'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('자료 다시 불러오기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(CheckboxListTile, '서울대'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '서울대'));
    await tester.pumpAndSettle();
    expect(CounselingSession.instance.catalogSelection, {'서울대'});
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(find.byType(TextField), '없는대학');
    await tester.pumpAndSettle();
    expect(find.textContaining('조건에 맞는 전형이 없습니다.'), findsOneWidget);
    expect(CounselingSession.instance.catalogSelection, {'서울대'});
    expect(tester.takeException(), isNull);
  });
}
