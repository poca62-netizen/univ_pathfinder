import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/home_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool demo,
  Size? size,
}) async {
  await tester.binding.setSurfaceSize(size ?? const Size(1280, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: PathfinderTheme.light,
      home: HomeScreen(nickname: '가상 학생', demoMode: demo),
    ),
  );
}

void main() {
  testWidgets('로그인 홈: 진학 컨설팅 리포트를 맨 위에, 나머지는 쓰임새별 묶음', (tester) async {
    await _pump(tester, demo: false);
    expect(find.text('안녕하세요, 가상 학생 님'), findsOneWidget);
    expect(find.text('진학 컨설팅 리포트'), findsOneWidget);
    expect(find.text('리포트 보기'), findsOneWidget);
    for (final t in ['내 자료', '대학 찾기·비교', '참고']) {
      expect(find.text(t), findsOneWidget);
    }
    for (final t in [
      '상담 자료',
      '성적표 등록',
      '성적 분석',
      '상담 요약',
      '생기부 컨설팅',
      '성적·생기부 대학 후보',
      '대학 탐색',
      '대학 비교',
      '출발지·대학 지도',
      '자료 출처',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.byTooltip('로그아웃'), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    // 핵심 기능 카드가 메뉴 묶음보다 위에 있다.
    expect(
      tester.getTopLeft(find.text('진학 컨설팅 리포트')).dy,
      lessThan(tester.getTopLeft(find.text('내 자료')).dy),
    );
  });

  testWidgets('체험 홈: 로그인 기능은 숨기고 대학 탐색으로 안내, 잘못된 "가상 예시" 표시 없음', (
    tester,
  ) async {
    await _pump(tester, demo: true);
    expect(find.textContaining('체험 모드입니다'), findsOneWidget);
    expect(find.text('대학 탐색 시작'), findsOneWidget);
    for (final t in ['진학 컨설팅 리포트', '성적표 등록', '생기부 컨설팅', '성적·생기부 대학 후보']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.textContaining('가상 예시'), findsNothing);
    expect(find.byTooltip('로그아웃'), findsNothing);
  });

  testWidgets('휴대폰 폭에서도 넘침 없이 그려진다', (tester) async {
    await _pump(tester, demo: false, size: const Size(360, 2400));
    expect(tester.takeException(), isNull);
    expect(find.text('리포트 보기'), findsOneWidget);
  });
}
