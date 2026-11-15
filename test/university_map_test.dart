import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/map_location.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';

MapLocation place(String name, double latitude, {String category = '대학교'}) =>
    MapLocation(
      id: name,
      name: name,
      address: '가상 주소 $name',
      latitude: latitude,
      longitude: 127,
      category: category,
    );
Widget testMap(MapLocation? origin, List<MapDestination> destinations) => Text(
  '지도 출발 ${origin?.name ?? "없음"} · 최단 ${mapConnections(origin, destinations).where((c) => c.nearest).map((c) => c.destination.label).join(",")}',
  key: const ValueKey('map-summary'),
);

void main() {
  final session = CounselingSession.instance;
  setUp(session.clear);
  tearDown(session.clear);

  test('구면 직선거리·최단·공동 최단·삭제 후 재계산·미확인 제외', () {
    final origin = place('출발', 37.5);
    final near = MapDestination(
      id: 'near',
      label: '가까운 곳',
      location: place('가까운 곳', 37.51),
    );
    final tie = MapDestination(
      id: 'tie',
      label: '공동 최단',
      location: place('공동 최단', 37.510004),
    );
    final far = MapDestination(
      id: 'far',
      label: '먼 곳',
      location: place('먼 곳', 37.8),
    );
    const pending = MapDestination(id: 'pending', label: '미확인 대학');
    final results = mapConnections(origin, [far, near, tie, pending]);
    expect(results.length, 3);
    expect(results.first.distanceKm, closeTo(1.112, 0.002));
    expect(
      results.where((c) => c.nearest).map((c) => c.destination.id).toSet(),
      {'near', 'tie'},
    );
    expect(mapConnections(origin, [far, pending]).single.nearest, isTrue);
    expect(mapConnections(null, [near]), isEmpty);
    expect(mapConnections(origin, [pending]), isEmpty);
    expect(
      mapConnections(origin, [
        MapDestination(id: 'same', label: '출발지와 동일', location: origin),
      ]).single.distanceKm,
      0,
    );
    expect(() => place('오류', double.nan), throwsArgumentError);
  });

  test('대학 자동 위치는 정확하고 유일한 대학 이름만 적용', () {
    expect(
      unambiguousUniversity('가까운대학교', [place('가까운대학교', 37.51)]),
      isNotNull,
    );
    expect(unambiguousUniversity('대학교', [place('대학교 본관', 37.51)]), isNull);
    expect(
      unambiguousUniversity('대학교', [place('대학교', 37.51), place('대학교', 37.7)]),
      isNull,
    );
    expect(
      unambiguousUniversity('대학교', [place('대학교', 37.51, category: '카페')]),
      isNull,
    );
  });

  for (final width in [1200.0, 390.0]) {
    testWidgets('기관·주소 출발지, 선택 대학 및 다른 목적지 추가·삭제 ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      session.toggleCatalogUniversity('가까운대');
      session.toggleCatalogUniversity('먼대');
      final app = MaterialApp(
        home: UniversityMapScreen(
          universityQueries: const {'가까운대': '가까운대학교', '먼대': '먼대학교'},
          mapBuilder: testMap,
          search: (query) async => switch (query) {
            '가까운대학교' => [place('가까운대학교', 37.51)],
            '먼대학교' => [place('먼대학교', 37.8)],
            '서울시청' => [place('서울시청', 37.5, category: '공공기관')],
            '서울 중구 세종대로 110' => [place('도로명 출발지', 37.52, category: '주소')],
            '도서관' => [place('도서관', 37.5001, category: '도서관')],
            _ => [],
          },
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final originField = find.widgetWithText(TextField, '출발지 기관명 또는 주소');
      final destinationField = find.widgetWithText(
        TextField,
        '목적지 대학·기관명 또는 주소',
      );
      Future<void> search(bool origin, String query, String result) async {
        final field = origin ? originField : destinationField;
        await tester.ensureVisible(field);
        await tester.enterText(field, query);
        final button = find.widgetWithText(
          FilledButton,
          origin ? '출발지 검색' : '목적지 검색',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final tile = find.widgetWithText(ListTile, result);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }

      await search(true, '서울시청', '서울시청');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('map-summary'))).data,
        contains('최단 가까운대'),
      );
      await search(false, '도서관', '도서관');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('map-summary'))).data,
        contains('지도 출발 서울시청 · 최단 도서관'),
      );
      await tester.ensureVisible(find.byTooltip('도서관 목적지 삭제'));
      await tester.tap(find.byTooltip('도서관 목적지 삭제'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('map-summary'))).data,
        contains('최단 가까운대'),
      );
      await search(true, '서울 중구 세종대로 110', '도로명 출발지');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('map-summary'))).data,
        contains('출발 도로명 출발지'),
      );
      session.toggleCatalogUniversity('가까운대');
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('map-summary'))).data,
        contains('최단 먼대'),
      );
      expect(tester.takeException(), isNull);
      session.clear();
      await tester.pumpAndSettle();
      expect(session.mapOrigin, isNull);
      expect(session.mapDestinations, isEmpty);
    });
  }

  testWidgets('검색어 변경 후 늦은 응답 무시·결과 없음과 오류 구분', (tester) async {
    final pending = Completer<List<MapLocation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityMapScreen(
          universityQueries: const {},
          mapBuilder: testMap,
          search: (query) async {
            if (query == '이전 검색') return pending.future;
            if (query == '실패') throw StateError('검색 서버 오류');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '출발지 기관명 또는 주소');
    final button = find.widgetWithText(FilledButton, '출발지 검색');
    await tester.enterText(field, '이전 검색');
    await tester.tap(button);
    await tester.pump();
    await tester.enterText(field, '새 검색');
    await tester.pump();
    pending.complete([place('과거 응답', 37.5)]);
    await tester.pumpAndSettle();
    expect(find.text('과거 응답'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('검색 결과가 없습니다.'), findsOneWidget);
    await tester.enterText(field, '실패');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('검색 서버 오류'), findsOneWidget);
  });
}
