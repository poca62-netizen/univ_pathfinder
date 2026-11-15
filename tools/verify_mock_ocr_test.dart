// Cached, private photo comparison. Not an automatic mock-exam parser.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';

void main() {
  test('모의고사 사진 상단 핵심 수치 OCR 대조와 현재 수동 입력 계약', () {
    final response = jsonDecode(
      File('tools/ocr/test-output/private-mock-response.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final expected = jsonDecode(
      File('tools/ocr/test-output/private-mock-expected.json')
          .readAsStringSync(),
    ) as List;
    final words = (response['data'][0]['text_detections'] as List).map((d) {
      final points = d['bounding_box']['points'] as List;
      return {
        'text': (d['text_prediction']['text'] as String).replaceAll(
          RegExp(r'\s'),
          '',
        ),
        'x':
            points
                .map((p) => (p['x'] as num).toDouble())
                .reduce((a, b) => a + b) /
            points.length,
        'y':
            points
                .map((p) => (p['y'] as num).toDouble())
                .reduce((a, b) => a + b) /
            points.length,
      };
    }).toList();
    final failures = <String>[];
    var checked = 0;
    final columns = <String, (double, double)>{
      'raw': (.18, .23),
      'standard': (.27, .32),
      'percentile': (.41, .455),
      'grade': (.46, .51),
    };
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i];
      final anchors = words
          .where(
            (w) =>
                w['text'] == e['label'] &&
                (w['x'] as double) < .15 &&
                (w['y'] as double) < .3,
          )
          .toList();
      if (anchors.length != 1) {
        failures.add('영역 ${i + 1} 이름');
        continue;
      }
      final y = anchors.single['y'] as double;
      final row = words
          .where((w) => ((w['y'] as double) - y).abs() < .01)
          .toList();
      for (final col in columns.entries) {
        if (e[col.key] == null) continue;
        checked++;
        final candidates = row.where(
          (w) =>
              (w['x'] as double) > col.value.$1 &&
              (w['x'] as double) < col.value.$2,
        );
        var matched = candidates.any(
          (w) => double.tryParse(w['text'] as String) == e[col.key],
        );
        if (col.key == 'grade' && !matched) {
          matched = row.any((w) {
            final m = RegExp(r'^원점수에의한등급\(([1-9])\)$')
                .firstMatch(w['text'] as String);
            return m != null && int.parse(m[1]!) == e[col.key];
          });
        }
        if (!matched) failures.add('영역 ${i + 1} ${col.key}');
      }
    }
    final preview = GradeImportParser().parse(
      normalizeNvidiaOcr(response),
      kind: StudentDocumentKind.mockExam,
      schoolYear: 2,
      semester: 1,
    );
    expect(preview.canStoreGrades, isFalse);
    expect(preview.result.subjects, isEmpty);
    expect(preview.rawText, isNotEmpty);
    stdout.writeln(
      '상단 핵심 수치 대조: $checked개, 불일치 ${failures.length}개. 자동 입력은 미구현.',
    );
    File('tools/ocr/test-output/private-mock-check.json').writeAsStringSync(
      jsonEncode({
        'checked': checked,
        'mismatches': failures,
        'automaticInput': false,
      }),
    );
    expect(failures, isEmpty, reason: failures.join(', '));
  });
}
