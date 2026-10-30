import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/grade_record.dart';

class GradeService {
  GradeService._();
  static final GradeService instance = GradeService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

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
      if (rawScore != null) 'raw_score': rawScore,
      if (subjectAverage != null) 'subject_average': subjectAverage,
      if (achievement != null && achievement.isNotEmpty) 'achievement': achievement,
      if (gradeRank != null) 'grade_rank': gradeRank,
      if (achievementDistribution != null && achievementDistribution.isNotEmpty)
        'achievement_distribution': achievementDistribution,
    };

    await _client.from('grade_records').insert(payload);
  }

  Future<void> insertGradesBatch(List<Map<String, dynamic>> payloads) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw GradeServiceException('인증되지 않은 사용자입니다. 시작 화면에서 다시 로그인해 주세요.');
    }
    final rows = payloads.map((p) => {...p, 'user_id': userId}).toList();
    if (rows.isEmpty) return;
    await _client.from('grade_records').insert(rows);
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
    return records;
  }
}

class GradeServiceException implements Exception {
  final String message;
  const GradeServiceException(this.message);
  @override
  String toString() => 'GradeServiceException: $message';
}
