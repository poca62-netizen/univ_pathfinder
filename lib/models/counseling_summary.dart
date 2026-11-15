import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';

class SummarySection<T> {
  SummarySection(Iterable<T> records, {this.failed = false})
    : records = List.unmodifiable(records);
  final List<T> records;
  final bool failed;
}

class CounselingSummary {
  const CounselingSummary({
    required this.grades,
    required this.mockExams,
    required this.activities,
  });
  final SummarySection<GradeRecord> grades;
  final SummarySection<MockExamRecord> mockExams;
  final SummarySection<SchoolRecordEvidence> activities;
  List<GradeRecord> get confirmedGrades => grades.records
      .where((r) => r.sourceConfirmedAt != null && r.isInGradeScope)
      .toList();
  int get unconfirmedGradeCount =>
      grades.records.where((r) => r.isInGradeScope).length -
      confirmedGrades.length;
  List<String> get careerInterests =>
      (activities.records
          .where((r) => r.careerEvidenceEnabled)
          .map((r) => r.careerInterest?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort());
  List<SchoolRecordEvidence> activitiesFor(String? interest) => activities
      .records
      .where(
        (r) =>
            r.careerEvidenceEnabled &&
            (interest == null || r.careerInterest?.trim() == interest),
      )
      .toList();
  List<String> get missingInformation => [
    if (!grades.failed && confirmedGrades.isEmpty) '원본 대조 확인된 내신이 없습니다.',
    if (unconfirmedGradeCount > 0)
      '내신 $unconfirmedGradeCount개 과목은 원본 대조 확인이 없어 요약에서 제외했습니다.',
    if (confirmedGrades.any(
      (r) => r.calendarYear == null || r.examKind == null,
    ))
      '확인된 내신 중 연도·시험 구분이 없는 기록이 있습니다.',
    if (!mockExams.failed && mockExams.records.isEmpty) '저장된 모의고사가 없습니다.',
    if (!activities.failed && activities.records.isEmpty) '저장된 생활기록부 근거가 없습니다.',
    if (!activities.failed &&
        activities.records.isNotEmpty &&
        careerInterests.isEmpty)
      '관심 진로 메모가 없습니다. 생활기록부 근거에서 작성할 수 있습니다.',
  ];
}
