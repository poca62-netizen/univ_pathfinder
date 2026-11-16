import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/app_help_screen.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';

void main() {
  group('AppHelpService', () {
    test('질문과 최근 대화만 보내고 답과 근거 문서를 돌려준다', () async {
      Map<String, dynamic>? sent;
      final service = AppHelpService(
        send: (body) async {
          sent = body;
          return {
            'answer': ' 회원가입부터 하세요. ',
            'sources': [
              {'source': '앱 사용 안내', 'title': '앱 사용 안내 > 처음 시작하는 순서'},
            ],
          };
        },
      );
      final history = [
        for (var i = 0; i < 6; i++)
          AppHelpMessage(role: i.isEven ? 'user' : 'assistant', text: '메시지 $i'),
      ];
      final answer = await service.ask('  뭐부터 하나요?  ', history);

      expect(sent!['question'], '뭐부터 하나요?');
      final sentHistory = sent!['history'] as List;
      expect(sentHistory, hasLength(AppHelpService.historyLimit));
      expect(sentHistory.first, {'role': 'user', 'content': '메시지 2'});
      expect(answer.isUser, isFalse);
      expect(answer.text, '회원가입부터 하세요.');
      expect(answer.sources, ['앱 사용 안내 > 앱 사용 안내 > 처음 시작하는 순서']);
    });

    test('빈 질문과 너무 긴 질문은 보내지 않는다', () async {
      var calls = 0;
      final service = AppHelpService(
        send: (_) async {
          calls++;
          return {'answer': 'x'};
        },
      );
      await expectLater(
        service.ask('   ', const []),
        throwsA(isA<AppHelpException>()),
      );
      await expectLater(
        service.ask('가' * (AppHelpService.maxQuestionLength + 1), const []),
        throwsA(isA<AppHelpException>()),
      );
      expect(calls, 0);
    });

    test('서버 오류 코드를 안내 문구로 바꾼다', () async {
      final service = AppHelpService(
        send: (_) async => {'error': 'RATE_LIMIT'},
      );
      await expectLater(
        service.ask('질문', const []),
        throwsA(
          isA<AppHelpException>().having(
            (e) => e.message,
            'message',
            contains('1분'),
          ),
        ),
      );
      final broken = AppHelpService(
        send: (_) async => throw StateError('network'),
      );
      await expectLater(
        broken.ask('질문', const []),
        throwsA(
          isA<AppHelpException>().having(
            (e) => e.message,
            'message',
            contains('다시 시도'),
          ),
        ),
      );
      expect(
        AppHelpService.messageFor('NOT_CONFIGURED'),
        contains('준비되지 않았습니다'),
      );
      expect(AppHelpService.messageFor('AUTH'), contains('로그인'));
    });
  });

  group('AppHelpScreen', () {
    Future<void> open(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
    }

    testWidgets('추천 질문을 누르면 답과 근거 문서를 보여 준다', (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      await open(
        tester,
        AppHelpScreen(service: AppHelpService(send: (_) => reply.future)),
      );
      expect(find.textContaining('개인정보는 적지 마세요'), findsOneWidget);
      expect(find.textContaining('Groq'), findsOneWidget);

      await tester.tap(find.text(AppHelpScreen.suggestions.first));
      await tester.pump();
      expect(
        find.text(AppHelpScreen.suggestions.first),
        findsOneWidget,
      ); // 내 질문 말풍선
      expect(find.text('답변을 찾는 중…'), findsOneWidget);

      reply.complete({
        'answer': '닉네임으로 회원가입한 뒤 상담 자료에서 성적을 올리세요.',
        'sources': [
          {'source': '앱 사용 안내', 'title': '처음 시작하는 순서'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('닉네임으로 회원가입한 뒤 상담 자료에서 성적을 올리세요.'), findsOneWidget);
      expect(find.text('근거 문서: 앱 사용 안내 > 처음 시작하는 순서'), findsOneWidget);
      expect(find.text('답변을 찾는 중…'), findsNothing);
    });

    testWidgets('실패하면 질문을 입력창에 되돌리고 오류를 보여 준다', (tester) async {
      await open(
        tester,
        AppHelpScreen(
          service: AppHelpService(
            send: (_) async => {'error': 'NOT_CONFIGURED'},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '계정 삭제는 어디서 하나요?');
      await tester.tap(find.byTooltip('보내기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('준비되지 않았습니다'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '계정 삭제는 어디서 하나요?');
      expect(find.text('이런 질문을 해 보세요'), findsOneWidget); // 대화 기록에 남기지 않음
    });

    testWidgets('체험 모드에서는 질문을 보내지 않는다', (tester) async {
      var calls = 0;
      await open(
        tester,
        AppHelpScreen(
          demoMode: true,
          service: AppHelpService(
            send: (_) async {
              calls++;
              return {'answer': 'x'};
            },
          ),
        ),
      );
      expect(find.textContaining('체험 모드에서는 AI 도움말을 쓸 수 없습니다'), findsOneWidget);
      await tester.tap(find.text(AppHelpScreen.suggestions.first));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(calls, 0);
    });
  });
}
