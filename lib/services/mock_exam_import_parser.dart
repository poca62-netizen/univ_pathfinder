import 'dart:math' as math;

import 'package:univ_pathfinder/models/mock_exam_draft.dart';

class _MockWord {
  _MockWord(Map value)
    : text = (value['text'] as String).replaceAll(RegExp(r'\s'), ''),
      x = (value['x'] as num).toDouble() + (value['w'] as num).toDouble() / 2,
      y = (value['y'] as num).toDouble(),
      h = (value['h'] as num?)?.toDouble() ?? 0;
  final String text;
  final double x, y, h;
}

class MockExamImportParser {
  MockExamImportResult parse(List pages) {
    final output = <MockExamDraft>[], warnings = <String>[];
    final text = pages
        .map((p) => p['text'])
        .join('\n')
        .replaceAll(RegExp(r'\s'), '');
    int? read(String pattern) =>
        int.tryParse(RegExp(pattern).firstMatch(text)?[1] ?? '');
    for (final page in pages) {
      final words = <_MockWord>[];
      for (final line in (page['lines'] as List? ?? [])) {
        for (final value in (line['words'] as List? ?? [])) {
          if (value is Map &&
              value['text'] is String &&
              value['x'] is num &&
              value['w'] is num &&
              value['y'] is num) {
            words.add(_MockWord(value));
          }
        }
      }
      words.sort((a, b) => a.y.compareTo(b.y));
      _MockWord? first(String label) =>
          words.where((w) => w.text == label).firstOrNull;
      final rawHeader = first('원점수'), standardHeader = first('표준점수');
      if (rawHeader == null ||
          standardHeader == null ||
          standardHeader.x <= rawHeader.x) {
        continue;
      }
      final headerWindow = math.max(
        rawHeader.h * 2.8,
        (rawHeader.y - standardHeader.y).abs() * 2,
      );
      final band = words
          .where((w) => (w.y - rawHeader.y).abs() <= headerWindow)
          .toList();
      _MockWord? header(bool Function(_MockWord) match) =>
          band.where(match).firstOrNull;
      final sub = band
          .where((w) => w.text == '득점' && w.y > rawHeader.y + rawHeader.h * .3)
          .toList();
      double scoreColumn(_MockWord parent) {
        if (sub.length < 2) return parent.x;
        return (sub.toList()..sort(
              (a, b) =>
                  (a.x - parent.x).abs().compareTo((b.x - parent.x).abs()),
            ))
            .first
            .x;
      }

      final rawX = scoreColumn(rawHeader),
          standardX = scoreColumn(standardHeader);
      var percentileX = header((w) => ['백분위', '전국백분위'].contains(w.text))?.x;
      var gradeX = header((w) => w.text == '등급')?.x;
      final group = header(
        (w) =>
            w.text.contains('석차') &&
            w.text.contains('백분위') &&
            w.text.contains('등급'),
      );
      final schoolRank = header((w) => ['학교석차', '학교석자'].contains(w.text));
      final respondents = header((w) => w.text == '응시자수');
      if (group != null &&
          schoolRank != null &&
          respondents != null &&
          respondents.x > schoolRank.x) {
        final step = (respondents.x - schoolRank.x) / 3;
        percentileX ??= schoolRank.x + step;
        gradeX ??= schoolRank.x + step * 2;
      }
      if (percentileX == null ||
          gradeX == null ||
          !(rawX < standardX &&
              standardX < percentileX &&
              percentileX < gradeX)) {
        warnings.add('모의고사 머리글의 점수·백분위·등급 열을 구분하지 못했습니다. 빈칸은 원본을 보고 입력하세요.');
        continue;
      }
      final names = {
        '국어': '국어',
        '수학': '수학',
        '영어': '영어',
        '한국사': '한국사',
        '통합사회': '통합사회',
        '통합과학': '통합과학',
        '사회': '사회탐구',
        '과학': '과학탐구',
        '사회탐구': '사회탐구',
        '과학탐구': '과학탐구',
        '직업탐구': '직업탐구',
        '제2외국어': '제2외국어',
        '한문': '한문',
      };
      final anchors = <_MockWord>[];
      final seen = <String>{};
      for (final w in words) {
        if (w.y > rawHeader.y + rawHeader.h &&
            w.x < rawX &&
            names.containsKey(w.text) &&
            seen.add(names[w.text]!)) {
          anchors.add(w);
        }
      }
      if (anchors.isEmpty) continue;
      final gaps = [
        for (var i = 1; i < anchors.length; i++)
          anchors[i].y - anchors[i - 1].y,
      ]..sort();
      final gap = gaps.isEmpty
          ? math.max(rawHeader.h * 3, 1e-5)
          : gaps[gaps.length ~/ 2];
      final tolerance =
          [
            standardX - rawX,
            percentileX - standardX,
            gradeX - percentileX,
          ].reduce(math.min) *
          .42;
      for (var i = 0; i < anchors.length; i++) {
        final anchor = anchors[i];
        // Stop at the next detached table instead of reading answer/summary rows.
        if (i > 0 && anchor.y - anchors[i - 1].y > gap * 1.8) break;
        final row = words
            .where((w) => (w.y - anchor.y).abs() < gap * .4)
            .toList();
        double? cell(double x, String label) {
          final cells = row.where((w) => (w.x - x).abs() < tolerance).toList();
          final values = cells
              .where((w) => RegExp(r'^\d+(?:\.\d+)?$').hasMatch(w.text))
              .map((w) => double.parse(w.text))
              .toSet();
          if (values.length == 1) return values.single;
          if (cells.isNotEmpty && cells.any((w) => w.text != '-')) {
            warnings.add('${names[anchor.text]}: $label 인식값을 원본과 대조해 입력하세요.');
          }
          return null;
        }

        final raw = cell(rawX, '원점수');
        final absolute = ['영어', '한국사'].contains(anchor.text);
        final standard = absolute ? null : cell(standardX, '표준점수');
        final percentile = absolute ? null : cell(percentileX, '백분위');
        var gradeNumber = cell(gradeX, '등급');
        if (gradeNumber == null && absolute) {
          final explicit = row
              .map((w) => RegExp(r'^원점수에의한등급\(([1-9])\)$').firstMatch(w.text))
              .whereType<RegExpMatch>()
              .toList();
          if (explicit.length == 1) {
            gradeNumber = double.parse(explicit.single[1]!);
          }
        }
        int? grade =
            gradeNumber != null && gradeNumber == gradeNumber.roundToDouble()
            ? gradeNumber.toInt()
            : null;
        var recovered = false;
        final recovery = (page['mockGradeRecoveries'] as List? ?? [])
            .where(
              (r) =>
                  r is Map &&
                  r['subject'] == anchor.text &&
                  r['grade'] is int &&
                  r['grade'] >= 1 &&
                  r['grade'] <= 9,
            )
            .toList();
        if (grade == null && recovery.length == 1) {
          grade = recovery.single['grade'] as int;
          recovered = true;
        } else if (grade != null && recovery.any((r) => r['grade'] != grade)) {
          warnings.add(
            '${names[anchor.text]}: 전체 인식과 부분 인식의 등급이 다릅니다. 원본을 확인하세요.',
          );
        }
        output.add(
          MockExamDraft(
            subject: names[anchor.text]!,
            rawScore: raw,
            standardScore: standard,
            percentile: percentile,
            gradeRank: grade,
            recoveredGrade: recovered,
          ),
        );
      }
    }
    if (output.isEmpty) {
      warnings.add('지원하는 영역별 표를 찾지 못했습니다. 아래 빈 표에 원본을 보고 입력하세요.');
    }
    return MockExamImportResult(
      rows: output,
      warnings: warnings.toSet().toList(),
      calendarYear: read(r'((?:19|20)\d{2})학년도'),
      schoolYear: read(r'고([1-3])') ?? read(r'([1-3])학년(?!도)'),
      examMonth: read(r'(\d{1,2})월'),
    );
  }
}
