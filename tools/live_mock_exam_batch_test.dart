// Explicit remote test: fictional records only. Cleans temporary Auth users.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';

void main() {
  test('모의고사 6영역 일괄 저장·재시도·RLS 및 DB 제약 원자성', () async {
    final config = jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
    final url = config['SUPABASE_URL'] as String,
        publicKey = config['SUPABASE_PUBLISHABLE_KEY'] as String;
    final project = Uri.parse(url).host.split('.').first;
    if (!RegExp(r'^[a-z]{20}$').hasMatch(project)) fail('프로젝트 확인 실패');
    SupabaseClient client() => SupabaseClient(
      url,
      publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final owner = client(), other = client();
    var stage = '가상 인증';
    try {
      await owner.auth.signInAnonymously();
      await other.auth.signInAnonymously();
      final service = MockExamService(client: owner),
          stranger = MockExamService(client: other);
      final rows = [
        for (var i = 0; i < 6; i++)
          MockExamRecord(
            id: MockExamService.newId(),
            calendarYear: 2026,
            schoolYear: 2,
            examMonth: 9,
            subject: '가상영역$i',
            rawScore: 81 + i.toDouble(),
            standardScore: i < 2 ? 121 + i.toDouble() : null,
            percentile: i < 2 ? 89 + i.toDouble() : null,
            gradeRank: i % 3 + 1,
          ),
      ];
      stage = '6영역 저장·동일 ID 재시도';
      await service.saveBatch(rows);
      await service.saveBatch(rows);
      final stored = await service.fetch();
      expect(stored.length, 6);
      expect(
        stored.every(
          (r) =>
              r.calendarYear == 2026 && r.schoolYear == 2 && r.examMonth == 9,
        ),
        isTrue,
      );
      expect(
        stored.firstWhere((r) => r.subject == '가상영역2').standardScore,
        isNull,
      );
      stage = '타인 ID 포함 요청은 전체 롤백';
      final ownNew = MockExamRecord(
        id: MockExamService.newId(),
        calendarYear: 2026,
        schoolYear: 2,
        examMonth: 9,
        subject: '가상다른사용자',
        gradeRank: 3,
      );
      await expectLater(
        stranger.saveBatch([ownNew, rows.first]),
        throwsA(isA<PostgrestException>()),
      );
      expect(await stranger.fetch(), isEmpty);
      expect((await service.fetch()).length, 6);
      stage = 'DB 범위 오류 요청은 전체 롤백';
      await expectLater(
        other.from('mock_exam_records').upsert([
          {...ownNew.toMap(), 'user_id': other.auth.currentUser!.id},
          {
            ...ownNew.toMap(),
            'id': MockExamService.newId(),
            'user_id': other.auth.currentUser!.id,
            'percentile': 101,
          },
        ], onConflict: 'id'),
        throwsA(isA<PostgrestException>()),
      );
      expect(await stranger.fetch(), isEmpty);
    } catch (_) {
      fail('$stage 검증 실패. 비밀값과 원본 예외는 출력하지 않습니다.');
    } finally {
      for (final c in [owner, other]) {
        final uid = c.auth.currentUser?.id;
        if (uid != null) {
          await c.from('mock_exam_records').delete().eq('user_id', uid);
        }
      }
      final users = [
        owner.auth.currentUser?.id,
        other.auth.currentUser?.id,
      ].whereType<String>().toList();
      if (users.isNotEmpty) {
        final keys = await Process.run('cmd.exe', [
          '/d',
          '/s',
          '/c',
          'npx supabase projects api-keys --remote=$project --output json',
        ]);
        if (keys.exitCode != 0) fail('임시 Auth 정리용 관리자 접근 실패');
        final key =
            (jsonDecode(keys.stdout as String) as List).firstWhere(
                  (k) => k['name'] == 'service_role',
                )['api_key']
                as String;
        for (final uid in users) {
          final deleted = await http.delete(
            Uri.parse('$url/auth/v1/admin/users/$uid'),
            headers: {'apikey': key, 'Authorization': 'Bearer $key'},
          );
          if (deleted.statusCode != 200) fail('임시 Auth 정리 실패');
        }
      }
      await owner.dispose();
      await other.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
