import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/map_location.dart';
import 'package:univ_pathfinder/services/kakao_directions.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';

import 'university_map_test.dart' as fixtures;

void main() {
  setUp(CounselingSession.instance.clear);
  tearDown(CounselingSession.instance.clear);
  test('길찾기는 선택한 수단·정확한 위경도와 인코딩한 장소명을 전달한다', () {
    final origin = fixtures.place('출발/지, A&B#?', 37.5);
    final destination = fixtures.place('목적지', 37.7);
    for (final mode in KakaoTravelMode.values) {
      final uri = kakaoDirectionsUri(origin, destination, mode);
      expect(uri.host, 'map.kakao.com');
      expect(uri.toString(), contains('/link/by/${mode.code}/'));
      expect(uri.toString(), contains('%2F'));
      expect(uri.toString(), contains('%2C'));
      expect(uri.toString(), endsWith(',37.7,127.0'));
      expect(uri.query, isEmpty);
      expect(uri.fragment, isEmpty);
    }
  });
  test('거리순 정렬은 미확인을 뒤에 두고 출발지 없으면 선택 순서 유지', () {
    final origin = fixtures.place('출발', 37.5);
    final far = MapDestination(
      id: 'far',
      label: '먼 곳',
      location: fixtures.place('먼 곳', 37.8),
    );
    final near = MapDestination(
      id: 'near',
      label: '가까운 곳',
      location: fixtures.place('가까운 곳', 37.51),
    );
    const pending = MapDestination(id: 'pending', label: '미확인');
    final list = [far, pending, near];
    expect(
      orderedMapDestinations(origin, list, byDistance: true).map((d) => d.id),
      ['near', 'far', 'pending'],
    );
    expect(orderedMapDestinations(null, list, byDistance: true), list);
    expect(orderedMapDestinations(origin, list, byDistance: false), list);
    expect(list.first, far);
  });
  testWidgets('출발지 미선택 차단·선택 후 길찾기·팝업 실패 링크 복사', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CounselingSession.instance.toggleCatalogUniversity('대학');
    Uri? opened;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityMapScreen(
          universityQueries: const {'대학': '대학교'},
          mapBuilder: fixtures.testMap,
          search: (q) async => [fixtures.place(q, q == '대학교' ? 37.7 : 37.5)],
          openDirections: (uri) {
            opened = uri;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final route = find.byKey(const ValueKey('route:university:대학'));
    expect(tester.widget<TextButton>(route).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, '출발지 기관명 또는 주소'),
      '출발 기관',
    );
    await tester.tap(find.widgetWithText(FilledButton, '출발지 검색'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '출발 기관'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(route);
    await tester.tap(route);
    await tester.pumpAndSettle();
    expect(opened!.path, contains('/link/by/traffic/'));
    expect(Uri.decodeComponent(opened!.path), contains('출발 기관,37.5,127.0'));
    expect(find.textContaining('새 창을 열지 못했습니다.'), findsOneWidget);
    await tester.tap(find.text('링크 복사'));
    await tester.pumpAndSettle();
    expect(copied, opened.toString());
    expect(tester.takeException(), isNull);
  });
}
