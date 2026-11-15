import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 화면 테스트는 데이터를 주입해 통과하므로, 실제 앱 번들에 빠진 자산은 여기서 잡는다.
void main() {
  test('lib에서 읽는 assets/ 파일은 모두 pubspec.yaml에 등록돼 있다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final used = <String>{};
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in RegExp(
        r"""['"](assets/[^'"$]+\.(?:json|pdf))['"]""",
      ).allMatches(f.readAsStringSync())) {
        used.add(m[1]!);
      }
    }
    expect(used, contains('assets/data/admission_results.json'));
    for (final path in used) {
      expect(pubspec, contains('- $path'), reason: '$path 미등록');
      expect(File(path).existsSync(), isTrue, reason: '$path 없음');
    }
  });
}
