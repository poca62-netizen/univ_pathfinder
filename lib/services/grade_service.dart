import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';

class GradeService {
  GradeService._() : _clientOverride = null;
  GradeService.forClient(SupabaseClient client) : _clientOverride = client;
  final SupabaseClient? _clientOverride;
  static final GradeService instance = GradeService._();

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;
  bool get isAuthenticated {
    try {
      return _currentUserId != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> insertGrade({
    required int schoolYear,
    required int semester,
    required String subjectName,
    required double credit,
    double? rawScore,
    double? subjectAverage,
    String? achievement,
    int? gradeRank,
    Map<String, double>? achievementDistribution,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw GradeServiceException('인증되지 않은 사용자입니다. 시작 화면에서 다시 로그인해 주세요.');
    }

    final payload = {
      'user_id': userId,
      'school_year': schoolYear,
      'semester': semester,
      'subject_name': subjectName.trim(),
      'credit': credit,
      'raw_score': ?rawScore,
      'subject_average': ?subjectAverage,
      if (achievement != null && achievement.isNotEmpty)
        'achievement': achievement,
      'grade_rank': ?gradeRank,
      if (achievementDistribution != null && achievementDistribution.isNotEmpty)
        'achievement_distribution': achievementDistribution,
    };

    final rows = _validatedRows([payload], userId);
    await _client.from('grade_records').insert(rows.single);
  }

  Future<void> insertGradesBatch(List<Map<String, dynamic>> payloads) async {
    if (payloads.isEmpty) return;
    final userId = _currentUserId;
    if (userId == null) {
      throw GradeServiceException('인증되지 않은 사용자입니다. 시작 화면에서 다시 로그인해 주세요.');
    }
    final rows = _validatedRows(payloads, userId);
    await _client.from('grade_records').insert(rows);
  }

  /// Review owns stable UUIDs, so a retry of the same confirmed batch cannot
  /// create duplicate rows. Importing the same file in a new review is separate.
  Future<void> upsertImportedGrades(List<Map<String, dynamic>> payloads) async {
    if (payloads.isEmpty) return;
    final userId = _currentUserId;
    if (userId == null) throw const GradeServiceException('로그인 후 성적을 저장해 주세요.');
    final rows = _validatedRows(payloads, userId, requireIds: true);
    await _client.from('grade_records').upsert(rows, onConflict: 'id');
  }

  List<Map<String, dynamic>> _validatedRows(
    List<Map<String, dynamic>> payloads,
    String userId, {
    bool requireIds = false,
  }) {
    int? integer(dynamic v) =>
        v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;
    double? number(dynamic v) => v is num ? v.toDouble() : null;
    return payloads.map((p) {
      final distribution = p['achievement_distribution'];
      if (distribution != null &&
          (distribution is! Map || distribution.values.any((v) => v is! num))) {
        throw const GradeServiceException('성취도 분포는 숫자로 입력해 주세요.');
      }
      for (final key in ['raw_score', 'subject_average', 'credit']) {
        if (p[key] != null && p[key] is! num) {
          throw const GradeServiceException('점수·학점은 숫자여야 합니다.');
        }
      }
      if (p['grade_rank'] != null && integer(p['grade_rank']) == null) {
        throw const GradeServiceException('석차등급은 정수여야 합니다.');
      }
      final draft = GradeDraft(
        schoolYear: integer(p['school_year']),
        semester: integer(p['semester']),
        subjectName: p['subject_name'] is String
            ? (p['subject_name'] as String).trim()
            : null,
        credit: number(p['credit']),
        rawScore: number(p['raw_score']),
        subjectAverage: number(p['subject_average']),
        achievement: p['achievement'] is String
            ? (p['achievement'] as String).trim()
            : null,
        gradeRank: integer(p['grade_rank']),
        achievementDistribution: distribution == null
            ? null
            : {
                for (final entry in (distribution as Map).entries)
                  entry.key.toString(): (entry.value as num).toDouble(),
              },
      );
      final errors = draft.validationErrors();
      if (errors.isNotEmpty) throw GradeServiceException(errors.join(' '));
      final id = p['id'];
      final calendarYear = p['calendar_year'];
      final examKind = p['exam_kind'];
      final confirmedAt = p['source_confirmed_at'];
      if (calendarYear != null &&
          (integer(calendarYear) == null ||
              calendarYear < 2000 ||
              calendarYear > 2100)) {
        throw const GradeServiceException('자료 연도는 2000~2100 사이 정수여야 합니다.');
      }
      if (examKind != null &&
          !const [
            'midterm',
            'finalExam',
            'semesterSummary',
          ].contains(examKind)) {
        throw const GradeServiceException('내신 시험 구분을 확인해 주세요.');
      }
      if (confirmedAt != null &&
          (confirmedAt is! String || DateTime.tryParse(confirmedAt) == null)) {
        throw const GradeServiceException('원본 대조 확인 시각을 확인해 주세요.');
      }
      if ((requireIds || id != null) &&
          (id is! String ||
              !RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
              ).hasMatch(id))) {
        throw const GradeServiceException('저장 요청 ID가 올바르지 않습니다.');
      }
      return <String, dynamic>{
        'id': ?id,
        'calendar_year': ?calendarYear,
        'exam_kind': ?examKind,
        'source_confirmed_at': ?confirmedAt,
        'user_id': userId,
        'school_year': draft.schoolYear,
        'semester': draft.semester,
        'subject_name': draft.subjectName,
        'credit': draft.credit,
        'raw_score': ?draft.rawScore,
        'subject_average': ?draft.subjectAverage,
        if (draft.achievement?.isNotEmpty ?? false)
          'achievement': draft.achievement,
        'grade_rank': ?draft.gradeRank,
        if (draft.achievementDistribution?.isNotEmpty ?? false)
          'achievement_distribution': draft.achievementDistribution,
      };
    }).toList();
  }

  Future<void> updateMyGrade(String id, Map<String, dynamic> payload) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw const GradeServiceException('로그인 후 성적을 수정해 주세요.');
    }
    final row = _validatedRows(
      [
        {...payload, 'id': id},
      ],
      userId,
      requireIds: true,
    ).single;
    // An emptied optional field must clear the stored value, rather than keep it.
    final updates =
        <String, dynamic>{
            ...row,
            // Old confirmation does not describe the edited values.
            'source_confirmed_at': null,
            for (final field in [
              'raw_score',
              'subject_average',
              'achievement',
              'grade_rank',
              'achievement_distribution',
            ])
              field: row[field],
          }
          ..remove('id')
          ..remove('user_id');
    final changed = await _client
        .from('grade_records')
        .update(updates)
        .eq('id', id)
        .eq('user_id', userId)
        .select('id');
    if (changed.isEmpty) {
      throw const GradeServiceException('수정할 성적을 찾지 못했습니다. 새로고침해 주세요.');
    }
  }

  Future<void> deleteMyGrade(String id) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw const GradeServiceException('로그인 후 성적을 삭제해 주세요.');
    }
    final deleted = await _client
        .from('grade_records')
        .delete()
        .eq('id', id)
        .eq('user_id', userId)
        .select('id');
    if (deleted.isEmpty) {
      throw const GradeServiceException('삭제할 성적을 찾지 못했습니다. 새로고침해 주세요.');
    }
  }

  Future<List<GradeRecord>> fetchMyGrades() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw GradeServiceException('인증되지 않은 사용자입니다. 시작 화면에서 다시 로그인해 주세요.');
    }

    final data = await _client
        .from('grade_records')
        .select()
        .eq('user_id', userId)
        .order('school_year', ascending: true)
        .order('semester', ascending: true)
        .order('subject_name', ascending: true);

    final records = (data as List)
        .map((e) => GradeRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return records.where((r) => r.isInGradeScope).toList();
  }
}

class GradeServiceException implements Exception {
  final String message;
  const GradeServiceException(this.message);
  @override
  String toString() => 'GradeServiceException: $message';
}
