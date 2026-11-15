class MockExamDraft {
  const MockExamDraft({
    required this.subject,
    this.rawScore,
    this.standardScore,
    this.percentile,
    this.gradeRank,
    this.recoveredGrade = false,
  });
  final String subject;
  final double? rawScore, standardScore, percentile;
  final int? gradeRank;
  final bool recoveredGrade;
}

class MockExamImportResult {
  const MockExamImportResult({
    this.rows = const [],
    this.warnings = const [],
    this.calendarYear,
    this.schoolYear,
    this.examMonth,
  });
  final List<MockExamDraft> rows;
  final List<String> warnings;
  final int? calendarYear, schoolYear, examMonth;
}
