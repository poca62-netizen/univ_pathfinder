class ExampleGrade {
  final String schoolYear;
  final String semester;
  final String subjectName;
  final int credit;
  final double? rawScore;
  final double? subjectAverage;
  final String? achievement;
  final int? gradeRank;
  final double? achievementDistributionRatio;

  const ExampleGrade({
    required this.schoolYear,
    required this.semester,
    required this.subjectName,
    required this.credit,
    this.rawScore,
    this.subjectAverage,
    this.achievement,
    this.gradeRank,
    this.achievementDistributionRatio,
  });
}

final List<ExampleGrade> exampleGrades = [
  ExampleGrade(schoolYear: '2027', semester: '1학기', subjectName: '국어', credit: 4, rawScore: 88, subjectAverage: 78, achievement: 'A', gradeRank: 2, achievementDistributionRatio: 0.15),
  ExampleGrade(schoolYear: '2027', semester: '1학기', subjectName: '수학', credit: 4, rawScore: 92, subjectAverage: 76, achievement: 'A+', gradeRank: 1, achievementDistributionRatio: 0.12),
  ExampleGrade(schoolYear: '2027', semester: '1학기', subjectName: '영어', credit: 4, rawScore: 85, subjectAverage: 80, achievement: 'B+', gradeRank: 3, achievementDistributionRatio: 0.22),
  ExampleGrade(schoolYear: '2027', semester: '2학기', subjectName: '국어', credit: 4, rawScore: 90, subjectAverage: 79, achievement: 'A', gradeRank: 2, achievementDistributionRatio: 0.18),
  ExampleGrade(schoolYear: '2027', semester: '2학기', subjectName: '수학', credit: 4, rawScore: null, subjectAverage: 77, achievement: 'A', gradeRank: 2, achievementDistributionRatio: null),
];
