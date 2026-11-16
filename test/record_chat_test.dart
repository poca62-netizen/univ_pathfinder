import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';
import 'package:univ_pathfinder/screens/record_chat_screen.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';

// 가상 학생 근거만 사용한다.
SchoolRecordEvidence evidence(String id, String category) =>
    SchoolRecordEvidence(
      id: id,
      calendarYear: 2025,
      schoolYear: 1,
      category: category,
      evidence: '가상 학생이 하천 수질을 조사하고 보고서를 작성함.',
      sourceLocation: '가상 4쪽',
      confirmedAt: DateTime.utc(2025),
    );

void main() {
  final a = evidence('ev-a', '세특(통합과학)');
  final b = evidence('ev-b', '동아리');

  group('RecordChatService', () {
    test('근거 ID·목표·질문만 보내고 원문은 보내지 않는다', () async {
      Map<String, dynamic>? sent;
      final service = RecordChatService(
        send: (body) async {
          sent = body;
          return {
            'answer': '수질 조사를 직접 설계했습니다 [근거 1].',
            'citations': [
              {'number': 1, 'id': 'ev-a', 'label': '2025년 1학년 · 세특(통합과학)'},
            ],
            'invalidCitations': 0,
          };
        },
      );
      final answer = await service.ask(
        '강점이 뭘까요?',
        const [],
        evidenceIds: ['ev-a', 'ev-b'],
        goal: '  환경공학  ',
      );
      expect(sent!['mode'], 'record');
      expect(sent!['evidenceIds'], ['ev-a', 'ev-b']);
      expect(sent!['goal'], '환경공학');
      expect(sent.toString(), isNot(contains('하천 수질')));
      expect(answer.sources, ['근거 1 2025년 1학년 · 세특(통합과학)']);
      expect(answer.note, isNull);
    });

    test('인용이 없거나 잘못된 인용을 지웠으면 주의 문구를 붙인다', () async {
      final service = RecordChatService(
        send: (_) async => {
          'answer': '꾸준히 노력하세요.',
          'citations': [],
          'invalidCitations': 2,
        },
      );
      final answer = await service.ask('조언', const [], evidenceIds: ['ev-a']);
      expect(answer.note, contains('인용하지 않았습니다'));
      expect(answer.note, contains('인용 2개를 지웠습니다'));
    });

    test('근거 수 제한과 서버 오류 코드', () async {
      var calls = 0;
      final service = RecordChatService(
        send: (_) async {
          calls++;
          return {'error': 'EVIDENCE'};
        },
      );
      await expectLater(
        service.ask('q', const [], evidenceIds: const []),
        throwsA(isA<AppHelpException>()),
      );
      await expectLater(
        service.ask('q', const [], evidenceIds: List.generate(7, (i) => 'e$i')),
        throwsA(isA<AppHelpException>()),
      );
      expect(calls, 0);
      await expectLater(
        service.ask('q', const [], evidenceIds: ['ev-a']),
        throwsA(
          isA<AppHelpException>().having(
            (e) => e.message,
            'message',
            contains('새로고침'),
          ),
        ),
      );
    });
  });

  group('RecordChatScreen', () {
    Future<void> open(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
    }

    testWidgets('동의 전에는 보내지 않고, 동의 후 답과 인용 근거를 보여 준다', (tester) async {
      var calls = 0;
      await open(
        tester,
        RecordChatScreen(
          evidence: [a, b],
          goal: '환경공학',
          service: RecordChatService(
            send: (_) async {
              calls++;
              return {
                'answer': '조사를 설계한 경험이 보입니다 [근거 2].',
                'citations': [
                  {'number': 2, 'id': 'ev-b', 'label': '2025년 1학년 · 동아리'},
                ],
              };
            },
          ),
        ),
      );
      expect(find.text('근거 1 · 2025년 1학년 · 세특(통합과학)'), findsOneWidget);
      expect(find.text('근거 2 · 2025년 1학년 · 동아리'), findsOneWidget);
      expect(find.text('상담 목표: 환경공학'), findsOneWidget);

      await tester.tap(find.text(RecordChatScreen.suggestions.first));
      await tester.pumpAndSettle();
      expect(find.text('외부 AI로 생기부 근거를 보냅니다'), findsOneWidget);
      expect(find.textContaining('근거 2개의 원문'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(calls, 0);

      await tester.tap(find.text(RecordChatScreen.suggestions.first));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 상담 시작'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('조사를 설계한 경험이 보입니다 [근거 2].'), findsOneWidget);
      expect(find.text('인용한 근거: 근거 2 2025년 1학년 · 동아리'), findsOneWidget);

      // 같은 화면에서는 다시 묻지 않는다.
      await tester.enterText(find.byType(TextField), '다음 탐구는?');
      await tester.tap(find.byTooltip('보내기'));
      await tester.pumpAndSettle();
      expect(find.text('외부 AI로 생기부 근거를 보냅니다'), findsNothing);
      expect(calls, 2);
    });

    testWidgets('인용 없는 답에는 주의 문구가 보인다', (tester) async {
      await open(
        tester,
        RecordChatScreen(
          evidence: [a],
          service: RecordChatService(send: (_) async => {'answer': '꾸준히 하세요.'}),
        ),
      );
      await tester.enterText(find.byType(TextField), '조언 주세요');
      await tester.tap(find.byTooltip('보내기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 상담 시작'));
      await tester.pumpAndSettle();
      expect(find.text(RecordChatService.uncitedNote), findsOneWidget);
    });
  });

  testWidgets('생기부 컨설팅: 근거를 고르면 AI 상담을 열고 고른 근거만 넘긴다', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultingScreen(
          loadSummary: () async => CounselingSummary(
            grades: SummarySection([]),
            mockExams: SummarySection([]),
            activities: SummarySection([a, b]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '선택한 근거로 AI 상담 (0개)');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택한 근거로 AI 상담 (1개)'));
    await tester.pumpAndSettle();
    expect(find.text('생기부 AI 상담'), findsOneWidget);
    expect(find.text('상담 근거 1개'), findsOneWidget);
  });
}
