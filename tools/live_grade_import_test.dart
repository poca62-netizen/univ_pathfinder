// Explicit opt-in integration test. Never run as part of the normal test/ suite.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';

String newId() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

void main() {
  test('가상 PDF 추출 → 실제 Supabase 저장·재시도·재조회 → 테스트 행 정리', () async {
    SupabaseClient? client;
    String? uid;
    var stage = '설정 읽기';
    var cleaned = false;
    try {
      final config =
          jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
      client = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_PUBLISHABLE_KEY'] as String,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      stage = '검증용 익명 인증';
      await client.auth.signInAnonymously();
      uid = client.auth.currentUser!.id;
      stage = '검증용 프로필';
      await client.from('profiles').insert({'id': uid, 'nickname': '가상OCR검증'});
      stage = '가상 성적표 인식';
      const useNvidia = bool.fromEnvironment('LIVE_NVIDIA');
      final extraction = useNvidia
          ? await recognizeNvidiaImage(
              await File('tools/ocr/test-output/sample.png').readAsBytes(),
              'image/png',
              client: client,
            )
          : File('test/fixtures/pdf_extraction.json').readAsStringSync();
      final preview = GradeImportParser().parse(
        extraction,
        kind: StudentDocumentKind.midterm,
        schoolYear: 2,
        semester: 1,
      );
      final payload = preview.result.subjects
          .map(
            (d) => <String, dynamic>{
              'id': newId(),
              'calendar_year': 2026,
              'exam_kind': 'midterm',
              'source_confirmed_at': '2026-11-03T01:00:00Z',
              'school_year': d.schoolYear,
              'semester': d.semester,
              'subject_name': d.subjectName,
              'credit': d.credit,
              'raw_score': d.rawScore,
              'subject_average': d.subjectAverage,
              'achievement': d.achievement,
              'grade_rank': d.gradeRank,
            },
          )
          .toList();
      expect(payload.length, 2);
      final service = GradeService.forClient(client);
      stage = '두 과목 배치 저장';
      await service.upsertImportedGrades(payload);
      stage = '동일 요청 재시도';
      await service.upsertImportedGrades(payload);
      stage = 'DB 재조회';
      final records = await service.fetchMyGrades();
      expect(records.length, 2);
      expect(
        records.every(
          (r) =>
              r.calendarYear == 2026 &&
              r.examKind == 'midterm' &&
              r.sourceConfirmedAt != null,
        ),
        isTrue,
      );
      expect(records.firstWhere((r) => r.subjectName == '국어').rawScore, 88);
      expect(records.firstWhere((r) => r.subjectName == '수학').rawScore, 92);
      stage = '기존 성적 수정 및 재조회';
      final edited = payload.first;
      await service.updateMyGrade(edited['id'] as String, {
        ...edited,
        'raw_score': null,
        'credit': 4,
      });
      final updated = (await service.fetchMyGrades()).firstWhere(
        (r) => r.id == edited['id'],
      );
      expect(updated.rawScore, isNull);
      expect(updated.credit, 4);
      expect(updated.calendarYear, 2026);
      expect(updated.examKind, 'midterm');
      expect(updated.sourceConfirmedAt, isNull);
      stage = '서비스를 통한 개별 성적 삭제';
      await service.deleteMyGrade(records.first.id);
      final remaining = await service.fetchMyGrades();
      expect(remaining.length, 1);
      expect(remaining.single.id, isNot(records.first.id));
      stage = '테스트 성적 정리';
      await client.from('grade_records').delete().eq('user_id', uid);
      expect(await service.fetchMyGrades(), isEmpty);
      stage = '테스트 프로필 정리';
      await client.from('profiles').delete().eq('id', uid);
      cleaned = true;
    } on AuthException catch (e) {
      fail('$stage 실패: 인증 응답 ${e.statusCode ?? "미확인"}. 비밀값은 출력하지 않습니다.');
    } on PostgrestException catch (e) {
      fail('$stage 실패: DB 코드 ${e.code ?? "미확인"}. 비밀값은 출력하지 않습니다.');
    } catch (_) {
      fail('$stage 단계 검증 실패. 비밀값과 원본 예외는 출력하지 않습니다.');
    } finally {
      if (!cleaned && uid != null && client != null) {
        try {
          await client.from('grade_records').delete().eq('user_id', uid);
          await client.from('profiles').delete().eq('id', uid);
        } catch (_) {
          /* Report cleanup state without logging tokens or request URLs. */
        }
      }
      await client?.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
