import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';
import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/screens/mock_exam_edit_screen.dart';

void main() {
  String source() => jsonEncode({
    'pages': [
      {
        'page': 1,
        'method': 'ocr',
        'text': '원본 문장 그대로',
        'provider': 'NVIDIA',
        'lines': [],
      },
    ],
  });
  test('부분 인식은 원문을 유지하고 모의고사 전용 제안만 전달', () {
    final normalized = applyMockGradeRecovery(
      source(),
      jsonEncode({
        'recovered': [
          {'subject': '영어', 'grade': 4, 'confidence': 85},
        ],
      }),
    );
    final preview = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.mockExam,
      schoolYear: 2,
      semester: 1,
    );
    expect(preview.rawText, contains('원본 문장 그대로'));
    expect(preview.recognizedMockGrades, {'영어': 4});
    expect(preview.canStoreGrades, isFalse);
    final school = GradeImportParser().parse(
      normalized,
      kind: StudentDocumentKind.midterm,
      schoolYear: 2,
      semester: 1,
    );
    expect(school.recognizedMockGrades, isEmpty);
  });
  test('낮은 신뢰도·잘못된 등급·중복 충돌·로컬 실패는 반영하지 않는다', () {
    for (final input in [
      null,
      'invalid',
      jsonEncode({
        'recovered': [
          {'subject': '한국사', 'grade': 10, 'confidence': 90},
        ],
      }),
      jsonEncode({
        'recovered': [
          {'subject': '영어', 'grade': 4, 'confidence': 64},
        ],
      }),
      jsonEncode({
        'recovered': [
          {'subject': '영어', 'grade': 4, 'confidence': 90},
          {'subject': '영어', 'grade': 5, 'confidence': 90},
        ],
      }),
    ]) {
      final result = jsonDecode(applyMockGradeRecovery(source(), input));
      expect(result['pages'][0]['mockGradeRecoveries'], isEmpty);
      expect(result['pages'][0]['text'], '원본 문장 그대로');
    }
  });
  testWidgets('영역 등급 반영은 이전 지표를 비우고 원본 대조를 초기화', (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MockExamEditScreen(recognizedGrades: {'영어': 4, '한국사': 3}),
      ),
    );
    Finder field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(field('원점수'), '82');
    await tester.enterText(field('백분위'), '91');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('영어 · 4등급 반영'));
    await tester.pump();
    expect(tester.widget<TextFormField>(field('영역')).controller!.text, '영어');
    expect(tester.widget<TextFormField>(field('등급')).controller!.text, '4');
    expect(
      tester.widget<TextFormField>(field('원점수')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextFormField>(field('백분위')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('한국사 · 3등급 반영'));
    await tester.pump();
    expect(tester.widget<TextFormField>(field('영역')).controller!.text, '한국사');
    expect(tester.widget<TextFormField>(field('등급')).controller!.text, '3');
  });
  test('로컬 보완 실패는 원본 유지, 취소는 늦은 결과 차단', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'text_detections': [
                  {
                    'text_prediction': {'text': '원본', 'confidence': .99},
                    'bounding_box': {
                      'points': [
                        {'x': .1, 'y': .1},
                        {'x': .2, 'y': .1},
                        {'x': .2, 'y': .12},
                        {'x': .1, 'y': .12},
                      ],
                    },
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final kept = await recognizeNvidiaImage(
      Uint8List(0),
      'image/jpeg',
      client: client,
      mockExam: true,
      mockRecovery: (bytes, mime, response, {onProgress}) async =>
          throw StateError('local failure'),
    );
    expect(jsonDecode(kept)['pages'][0]['text'], '원본');
    expect(calls, 1);
    var cancelled = false;
    await expectLater(
      recognizeNvidiaImage(
        Uint8List(0),
        'image/jpeg',
        client: client,
        mockExam: true,
        isCancelled: () => cancelled,
        mockRecovery: (bytes, mime, response, {onProgress}) async {
          cancelled = true;
          return null;
        },
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', '인식을 취소했습니다.'),
      ),
    );
    await client.dispose();
  });
}
