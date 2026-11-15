import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/school_record_edit_screen.dart';
import 'package:univ_pathfinder/screens/school_record_screen.dart';

SchoolRecordEvidence sample({
  String location = '3쪽 · 진로활동',
  String evidence = '가상 탐구 활동을 기록함.',
}) => SchoolRecordEvidence(
  id: 'fictional',
  calendarYear: 2026,
  schoolYear: 2,
  category: '진로활동',
  evidence: evidence,
  sourceLocation: location,
  confirmedAt: DateTime.utc(2026, 11, 4),
);
void main() {
  test('근거와 출처 필수 및 DB 왕복', () {
    expect(sample(location: ' ').validationErrors(), isNotEmpty);
    expect(sample(evidence: '').validationErrors(), isNotEmpty);
    final restored = SchoolRecordEvidence.fromJson(sample().toMap());
    expect(restored.evidence, sample().evidence);
    expect(restored.sourceLocation, sample().sourceLocation);
    expect(restored.confirmedAt, sample().confirmedAt);
  });
  testWidgets('저장 실패 후 입력 유지와 수정 후 재확인', (tester) async {
    var calls = 0;
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolRecordEditScreen(
          record: sample(),
          saveRecord: (r, e) async {
            calls++;
            throw StateError('offline');
          },
        ),
      ),
    );
    final save = find.widgetWithText(FilledButton, '생활기록부 근거 저장');
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
    expect(find.text('가상 탐구 활동을 기록함.'), findsOneWidget);
    final field = find.byType(TextFormField).at(2);
    await tester.ensureVisible(field);
    await tester.enterText(field, '세특');
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });
  testWidgets('체험 자료 저장 차단', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolRecordEditScreen(record: sample(), saveAllowed: false),
      ),
    );
    final save = find.widgetWithText(FilledButton, '생활기록부 근거 저장');
    await tester.ensureVisible(save);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });
  testWidgets('조회 실패 재시도 후 원문과 출처 표시', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolRecordScreen(
          loadRecords: () async {
            if (calls++ == 0) throw StateError('offline');
            return [sample()];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
    expect(find.text('출처: 3쪽 · 진로활동'), findsOneWidget);
    expect(find.text('가상 탐구 활동을 기록함.'), findsOneWidget);
  });
}
