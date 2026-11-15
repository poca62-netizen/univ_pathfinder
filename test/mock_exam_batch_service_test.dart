import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';

void main() {
  test('일괄 저장 한 요청·사용자 ID 제한·실패 재시도·빈 지표 및 전체 사전 검증', () async {
    const uid = '12345678-1234-4234-8234-123456789012';
    var writes = 0;
    var partial = false;
    final stored = <String, Map<String, dynamic>>{};
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/signup')) {
          return http.Response(
            jsonEncode({
              'access_token': token,
              'token_type': 'bearer',
              'refresh_token': 'test',
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
            request: req,
          );
        }
        expect(req.url.path, '/rest/v1/mock_exam_records');
        expect(req.method, 'POST');
        expect(req.url.queryParameters['on_conflict'], 'id');
        final rows = jsonDecode(req.body) as List;
        expect(rows.length, 2);
        for (final r in rows) {
          expect(r['user_id'], uid);
          stored[r['id'] as String] = Map<String, dynamic>.from(r as Map);
        }
        writes++;
        if (writes == 1) {
          return http.Response(
            jsonEncode({'message': 'uncertain response', 'code': 'XX000'}),
            500,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }
        return http.Response(
          jsonEncode([
            for (final r in (partial ? rows.take(1) : rows)) {'id': r['id']},
          ]),
          201,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      }),
    );
    await client.auth.signInAnonymously();
    final service = MockExamService(client: client);
    final records = [
      MockExamRecord(
        id: MockExamService.newId(),
        calendarYear: 2026,
        schoolYear: 2,
        examMonth: 9,
        subject: '가상국어',
        rawScore: 82,
        gradeRank: 2,
      ),
      MockExamRecord(
        id: MockExamService.newId(),
        calendarYear: 2026,
        schoolYear: 2,
        examMonth: 9,
        subject: '가상영어',
        rawScore: 91,
        gradeRank: 1,
      ),
    ];
    await expectLater(
      service.saveBatch(records),
      throwsA(isA<PostgrestException>()),
    );
    await service.saveBatch(records);
    expect(stored.length, 2);
    expect(stored[records.last.id]!['standard_score'], isNull);
    expect(stored[records.last.id]!['percentile'], isNull);
    final invalid = MockExamRecord(
      id: MockExamService.newId(),
      calendarYear: 2026,
      schoolYear: 2,
      examMonth: 9,
      subject: '오류',
      gradeRank: 10,
    );
    await expectLater(
      service.saveBatch([records.first, invalid]),
      throwsArgumentError,
    );
    expect(writes, 2);
    await expectLater(
      service.saveBatch([records.first, records.first]),
      throwsArgumentError,
    );
    expect(writes, 2);
    partial = true;
    await expectLater(service.saveBatch(records), throwsStateError);
    await client.dispose();
  });
}
