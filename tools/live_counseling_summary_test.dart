// Explicit integration test: fictional records only, no OCR or AI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';

void main() {
  test('실제 DB 세 자료 상담 요약과 수정·삭제 반영 및 사용자 격리', () async {
    final config = jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
    SupabaseClient client() => SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_PUBLISHABLE_KEY'] as String,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final owner = client(), other = client();
    final gradeService = GradeService.forClient(owner),
        mocks = MockExamService(client: owner),
        activities = SchoolRecordService(client: owner);
    CounselingSummaryService summaryService(SupabaseClient c) =>
        CounselingSummaryService(
          loadGrades: GradeService.forClient(c).fetchMyGrades,
          loadMockExams: MockExamService(client: c).fetch,
          loadActivities: SchoolRecordService(client: c).fetch,
        );
    var stage = '가상 인증';
    try {
      await owner.auth.signInAnonymously();
      await other.auth.signInAnonymously();
      await owner.from('profiles').insert({
        'id': owner.auth.currentUser!.id,
        'nickname': '가상상담검증',
      });
      stage = '가상 자료 저장';
      final gradeId = MockExamService.newId();
      final payload = <String, dynamic>{
        'id': gradeId,
        'calendar_year': 2026,
        'exam_kind': 'midterm',
        'source_confirmed_at': '2026-11-04T01:00:00Z',
        'school_year': 2,
        'semester': 1,
        'subject_name': '가상수학',
        'credit': 3,
        'raw_score': 88,
      };
      await gradeService.upsertImportedGrades([
        payload,
        {
          ...payload,
          'id': MockExamService.newId(),
          'subject_name': '미확인가상과목',
          'source_confirmed_at': null,
        },
      ]);
      await mocks.save(
        MockExamRecord(
          id: MockExamService.newId(),
          calendarYear: 2026,
          schoolYear: 2,
          examMonth: 9,
          subject: '가상국어',
          gradeRank: 2,
        ),
      );
      await activities.save(
        SchoolRecordEvidence(
          id: SchoolRecordService.newId(),
          calendarYear: 2026,
          schoolYear: 2,
          category: '가상진로',
          evidence: '가상 탐구 활동',
          sourceLocation: '3쪽 · 가상진로',
          careerInterest: '가상공학',
          confirmedAt: DateTime.utc(2026, 11, 4),
        ),
      );
      stage = '요약 재조회';
      final service = summaryService(owner);
      final summary = await service.fetch();
      expect(summary.grades.failed, isFalse);
      expect(summary.mockExams.failed, isFalse);
      expect(summary.activities.failed, isFalse);
      expect(summary.confirmedGrades.single.subjectName, '가상수학');
      expect(summary.unconfirmedGradeCount, 1);
      expect(summary.mockExams.records.single.gradeRank, 2);
      expect(summary.activitiesFor('가상공학').single.sourceLocation, '3쪽 · 가상진로');
      stage = '다른 사용자 요약 격리';
      final stranger = await summaryService(other).fetch();
      expect(stranger.grades.failed, isFalse);
      expect(stranger.grades.records, isEmpty);
      expect(stranger.mockExams.records, isEmpty);
      expect(stranger.activities.records, isEmpty);
      expect(stranger.careerInterests, isEmpty);
      stage = '성적 수정 후 대조 해제 반영';
      await gradeService.updateMyGrade(gradeId, {...payload, 'raw_score': 89});
      final changed = await service.fetch();
      expect(changed.confirmedGrades, isEmpty);
      expect(changed.unconfirmedGradeCount, 2);
      stage = '활동 삭제 후 진로 메모 제거 반영';
      await activities.delete(summary.activities.records.single.id);
      final deleted = await service.fetch();
      expect(deleted.careerInterests, isEmpty);
      expect(deleted.activities.records, isEmpty);
    } catch (_) {
      fail('$stage 검증 실패. 비밀값과 원본 예외는 출력하지 않습니다.');
    } finally {
      final uid = owner.auth.currentUser?.id;
      if (uid != null) {
        for (final table in [
          'grade_records',
          'mock_exam_records',
          'school_record_evidence',
        ]) {
          await owner.from(table).delete().eq('user_id', uid);
        }
        await owner.from('profiles').delete().eq('id', uid);
      }
      await owner.dispose();
      await other.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
