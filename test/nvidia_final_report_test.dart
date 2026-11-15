import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';

import 'nvidia_report_layout_test.dart' show box;

void main() {
  test('기말 다단 분포가 석차등급에 섞이지 않고 하단 제외 표는 저장 후보에서 제외', () {
    final detections = [
      box('성적 통지표', .5, .08),
      box('2026학년도 1학년 2학기', .3, .12),
      for (final h in [
        ('과목명', .13),
        ('과목점수', .26),
        ('원점수', .35),
        ('성취도', .44),
        ('성취도별', .54),
        ('석차등급', .64),
        ('석차(동석차수)', .75),
        ('수강자수', .85),
        ('과목평균', .94),
      ])
        box(h.$1, h.$2, .23),
      box('분포비율', .54, .245),
      for (var i = 0; i < 2; i++) ...[
        box('가상과목${i + 1}(4)', .13, .32 + i * .13),
        box('85.40', .26, .32 + i * .13),
        box('85', .35, .32 + i * .13),
        box('B', .44, .32 + i * .13),
        for (var j = 0; j < 5; j++)
          box(
            '${'ABCDE'[j]}(${[10, 20, 30, 25, 15][j]})',
            .54,
            .28 + i * .13 + j * .02,
          ),
        box(i == 0 ? '3' : '2', .64, .32 + i * .13),
        box('21(2)', .75, .32 + i * .13),
        box('220', .85, .32 + i * .13),
        box('72.3', .94, .32 + i * .13),
      ],
      box('체육·예술과목 / 과학탐구실험', .3, .56),
      box('과목명', .13, .61),
      box('과목점수', .4, .61),
      box('성취도', .65, .61),
      box('가상예술2(2)', .13, .68),
      box('87.00', .4, .68),
      box('B', .65, .68),
    ];
    final normalized = normalizeNvidiaOcr({
      'data': [
        {'text_detections': detections},
      ],
    });
    final result = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.finalExam,
      schoolYear: 1,
      semester: 2,
    );
    expect(result.result.subjects.length, 2);
    expect(result.result.subjects.map((d) => d.gradeRank), [3, 2]);
    expect(result.result.subjects.map((d) => d.credit), [4, 4]);
    expect(result.result.subjects.map((d) => d.achievement), ['B', 'B']);
    expect(result.result.subjects.first.rawScore, 85);
    expect(result.result.subjects.first.subjectAverage, 72.3);
    expect(result.warnings.where((w) => w.contains('석차등급의 인식값')), isEmpty);
  });
}
