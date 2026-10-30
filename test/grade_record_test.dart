import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/grade_record.dart';

void main() {
  group('GradeRecord', () {
    test('fromJson parses valid data', () {
      final json = {
        'id': '111',
        'user_id': 'u1',
        'school_year': 2,
        'semester': 1,
        'subject_name': '수학',
        'credit': 3.5,
        'raw_score': 88.0,
        'subject_average': 80.0,
        'achievement': 'A',
        'grade_rank': 2,
        'achievement_distribution': {'A': 40, 'B': 30, 'C': 20, 'D': 10, 'E': 0},
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };
      final rec = GradeRecord.fromJson(json);
      expect(rec.id, '111');
      expect(rec.schoolYear, 2);
      expect(rec.semester, 1);
      expect(rec.credit, 3.5);
      expect(rec.achievementDistribution?['A'], 40);
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': '222',
        'user_id': 'u2',
        'school_year': 1,
        'semester': 2,
        'subject_name': '영어',
        'credit': 2,
        'created_at': '',
        'updated_at': '',
      };
      final rec = GradeRecord.fromJson(json);
      expect(rec.rawScore, isNull);
      expect(rec.gradeRank, isNull);
      expect(rec.achievementDistribution, isNull);
    });

    test('toMap omits null values', () {
      final rec = GradeRecord(
        id: 'x',
        userId: 'u',
        schoolYear: 1,
        semester: 1,
        subjectName: '과학',
        credit: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final map = rec.toMap();
      expect(map.containsKey('raw_score'), isFalse);
      expect(map['school_year'], 1);
    });
  });
}
