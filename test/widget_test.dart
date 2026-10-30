import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/grade_upload_screen.dart';

Finder field(String label) => find.ancestor(
  of: find.text(label), matching: find.byType(TextFormField),
);
Future<void> openForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: GradeUploadScreen()));
}
Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
}
Future<void> submit(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, '저장');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
void main() {
  testWidgets('required fields prevent saving', (tester) async {
    await openForm(tester);
    await submit(tester);
    expect(find.text('과목 항목을 입력하세요.'), findsOneWidget);
    expect(find.text('학점 항목을 입력하세요.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  final cases = <String, List<String>>{
    '원점수 문자': ['원점수', 'abc', '올바른 숫자를 입력하세요.'],
    '원점수 NaN': ['원점수', 'NaN', '올바른 숫자를 입력하세요.'],
    '평균 무한대': ['과목평균', 'Infinity', '올바른 숫자를 입력하세요.'],
    '점수 범위': ['원점수', '101', '0~100으로 입력하세요.'],
    '등급 소수': ['석차등급', '2.5', '1~5 정수를 입력하세요.'],
    '등급 범위': ['석차등급', '6', '1~5 정수를 입력하세요.'],
    '분포 음수': ['A', '-1', '0~100으로 입력하세요.'],
    '분포 문자': ['B', 'abc', '올바른 숫자를 입력하세요.'],
  };
  for (final entry in cases.entries) {
    testWidgets(entry.key, (tester) async {
      await openForm(tester);
      await enter(tester, '과목', '수학');
      await enter(tester, '학점', '3.5');
      await enter(tester, entry.value[0], entry.value[1]);
      await submit(tester);
      expect(find.text(entry.value[2]), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('distribution total must be about 100', (tester) async {
    await openForm(tester);
    await enter(tester, '과목', '국어');
    await enter(tester, '학점', '2');
    for (final label in ['A', 'B', 'C', 'D', 'E']) {
      await enter(tester, label, '10');
    }
    await submit(tester);
    expect(find.text('A~E 비율의 합은 99.5~100.5%여야 합니다.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('valid optional blanks show confirmation and cancel preserves input', (tester) async {
    await openForm(tester);
    await enter(tester, '과목', '수학');
    await enter(tester, '학점', '3.5');
    await submit(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('성적 저장 확인'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<TextFormField>(field('과목')).controller!.text, '수학');
    expect(tester.widget<TextFormField>(field('학점')).controller!.text, '3.5');
    expect(tester.takeException(), isNull);
  });
}
