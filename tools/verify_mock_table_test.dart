import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

void main() {
  test('제공된 모의고사 6영역의 표 검토 초기값 전체 대조', () {
    final raw = jsonDecode(
      File('tools/ocr/test-output/private-mock-response.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final recovered = File('tools/ocr/test-output/private-mock-recovered.json')
        .readAsStringSync();
    final expected = jsonDecode(
      File('tools/ocr/test-output/private-mock-expected.json')
          .readAsStringSync(),
    ) as List;
    final preview = GradeImportParser().parse(
      applyMockGradeRecovery(normalizeNvidiaOcr(raw), recovered),
      kind: StudentDocumentKind.mockExam,
      schoolYear: 2,
      semester: 1,
    );
    final rows = preview.mockExamImport!.rows;
    final failures = <String>[];
    if (rows.length != expected.length) failures.add('영역 수');
    for (var i = 0; i < rows.length && i < expected.length; i++) {
      final r = rows[i], e = expected[i];
      for (final check in <String, bool>{
        '영역': r.subject.replaceAll('탐구', '') == e['label'],
        '원점수': r.rawScore == e['raw'],
        '표준점수': r.standardScore == e['standard'],
        '백분위': r.percentile == e['percentile'],
        '등급': r.gradeRank == e['grade'],
      }.entries) {
        if (!check.value) failures.add('행 ${i + 1} ${check.key}');
      }
    }
    expect(failures, isEmpty, reason: failures.join(', '));
    expect(rows.where((r) => r.recoveredGrade).length, 2);
    expect(preview.mockExamImport!.calendarYear, 2026);
    expect(preview.mockExamImport!.schoolYear, 2);
    expect(preview.mockExamImport!.examMonth, 9);
  });
}
