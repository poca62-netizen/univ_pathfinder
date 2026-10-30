class ExampleUniversity {
  final String name;
  final String department;
  final String careerCategory;
  final int tuition;
  final String referenceYear;

  const ExampleUniversity({
    required this.name,
    required this.department,
    required this.careerCategory,
    required this.tuition,
    required this.referenceYear,
  });
}

final List<ExampleUniversity> exampleUniversities = [
  ExampleUniversity(name: '가상대학교 A', department: '컴퓨터공학과', careerCategory: '공학', tuition: 5000000, referenceYear: '2027'),
  ExampleUniversity(name: '가상대학교 B', department: '경영학과', careerCategory: '인문사회', tuition: 4800000, referenceYear: '2027'),
  ExampleUniversity(name: '가상대학교 C', department: '심리학과', careerCategory: '인문사회', tuition: 4500000, referenceYear: '2027'),
  ExampleUniversity(name: '가상대학교 D', department: '기계공학과', careerCategory: '공학', tuition: 5200000, referenceYear: '2027'),
  ExampleUniversity(name: '가상대학교 E', department: '수학과', careerCategory: '자연과학', tuition: 4400000, referenceYear: '2027'),
];
