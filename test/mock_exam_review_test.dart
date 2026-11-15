import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_draft.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_import_parser.dart';
import 'package:univ_pathfinder/screens/mock_exam_review_screen.dart';

Map<String, dynamic> word(String text, double x, double y) => {
  'text': text,
  'x': x - 5,
  'y': y,
  'w': 10,
  'h': 4,
};
void main() {
  test('2028 통합 탐구 영역명을 선택탐구로 바꾸지 않음', () {
    final words = [
      for (final h in [
        ('원점수', 200.0),
        ('표준점수', 300.0),
        ('백분위', 400.0),
        ('등급', 500.0),
      ])
        word(h.$1, h.$2, 10),
      for (var i = 0; i < 2; i++) ...[
        word(['통합사회', '통합과학'][i], 20, 30 + i * 20),
        word('80', 200, 30 + i * 20),
        word('120', 300, 30 + i * 20),
        word('90', 400, 30 + i * 20),
        word('2', 500, 30 + i * 20),
      ],
    ];
    final result = MockExamImportParser().parse([
      {
        'text': '2026학년도 9월 고2',
        'lines': [
          {'words': words},
        ],
      },
    ]);
    expect(result.rows.map((r) => r.subject), ['통합사회', '통합과학']);
    expect(result.rows.map((r) => r.gradeRank), [2, 2]);
  });
  test('영역별 열 매핑·빈 지표·기존 등급 우선 및 분포표 제외', () {
    final words = [
      for (final h in [
        ('원점수', 200.0),
        ('표준점수', 300.0),
        ('백분위', 400.0),
        ('등급', 500.0),
      ])
        word(h.$1, h.$2, 10),
      for (var i = 0; i < 3; i++) ...[
        word(['국어', '수학', '영어'][i], 20, 30 + i * 20),
        word('${80 + i}', 200, 30 + i * 20),
        if (i < 2) ...[
          word('${120 + i}', 300, 30 + i * 20),
          word('${90 + i}', 400, 30 + i * 20),
        ],
        word('${i + 2}', 500, 30 + i * 20),
        word('99999', 650, 30 + i * 20),
      ],
    ];
    final result = MockExamImportParser().parse([
      {
        'text': '2026학년도 9월 고2 전국연합학력평가',
        'lines': [
          {'words': words},
        ],
        'mockGradeRecoveries': [
          {'subject': '영어', 'grade': 1},
        ],
      },
    ]);
    expect(result.rows.length, 3);
    expect(result.rows.first.rawScore, 80);
    expect(result.rows.first.standardScore, 120);
    expect(result.rows.first.percentile, 90);
    expect(result.rows.last.standardScore, isNull);
    expect(result.rows.last.percentile, isNull);
    expect(result.rows.last.gradeRank, 4);
    expect(result.rows.last.recoveredGrade, isFalse);
    expect(result.warnings.any((w) => w.contains('다릅니다')), isTrue);
  });
  test('확인 못한 머리글과 서로 다른 같은 칸 수치는 추측하지 않는다', () {
    expect(
      MockExamImportParser().parse([
        {'text': '점수 81 등급 2', 'lines': []},
      ]).rows,
      isEmpty,
    );
    final words = [
      word('원점수', 200, 10),
      word('표준점수', 300, 10),
      word('백분위', 400, 10),
      word('등급', 500, 10),
      word('국어', 20, 30),
      word('81', 200, 30),
      word('82', 201, 30),
      word('120', 300, 30),
    ];
    final result = MockExamImportParser().parse([
      {
        'text': '가상',
        'lines': [
          {'words': words},
        ],
      },
    ]);
    expect(result.rows.single.rawScore, isNull);
    expect(result.warnings, isNotEmpty);
  });
  testWidgets('표 수정·확인 초기화·저장 실패 재시도는 같은 ID 유지', (t) async {
    t.view.physicalSize = const Size(1500, 1700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final requests = <List<MockExamRecord>>[];
    await t.pumpWidget(
      MaterialApp(
        home: MockExamReviewScreen(
          importResult: const MockExamImportResult(
            rows: [
              MockExamDraft(
                subject: '국어',
                rawScore: 80,
                standardScore: 120,
                percentile: 90,
                gradeRank: 2,
              ),
              MockExamDraft(
                subject: '영어',
                rawScore: 92,
                gradeRank: 1,
                recoveredGrade: true,
              ),
            ],
          ),
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          saveRecords: (records) async {
            requests.add(records);
            throw StateError('offline');
          },
        ),
      ),
    );
    final confirm = find.byKey(const ValueKey('mock-batch-confirm'));
    await t.tap(confirm);
    await t.pump();
    final field = find.byKey(const ValueKey('mock-0-raw'));
    await t.enterText(field, '83');
    await t.pump();
    expect(t.widget<CheckboxListTile>(confirm).value, isFalse);
    for (var i = 0; i < 2; i++) {
      if (!t.widget<CheckboxListTile>(confirm).value!) {
        await t.tap(confirm);
      }
      await t.pump();
      final save = find.widgetWithText(FilledButton, '선택 영역 일괄 저장');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '저장'));
      await t.pumpAndSettle();
    }
    expect(requests.length, 2);
    expect(requests.first.map((r) => r.id), requests.last.map((r) => r.id));
    expect(requests.last.first.rawScore, 83);
    expect(requests.last.last.standardScore, isNull);
    expect(requests.last.last.percentile, isNull);
    expect(find.textContaining('수정값은 유지됩니다'), findsOneWidget);
  });
  testWidgets('문자 수치와 빈 영역은 저장 차단, 체험 저장 차단', (t) async {
    t.view.physicalSize = const Size(1500, 1700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: MockExamReviewScreen(
          importResult: const MockExamImportResult(
            rows: [MockExamDraft(subject: '국어', rawScore: 80)],
          ),
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          saveRecords: (_) async {
            calls++;
          },
        ),
      ),
    );
    await t.enterText(find.byKey(const ValueKey('mock-0-raw')), '문자');
    await t.tap(find.byKey(const ValueKey('mock-batch-confirm')));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '선택 영역 일괄 저장'));
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('숫자를 입력하세요.'), findsOneWidget);
    await t.pumpWidget(
      const MaterialApp(
        home: MockExamReviewScreen(
          importResult: MockExamImportResult(),
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          saveAllowed: false,
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('mock-batch-confirm')));
    await t.pump();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '선택 영역 일괄 저장'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('작은 화면·키보드에서도 표를 가로 이동하고 저장 영역까지 스크롤', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(
      MaterialApp(
        home: MockExamReviewScreen(
          importResult: MockExamImportResult(
            rows: [
              for (final s in ['국어', '수학', '영어', '한국사', '사회탐구', '과학탐구'])
                MockExamDraft(subject: s, rawScore: 80, gradeRank: 2),
            ],
          ),
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
        ),
      ),
    );
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('mock-0-subject')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    final horizontal = find.byType(SingleChildScrollView).first;
    await t.ensureVisible(horizontal);
    await t.dragFrom(
      t.getTopLeft(horizontal) + const Offset(200, 20),
      const Offset(-900, 0),
    );
    expect(
      t
          .state<ScrollableState>(
            find
                .descendant(of: horizontal, matching: find.byType(Scrollable))
                .first,
          )
          .position
          .pixels,
      greaterThan(0),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(
      find.widgetWithText(FilledButton, '선택 영역 일괄 저장'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
