// Explicit remote test; uses fictional records only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';

void main() {
  test('모의고사 실제 DB 저장·수정·조회·RLS·삭제', () async {
    final config = jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
    SupabaseClient client() => SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_PUBLISHABLE_KEY'] as String,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final owner = client(), other = client();
    final id = MockExamService.newId();
    final service = MockExamService(client: owner);
    var stage = '가상 사용자 인증';
    try {
      await owner.auth.signInAnonymously();
      await other.auth.signInAnonymously();
      MockExamRecord record({double? percentile = 92, int grade = 2}) =>
          MockExamRecord(
            id: id,
            calendarYear: 2026,
            schoolYear: 2,
            examMonth: 9,
            subject: '가상국어',
            standardScore: 128,
            percentile: percentile,
            gradeRank: grade,
          );
      stage = '저장과 동일 ID 재시도';
      await service.save(record());
      await service.save(record());
      final stored = await service.fetch();
      expect(stored.length, 1);
      expect(stored.single.standardScore, 128);
      expect(stored.single.percentile, 92);
      stage = '타인 조회·수정·삭제 차단';
      final stranger = MockExamService(client: other);
      expect(await stranger.fetch(), isEmpty);
      await expectLater(
        stranger.save(record(grade: 9), editing: true),
        throwsA(isA<StateError>()),
      );
      await expectLater(stranger.delete(id), throwsA(isA<StateError>()));
      expect((await service.fetch()).single.gradeRank, 2);
      stage = '선택 지표 비우기와 9등급 수정';
      await service.save(record(percentile: null, grade: 9), editing: true);
      final edited = (await service.fetch()).single;
      expect(edited.percentile, isNull);
      expect(edited.gradeRank, 9);
      stage = '잘못된 점수 DB 제약';
      await expectLater(
        owner
            .from('mock_exam_records')
            .update({'percentile': 101})
            .eq('id', id),
        throwsA(isA<PostgrestException>()),
      );
      stage = '삭제';
      await service.delete(id);
      expect(await service.fetch(), isEmpty);
    } catch (_) {
      fail('$stage 단계 검증 실패. 비밀값과 원본 예외는 출력하지 않습니다.');
    } finally {
      if (owner.auth.currentUser != null) {
        await owner
            .from('mock_exam_records')
            .delete()
            .eq('id', id)
            .eq('user_id', owner.auth.currentUser!.id);
      }
      await owner.dispose();
      await other.dispose();
    }
  });
}
