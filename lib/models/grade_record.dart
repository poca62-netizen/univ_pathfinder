import 'package:univ_pathfinder/models/grade_scope.dart';

class GradeRecord {
  bool get isInGradeScope => !GradeScope.isExcludedSubject(subjectName);
  final String id;
  final String userId;
  final int schoolYear;
  final int semester;
  final String subjectName;
  final double credit;
  final double? rawScore;
  final double? subjectAverage;
  final String? achievement;
  final int? gradeRank;
  final Map<String, double>? achievementDistribution;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? calendarYear;
  final String? examKind;
  final DateTime? sourceConfirmedAt;
  final String? sourceLocation;

  String get examLabel => switch (examKind) {
    'midterm' => '중간고사',
    'finalExam' => '기말고사',
    'semesterSummary' => '학기 종합',
    _ => '시험 구분 미상',
  };

  const GradeRecord({
    required this.id,
    required this.userId,
    required this.schoolYear,
    required this.semester,
    required this.subjectName,
    required this.credit,
    this.rawScore,
    this.subjectAverage,
    this.achievement,
    this.gradeRank,
    this.achievementDistribution,
    required this.createdAt,
    required this.updatedAt,
    this.calendarYear,
    this.examKind,
    this.sourceConfirmedAt,
    this.sourceLocation,
  });

  factory GradeRecord.fromJson(Map<String, dynamic> json) {
    Map<String, double>? parseDistribution(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        final map = <String, double>{};
        for (final e in value.entries) {
          final k = e.key?.toString();
          final v = e.value;
          if (k != null && k.isNotEmpty) {
            final numVal = _toDoubleSafe(v);
            if (numVal != null) map[k] = numVal;
          }
        }
        return map.isEmpty ? null : map;
      }
      return null;
    }

    return GradeRecord(
      sourceLocation: json['source_location'] as String?,
      calendarYear: json['calendar_year'] as int?,
      examKind: json['exam_kind'] as String?,
      sourceConfirmedAt: DateTime.tryParse(
        json['source_confirmed_at']?.toString() ?? '',
      ),
      id: json['id'] as String,
      userId: json['user_id'] as String,
      schoolYear: json['school_year'] as int,
      semester: json['semester'] as int,
      subjectName: json['subject_name'] as String,
      credit: _toDoubleSafe(json['credit']) ?? 0,
      rawScore: _toDoubleSafe(json['raw_score']),
      subjectAverage: _toDoubleSafe(json['subject_average']),
      achievement: json['achievement'] as String?,
      gradeRank: json['grade_rank'] as int?,
      achievementDistribution: parseDistribution(
        json['achievement_distribution'],
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      if (sourceLocation != null) 'source_location': sourceLocation,
      if (calendarYear != null) 'calendar_year': calendarYear,
      if (examKind != null) 'exam_kind': examKind,
      if (sourceConfirmedAt != null)
        'source_confirmed_at': sourceConfirmedAt!.toUtc().toIso8601String(),
      'user_id': userId,
      'school_year': schoolYear,
      'semester': semester,
      'subject_name': subjectName,
      'credit': credit,
    };
    if (rawScore != null) map['raw_score'] = rawScore;
    if (subjectAverage != null) map['subject_average'] = subjectAverage;
    if (achievement != null && achievement!.isNotEmpty) {
      map['achievement'] = achievement;
    }
    if (gradeRank != null) map['grade_rank'] = gradeRank;
    if (achievementDistribution != null &&
        achievementDistribution!.isNotEmpty) {
      map['achievement_distribution'] = achievementDistribution!;
    }
    return map;
  }

  static double? _toDoubleSafe(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      if (value.isFinite) return value.toDouble();
      return null;
    }
    final parsed = double.tryParse(value.toString());
    if (parsed != null && parsed.isFinite) return parsed;
    return null;
  }
}
