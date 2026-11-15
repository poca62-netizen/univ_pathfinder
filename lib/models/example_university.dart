class ExampleUniversity {
  final String name;
  final String department;
  final String careerCategory;
  final int tuition;
  final String referenceYear;
  final int? admissionYear;
  final int? quota;
  final String? admissionTrack;
  final String? officialSource;
  final double? latitude;
  final double? longitude;

  const ExampleUniversity({
    required this.name,
    required this.department,
    required this.careerCategory,
    required this.tuition,
    required this.referenceYear,
    this.admissionYear,
    this.quota,
    this.admissionTrack,
    this.officialSource,
    this.latitude,
    this.longitude,
  });
}

final List<ExampleUniversity> exampleUniversities = [
  ExampleUniversity(
    name: '가상대학교 A',
    department: '컴퓨터공학과',
    careerCategory: '공학',
    tuition: 5000000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 B',
    department: '경영학과',
    careerCategory: '인문사회',
    tuition: 4800000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 C',
    department: '심리학과',
    careerCategory: '인문사회',
    tuition: 4500000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 D',
    department: '기계공학과',
    careerCategory: '공학',
    tuition: 5200000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 E',
    department: '수학과',
    careerCategory: '자연과학',
    tuition: 4400000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 F',
    department: '간호학과',
    careerCategory: '보건',
    tuition: 4300000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 G',
    department: '교육학과',
    careerCategory: '교육',
    tuition: 3900000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 H',
    department: '디자인학과',
    careerCategory: '예술체육',
    tuition: 5100000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 I',
    department: '생명과학과',
    careerCategory: '자연과학',
    tuition: 4600000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 J',
    department: '전자공학과',
    careerCategory: '공학',
    tuition: 4900000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 K',
    department: '사회복지학과',
    careerCategory: '인문사회',
    tuition: 3800000,
    referenceYear: '2027',
  ),
  ExampleUniversity(
    name: '가상대학교 L',
    department: '체육학과',
    careerCategory: '예술체육',
    tuition: 4200000,
    referenceYear: '2027',
  ),
];
