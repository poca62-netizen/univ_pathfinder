import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/nvidia_ocr.dart';

Map<String, dynamic> detection(String text, double x, double y) => {
  'text_prediction': {'text': text, 'confidence': .95},
  'bounding_box': {
    'points': [
      {'x': x, 'y': y},
      {'x': x + .08, 'y': y},
      {'x': x + .08, 'y': y + .02},
      {'x': x, 'y': y + .02},
    ],
  },
};

void main() {
  test('취소된 인식은 서버 호출 전 중단한다', () async {
    await expectLater(
      recognizeNvidiaImage(Uint8List(0), 'image/png', isCancelled: () => true),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', '인식을 취소했습니다.'),
      ),
    );
  });
  test('NVIDIA boxes become sorted rows with independent numeric columns', () {
    final result = jsonDecode(
      normalizeNvidiaOcr({
        'data': [
          {
            'text_detections': [
              detection('81', .7, .2),
              detection('과목명', .1, .1),
              detection('가상과목', .1, .2),
              detection('원점수', .7, .1),
            ],
          },
        ],
      }),
    );
    final lines = result['pages'][0]['lines'] as List;
    expect(lines.length, 2);
    expect(lines[0]['text'], '과목명 원점수');
    expect(lines[1]['text'], '가상과목 81');
    expect(lines[1]['words'][1]['confidence'], 95);
  });
  test(
    'invalid provider coordinates rejected rather than mapped to grades',
    () {
      expect(
        () => normalizeNvidiaOcr({
          'data': [
            {
              'text_detections': [detection('81', 2, .1)],
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => normalizeNvidiaOcr({'error': 'failure'}),
        throwsFormatException,
      );
    },
  );
}
