import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/consulting_draft_store.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';

import 'consulting_test.dart' as fixtures;

void main() {
  test('목표·선택 복원과 계정 분리, 잘못된 데이터 및 쓰기 오류', () async {
    final values = <String, String>{};
    ConsultingDraftStore store(String uid) => ConsultingDraftStore(
      uid,
      read: (key) async => values[key],
      write: (key, value) async {
        values[key] = value;
      },
    );
    await store('alice').save(ConsultingDraft('탐구 질문', {'visible'}));
    expect((await store('alice').load()).goal, '탐구 질문');
    expect((await store('alice').load()).selected, {'visible'});
    expect((await store('bob').load()).selected, isEmpty);
    await store('alice').save(ConsultingDraft('', {}));
    expect((await store('alice').load()).selected, isEmpty);
    await expectLater(
      store('').save(ConsultingDraft('', {})),
      throwsStateError,
    );
    await expectLater(
      ConsultingDraftStore(
        'a',
        read: (_) async => '{"version":1,"goal":"x","selected":[3]}',
      ).load(),
      throwsFormatException,
    );
    await expectLater(
      ConsultingDraftStore(
        'a',
        write: (_, _) async => throw StateError('denied'),
      ).save(ConsultingDraft('', {})),
      throwsStateError,
    );
  });

  testWidgets('저장한 목표 복원과 비활성 선택 정리, 복원 실패 덮어쓰기 차단', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? saved;
    final store = ConsultingDraftStore(
      'alice',
      read: (_) async => saved,
      write: (_, value) async {
        saved = value;
      },
    );
    await store.save(ConsultingDraft('생명과학', {'visible', 'hidden', 'deleted'}));
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultingScreen(
          draftStore: store,
          loadSummary: () async => fixtures.summary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('상담 목표: 생명과학'), findsOneWidget);
    expect(find.text('선택한 근거만 보기 (1개)'), findsOneWidget);
    await tester.tap(find.text('상담 준비 저장'));
    await tester.pumpAndSettle();
    expect((await store.load()).selected, {'visible'});
    expect(find.text('이 기기에 상담 준비를 저장했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultingScreen(
          draftStore: ConsultingDraftStore(
            'alice',
            read: (_) async => 'broken',
          ),
          loadSummary: () async => fixtures.summary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('상담 준비를 복원하지 못했습니다.'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '상담 준비 저장'),
    );
    expect(button.onPressed, isNull);
  });
}
