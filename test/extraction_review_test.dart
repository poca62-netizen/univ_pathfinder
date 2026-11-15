import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/screens/grade_extraction_review_screen_v2.dart';

GradeDraft sample(String name) => GradeDraft(
  schoolYear: 2,
  semester: 1,
  subjectName: name,
  credit: 3,
  rawScore: 88,
  gradeRank: 2,
);

Future<void> open(
  WidgetTester tester,
  List<GradeDraft> drafts, {
  bool isTest = false,
  Future<void> Function(List<Map<String, dynamic>>)? save,
}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: GradeExtractionReviewScreenV2(
        result: ExtractionResult(subjects: drafts),
        isTest: isTest,
        saveGrades: save,
      ),
    ),
  );
}

void main() {
  testWidgets('선택 점수 문자 오류도 과목 안내에 반영되고 빈칸으로 고치면 해제된다', (tester) async {
    await open(tester, [sample('수학')]);
    final score = find.widgetWithText(TextFormField, '원점수 0~100');
    await tester.ensureVisible(score);
    await tester.enterText(score, 'abc');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, '수학 · 수정 필요'), findsOneWidget);
    expect(find.text('원점수 0~100: 올바른 숫자를 입력하세요.'), findsOneWidget);
    await tester.enterText(score, '');
    await tester.pump();
    expect(find.byType(ActionChip), findsNothing);
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('수정 필요 과목으로 이동하고 학점을 보완하면 안내가 사라진다', (tester) async {
    await open(tester, [sample('국어'), sample('영어')..credit = null]);
    expect(find.widgetWithText(ActionChip, '영어 · 수정 필요'), findsOneWidget);
    await tester.tap(find.text('영어 · 수정 필요'));
    await tester.pumpAndSettle();
    expect(find.text('학점은 0보다 커야 합니다.').hitTestable(), findsOneWidget);
    final credit = find.widgetWithText(TextFormField, '학점').last;
    await tester.ensureVisible(credit);
    await tester.enterText(credit, '3');
    await tester.pump();
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('학점은 0보다 커야 합니다.'), findsNothing);
    expect(find.text('국어'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('원본을 확대해 보고 닫아도 수정한 입력값은 유지된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GradeExtractionReviewScreenV2(
          result: ExtractionResult(subjects: [sample('가상국어2')]),
          sourceImage: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        ),
      ),
    );
    final field = find.byType(TextFormField).first;
    await tester.enterText(field, '가상영어2');
    await tester.tap(find.text('원본 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('원본 이미지 대조'), findsOneWidget);
    await tester.tap(find.byTooltip('원본 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('가상영어2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('처음부터 추출 결과가 없으면 전체 제외로 오인하지 않고 재선택을 제공한다', (tester) async {
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GradeExtractionReviewScreenV2(
          result: const ExtractionResult(subjects: []),
          sourceText: 'dies Ee EN',
          requireSourceConfirmation: true,
          onSelectAnotherFile: () => selections++,
        ),
      ),
    );
    expect(find.text('모든 과목을 제외했습니다. 저장할 내용이 없습니다.'), findsNothing);
    expect(find.text('자동으로 추출된 과목이 없습니다. 아직 저장된 성적은 없습니다.'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 저장'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('파일 다시 선택'));
    expect(selections, 1);
  });

  testWidgets('스크롤 밖 과목의 잘못된 입력도 저장을 막는다', (tester) async {
    var calls = 0;
    await open(
      tester,
      [sample('수학'), sample('영어'), sample('국어')],
      save: (_) async {
        calls++;
      },
    );
    final field = find.widgetWithText(TextFormField, '원점수 0~100').first;
    await tester.enterText(field, 'abc');
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, 0);
    expect(find.text('수정이 필요한 과목의 입력값을 확인해 주세요.'), findsOneWidget);
    expect(
      find.text('원점수 0~100: 올바른 숫자를 입력하세요.').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('추출값 초기 표시, 수정은 원본 객체에 영향을 주지 않는다', (tester) async {
    final original = sample('수학');
    await open(tester, [original]);
    expect(find.text('수학'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '국어');
    await tester.pump();
    expect(original.subjectName, '수학');
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('국어'), findsOneWidget);
  });

  testWidgets('테스트 모드는 저장할 수 없다', (tester) async {
    var calls = 0;
    await open(
      tester,
      [sample('수학')],
      isTest: true,
      save: (_) async {
        calls++;
      },
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 저장'))
          .onPressed,
      isNull,
    );
    expect(calls, 0);
  });

  testWidgets('전체 제외 시 저장 비활성화', (tester) async {
    await open(tester, [sample('수학')]);
    await tester.tap(find.text('제외'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 저장'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('제외 후 남은 과목 필드 값이 다른 과목으로 바뀌지 않는다', (tester) async {
    await open(tester, [sample('수학'), sample('영어')]);
    await tester.tap(find.text('제외').first);
    await tester.pumpAndSettle();
    expect(find.text('영어'), findsOneWidget);
    expect(find.text('수학'), findsNothing);
  });

  testWidgets('선택 점수의 문자 입력은 null로 조용히 저장되지 않는다', (tester) async {
    var calls = 0;
    await open(
      tester,
      [sample('수학')],
      save: (_) async {
        calls++;
      },
    );
    final field = find.widgetWithText(TextFormField, '원점수 0~100');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'abc');
    await tester.pump();
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('올바른 숫자를 입력하세요.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('저장 실패 시 수정값 유지와 재시도 가능', (tester) async {
    var calls = 0;
    await open(
      tester,
      [sample('수학')],
      save: (_) async {
        calls++;
        throw Exception('offline');
      },
    );
    await tester.enterText(find.byType(TextFormField).first, '수학 수정');
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('수학 수정'), findsOneWidget);
    expect(find.text('저장하지 못했습니다. 입력은 유지됩니다. 다시 시도해 주세요.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 저장'))
          .onPressed,
      isNotNull,
    );
  });
}
