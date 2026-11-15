class MockExamRecord {
  const MockExamRecord({
    required this.id,
    required this.calendarYear,
    required this.schoolYear,
    required this.examMonth,
    required this.subject,
    this.institution,
    this.elective,
    this.rawScore,
    this.standardScore,
    this.percentile,
    this.gradeRank,
  });
  final String id;
  final int calendarYear, schoolYear, examMonth;
  final String subject;
  final String? institution, elective;
  final double? rawScore, standardScore, percentile;
  final int? gradeRank;

  factory MockExamRecord.fromJson(Map<String, dynamic> row) => MockExamRecord(
    id: row['id'] as String,
    calendarYear: row['calendar_year'] as int,
    schoolYear: row['school_year'] as int,
    examMonth: row['exam_month'] as int,
    subject: row['subject'] as String,
    institution: row['institution'] as String?,
    elective: row['elective'] as String?,
    rawScore: (row['raw_score'] as num?)?.toDouble(),
    standardScore: (row['standard_score'] as num?)?.toDouble(),
    percentile: (row['percentile'] as num?)?.toDouble(),
    gradeRank: row['grade_rank'] as int?,
  );
  Map<String, dynamic> toMap() => {
    'id': id,
    'calendar_year': calendarYear,
    'school_year': schoolYear,
    'exam_month': examMonth,
    'subject': subject.trim(),
    'institution': institution?.trim(),
    'elective': elective?.trim(),
    'raw_score': rawScore,
    'standard_score': standardScore,
    'percentile': percentile,
    'grade_rank': gradeRank,
  };
  List<String> validationErrors() {
    final errors = <String>[];
    if (calendarYear < 2000 || calendarYear > 2100) {
      errors.add('연도는 2000~2100이어야 합니다.');
    }
    if (schoolYear < 1 || schoolYear > 3) errors.add('학년은 1~3이어야 합니다.');
    if (examMonth < 1 || examMonth > 12) errors.add('시행 월은 1~12이어야 합니다.');
    if (subject.trim().isEmpty) errors.add('영역은 필수입니다.');
    if (rawScore != null &&
        (!rawScore!.isFinite || rawScore! < 0 || rawScore! > 100)) {
      errors.add('원점수는 0~100이어야 합니다.');
    }
    if (standardScore != null &&
        (!standardScore!.isFinite || standardScore! < 0)) {
      errors.add('표준점수는 0 이상의 유한 숫자여야 합니다.');
    }
    if (percentile != null &&
        (!percentile!.isFinite || percentile! < 0 || percentile! > 100)) {
      errors.add('백분위는 0~100이어야 합니다.');
    }
    if (gradeRank != null && (gradeRank! < 1 || gradeRank! > 9)) {
      errors.add('등급은 1~9이어야 합니다.');
    }
    if (rawScore == null &&
        standardScore == null &&
        percentile == null &&
        gradeRank == null) {
      errors.add('성적 지표를 하나 이상 입력하세요.');
    }
    return errors;
  }
}
