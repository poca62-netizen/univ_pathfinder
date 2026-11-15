import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/screens/grade_extraction_review_screen_v2.dart';
import 'package:univ_pathfinder/screens/grade_upload_file_screen_v2.dart';
import 'package:univ_pathfinder/services/grade_file_import_service.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

class FakeImporter extends GradeFileImportService {
  @override
  bool get available => true;
  @override
  Future<ImportPreview> extract(
    Uint8List bytes,
    String mime, {
    required StudentDocumentKind kind,
    required int schoolYear,
    required int semester,
    bool forceOcr = false,
    bool enhancedRecognition = false,
    void Function(String)? onProgress,
  }) async {
    expect(enhancedRecognition, isTrue);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(mime, 'application/pdf');
    return GradeImportParser().parse(
      File('test/fixtures/pdf_extraction.json').readAsStringSync(),
      kind: kind,
      schoolYear: schoolYear,
      semester: semester,
    );
  }
}

void main() {
  testWidgets('가상 PDF 선택부터 추출 결과까지 연결되고 예시 DB 저장은 차단된다', (tester) async {
    await tester.runAsync(
      () => rootBundle.load('assets/samples/sample_grades.pdf'),
    );
    await tester.pumpWidget(
      MaterialApp(home: GradeUploadFileScreenV2(importService: FakeImporter())),
    );
    final sample = find.text('가상 PDF로 인식 시험 · 저장 안 됨');
    await tester.scrollUntilVisible(
      sample,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(sample);
    await tester.pumpAndSettle();
    final extract = find.text('성적 추출 → 확인·수정');
    await tester.scrollUntilVisible(
      extract,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(extract);
    await tester.pumpAndSettle();
    expect(find.text('국어'), findsOneWidget);
    expect(find.text('가상 예시 파일입니다. DB 저장은 차단됩니다.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '확인 후 저장'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('원본 대조 확인 전 저장 차단, 저장 실패 재시도는 같은 UUID 사용', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <List<Map<String, dynamic>>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GradeExtractionReviewScreenV2(
          result: ExtractionResult(
            subjects: [
              GradeDraft(
                schoolYear: 2,
                semester: 1,
                subjectName: '국어',
                credit: 3,
                rawScore: 88,
              ),
            ],
          ),
          requireSourceConfirmation: true,
          sourceText: '가상 성적표',
          saveGrades: (rows) async {
            requests.add(rows);
            throw Exception('network response lost');
          },
        ),
      ),
    );
    final save = find.widgetWithText(FilledButton, '확인 후 저장');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final check = find.byType(CheckboxListTile);
    await tester.ensureVisible(check);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
    }
    expect(requests.length, 2);
    expect(requests[0].single['id'], requests[1].single['id']);
    expect(requests[0].single.containsKey('source_text'), isFalse);
    final subject = find.widgetWithText(TextFormField, '과목명');
    await tester.ensureVisible(subject);
    await tester.pumpAndSettle();
    await tester.enterText(subject, '국어 수정');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });
}
