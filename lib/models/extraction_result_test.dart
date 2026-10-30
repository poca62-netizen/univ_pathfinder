import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';

void main() {
  group('GradeDraft validation', () {
    test('valid draft passes', () {
      final d = GradeDraft(schoolYear: 2, semester: 1, subjectName: '수학', credit: 3.0);
      expect(d.isValid, true);
      expect(d.validationErrors(), isEmpty);
    });

    test('missing required fields fails', () {
      final d = GradeDraft(schoolYear: null, semester: 1, subjectName: '', credit: 0);
      expect(d.isValid, false);
      final errors = d.validationErrors();
      expect(errors, contains('학년은 1~3이어야 합니다'));
      expect(errors, contains('과목명은 필수입니다'));
      expect(errors, contains('학점은 0보다 커야 합니다'));
    });

    test('range checks', () {
      final d1 = GradeDraft(schoolYear: 4, semester: 0, subjectName: '영어', credit: 2);
      expect(d1.validationErrors(), contains('학년은 1~3이어야 합니다'));
      expect(d1.validationErrors(), contains('학기는 1~2이어야 합니다'));
    });
  });

  group('ExtractionResult', () {
    test('virtual sample structure', () {
      // This test is offline, just check construction
      final result = ExtractionResult(subjects: [
        GradeDraft(schoolYear: 1, semester: 1, subjectName: '국어', credit: 2),
      ]);
      expect(result.subjects.length, 1);
      expect(result.subjects.first.isValid, true);
    });
  });
}
