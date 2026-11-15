import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/grade_service.dart';

void main() {
  const uid = '12345678-1234-4234-8234-123456789012';
  const rowId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  late SupabaseClient client;
  late GradeService service;
  late Map<String, Map<String, dynamic>> rows;
  late int writes;
  Map<String, dynamic> payload() => {
    'id': rowId,
    'user_id': 'spoofed',
    'school_year': 2,
    'semester': 1,
    'subject_name': '국어',
    'credit': 3,
    'raw_score': 88,
    'subject_average': 75.5,
    'grade_rank': 2,
    'source_text': 'must not leave device',
  };
  setUp(() async {
    rows = {};
    writes = 0;
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/signup')) {
        return http.Response(
          jsonEncode({
            'access_token': token,
            'token_type': 'bearer',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
            'user': {
              'id': uid,
              'aud': 'authenticated',
              'created_at': '2026-11-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'PATCH') {
        expect(request.url.queryParameters['user_id'], 'eq.$uid');
        final id = request.url.queryParameters['id']!.substring(3);
        final row = rows[id];
        final allowed = row != null && row['user_id'] == uid;
        if (allowed) {
          row.addAll(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
        }
        return http.Response(
          jsonEncode(
            allowed
                ? [
                    {'id': id},
                  ]
                : [],
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') {
        expect(request.url.queryParameters['user_id'], 'eq.$uid');
        final id = request.url.queryParameters['id']!.substring(3);
        final row = rows[id];
        final deleted = row != null && row['user_id'] == uid;
        if (deleted) rows.remove(id);
        return http.Response(
          jsonEncode(
            deleted
                ? [
                    {'id': id},
                  ]
                : [],
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.method == 'POST') {
        writes++;
        expect(request.url.queryParameters['on_conflict'], 'id');
        expect(
          request.headers['Prefer'],
          contains('resolution=merge-duplicates'),
        );
        for (final row in jsonDecode(request.body) as List) {
          rows[row['id'] as String] = Map<String, dynamic>.from(row as Map);
        }
        return http.Response(
          '',
          201,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(
          rows.values
              .map(
                (r) => {
                  ...r,
                  'created_at': '2026-11-01T00:00:00Z',
                  'updated_at': '2026-11-01T00:00:00Z',
                },
              )
              .toList(),
        ),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: mock,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInAnonymously();
    service = GradeService.forClient(client);
  });
  tearDown(() async => client.dispose());

  test('수정은 선택 필드를 비울 수 있고 시험 정보는 유지하며 타인 행은 거부한다', () async {
    await service.upsertImportedGrades([
      {
        ...payload(),
        'calendar_year': 2026,
        'exam_kind': 'midterm',
        'source_confirmed_at': '2026-11-03T01:00:00Z',
      },
    ]);
    await service.updateMyGrade(rowId, {
      ...payload(),
      'raw_score': null,
      'credit': 4,
    });
    final stored = (await service.fetchMyGrades()).single;
    expect(stored.rawScore, isNull);
    expect(stored.credit, 4);
    expect(stored.examKind, 'midterm');
    expect(stored.sourceConfirmedAt, isNull);
    rows[rowId]!['user_id'] = 'another-user';
    await expectLater(
      service.updateMyGrade(rowId, payload()),
      throwsA(isA<GradeServiceException>()),
    );
    expect(rows[rowId]!['credit'], 4);
  });

  test('연도 시험 구분 확인 시각은 저장 후 재조회에도 유지된다', () async {
    await service.upsertImportedGrades([
      {
        ...payload(),
        'calendar_year': 2026,
        'exam_kind': 'midterm',
        'source_confirmed_at': '2026-11-03T01:00:00Z',
      },
    ]);
    final stored = (await service.fetchMyGrades()).single;
    expect(stored.calendarYear, 2026);
    expect(stored.examLabel, '중간고사');
    expect(stored.sourceConfirmedAt, DateTime.utc(2026, 11, 3, 1));
    for (final invalid in [
      {...payload(), 'calendar_year': 1999},
      {...payload(), 'exam_kind': 'mockExam'},
      {...payload(), 'source_confirmed_at': 'invalid'},
    ]) {
      await expectLater(
        service.upsertImportedGrades([invalid]),
        throwsA(isA<GradeServiceException>()),
      );
    }
    expect(writes, 1);
  });

  test('내 성적 삭제 후 재조회에서 사라지고 타인 행은 삭제하지 않는다', () async {
    await service.upsertImportedGrades([payload()]);
    await service.deleteMyGrade(rowId);
    expect(await service.fetchMyGrades(), isEmpty);
    rows[rowId] = {...payload(), 'user_id': 'another-user'};
    await expectLater(
      service.deleteMyGrade(rowId),
      throwsA(isA<GradeServiceException>()),
    );
    expect(rows[rowId], isNotNull);
  });

  test('사용자 ID를 강제 주입하고 허용된 성적 값만 한 요청으로 저장·조회', () async {
    await service.upsertImportedGrades([payload()]);
    expect(writes, 1);
    expect(rows.length, 1);
    expect(rows[rowId]!['user_id'], uid);
    expect(rows[rowId]!.containsKey('source_text'), isFalse);
    final stored = await service.fetchMyGrades();
    expect(stored.single.subjectName, '국어');
    expect(stored.single.rawScore, 88);
  });
  test('같은 요청 ID로 재시도하면 기존 행을 갱신하고 중복 행이 생기지 않는다', () async {
    await service.upsertImportedGrades([payload()]);
    await service.upsertImportedGrades([
      {...payload(), 'raw_score': 89},
    ]);
    expect(rows.length, 1);
    expect(rows[rowId]!['raw_score'], 89);
  });
  test('누락 학점·비유한 점수·잘못된 등급은 DB 요청 전에 차단', () async {
    for (final row in [
      {...payload(), 'credit': null},
      {...payload(), 'raw_score': double.nan},
      {...payload(), 'grade_rank': 7},
    ]) {
      await expectLater(
        service.upsertImportedGrades([row]),
        throwsA(isA<GradeServiceException>()),
      );
    }
    expect(writes, 0);
  });
  test('제외 과목은 단건·배치·수정 모두 DB 요청 전 차단', () async {
    final excluded = {...payload(), 'subject_name': '과학탐구실험2'};
    await expectLater(
      service.insertGradesBatch([excluded]),
      throwsA(isA<GradeServiceException>()),
    );
    await expectLater(
      service.upsertImportedGrades([excluded]),
      throwsA(isA<GradeServiceException>()),
    );
    await expectLater(
      service.updateMyGrade(rowId, excluded),
      throwsA(isA<GradeServiceException>()),
    );
    await expectLater(
      service.insertGrade(
        schoolYear: 1,
        semester: 1,
        subjectName: '체육2',
        credit: 2,
      ),
      throwsA(isA<GradeServiceException>()),
    );
    expect(writes, 0);
  });
}
