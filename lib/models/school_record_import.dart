import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';

class SchoolGradeCandidate {
  SchoolGradeCandidate({
    required this.grade,
    required this.source,
    this.calendarYear,
  });
  final GradeDraft grade;
  final String source;
  int? calendarYear;
  bool selected = true;
  final String id = SchoolRecordService.newId();
  Map<String, dynamic> toMap(DateTime confirmed) => {
    'id': id,
    'calendar_year': calendarYear,
    'school_year': grade.schoolYear,
    'semester': grade.semester,
    'subject_name': grade.subjectName,
    'credit': grade.credit,
    'raw_score': grade.rawScore,
    'subject_average': grade.subjectAverage,
    'achievement': grade.achievement,
    'grade_rank': grade.gradeRank,
    'achievement_distribution': grade.achievementDistribution,
    'exam_kind': 'semesterSummary',
    'source_confirmed_at': confirmed.toUtc().toIso8601String(),
    'source_location': source,
  };
}

class SchoolEvidenceCandidate {
  SchoolEvidenceCandidate({
    required this.category,
    required this.text,
    required this.source,
    this.schoolYear,
    this.calendarYear,
  });
  String category, text, source;
  int? schoolYear, calendarYear;
  String? careerInterest;
  bool selected = true;
  final String id = SchoolRecordService.newId();
  SchoolRecordEvidence record(DateTime confirmed) => SchoolRecordEvidence(
    id: id,
    calendarYear: calendarYear ?? 0,
    schoolYear: schoolYear ?? 0,
    category: category,
    evidence: text,
    sourceLocation: source,
    careerInterest: careerInterest,
    confirmedAt: confirmed,
  );
}

class SchoolRecordImport {
  SchoolRecordImport({
    List<SchoolGradeCandidate> grades = const [],
    List<SchoolEvidenceCandidate> evidence = const [],
    this.warnings = const [],
  }) : grades = List.of(grades),
       evidence = List.of(evidence);
  final List<SchoolGradeCandidate> grades;
  final List<SchoolEvidenceCandidate> evidence;
  final List<String> warnings;
}
