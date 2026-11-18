import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/widgets/prediction_style.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';
import 'package:univ_pathfinder/widgets/ui_kit.dart';

void main() {
  testWidgets('ActionCard: 화면 낭독기에 제목은 버튼 이름, 설명은 따로', (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: PathfinderTheme.light,
        home: Scaffold(
          body: ActionCard(
            title: '대학 탐색',
            subtitle: '수도권 대학 검색',
            icon: Icons.search,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(ActionCard));
    expect(node.label, '대학 탐색');
    expect(node.hint, '수도권 대학 검색');
    expect(node.flagsCollection.isButton, isTrue);
    await tester.tap(find.text('대학 탐색'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('상담 자료: 올리기 → 저장한 자료 → 다음 단계 순서, 개발 용어 없음', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: PathfinderTheme.light,
        home: CounselingDocumentsScreen(
          loadGrades: () async => [],
          loadMockExams: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t).last).dy;
    expect(y('자료 올리기'), lessThan(y('저장한 자료')));
    expect(y('저장한 자료'), lessThan(y('다음 단계')));
    for (final t in ['내신 성적표', '모의고사', '생활기록부']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('아직 저장한 내신이 없어요'), findsOneWidget);
    expect(find.textContaining('DB'), findsNothing);
    expect(find.textContaining('NVIDIA'), findsNothing);
  });

  testWidgets("예측 분포 막대: 개수 비율대로 색 칸이 보이고 범례에 글자가 함께 있다", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              LevelDistribution({
                PredictionLevel.safe: 6,
                PredictionLevel.fit: 3,
                PredictionLevel.hard: 0,
              }),
            ],
          ),
        ),
      ),
    );
    final bars = find.descendant(
      of: find.byType(LevelDistribution),
      matching: find.byType(ColoredBox),
    );
    expect(bars, findsNWidgets(2)); // 0개인 단계는 칸이 없다
    final a = tester.getSize(bars.at(0));
    final b = tester.getSize(bars.at(1));
    expect(a.height, 8);
    expect(a.width / b.width, closeTo(2, .05));
    expect(find.text("안정 6"), findsOneWidget);
    expect(find.text("적정 3"), findsOneWidget);
    expect(find.text("어려움 0"), findsNothing);
    expect(slotColor("상향"), levelColor(PredictionLevel.reach));
  });
}
