import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/screens/mock_exam_edit_screen.dart';
import 'package:univ_pathfinder/screens/mock_exam_screen.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';

MockExamRecord sample({
  String id = 'test',
  int month = 9,
  int? grade = 2,
  double? percentile = 91,
}) => MockExamRecord(
  id: id,
  calendarYear: 2026,
  schoolYear: 2,
  examMonth: month,
  subject: '국어',
  gradeRank: grade,
  percentile: percentile,
);
void main() {
  testWidgets('상담 자료에서 DB 모의고사를 복원하고 전용 목록으로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CounselingDocumentsScreen(
          loadGrades: () async => [],
          loadMockExams: () async => [sample()],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026년 2학년 9월'), findsOneWidget);
    await tester.tap(find.text('모의고사 저장·조회'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 2학년 9월 · 국어'), findsOneWidget);
    expect(find.text('백분위 91.0 · 등급 2'), findsOneWidget);
  });
  test('모의고사는 9등급과 선택 지표를 허용하고 잘못된 값과 빈 지표를 거부한다', () {
    expect(sample(grade: 9).validationErrors(), isEmpty);
    expect(sample(grade: 10).validationErrors(), isNotEmpty);
    expect(sample(percentile: double.nan).validationErrors(), isNotEmpty);
    expect(sample(percentile: 101).validationErrors(), isNotEmpty);
    expect(
      sample(grade: null, percentile: null).validationErrors(),
      isNotEmpty,
    );
    expect(MockExamRecord.fromJson(sample().toMap()).toMap(), sample().toMap());
  });
  testWidgets('원본 확인 후 저장 실패 재시도는 같은 ID를 유지하고 수정하면 확인을 초기화한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ids = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MockExamEditScreen(
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          saveRecord: (record, editing) async {
            ids.add(record.id);
            expect(editing, false);
            throw Exception('offline');
          },
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, '영역'), '영어');
    await tester.enterText(find.widgetWithText(TextFormField, '등급'), '9');
    final check = find.byType(CheckboxListTile);
    await tester.tap(check);
    await tester.pump();
    await tester.tap(find.text('모의고사 저장'));
    await tester.pumpAndSettle();
    expect(find.text('저장하지 못했습니다. 입력은 유지됩니다. 다시 시도해 주세요.'), findsOneWidget);
    await tester.tap(find.text('모의고사 저장'));
    await tester.pumpAndSettle();
    expect(ids.length, 2);
    expect(ids.toSet().length, 1);
    await tester.enterText(find.widgetWithText(TextFormField, '등급'), '8');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(check).value, false);
  });
  testWidgets('숫자 문자 오류는 저장하지 않고 체험 자료는 저장 버튼을 제공하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MockExamEditScreen(
          saveRecord: (_, _) async {
            calls++;
          },
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, '영역'), '수학');
    await tester.enterText(find.widgetWithText(TextFormField, '표준점수'), 'abc');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('모의고사 저장'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('숫자를 입력하세요.'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: MockExamEditScreen(saveAllowed: false)),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
  testWidgets('저장 목록은 월 필터와 삭제 후 재조회를 지원한다', (tester) async {
    final records = [sample(id: 'march', month: 3), sample(id: 'sept')];
    await tester.pumpWidget(
      MaterialApp(
        home: MockExamScreen(
          loadRecords: () async => List.of(records),
          deleteRecord: (id) async => records.removeWhere((r) => r.id == id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '9월'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 2학년 9월 · 국어'), findsOneWidget);
    expect(find.text('2026년 2학년 3월 · 국어'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('DB에 저장된 모의고사 1개 영역'), findsOneWidget);
    expect(find.text('선택한 조건에 저장된 모의고사가 없습니다.'), findsOneWidget);
  });
}
