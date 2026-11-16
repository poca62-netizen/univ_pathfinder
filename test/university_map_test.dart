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

  test('앱 대학 이름은 카카오 장소 이름과 정확히 같을 때만 붙인다', () {
    const queries = {'가까운대': '가까운대학교', '캠퍼스대(서울)': '캠퍼스대학교 서울캠퍼스'};
    expect(appUniversityFor(place('가까운대학교', 37.5), queries), '가까운대');
    expect(appUniversityFor(place('캠퍼스대학교 서울캠퍼스', 37.5), queries), '캠퍼스대(서울)');
    expect(appUniversityFor(place('캠퍼스대학교', 37.5), queries), isNull);
    expect(appUniversityFor(place('가까운대학교 본관', 37.5), queries), isNull);
    final r = CampusSearchResult.fromJson({
      'places': [
        {
          'id': 'p1',
          'name': '가까운대학교',
          'address': '가상',
          'category': '교육,학문 > 학교 > 대학교',
          'latitude': 37.5,
          'longitude': 127.0,
        },
      ],
      'truncated': true,
    });
    expect(r.places.single.name, '가까운대학교');
    expect(r.truncated, isTrue);
    expect(r.failed, isFalse);
  });

  testWidgets('대학 버튼: 지도 영역의 대학 표시, 목적지·관심 대학 추가, 넓은 지도 안내', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    UniversityLayer? layer;
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityMapScreen(
          universityQueries: const {'가까운대': '가까운대학교'},
          search: (_) async => [],
          layerMapBuilder: (origin, destinations, l) {
            layer = l;
            return Text('대학 표시 ${l.visible}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('대학 표시 false'), findsOneWidget);
    expect(find.text('지도 영역의 대학'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '대학'));
    await tester.pump();
    expect(find.text('대학 표시 true'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets); // 검색 중

    layer!.onFound(
      CampusSearchResult(
        places: [place('가까운대학교', 37.51), place('다른대학교', 37.52)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('지도 영역의 대학 2곳'), findsOneWidget);
    expect(find.textContaining('앱 대학 목록에 있음: 가까운대'), findsOneWidget);

    // 앱 대학은 관심 대학으로 추가할 수 있다.
    await tester.tap(find.byTooltip('가까운대 관심 대학에 추가'));
    await tester.pumpAndSettle();
    expect(session.catalogSelection, contains('가까운대'));
    expect(find.byTooltip('가까운대 관심 대학에 추가'), findsNothing);

    // 다른 대학은 목적지로 추가한다.
    await tester.tap(find.byTooltip('다른대학교 목적지에 추가'));
    await tester.pumpAndSettle();
    expect(
      session.mapDestinations.values.map((d) => d.label),
      contains('다른대학교'),
    );

    // '현 지도에서 검색'을 누르면 이전 목록을 지우고 검색 중으로 바뀐다.
    layer!.onFound(const CampusSearchResult(searching: true));
    await tester.pump();
    expect(find.text('지도 영역의 대학'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    layer!.onFound(CampusSearchResult(places: [place('다른대학교', 37.52)]));
    await tester.pumpAndSettle();
    expect(find.text('지도 영역의 대학 1곳'), findsOneWidget);

    // 지도 마커를 누르면 목적지 추가를 제안한다.
    layer!.onTap(place('세번째대학교', 37.53));
    await tester.pump();
    expect(find.textContaining('세번째대학교'), findsWidgets);
    expect(find.widgetWithText(SnackBarAction, '목적지에 추가'), findsOneWidget);
    // 다른 대학을 누르면 앞 알림을 닫고 새 알림을 바로 보인다(앞 알림에 막히지 않음).
    layer!.onTap(place('네번째대학교', 37.54));
    await tester.pumpAndSettle();
    expect(find.textContaining('네번째대학교'), findsOneWidget);
    expect(find.textContaining('세번째대학교'), findsNothing);

    layer!.onFound(const CampusSearchResult(tooWide: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('지도가 너무 넓어'), findsOneWidget);

    // 브라우저에 예전 지도 스크립트가 남아 있으면 화면을 멈추지 않고 새로고침을 안내한다.
    layer!.onFound(const CampusSearchResult(needsReload: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('강력 새로고침'), findsOneWidget);

    // 끄면 목록이 사라지고 늦게 온 결과는 무시한다.
    await tester.tap(find.widgetWithText(FilterChip, '대학'));
    await tester.pumpAndSettle();
    layer!.onFound(CampusSearchResult(places: [place('늦은대학교', 37.6)]));
    await tester.pumpAndSettle();
    expect(find.textContaining('늦은대학교'), findsNothing);
    expect(find.textContaining('지도 영역의 대학 '), findsNothing); // 목록 제목
    expect(find.textContaining('지도가 너무 넓어'), findsNothing);
  });
}
