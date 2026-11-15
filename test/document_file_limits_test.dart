import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/document_file_limits.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_file_import_service.dart';

void main() {
  test('생활기록부 PDF 7.96MB 허용, 이미지 5MB 유지 및 PDF 상한 경계', () {
    expect(
      DocumentFileLimits.validate(
        (7.96 * 1024 * 1024).round(),
        'application/pdf',
      ),
      isNull,
    );
    expect(
      DocumentFileLimits.validate(
        DocumentFileLimits.pdfBytes,
        'application/pdf',
      ),
      isNull,
    );
    expect(
      DocumentFileLimits.validate(
        DocumentFileLimits.pdfBytes + 1,
        'application/pdf',
      ),
      isNotNull,
    );
    expect(
      DocumentFileLimits.validate(DocumentFileLimits.imageBytes, 'image/jpeg'),
      isNull,
    );
    expect(
      DocumentFileLimits.validate(
        DocumentFileLimits.imageBytes + 1,
        'image/jpeg',
      ),
      isNotNull,
    );
    expect(DocumentFileLimits.validate(0, 'application/pdf'), isNotNull);
  });
  test('인식 서비스에서도 초과 PDF를 처리 시작 전에 차단', () async {
    await expectLater(
      GradeFileImportService().extract(
        Uint8List(DocumentFileLimits.pdfBytes + 1),
        'application/pdf',
        kind: StudentDocumentKind.schoolRecord,
        schoolYear: 1,
        semester: 1,
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('20MB')),
      ),
    );
  });
}
