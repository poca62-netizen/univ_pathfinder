import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/services/extraction_service.dart';

class ExtractionServiceTest implements ExtractionService {
  @override
  bool get isReady => false;

  @override
  Future<ExtractionResult> extract({required String sourceIdentifier}) async {
    throw ExtractionServiceException('테스트 모드: 실제 추출은 연결되지 않았습니다.');
  }

  static ExtractionResult virtualSample() {
    return ExtractionResult(subjects: [
      GradeDraft(
        schoolYear: 2,
        semester: 1,
        subjectName: '인공지능개론',
        credit: 3.0,
        rawScore: 88.5,
        subjectAverage: 75.0,
        achievement: 'A+',
        gradeRank: 1,
        achievementDistribution: {'A': 25.0, 'B': 35.0, 'C': 25.0, 'D': 10.0, 'E': 5.0},
      ),
      GradeDraft(
        schoolYear: 2,
        semester: 1,
        subjectName: '데이터구조',
        credit: 3.0,
        rawScore: 92.0,
        subjectAverage: 78.0,
        achievement: 'A0',
        gradeRank: 1,
        achievementDistribution: null,
      ),
    ]);
  }
}
