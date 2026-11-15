// Explicit local reproduction only; private inputs stay in ignored test-output.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

void main() {
  test('사용자 지정 사진의 추출값을 로컬 원본 대조값과 비교 (값 출력 없음)', () {
    final response = jsonDecode(
      File('tools/ocr/test-output/private-nvidia.json').readAsStringSync(),
    );
    final normalized = normalizeNvidiaOcr(Map<String, dynamic>.from(response));
    final preview = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.midterm,
      schoolYear: 2,
      semester: 1,
    );
    final expected = jsonDecode(
      File('tools/ocr/test-output/private-expected.json').readAsStringSync(),
    ) as List;
    File('tools/ocr/test-output/private-normalized.json')
        .writeAsStringSync(normalized);
    expect(
      preview.result.subjects.length == expected.length,
      isTrue,
      reason: '과목 수 불일치',
    );
    final failures = <String>[];
    for (
      var i = 0;
      i < expected.length && i < preview.result.subjects.length;
      i++
    ) {
      final actual = preview.result.subjects[i];
      final e = expected[i];
      for (final check in <String, bool>{
        '과목': actual.subjectName == e['subject'],
        '학점': actual.credit == e['credit'],
        '원점수': actual.rawScore == e['score'],
        '평균': actual.subjectAverage == e['average'],
        '등급공란': actual.gradeRank == null,
        '성취도공란': actual.achievement == null,
        '유효성': actual.isValid,
      }.entries) {
        if (!check.value) failures.add('행 ${i + 1}: ${check.key} 불일치');
      }
    }
    File('tools/ocr/test-output/private-normalized.json')
        .writeAsStringSync(normalized);
    print(
      '과목 수: ${preview.result.subjects.length}, 수치·유효성 불일치: ${failures.where((f) => !f.contains("과목")).length}, 과목명 불일치: ${failures.where((f) => f.contains("과목")).length}',
    );
    expect(failures, isEmpty, reason: '값은 출력하지 않고 불일치 항목만 보고합니다.');
  });
}
