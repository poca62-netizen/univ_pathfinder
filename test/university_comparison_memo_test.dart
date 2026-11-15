import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The plugin's in-memory backend avoids using the host preference store.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/services/university_comparison_memo.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';

import 'university_recommendation_test.dart' as fixtures;

const tuition = TuitionCatalog(
  source: '공식 등록금 출처',
  sourceUrl: 'https://example.org/source',
  note: '학과별 금액 아님',
  rows: [
    TuitionRecord(
      university: '서울대',
      officialName: '서울대학교',
      campus: '본교',
      region: '서울',
      year: 2026,
      asOf: '2026-05-19',
      annualWon: 6000000,
      scope: '학부',
    ),
  ],
);

void main() {
  final session = CounselingSession.instance;
  setUp(session.clear);
  tearDown(session.clear);
  testWidgets('비교 기록 재진입 복원과 계정별 격리', (tester) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(String user) => MaterialApp(
      home: UniversitySearchScreen(
        compare: true,
        selectionStore: UniversitySelectionStore(
          user,
          read: (_) async => '{"version":1,"year":2028,"names":["서울대"]}',
        ),
        loadCatalog: () async => fixtures.catalog(),
        loadTuition: () async => tuition,
      ),
    );
    await tester.pumpWidget(app('alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('비교 결과 저장'));
    await tester.pumpAndSettle();
    expect(find.text('이 브라우저에 비교 결과를 저장했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.clear();
    await tester.pumpWidget(app('alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장한 비교 보기'));
    await tester.pumpAndSettle();
    final record = find.textContaining('· 서울대');
    expect(record, findsOneWidget);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    session.clear();
    await tester.pumpWidget(app('bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장한 비교 보기'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 비교 결과가 없습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.clear();
    await tester.pumpWidget(app('alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장한 비교 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('비교 기록 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(record, findsOneWidget);
    await tester.tap(find.byTooltip('비교 기록 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 비교 결과가 없습니다.'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장한 비교 보기'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 비교 결과가 없습니다.'), findsOneWidget);
  });
  test('필터·선택 범위·원문·공시 출처를 보존한다', () {
    final catalog = fixtures.catalog([
      fixtures.track('서울대', name: '일반전형', department: '컴퓨터공학과'),
      fixtures.track('서울대', name: '농어촌전형', department: '컴퓨터공학과'),
      fixtures.track('미선택대학', department: '컴퓨터공학과'),
      fixtures.track('다른대학', type: '학생부교과'),
    ]);
    final memo = UniversityComparisonMemo().build(
      catalog: catalog,
      selected: {'서울대', '다른대학', '이전대학'},
      tuition: tuition,
      query: '컴퓨터',
      type: '학생부종합',
    );
    expect(memo, contains('일반전형'));
    expect(memo, isNot(contains('농어촌전형')));
    expect(memo, isNot(contains('미선택대학')));
    expect(memo, contains('조건에 맞는 전형이 없습니다'));
    expect(memo, contains('현재 전형 자료에 없는 대학'));
    expect(memo, contains('서류 100%'));
    expect(memo, contains('2026년 연간 평균 600.0만원'));
    expect(memo, contains('2026-05-19'));
    expect(memo, contains('https://example.org/source'));
    expect(memo, isNot(contains(catalog.source)));
    expect(memo, contains(catalog.status));
    expect(memo, contains('합격을 판정한 결과가 아닙니다'));
    expect(
      UniversityComparisonMemo().build(catalog: catalog, selected: {}),
      isEmpty,
    );
    expect(
      UniversityComparisonMemo().build(
        catalog: catalog,
        selected: {'서울대'},
        includeSpecial: true,
      ),
      contains('농어촌전형'),
    );
  });

  testWidgets('모바일에서 현재 조건을 복사하고 클립보드 실패는 재시도한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    var fail = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (fail) throw PlatformException(code: 'denied');
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
    session.toggleCatalogUniversity('서울대');
    await tester.pumpWidget(
      MaterialApp(
        home: UniversitySearchScreen(
          compare: true,
          loadCatalog: () async =>
              fixtures.catalog([fixtures.track('서울대', department: '컴퓨터공학과')]),
          loadTuition: () async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '컴퓨터');
    await tester.pumpAndSettle();
    final button = find.text('선택 대학 비교 메모 복사');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(copied, contains('검색어: 컴퓨터'));
    expect(copied, contains('등록금: 조회 실패 또는 자료 미확보'));
    expect(copied, contains('컴퓨터공학과'));
    fail = true;
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('메모를 복사하지 못했습니다. 다시 시도하세요.'), findsOneWidget);
    expect(session.catalogSelection, {'서울대'});
    expect(tester.takeException(), isNull);
  });
}
