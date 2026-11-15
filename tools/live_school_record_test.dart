// Explicit remote test: fictional activity only, no OCR calls.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';

void main() {
  test('생활기록부 실제 DB 저장·수정·RLS·삭제', () async {
    final config = jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
    SupabaseClient client() => SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_PUBLISHABLE_KEY'] as String,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final owner = client(), other = client();
    final service = SchoolRecordService(client: owner);
    final id = SchoolRecordService.newId();
    var stage = '가상 인증';
    SchoolRecordEvidence record({
      String? career = '가상 진로',
      String evidence = '가상 탐구 활동을 수행함.',
    }) => SchoolRecordEvidence(
      id: id,
      calendarYear: 2026,
      schoolYear: 2,
      category: '진로활동',
      evidence: evidence,
      sourceLocation: '3쪽 · 진로활동 두 번째 문단',
      careerInterest: career,
      confirmedAt: DateTime.utc(2026, 11, 4),
    );
    try {
      await owner.auth.signInAnonymously();
      await other.auth.signInAnonymously();
      stage = '저장·동일 ID 재시도';
      await service.save(record());
      await service.save(record());
      final stored = await service.fetch();
      expect(stored.length, 1);
      expect(stored.single.sourceLocation, record().sourceLocation);
      expect(stored.single.confirmedAt, record().confirmedAt);
      stage = '타인 접근 차단';
      final stranger = SchoolRecordService(client: other);
      expect(await stranger.fetch(), isEmpty);
      await expectLater(
        stranger.save(record(), editing: true),
        throwsA(isA<StateError>()),
      );
      await expectLater(stranger.delete(id), throwsA(isA<StateError>()));
      await expectLater(
        stranger.save(record()),
        throwsA(isA<PostgrestException>()),
      );
      stage = '수정·메모 비우기';
      await service.save(
        record(career: null, evidence: '가상 수정 근거'),
        editing: true,
      );
      final edited = (await service.fetch()).single;
      expect(edited.careerInterest, isNull);
      expect(edited.evidence, '가상 수정 근거');
      stage = '출처 DB 제약';
      await expectLater(
        owner
            .from('school_record_evidence')
            .update({'source_location': ' '})
            .eq('id', id),
        throwsA(isA<PostgrestException>()),
      );
      stage = '삭제';
      await service.delete(id);
      expect(await service.fetch(), isEmpty);
    } catch (_) {
      fail('$stage 단계 검증 실패. 비밀값과 원문 예외는 출력하지 않습니다.');
    } finally {
      if (owner.auth.currentUser != null) {
        await owner
            .from('school_record_evidence')
            .delete()
            .eq('id', id)
            .eq('user_id', owner.auth.currentUser!.id);
      }
      await owner.dispose();
      await other.dispose();
    }
  });
}
