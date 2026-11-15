import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';
import 'package:univ_pathfinder/screens/counseling_summary_screen.dart';

GradeRecord grade(String id, {bool confirmed = true}) => GradeRecord(
  id: id,
  userId: 'fictional',
  schoolYear: 2,
  semester: 1,
  subjectName: '수학$id',
  credit: 3,
  rawScore: 88,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  calendarYear: 2026,
  examKind: 'midterm',
  sourceConfirmedAt: confirmed ? DateTime.utc(2026, 11, 4) : null,
);
SchoolRecordEvidence activity(String id, String career) => SchoolRecordEvidence(
  id: id,
  calendarYear: 2026,
  schoolYear: 2,
  category: '진로활동',
  evidence: '가상 활동 $id',
  sourceLocation: '3쪽 $id문단',
  careerInterest: career,
  confirmedAt: DateTime.utc(2026, 11, 4),
);
CounselingSummary summary() => CounselingSummary(
  grades: SummarySection([grade('확인'), grade('미확인', confirmed: false)]),
  mockExams: SummarySection([
    const MockExamRecord(
      id: 'mock',
      calendarYear: 2026,
      schoolYear: 2,
      examMonth: 9,
      subject: '국어',
      gradeRank: 2,
    ),
  ]),
  activities: SummarySection([activity('공학', ' 공학 '), activity('인문', '인문')]),
);
void large(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('미확인 내신 제외 및 사용자가 적은 진로 메모만 정확히 연결', () {
    final s = summary();
    expect(s.confirmedGrades.map((r) => r.id), ['확인']);
    expect(s.unconfirmedGradeCount, 1);
    expect(s.activitiesFor('공학').single.id, '공학');
    expect(s.activitiesFor('공'), isEmpty);
    expect(s.careerInterests, ['공학', '인문']);
    expect(s.activitiesFor(null).length, 2);
  });
  test('자료별 병렬 조회와 부분 실패는 빈 자료와 구분', () async {
    final barrier = Completer<void>();
    var started = 0;
    Future<void> wait() async {
      started++;
      if (started == 3) barrier.complete();
      await barrier.future;
    }

    final service = CounselingSummaryService(
      loadGrades: () async {
        await wait();
        throw StateError('offline');
      },
      loadMockExams: () async {
        await wait();
        return [];
      },
      loadActivities: () async {
        await wait();
        return [activity('1', '공학')];
      },
    );
    final result = await service.fetch();
    expect(result.grades.failed, isTrue);
    expect(result.mockExams.failed, isFalse);
    expect(result.activities.records.length, 1);
    expect(result.missingInformation, contains('저장된 모의고사가 없습니다.'));
    expect(result.missingInformation, isNot(contains('원본 대조 확인된 내신이 없습니다.')));
  });
  testWidgets('요약은 원문 출처와 분리된 성적을 표시하고 관심 분야 필터', (tester) async {
    large(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: CounselingSummaryScreen(loadSummary: () async => summary()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('수학확인'), findsOneWidget);
    expect(find.textContaining('수학미확인'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, '공학'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '공학'));
    await tester.pumpAndSettle();
    expect(find.text('가상 활동 공학'), findsOneWidget);
    expect(find.text('가상 활동 인문'), findsNothing);
    expect(find.text('출처: 3쪽 공학문단'), findsOneWidget);
  });
  testWidgets('부분 조회 실패는 누락으로 단정하지 않고 재시도', (tester) async {
    large(tester);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CounselingSummaryScreen(
          loadSummary: () async {
            if (calls++ == 0) {
              return CounselingSummary(
                grades: SummarySection([], failed: true),
                mockExams: SummarySection([]),
                activities: SummarySection([]),
              );
            }
            return summary();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('내신을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('• 원본 대조 확인된 내신이 없습니다.'), findsNothing);
    await tester.tap(find.text('실패한 자료 다시 조회'));
    await tester.pumpAndSettle();
    expect(find.textContaining('수학확인'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('재조회 후 삭제된 진로 메모 선택 초기화', (tester) async {
    large(tester);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CounselingSummaryScreen(
          loadSummary: () async {
            final original = summary();
            return calls++ == 0
                ? original
                : CounselingSummary(
                    grades: original.grades,
                    mockExams: original.mockExams,
                    activities: SummarySection([activity('인문', '인문')]),
                  );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, '공학'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '공학'));
    await tester.pump();
    await tester.tap(find.byTooltip('상담 요약 새로고침'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, '전체 활동'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '전체 활동'))
          .selected,
      isTrue,
    );
    expect(find.text('가상 활동 인문'), findsOneWidget);
  });
  testWidgets('비로그인 체험에서 서버 조회 없이 안내', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CounselingSummaryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('로그인하면 저장한 자료로 상담 요약을 볼 수 있습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
