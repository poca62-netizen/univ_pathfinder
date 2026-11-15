import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

String table(List<String> headers, List<List<String>> rows) => jsonEncode({
  'pages': [
    {
      'page': 1,
      'method': 'pdf-text',
      'text': [headers, ...rows].map((r) => r.join(' ')).join('\n'),
      'lines': [headers, ...rows]
          .map(
            (r) => {
              'words': [
                for (var i = 0; i < r.length; i++)
                  {'text': r[i], 'x': i * 150, 'w': 50},
              ],
            },
          )
          .toList(),
    },
  ],
});

ImportPreview parse(
  String source, {
  StudentDocumentKind kind = StudentDocumentKind.midterm,
}) => GradeImportParser().parse(source, kind: kind, schoolYear: 2, semester: 1);

void main() {
  test('과목명의 아라비아 숫자는 보존하고 끝 괄호만 학점으로 분리한다', () {
    final preview = parse(
      table(
        ['과목명', '만점', '받은점수', '합계', '원점수', '석차등급', '석차(동석차수)', '과목평균'],
        [
          ['공통국어2 (4)', '100', '81.5', '81.5', '82', '', '1(2)', '65.1'],
          ['영어2(3)', '100', '91', '91', '91', '', '3', '60.2'],
          ['화법과 언어 ()', '100', '87', '87', '87', '', '2', '62.3'],
        ],
      ),
    );
    final rows = preview.result.subjects;
    expect(rows.map((d) => d.subjectName), ['공통국어2', '영어2', '화법과 언어']);
    expect(rows.map((d) => d.credit), [4, 3, null]);
    expect(rows.every((d) => d.gradeRank == null), isTrue);
    expect(rows.last.isValid, isFalse);
  });
  test('학기 합산표를 중간 또는 기말 단일 성적으로 저장하지 않는다', () {
    final source = table(
      ['과목', '학점', '원점수'],
      [
        ['가상국어', '4', '88'],
      ],
    );
    final mixed = source.replaceAll('가상국어', '중간고사 기말고사 가상국어');
    final preview = parse(mixed);
    expect(preview.canStoreGrades, isFalse);
    expect(preview.result.subjects, isEmpty);
    expect(preview.warnings.join(), contains('학기 종합표'));
    final summary = parse(source, kind: StudentDocumentKind.semesterSummary);
    expect(summary.canStoreGrades, isFalse);
  });
  test('통지표의 받은점수·합계·석차를 원점수·등급과 혼동하지 않는다', () {
    final preview = parse(
      table(
        [
          '과목명',
          '구분',
          '고사/영역명(반영비율)',
          '만점',
          '받은점수',
          '합계',
          '원점수',
          '성취도',
          '성취도별분포비율',
          '석차등급',
          '석차(동석차수)',
          '수강자수',
          '과목평균',
        ],
        [
          [
            '가상국어2(4)',
            '지필',
            '중간고사(100%)',
            '100',
            '82.5',
            '82.5',
            '82',
            '',
            '',
            '',
            '12(2)',
            '200',
            '61.2',
          ],
        ],
      ),
    );
    final draft = preview.result.subjects.single;
    expect(draft.subjectName, '가상국어2');
    expect(draft.credit, 4);
    expect(draft.rawScore, 82);
    expect(draft.subjectAverage, 61.2);
    expect(draft.gradeRank, isNull);
  });

  test('스캔 PDF의 OCR 결과도 국어·수학 점수와 학점을 분리한다', () {
    final preview = parse(
      File('test/fixtures/scanned_extraction.json').readAsStringSync(),
    );
    expect(preview.usedOcr, isTrue);
    expect(preview.result.subjects.length, 2);
    expect(preview.result.subjects.first.subjectName, '국어');
    expect(preview.result.subjects.first.credit, 3);
    expect(preview.result.subjects.last.subjectName, '수학');
    expect(preview.result.subjects.last.rawScore, 92);
  });

  test('실제 PDF.js가 추출한 가상 PDF의 두 과목을 정확히 매핑한다', () {
    final preview = parse(
      File('test/fixtures/pdf_extraction.json').readAsStringSync(),
    );
    expect(preview.result.subjects.length, 2);
    final first = preview.result.subjects.first;
    expect(first.subjectName, '국어');
    expect(first.credit, 3);
    expect(first.rawScore, 88);
    expect(first.subjectAverage, 75.5);
    expect(first.achievement, 'A');
    expect(first.gradeRank, 2);
    expect(first.schoolYear, 2);
    expect(first.semester, 1);
  });
  test('실제 한국어 OCR 좌표를 사용하고 불확실한 성취도는 임의 보정하지 않는다', () {
    final preview = parse(
      File('test/fixtures/image_extraction.json').readAsStringSync(),
    );
    expect(preview.usedOcr, isTrue);
    expect(preview.result.subjects.length, 2);
    expect(preview.result.subjects.first.subjectName, '국어');
    expect(preview.result.subjects.first.rawScore, 88);
    expect(preview.result.subjects.last.subjectName, '수학');
    expect(preview.result.subjects.last.rawScore, 92);
    expect(preview.result.subjects.first.achievement, isNull);
    expect(preview.warnings.any((w) => w.contains('성취도')), isTrue);
  });
  test('학점 없는 표는 점수로 학점을 추측하지 않는다', () {
    final preview = parse(
      table(
        ['과목', '원점수', '과목평균'],
        [
          ['국어', '88', '75.5'],
        ],
      ),
    );
    expect(preview.result.subjects.single.credit, isNull);
    expect(preview.result.subjects.single.isValid, isFalse);
    expect(preview.warnings.any((w) => w.contains('학점')), isTrue);
  });
  test('원점수/평균(표준편차)와 성취도(수강자수) 복합 셀 처리', () {
    final preview = parse(
      table(
        ['과목', '단위수', '원점수/과목평균(표준편차)', '성취도(수강자수)', '석차등급'],
        [
          ['영어', '4', '91/75.3(12.2)', 'A(100)', '2'],
        ],
      ),
    );
    expect(preview.result.subjects.single.rawScore, 91);
    expect(preview.result.subjects.single.subjectAverage, 75.3);
    expect(preview.result.subjects.single.achievement, 'A');
  });
  test('모의고사·생기부 자료와 잘못 분류한 모의고사는 내신 저장 후보가 아니다', () {
    final json = table(
      ['과목', '학점', '원점수'],
      [
        ['국어', '3', '88'],
      ],
    );
    expect(
      parse(json, kind: StudentDocumentKind.mockExam).result.subjects,
      isEmpty,
    );
    expect(
      parse(json, kind: StudentDocumentKind.schoolRecord).result.subjects,
      isEmpty,
    );
    expect(parse(json.replaceAll('원점수', '표준점수')).result.subjects, isEmpty);
  });
  test('표 머리글 없는 텍스트에서 임의 성적을 만들지 않는다', () {
    final preview = parse(
      table(
        ['항목', '내용'],
        [
          ['동아리', '과학 실험 88회'],
        ],
      ),
    );
    expect(preview.result.subjects, isEmpty);
    expect(preview.warnings, isNotEmpty);
  });
  test('9등급 자료는 변환하지 않고 차단한다', () {
    final json = table(
      ['과목', '학점', '원점수', '등급'],
      [
        ['국어', '3', '88', '7'],
      ],
    );
    final draft = parse(json).result.subjects.single;
    expect(draft.gradeRank, 7);
    expect(draft.isValid, isFalse);
    expect(parse(json.replaceAll('국어', '9등급제 국어')).result.subjects, isEmpty);
  });
}
