import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/favorites_settings_screen.dart';
import 'package:univ_pathfinder/services/account_deletion_service.dart';
import 'package:univ_pathfinder/services/nickname_auth_service.dart';

const uid = '12345678-1234-4234-8234-123456789012';

http.Response json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A client with a signed-in session for [uid]; [onFunction] answers the Edge Function call.
Future<(SupabaseClient, List<String>)> signedInClient(
  http.Response Function(http.Request req) onFunction,
) async {
  final paths = <String>[];
  final token =
      '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path == '/auth/v1/token') {
        return json({
          'access_token': token,
          'token_type': 'bearer',
          'refresh_token': 'r',
          'expires_in': 3600,
          'user': {
            'id': uid,
            'aud': 'authenticated',
            'created_at': '2026-11-04T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {},
          },
        }, 200);
      }
      if (req.url.path == '/auth/v1/logout') return http.Response('', 204);
      return onFunction(req);
    }),
  );
  await client.auth.setSession('r');
  paths.clear();
  return (client, paths);
}

void main() {
  test('계정별 로컬 저장 키 4종을 모두 지운다', () {
    expect(AccountDeletionService.localKeysFor(uid), [
      'university_selection_v1/$uid',
      'consulting_draft_v1/$uid',
      'admission_conditions_v1/$uid',
      'comparison_history_v1/$uid',
    ]);
  });

  test('서버 삭제 확인 후 로컬 기록 삭제·로그아웃', () async {
    final removed = <String>[];
    final (client, paths) = await signedInClient((req) {
      expect(req.url.path, '/functions/v1/delete-account');
      expect(jsonDecode(req.body), {'pin': '0786'});
      expect(req.headers['Authorization'], startsWith('Bearer '));
      return json({'deleted': true}, 200);
    });
    await AccountDeletionService(
      client: client,
      remove: (key) async => removed.add(key),
    ).deleteAccount('0786');
    expect(removed, AccountDeletionService.localKeysFor(uid));
    expect(paths, contains('/auth/v1/logout'));
    expect(client.auth.currentUser, isNull);
    await client.dispose();
  });

  test('로컬 정리 실패는 이미 끝난 서버 삭제를 실패로 바꾸지 않는다', () async {
    final (client, _) = await signedInClient(
      (_) => json({'deleted': true}, 200),
    );
    await AccountDeletionService(
      client: client,
      remove: (_) async => throw Exception('storage'),
    ).deleteAccount('0786');
    expect(client.auth.currentUser, isNull);
    await client.dispose();
  });

  test('서버 오류 코드별 안내, 실패 시 세션·로컬 기록 유지', () async {
    for (final entry in {
      'INVALID_CREDENTIALS': (401, '비밀번호가 올바르지 않습니다.'),
      'LOCKED': (429, '15분 후'),
      'AUTH': (401, '로그인이 만료'),
      'NO_NICKNAME_ACCOUNT': (409, '관리자'),
      'UNAVAILABLE': (503, '자료는 그대로'),
    }.entries) {
      final removed = <String>[];
      final (client, _) = await signedInClient(
        (_) => json({'error': entry.key}, entry.value.$1),
      );
      await expectLater(
        AccountDeletionService(
          client: client,
          remove: (key) async => removed.add(key),
        ).deleteAccount('0786'),
        throwsA(
          isA<NicknameAuthException>().having(
            (e) => e.message,
            entry.key,
            contains(entry.value.$2),
          ),
        ),
      );
      expect(removed, isEmpty);
      expect(client.auth.currentUser?.id, uid);
      await client.dispose();
    }
  });

  test('PIN 형식 오류와 미로그인은 서버 요청 전에 차단', () async {
    var calls = 0;
    final (client, _) = await signedInClient((_) {
      calls++;
      return json({'deleted': true}, 200);
    });
    await expectLater(
      AccountDeletionService(client: client).deleteAccount('12a4'),
      throwsA(isA<NicknameAuthException>()),
    );
    expect(calls, 0);
    await client.dispose();

    final anonymous = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient((_) async => throw StateError('no request')),
    );
    await expectLater(
      AccountDeletionService(client: anonymous).deleteAccount('0786'),
      throwsA(
        isA<NicknameAuthException>().having(
          (e) => e.message,
          'message',
          contains('로그인'),
        ),
      ),
    );
    await anonymous.dispose();
  });

  testWidgets('확인 창: 잘못된 PIN은 창 안에 안내, 취소하면 아무것도 삭제하지 않음', (tester) async {
    final service = _FakeDeletion(
      (pin) async => throw NicknameAuthException(
        AccountDeletionService.messageFor('INVALID_CREDENTIALS'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: FavoritesSettingsScreen(accountDeletion: service)),
    );
    final open = find.byIcon(Icons.person_remove_outlined);
    await tester.scrollUntilVisible(
      open,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('계정을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.text('계정 영구 삭제'));
    await tester.pump();
    expect(find.text('비밀번호는 숫자 4자리로 입력하세요.'), findsOneWidget);
    expect(service.pins, isEmpty);

    await tester.enterText(
      find.byKey(const Key('account-deletion-pin')),
      '1111',
    );
    await tester.tap(find.text('계정 영구 삭제'));
    await tester.pumpAndSettle();
    expect(service.pins, ['1111']);
    expect(find.text('비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(find.text('계정을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('계정을 삭제할까요?'), findsNothing);
    expect(find.text('즐겨찾기 및 설정'), findsOneWidget);
  });

  testWidgets('삭제 성공 시 시작 화면으로 이동하고 완료 안내', (tester) async {
    final service = _FakeDeletion((_) async {});
    await tester.pumpWidget(
      MaterialApp(home: FavoritesSettingsScreen(accountDeletion: service)),
    );
    final open = find.byIcon(Icons.person_remove_outlined);
    await tester.scrollUntilVisible(
      open,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-deletion-pin')),
      '0786',
    );
    await tester.tap(find.text('계정 영구 삭제'));
    await tester.pumpAndSettle();
    expect(service.pins, ['0786']);
    expect(find.text('즐겨찾기 및 설정'), findsNothing);
    expect(find.text('계정과 모든 자료를 삭제했습니다.'), findsOneWidget);
  });
}

class _FakeDeletion extends AccountDeletionService {
  _FakeDeletion(this.onDelete);
  final Future<void> Function(String pin) onDelete;
  final pins = <String>[];

  @override
  Future<void> deleteAccount(String pin) {
    pins.add(pin);
    return onDelete(pin);
  }
}
