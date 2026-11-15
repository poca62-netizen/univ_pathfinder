import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';

import 'university_recommendation_test.dart' as fixtures;

void main() {
  final session = CounselingSession.instance;
  setUp(session.clear);
  tearDown(session.clear);

  test('계정 분리·빈 목록 저장·버전 및 중복 검증', () async {
    final data = <String, String>{};
    UniversitySelectionStore store(String id) => UniversitySelectionStore(
      id,
      read: (key) async => data[key],
      write: (key, raw) async {
        data[key] = raw;
      },
    );
    await store('alice').save({'서울대'});
    expect(await store('alice').load(), {'서울대'});
    expect(await store('bob').load(), isEmpty);
    await store('alice').save({});
    expect(await store('alice').load(), isEmpty);
    for (final raw in [
      '[]',
      '{"version":2,"year":2028,"names":[]}',
      '{"version":1,"year":2028,"names":["a","a"]}',
      '{"version":1,"year":2028,"names":[3]}',
    ]) {
      await expectLater(
        UniversitySelectionStore('x', read: (_) async => raw).load(),
        throwsFormatException,
      );
    }
    await expectLater(store('').save({}), throwsStateError);
  });

  test('복원 중 수정 차단·실패 덮어쓰기 차단·로그아웃 뒤 늦은 응답 무시', () async {
    final response = Completer<String?>();
    final loading = session.restoreSelection(
      UniversitySelectionStore('alice', read: (_) => response.future),
    );
    expect(session.toggleCatalogUniversity('서울대'), isFalse);
    session.clear();
    response.complete('{"version":1,"year":2028,"names":["서울대"]}');
    await loading;
    expect(session.catalogSelection, isEmpty);
    var writes = 0;
    final broken = UniversitySelectionStore(
      'alice',
      read: (_) async => 'broken',
      write: (_, _) async {
        writes++;
      },
    );
    await session.restoreSelection(broken);
    expect(session.selectionError, isNotNull);
    await session.saveSelection();
    expect(writes, 0);
    expect(session.toggleCatalogUniversity('서울대'), isFalse);
    await session.restoreSelection(
      UniversitySelectionStore('alice', read: (_) async => null),
      retry: true,
    );
    expect(session.selectionError, isNull);
    expect(session.toggleCatalogUniversity('서울대'), isTrue);
  });

  test('다른 화면 진입은 미저장 선택 보존·저장 오류 재시도·계정 전환', () async {
    var fail = true;
    final data = <String, String>{};
    final store = UniversitySelectionStore(
      'alice',
      read: (k) async => data[k],
      write: (k, v) async {
        if (fail) throw StateError('denied');
        data[k] = v;
      },
    );
    await session.restoreSelection(store);
    session.toggleCatalogUniversity('서울대');
    await session.restoreSelection(store);
    expect(session.catalogSelection, {'서울대'});
    await session.saveSelection();
    expect(session.selectionDirty, isTrue);
    expect(session.selectionStatus, contains('저장하지 못했습니다'));
    fail = false;
    await session.saveSelection();
    expect(session.selectionDirty, isFalse);
    expect(await store.load(), {'서울대'});
    await session.restoreSelection(
      UniversitySelectionStore('bob', read: (_) async => null),
    );
    expect(session.catalogSelection, isEmpty);
  });

  testWidgets('저장 목록 재진입 복원·현재 자료 없는 대학 표시', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? raw;
    final store = UniversitySelectionStore(
      'alice',
      read: (_) async => raw,
      write: (_, v) async {
        raw = v;
      },
    );
    await store.save({'서울대', '이전 대학명'});
    Widget app() => MaterialApp(
      home: UniversitySearchScreen(
        selectionStore: store,
        loadCatalog: () async => fixtures.catalog(),
        loadTuition: () async =>
            const TuitionCatalog(source: '', sourceUrl: '', note: '', rows: []),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(session.catalogSelection, {'서울대', '이전 대학명'});
    expect(find.text('이전 대학명 · 현재 자료 없음'), findsOneWidget);
    session.toggleCatalogUniversity('이전 대학명');
    await tester.pump();
    await tester.tap(find.text('관심 대학 목록 저장 · 변경 있음'));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 관심 대학을 저장했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.clear();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(session.catalogSelection, {'서울대'});
  });
}
