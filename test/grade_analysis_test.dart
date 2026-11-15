import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';

GradeRecord record(String id, int year, int semester) => GradeRecord(
  id: id,
  userId: 'test-user',
  schoolYear: year,
  semester: semester,
  subjectName: '과목$id',
  credit: 3,
  rawScore: 88,
  subjectAverage: 75,
  achievement: 'A',
  gradeRank: 2,
  achievementDistribution: {'A': 20},
  createdAt: DateTime(2026, 11, 3),
  updatedAt: DateTime(2026, 11, 3),
);

void main() {
  testWidgets('자료 화면은 세션 파일 목록 없이 DB 성적을 복원하고 해당 기간을 연다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CounselingSession.instance.clear();
    var loads = 0;
    Future<List<GradeRecord>> load() async {
      loads++;
      return [record('1', 1, 1), record('2', 2, 2)];
    }

    await tester.pumpWidget(
      MaterialApp(home: CounselingDocumentsScreen(loadGrades: load)),
    );
    await tester.pumpAndSettle();
    expect(find.text('연도 미상 · 2학년 2학기 · 시험 구분 미상'), findsOneWidget);
    expect(CounselingSession.instance.documents, isEmpty);
    await tester.tap(find.text('연도 미상 · 2학년 2학기 · 시험 구분 미상'));
    await tester.pumpAndSettle();
    expect(find.text('2학년 2학기 · 과목2'), findsOneWidget);
    expect(find.text('1학년 1학기 · 과목1'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(loads, 3);
  });

  testWidgets('저장된 성적 수정은 DB 반영 후 목록을 다시 조회한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var stored = record('1', 1, 1);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GradeAnalysisScreen(
          loadGrades: () async {
            loads++;
            return [stored];
          },
          updateGrade: (id, payload) async {
            expect(id, '1');
            expect(payload['subject_name'], '수정한 과목');
            stored = GradeRecord.fromJson({
              ...stored.toMap(),
              ...payload,
              'id': id,
              'created_at': '2026-11-03T01:00:00Z',
              'updated_at': '2026-11-03T02:00:00Z',
            });
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('과목1 성적 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '과목명'), '수정한 과목');
    await tester.tap(find.text('확인 후 저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('1학년 1학기 · 수정한 과목'), findsOneWidget);
  });
  testWidgets('같은 학년 학기도 연도와 시험별로 구분하고 기존 기록은 미상으로 조회한다', (tester) async {
    GradeRecord exam(String id, String kind) => GradeRecord(
      id: id,
      userId: 'test-user',
      schoolYear: 2,
      semester: 1,
      subjectName: '수학$id',
      credit: 3,
      calendarYear: 2026,
      examKind: kind,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GradeAnalysisScreen(
          loadGrades: () async => [
            exam('mid', 'midterm'),
            exam('final', 'finalExam'),
            record('old', 2, 1),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '2026년'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('old')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '중간고사'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mid')), findsOneWidget);
    expect(find.byKey(const ValueKey('final')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '전체 연도'));
    await tester.tap(find.widgetWithText(ChoiceChip, '시험 미상'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('old')), findsOneWidget);
    expect(find.byKey(const ValueKey('mid')), findsNothing);
  });
  testWidgets('DB 조회 결과를 표시하고 학년 학기로 필터링한다', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GradeAnalysisScreen(
          loadGrades: () async {
            loads++;
            return [record('1', 1, 1), record('2', 2, 2)];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DB에 저장된 내 성적 2개'), findsOneWidget);
    expect(find.text('학점 3.0 · 원점수 88.0 · 평균 75.0'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, '2학년'));
    await tester.pumpAndSettle();
    expect(find.text('2학년 2학기 · 과목2'), findsOneWidget);
    expect(find.text('1학년 1학기 · 과목1'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '1학기'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 학년·학기에 저장된 성적이 없습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('새로고침'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('조회 실패 후 재시도로 저장된 성적을 불러온다', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GradeAnalysisScreen(
          loadGrades: () async {
            if (++loads == 1) throw Exception('offline');
            return [record('1', 1, 1)];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
    expect(find.text('1학년 1학기 · 과목1'), findsOneWidget);
  });

  testWidgets('삭제 취소와 실패는 기록을 유지하고 성공 후 재조회에도 삭제가 반영된다', (tester) async {
    final stored = [record('1', 1, 1)];
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GradeAnalysisScreen(
          loadGrades: () async => List.of(stored),
          deleteGrade: (id) async {
            if (++calls == 1) throw Exception('offline');
            stored.removeWhere((r) => r.id == id);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('과목1 성적 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('과목1 성적 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      if (i == 0) expect(find.text('1학년 1학기 · 과목1'), findsOneWidget);
    }
    await tester.tap(find.byTooltip('새로고침'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('DB에 저장된 내 성적 0개'), findsOneWidget);
  });
}
