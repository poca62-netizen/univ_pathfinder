// Explicit local reproduction only. Does not send student data or write a DB.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

void main() {
  test('로컬 첨부 사진에서 과목·학점·원점수·평균을 분리하고 석차를 등급으로 오인하지 않는다', () {
    final json = File('tools/ocr/test-output/private-reproduction.json').readAsStringSync();
    final preview = GradeImportParser().parse(json, kind: StudentDocumentKind.midterm,
      schoolYear: 1, semester: 1);
    const count = int.fromEnvironment('EXPECTED_SUBJECT_COUNT');
    if (count > 0) expect(preview.result.subjects.length, count);
    expect(preview.result.subjects, isNotEmpty);
    for (final draft in preview.result.subjects) {
      expect(draft.subjectName, isNotEmpty);
      expect(draft.credit, isNotNull);
      expect(draft.rawScore, isNotNull);
      expect(draft.subjectAverage, isNotNull);
      expect(draft.gradeRank, isNull);
      expect(draft.isValid, isTrue, reason: draft.validationErrors().join(' '));
    }
    // Value-level reproduction is inspected locally, never printed in logs.
  });
}
