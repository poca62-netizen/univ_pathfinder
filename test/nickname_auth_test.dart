import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/nickname_auth_service.dart';
import 'package:univ_pathfinder/screens/start_screen.dart';

Future<void> submit(WidgetTester t) async {
  final button = find.widgetWithText(FilledButton, '로그인');
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

void main() {
  test('닉네임 및 숫자 4자리 검증은 서버 요청 전에 수행', () async {
    for (final pin in ['123', '12345', 'ab12', '１２３４']) {
      expect(NicknameAuthService.validatePin(pin), isNotNull);
    }
    expect(NicknameAuthService.validatePin('0786'), isNull);
    expect(NicknameAuthService.validateNickname('강아지'), isNull);
    expect(NicknameAuthService.validateNickname('a'), isNotNull);
    expect(NicknameAuthService.validateNickname('강 아지'), isNotNull);
    await expectLater(
      NicknameAuthService().authenticate('유효닉네임', 'abcd', false),
      throwsA(isA<NicknameAuthException>()),
    );
  });
  test('서버 인증 후 Supabase 세션 복원 및 동일 사용자 ID 유지', () async {
    const uid = '12345678-1234-4234-8234-123456789012';
    var calls = 0;
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        calls++;
        if (req.url.path.endsWith('nickname-auth')) {
          expect(jsonDecode(req.body), {
            'action': 'login',
            'nickname': 'student',
            'pin': '0786',
          });
          return http.Response(
            jsonEncode({
              'refresh_token': 'test-refresh',
              'nickname': 'student',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(req.url.path, '/auth/v1/token');
        expect(jsonDecode(req.body)['refresh_token'], 'test-refresh');
        return http.Response(
          jsonEncode({
            'access_token': token,
            'token_type': 'bearer',
            'refresh_token': 'rotated-refresh',
            'expires_in': 3600,
            'user': {
              'id': uid,
              'aud': 'authenticated',
              'created_at': '2026-11-04T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final nickname = await NicknameAuthService(client: client)
        .authenticate(' Student ', '0786', false);
    expect(nickname, 'student');
    expect(client.auth.currentUser?.id, uid);
    expect(calls, 2);
    await client.dispose();
  });
  test('중복 닉네임·오류 비밀번호·잠금은 구분된 안내', () async {
    for (final entry in {
      'NICKNAME_TAKEN': 409,
      'INVALID_CREDENTIALS': 401,
      'LOCKED': 429,
    }.entries) {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': entry.key}),
            entry.value,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        NicknameAuthService(client: client)
            .authenticate('student', '0786', true),
        throwsA(
          isA<NicknameAuthException>().having(
            (e) => e.message,
            'message',
            NicknameAuthService.messageFor(entry.key),
          ),
        ),
      );
      await client.dispose();
    }
  });
  testWidgets('로그인 형식 검증·마스킹·숫자 4자리 제한', (t) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: StartScreen(
          authenticate: (n, p, r) async {
            calls++;
            return n;
          },
        ),
      ),
    );
    await submit(t);
    expect(calls, 0);
    final pin = find.byType(TextFormField).at(1);
    await t.ensureVisible(pin);
    await t.enterText(pin, 'ab12cd345');
    await t.pump();
    final widget = t.widget<TextFormField>(pin);
    expect(widget.controller!.text, '1234');
    expect(
      t
          .widget<TextField>(
            find.descendant(of: pin, matching: find.byType(TextField)),
          )
          .obscureText,
      isTrue,
    );
  });
  testWidgets('회원가입 중복 안내 후 기존 계정 로그인으로 전환', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: StartScreen(
          authenticate: (n, p, r) async {
            expect(r, isTrue);
            throw const NicknameAuthException('이미 사용 중인 닉네임입니다.');
          },
        ),
      ),
    );
    final toggle = find.text('처음 사용하나요? 회원가입');
    await t.ensureVisible(toggle);
    await t.tap(toggle);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, '가상닉네임');
    await t.enterText(find.byType(TextFormField).at(1), '0786');
    final signup = find.widgetWithText(FilledButton, '가입하고 시작하기');
    await t.ensureVisible(signup);
    await t.tap(signup);
    await t.pumpAndSettle();
    expect(find.text('이미 사용 중인 닉네임입니다.'), findsOneWidget);
    final login = find.text('이미 계정이 있어요 · 로그인');
    await t.ensureVisible(login);
    await t.tap(login);
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(
      t
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('로그인 성공 후 닉네임을 유지한 홈으로 진입', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: StartScreen(
          authenticate: (n, p, r) async {
            expect(r, isFalse);
            return '가상사용자';
          },
        ),
      ),
    );
    await t.enterText(find.byType(TextFormField).first, '가상사용자');
    await t.enterText(find.byType(TextFormField).at(1), '0786');
    await submit(t);
    expect(find.text('안녕하세요, 가상사용자 님'), findsOneWidget);
    expect(find.byTooltip('로그아웃'), findsOneWidget);
  });
}
