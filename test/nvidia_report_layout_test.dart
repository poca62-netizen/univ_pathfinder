import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

Map<String, dynamic> box(
  String text,
  double x,
  double y, {
  double width = .045,
}) => {
  'text_prediction': {'text': text, 'confidence': .99},
  'bounding_box': {
    'points': [
      {'x': x - width / 2, 'y': y - .004},
      {'x': x + width / 2, 'y': y - .004},
      {'x': x + width / 2, 'y': y + .004},
      {'x': x - width / 2, 'y': y + .004},
    ],
  },
};

void main() {
  test('merged multiline headers, wrapped subjects and unrelated sections', () {
    final detections = [
      box('성적 통지표', .45, .1),
      box('2026학년도 2학년 1학기', .3, .15),
      box('과목명', .10, .27),
      box('구분', .18, .27),
      box('고사/영역명', .26, .26),
      box('(반영비율)', .26, .28),
      box('받은점수', .4, .27),
      box('합계', .46, .27),
      box('원점수', .52, .27),
      box('성취도별 석차', .67, .26, width: .11),
      box('문포비율 등급 (동석차수)', .71, .28, width: .21),
      box('석차', .77, .26),
      box('수강자수 과목평균', .885, .27, width: .14),
      for (var i = 0; i < 2; i++) ...[
        box(i == 0 ? '가상국어(4)' : '가상사회와', .1, .31 + i * .03),
        if (i == 1) box('문화(3)', .1, .35),
        box('지필', .18, .31 + i * .03),
        box('100.00', .34, .31 + i * .03),
        box('81.40', .4, .31 + i * .03),
        box('81.40', .46, .31 + i * .03),
        box(i == 0 ? '81' : '94', .53, .31 + i * .03),
        box('16(2)', .77, .31 + i * .03),
        box('220', .85, .31 + i * .03),
        box(i == 0 ? '62.3' : '57.1', .92, .31 + i * .03),
      ],
      box('체육·예술과목', .2, .4),
      box('과목명', .1, .45),
      box('출석상황', .2, .6),
      box('43', .1, .7),
    ];
    final normalized = normalizeNvidiaOcr({
      'data': [
        {'text_detections': detections},
      ],
    });
    final preview = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.midterm,
      schoolYear: 2,
      semester: 1,
    );
    expect(preview.result.subjects.length, 2);
    final first = preview.result.subjects.first,
        second = preview.result.subjects.last;
    expect(first.subjectName, '가상국어');
    expect(first.credit, 4);
    expect(first.rawScore, 81);
    expect(first.subjectAverage, 62.3);
    expect(second.subjectName, '가상사회와 문화');
    expect(second.credit, 3);
    expect(second.rawScore, 94);
    expect(second.subjectAverage, 57.1);
    expect(
      preview.result.subjects.every(
        (d) => d.isValid && d.gradeRank == null && d.achievement == null,
      ),
      isTrue,
    );
    expect(preview.engine, 'NVIDIA Nemotron OCR v2');
    expect(jsonDecode(normalized)['pages'][0]['text'], contains('출석상황'));
  });
}
