class ExtractionResult {
  final List<GradeDraft> subjects;
  const ExtractionResult({required this.subjects});
}

class GradeDraft {
  int? schoolYear;
  int? semester;
  String? subjectName;
  double? credit;
  double? rawScore;
  double? subjectAverage;
  String? achievement;
  int? gradeRank;
  Map<String, double>? achievementDistribution;

  GradeDraft({
    this.schoolYear,
    this.semester,
    this.subjectName,
    this.credit,
    this.rawScore,
    this.subjectAverage,
    this.achievement,
    this.gradeRank,
    this.achievementDistribution,
  });

  bool get isValid => schoolYear != null && semester != null && subjectName != null && credit != null && credit! > 0;
  List<String> validationErrors() {
    final errors = <String>[];
    if (schoolYear == null || schoolYear! < 1 || schoolYear! > 3) errors.add('학년은 1~3이어야 합니다.');
    if (semester == null || semester! < 1 || semester! > 2) errors.add('학기는 1~2이어야 합니다.');
    if (subjectName == null || subjectName!.trim().isEmpty) errors.add('과목명은 필수입니다.');
    if (credit == null || credit! <= 0) errors.add('학점은 0보다 커야 합니다.');
    if (rawScore != null && (rawScore! < 0 || rawScore! > 100)) errors.add('원점수는 0~100이어야 합니다.');
    if (subjectAverage != null && (subjectAverage! < 0 || subjectAverage! > 100)) errors.add('과목평균은 0~100이어야 합니다.');
    if (gradeRank != null && (gradeRank! < 1 || gradeRank! > 5)) errors.add('석차등급은 1~5이어야 합니다.');
    if (achievementDistribution != null) {
      for (final entry in achievementDistribution!.entries) {
        final v = entry.value;
        if (!v.isFinite || v < 0 || v > 100) {
          errors.add('${entry.key} 분포는 0~100이어야 합니다.');
        }
      }
      if (achievementDistribution!.length == 5) {
        final sum = achievementDistribution!.values.fold<double>(0, (a, b) => a + b);
        if (sum < 99.5 || sum > 100.5) errors.add('A~E 분포 합은 99.5~100.5%여야 합니다.');
      }
    }
    return errors;
  }
}
