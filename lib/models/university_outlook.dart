enum AdmissionLikelihood {
  weak('약', '합격 가능성을 낮게 보는 근거가 있는 경우'),
  medium('중', '합격 가능성을 중간 정도로 보는 근거가 있는 경우'),
  strong('강', '합격 가능성을 높게 보는 근거가 있는 경우'),
  insufficient('자료 부족', '비교 가능한 입결·환산식·지원조건 확인이 필요합니다.');

  const AdmissionLikelihood(this.label, this.description);
  final String label, description;
}

class AdmissionAssessment {
  const AdmissionAssessment({required this.level, required this.reason});
  final AdmissionLikelihood level;
  final String reason;
  // Readiness counts and keyword matches must never become admission odds.
  static const unavailable = AdmissionAssessment(
    level: AdmissionLikelihood.insufficient,
    reason: '최종 합격 판단에는 2028 학과 모집·대학별 환산식·지원자격·수능 최저·서류평가 확인과 추정 방법 검증이 더 필요합니다. 아래 학업 비교와 구분합니다.',
  );
}

class TuitionRecord {
  const TuitionRecord({
    required this.university,
    required this.officialName,
    required this.campus,
    required this.region,
    required this.year,
    required this.asOf,
    required this.annualWon,
    required this.scope,
  });
  final String university, officialName, campus, region, asOf, scope;
  final int year;
  final double annualWon;
  factory TuitionRecord.fromJson(Map<String, dynamic> r) => TuitionRecord(
    university: r['university'] as String,
    officialName: r['officialName'] as String,
    campus: r['campus'] as String,
    region: r['region'] as String,
    year: r['year'] as int,
    asOf: r['asOf'] as String,
    annualWon: (r['annualWon'] as num).toDouble(),
    scope: r['scope'] as String,
  );
  String get amountLabel => '${(annualWon / 10000).toStringAsFixed(1)}만원';
}

class TuitionCatalog {
  const TuitionCatalog({
    required this.source,
    required this.sourceUrl,
    required this.note,
    required this.rows,
  });
  final String source, sourceUrl, note;
  final List<TuitionRecord> rows;
  factory TuitionCatalog.fromJson(Map<String, dynamic> r) => TuitionCatalog(
    source: r['source'] as String,
    sourceUrl: r['sourceUrl'] as String,
    note: r['note'] as String,
    rows: (r['rows'] as List)
        .map((r) => TuitionRecord.fromJson(Map<String, dynamic>.from(r)))
        .toList(),
  );
  List<TuitionRecord> forUniversity(String name) =>
      rows.where((r) => r.university == name).toList();
  String labelFor(String name) {
    final records = forUniversity(name);
    if (records.isEmpty) return '연간 평균 등록금: 자료 없음';
    final amounts = records.map((r) => r.annualWon).toList()..sort();
    final min = (amounts.first / 10000).toStringAsFixed(1);
    final max = (amounts.last / 10000).toStringAsFixed(1);
    final years = records.map((r) => r.year).toSet().join('/');
    return '연간 평균 등록금: ${min == max ? min : "$min~$max"}만원 ($years년 공시)';
  }
}
