class SchoolRecordEvidence {
  const SchoolRecordEvidence({
    required this.id,
    required this.calendarYear,
    required this.schoolYear,
    required this.category,
    required this.evidence,
    required this.sourceLocation,
    required this.confirmedAt,
    this.careerInterest,
    this.careerEvidenceEnabled = true,
  });
  final String id, category, evidence, sourceLocation;
  final int calendarYear, schoolYear;
  final String? careerInterest;
  final DateTime confirmedAt;
  final bool careerEvidenceEnabled;
  factory SchoolRecordEvidence.fromJson(Map<String, dynamic> r) =>
      SchoolRecordEvidence(
        id: r['id'] as String,
        calendarYear: r['calendar_year'] as int,
        schoolYear: r['school_year'] as int,
        category: r['category'] as String,
        evidence: r['evidence'] as String,
        sourceLocation: r['source_location'] as String,
        careerInterest: r['career_interest'] as String?,
        careerEvidenceEnabled: r['career_evidence_enabled'] as bool? ?? true,
        confirmedAt: DateTime.parse(r['source_confirmed_at'] as String),
      );
  Map<String, dynamic> toMap() => {
    'id': id,
    'calendar_year': calendarYear,
    'school_year': schoolYear,
    'category': category.trim(),
    'evidence': evidence.trim(),
    'source_location': sourceLocation.trim(),
    'career_interest': careerInterest?.trim().isEmpty == true
        ? null
        : careerInterest?.trim(),
    'source_confirmed_at': confirmedAt.toUtc().toIso8601String(),
    'career_evidence_enabled': careerEvidenceEnabled,
  };
  List<String> validationErrors() => [
    if (calendarYear < 2000 || calendarYear > 2100) '연도는 2000~2100이어야 합니다.',
    if (schoolYear < 1 || schoolYear > 3) '학년은 1~3이어야 합니다.',
    if (category.trim().isEmpty || category.length > 100)
      '활동 항목은 1~100자로 입력하세요.',
    if (evidence.trim().isEmpty || evidence.length > 10000)
      '원문 근거는 1~10000자로 입력하세요.',
    if (sourceLocation.trim().isEmpty || sourceLocation.length > 300)
      '출처 위치는 1~300자로 입력하세요.',
    if ((careerInterest?.length ?? 0) > 300) '관심 진로는 300자 이내로 입력하세요.',
  ];
}
