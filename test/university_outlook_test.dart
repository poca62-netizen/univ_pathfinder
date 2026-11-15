import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';

import 'university_recommendation_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = UniversityRecommendationService();
  test('55개 대학 학부 연간 공시 로드, 서울대 값·연도·출처 보존', () async {
    final tuition = await service.loadTuition();
    expect(tuition.rows.map((r) => r.university).toSet().length, 55);
    expect(tuition.rows.length, 64);
    final snu = tuition.forUniversity('서울대').single;
    expect(snu.annualWon, 6091815.7);
    expect(snu.year, 2026);
    expect(snu.asOf, '2026-05-19');
    expect(tuition.sourceUrl, startsWith('https://www.data.go.kr/'));
    expect(tuition.labelFor('서울대'), '연간 평균 등록금: 609.2만원 (2026년 공시)');
    expect(
      tuition.forUniversity('한양대(ERICA)').single.officialName,
      '한양대학교(ERICA)',
    );
    expect(
      tuition.forUniversity('한국외대(글로벌)').single.scope,
      contains('글로벌 캠퍼스 미분리'),
    );
    expect(tuition.labelFor('없는대학'), contains('자료 없음'));
    expect(tuition.labelFor('명지대'), contains('~'));
  });
  test('준비 자료 존재나 키워드 연결을 합격 강으로 바꾸지 않는다', () {
    final candidates = service
        .recommend(
          catalog: fixtures.catalog(),
          summary: fixtures.summary(),
          interest: '약학',
          count: 3,
        )
        .candidates;
    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (u) => u.assessment.level == AdmissionLikelihood.insufficient,
      ),
      isTrue,
    );
    expect(AdmissionLikelihood.values.map((v) => v.label), [
      '약',
      '중',
      '강',
      '자료 부족',
    ]);
  });
  testWidgets('등록금 조회 실패가 대학 후보 생성을 막지 않음', (tester) async {
    final comparison = await tester.runAsync(
      UniversityRecommendationService().loadComparison,
    );
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversityRecommendationScreen(
          loadSummary: () async => fixtures.summary(),
          loadCatalog: () async => fixtures.catalog(),
          loadTuition: () async => throw StateError('offline'),
          loadComparison: () async => comparison!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '관심 학과·분야'), '약학');
    final button = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('지원 검토 대학 3개 / 조건에 맞는 3개'), findsOneWidget);
    expect(find.textContaining('등록금 자료를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('학업 비교: 미지원 학과·전형'), findsWidgets);
  });
}
