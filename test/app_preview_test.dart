import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/main.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/screens/start_screen.dart';

void main() {
  testWidgets('체험 모드는 Supabase 초기화 없이 상담 자료와 대학 화면을 연다', (tester) async {
    await tester.pumpWidget(const UnivPathfinderApp(demoMode: true));
    expect(find.text('상담 자료'), findsOneWidget);
    expect(find.text('성적 분석'), findsNothing);
    await tester.tap(find.text('상담 자료'));
    await tester.pumpAndSettle();
    expect(find.text('상담 자료 모아보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 키보드 영역에서도 시작 화면이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(home: StartScreen()));
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '로그인'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('추출 모델은 비유한 값·분포의 잘못된 키·잘못된 합계를 거부한다', () {
    GradeDraft draft() =>
        GradeDraft(schoolYear: 2, semester: 1, subjectName: '수학', credit: 3);
    expect((draft()..rawScore = double.nan).isValid, isFalse);
    expect((draft()..credit = double.infinity).isValid, isFalse);
    expect(
      (draft()..subjectAverage = double.negativeInfinity).isValid,
      isFalse,
    );
    expect((draft()..achievementDistribution = {'Z': 100}).isValid, isFalse);
    expect(
      (draft()
            ..achievementDistribution = {
              'A': 10,
              'B': 10,
              'C': 10,
              'D': 10,
              'E': 10,
            })
          .isValid,
      isFalse,
    );
  });
}
