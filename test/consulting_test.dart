import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';
import 'package:univ_pathfinder/services/consulting_service.dart';

SchoolRecordEvidence evidence(String id, {bool enabled = true}) =>
    SchoolRecordEvidence(
      id: id,
      calendarYear: 2026,
      schoolYear: 2,
      category: '세특 · 과학탐구실험',
      evidence: '모둠 실험에서 측정 방법을 분석하고 결과를 발표한 뒤 피드백에 따라 수정함.',
      sourceLocation: '5쪽 · 가상 근거 $id',
      confirmedAt: DateTime.utc(2026),
      careerEvidenceEnabled: enabled,
    );
CounselingSummary summary({bool failed = false, bool enabled = true}) =>
    CounselingSummary(
      grades: SummarySection([]),
      mockExams: SummarySection([]),
      activities: SummarySection([
        evidence('visible', enabled: enabled),
        evidence('hidden', enabled: false),
      ], failed: failed),
    );

void main() {
  test('상담 메모는 선택된 활성 근거만 출처와 목표를 포함한다', () {
    final service = ConsultingService();
    final memo = service.memo(summary(), {'visible', 'hidden'}, '생명과학 탐구');
    expect(memo, contains('상담 목표: 생명과학 탐구'));
    expect(memo, contains('근거 ID: visible'));
    expect(memo, isNot(contains('근거 ID: hidden')));
    expect(memo, contains('출처: 5쪽'));
    expect(memo, contains('다음 행동 제안:'));
    expect(service.memo(summary(failed: true), {'visible'}, ''), isEmpty);
    expect(service.memo(summary(), {}, ''), isEmpty);
  });
  test('상담 비활성 근거와 조회 실패는 제안에서 제외, 제외 교과 서술은 유지', () {
    final result = ConsultingService().build(summary());
    expect(result.single.source.id, 'visible');
    expect(result.single.source.sourceLocation, contains('5쪽'));
    expect(result.single.points.length, 5);
    expect(ConsultingService().build(summary(failed: true)), isEmpty);
    expect(ConsultingService().build(summary(enabled: false)), isEmpty);
  });

  testWidgets('원문 출처 확인과 선택 보기, 새로고침 후 비활성 근거 제거', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var enabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultingScreen(
          loadSummary: () async => summary(enabled: enabled),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('진로 연결 탐색'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '생명과학');
    await tester.pump();
    expect(find.text('상담 목표: 생명과학'), findsOneWidget);
    expect(find.text('진로 연결 탐색'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('선택한 근거만 보기 (1개)'), findsOneWidget);
    await tester.tap(find.text('근거 원문·출처 확인'));
    await tester.pumpAndSettle();
    expect(find.text('출처: 5쪽 · 가상 근거 visible'), findsOneWidget);
    enabled = false;
    await tester.tap(find.byTooltip('최신 자료로 새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 근거만 보기 (0개)'), findsOneWidget);
    expect(find.text('진로 연결 탐색'), findsNothing);
    expect(find.textContaining('상담에 활용할 생기부 근거가 없습니다.'), findsOneWidget);
  });
}
