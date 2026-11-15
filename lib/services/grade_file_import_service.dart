import 'package:univ_pathfinder/models/document_file_limits.dart';

import 'dart:typed_data';

import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/services/local_ocr.dart' as ocr;
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_service.dart';

class GradeFileImportService {
  int _generation = 0;
  bool get usesNvidia => GradeService.instance.isAuthenticated;
  bool get available => usesNvidia || ocr.localOcrAvailable;
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
    final sizeError = DocumentFileLimits.validate(bytes.length, mime);
    if (sizeError != null) throw StateError(sizeError);
    final generation = ++_generation;
    final remote = usesNvidia && mime.startsWith('image/');
    if (remote) onProgress?.call('NVIDIA 서버에서 이미지 글자를 인식하고 있습니다.');
    final json = remote
        ? await recognizeNvidiaImage(
            bytes,
            mime,
            mockExam: kind == StudentDocumentKind.mockExam,
            isCancelled: () => generation != _generation,
            onProgress: onProgress,
          )
        : await ocr.recognizeDocument(
            bytes,
            mime,
            forceOcr: forceOcr,
            enhancedRecognition: enhancedRecognition,
            onProgress: onProgress,
          );
    if (generation != _generation) throw StateError('인식을 취소했습니다.');
    return GradeImportParser().parse(
      json,
      kind: kind,
      schoolYear: schoolYear,
      semester: semester,
    );
  }

  void cancel() {
    _generation++;
    ocr.cancelDocumentRecognition();
  }
}
