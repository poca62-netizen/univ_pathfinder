// Private final-report reproduction. Cached response remains Git-ignored.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';

void main() {
  test('제공된 기말 사진 등급·일반교과 점수 대조 (나머지 필드는 별도 보고)', () async {
    final cache = File('tools/ocr/test-output/private-final-response.json');
    if (const bool.fromEnvironment('LIVE_FINAL_OCR')) {
      final config =
          jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
      final client = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_PUBLISHABLE_KEY'] as String,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await client.auth.signInAnonymously();
        final response = await client.functions.invoke(
          'nemotron-ocr',
          body: await File('성적표/1-2-2.jpg').readAsBytes(),
          headers: {'Content-Type': 'image/jpeg'},
        );
        if (response.status != 200) throw StateError('OCR 응답 실패');
        cache.writeAsStringSync(jsonEncode(response.data));
      } finally {
        await client.dispose();
      }
    }
    final normalized = normalizeNvidiaOcr(
      Map<String, dynamic>.from(jsonDecode(cache.readAsStringSync()) as Map),
    );
    File('tools/ocr/test-output/private-final-normalized.json')
        .writeAsStringSync(normalized);
    final page = (jsonDecode(normalized) as Map)['pages'][0];
    stdout.writeln('표 재구성: ${page['reportTable']}');
    final preview = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.finalExam,
      schoolYear: 1,
      semester: 2,
    );
    final expected = jsonDecode(
      File('tools/ocr/test-output/private-final-expected.json')
          .readAsStringSync(),
    ) as List;
    final mismatches = <String>[];
    if (preview.result.subjects.length != expected.take(6).length) {
      mismatches.add('과목 수');
    }
    for (
      var i = 0;
      i < preview.result.subjects.length && i < expected.take(6).length;
      i++
    ) {
      final d = preview.result.subjects[i];
      final e = expected[i];
      for (final check in <String, bool>{
        '과목': d.subjectName == e['subject'],
        '학점': d.credit == e['credit'],
        '등급': d.gradeRank == e['rank'],
        '성취도': d.achievement == e['achievement'],
      }.entries) {
        if (!check.value) mismatches.add('행 ${i + 1} ${check.key}');
      }
    }
    stdout.writeln(
      '추출 과목 수: ${preview.result.subjects.length}, 대조 불일치: ${mismatches.length}',
    );
    final ranks = preview.result.subjects.map((d) => d.gradeRank).toList();
    expect(
      ranks,
      expected.take(6).map((e) => e['rank']).toList(),
      reason: '등급 대조',
    );
    final credits = preview.result.subjects
        .take(6)
        .map((d) => d.credit)
        .toList();
    expect(
      credits,
      expected.take(6).map((e) => e['credit']).toList(),
      reason: '일반교과 학점 대조',
    );
    final scores = preview.result.subjects
        .take(6)
        .map((d) => d.rawScore)
        .toList();
    final averages = preview.result.subjects
        .take(6)
        .map((d) => d.subjectAverage)
        .toList();
    expect(
      scores,
      expected.take(6).map((e) => e['score']).toList(),
      reason: '원점수 대조',
    );
    expect(
      averages,
      expected.take(6).map((e) => e['average']).toList(),
      reason: '평균 대조',
    );
    if (const bool.fromEnvironment('VERIFY_FULL_FINAL')) {
      expect(mismatches, isEmpty, reason: mismatches.join(', '));
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
