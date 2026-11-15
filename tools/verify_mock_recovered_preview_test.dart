import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
void main(){test('사진의 브라우저 보완 결과가 모의고사 입력 제안까지 연결',(){
 final raw=jsonDecode(File('tools/ocr/test-output/private-mock-response.json').readAsStringSync()) as Map<String,dynamic>;
 final recovered=File('tools/ocr/test-output/private-mock-recovered.json').readAsStringSync();
 final normalized=normalizeNvidiaOcr(raw);
 final combined=applyMockGradeRecovery(normalized,recovered);
 final preview=GradeImportParser().parse(combined,kind:StudentDocumentKind.mockExam,schoolYear:2,semester:1);
 final expected=jsonDecode(File('tools/ocr/test-output/private-mock-expected.json').readAsStringSync()) as List;
 for(final name in ['영어','한국사']){expect(preview.recognizedMockGrades[name],expected.firstWhere((r)=>r['label']==name)['grade']);}
 expect(preview.recognizedMockGrades.length,2);
 expect(preview.rawText,contains(jsonDecode(normalized)['pages'][0]['text']));
 expect(preview.canStoreGrades,isFalse);
 });}
