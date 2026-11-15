import 'package:univ_pathfinder/services/mock_grade_recovery.dart';
import 'package:univ_pathfinder/models/grade_scope.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/ocr_image_crop.dart';

import 'dart:math' as math;

import 'package:univ_pathfinder/services/grade_import_parser.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';

// Korean report headers often span two lines, while multilingual OCR merges
// adjacent header cells. Recover only a positively identified report table.
List<Map<String, dynamic>> _basicLines(List<Map<String, dynamic>> words) {
  final rows = <List<Map<String, dynamic>>>[];
  final ordered = [...words]
    ..sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
  for (final word in ordered) {
    if (rows.isEmpty ||
        ((word['y'] as double) - (rows.last.first['y'] as double)).abs() >
            ((word['h'] as double) + (rows.last.first['h'] as double)) * .25) {
      rows.add([word]);
    } else {
      rows.last.add(word);
    }
  }
  return rows.map((row) {
    row.sort((a, b) => (a['x'] as double).compareTo(b['x'] as double));
    return <String, dynamic>{
      'text': row.map((w) => w['text']).join(' '),
      'words': row,
    };
  }).toList();
}

List<Map<String, dynamic>>? _reportLines(List<Map<String, dynamic>> words) {
  final subjects =
      words
          .where(
            (w) => (w['text'] as String).replaceAll(RegExp(r'\s'), '') == '과목명',
          )
          .toList()
        ..sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
  if (subjects.isEmpty) return null;
  final lines = <Map<String, dynamic>>[];
  var reconstructed = false;
  for (var i = 0; i < subjects.length; i++) {
    final start =
        (subjects[i]['y'] as double) -
        math.max(.025, (subjects[i]['h'] as double) * 2.2);
    final end = i + 1 < subjects.length
        ? (subjects[i + 1]['y'] as double) -
              math.max(.025, (subjects[i + 1]['h'] as double) * 2.2)
        : 1.0;
    final table = words
        .where((w) => (w['y'] as double) >= start && (w['y'] as double) < end)
        .toList();
    final rebuilt = _reportTableLines(table);
    reconstructed |= rebuilt != null;
    lines.addAll(rebuilt ?? _basicLines(table));
    if (rebuilt != null) {
      // Retain section boundaries removed by table reconstruction so the parser
      // never treats a later excluded table as ordinary school grades.
      final boundaries = table
          .where(
            (w) =>
                GradeScope.isExcludedSection(w['text'] as String) &&
                (w['y'] as double) > (subjects[i]['y'] as double),
          )
          .toList();
      lines.addAll(_basicLines(boundaries));
    }
  }
  return reconstructed ? lines : null;
}

List<Map<String, dynamic>>? _reportTableLines(
  List<Map<String, dynamic>> words,
) {
  String compact(String value) => value.replaceAll(RegExp(r'\s'), '');
  final subjects = words.where((w) => compact(w['text']) == '과목명').toList();
  if (subjects.isEmpty) return null;
  final subject = subjects.first;
  final y = subject['y'] as double;
  final headerWindow = math.max(.025, (subject['h'] as double) * 2.2);
  final band = words
      .where((w) => ((w['y'] as double) - y).abs() < headerWindow)
      .map(
        (w) => {
          ...w,
          'text': (w['text'] as String)
              .replaceAll('수험수', '원점수')
              .replaceAll('함계', '합계')
              .replaceAll('수형수', '원점수')
              .replaceAll('가강자수', '수강자수')
              .replaceAll('서프비울', '분포비율')
              .replaceAll('문포비율', '분포비율'),
        },
      )
      .toList();
  final bandText = band.map((w) => compact(w['text'])).join();
  if (!bandText.contains('원점수') || !bandText.contains('과목평균')) {
    return null;
  }
  final pieces = <Map<String, dynamic>>[];
  final tokens = RegExp(
    r'석차등급|수강자수|과목평균|과목점수|원점수|성취도별|성취도|분포비율|\(동석차수\)?|석차|등급',
  );
  for (final word in band) {
    final text = word['text'] as String;
    final matches = tokens.allMatches(text).toList();
    if (matches.length < 2) {
      pieces.add(word);
      continue;
    }
    for (final match in matches) {
      pieces.add({
        ...word,
        'text': match[0],
        'x':
            (word['x'] as double) +
            (word['w'] as double) * match.start / text.length,
        'w': (word['w'] as double) * (match.end - match.start) / text.length,
      });
    }
  }
  double center(Map<String, dynamic> w) =>
      (w['x'] as double) + (w['w'] as double) / 2;
  pieces.sort((a, b) => center(a).compareTo(center(b)));
  final groups = <List<Map<String, dynamic>>>[];
  for (final piece in pieces) {
    if (groups.isEmpty ||
        (center(piece) - center(groups.last.first)).abs() > 230) {
      groups.add([piece]);
    } else {
      groups.last.add(piece);
    }
  }
  final headers = <Map<String, dynamic>>[];
  for (final group in groups) {
    group.sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
    final text = compact(group.map((w) => w['text']).join());
    String label = '비고';
    for (final known in [
      '과목명',
      '구분',
      '과목점수',
      '받은점수',
      '합계',
      '원점수',
      '과목평균',
      '수강자수',
    ]) {
      if (text == known) label = known;
    }
    if (text.contains('고사/영역명')) label = '고사/영역명(반영비율)';
    if (text == '석차등급') label = '석차등급';
    if (text.contains('동석차수')) label = '석차(동석차수)';
    if (text == '성취도') label = '성취도';
    if (text.contains('분포비율')) label = '성취도별분포비율';
    final cx = group.map(center).reduce((a, b) => a + b) / group.length;
    headers.add({'text': label, 'x': cx - 1, 'w': 2.0, 'confidence': 100.0});
  }
  final scoreHeaders = headers.where((w) => w['text'] == '원점수').toList();
  final averageHeaders = headers.where((w) => w['text'] == '과목평균').toList();
  if (scoreHeaders.length != 1 || averageHeaders.length != 1) return null;
  final bottom = words
      .where(
        (w) =>
            (w['y'] as double) > y + headerWindow * 1.2 &&
            RegExp(r'체육.?예술|교양교과|출석상황|과목명').hasMatch(compact(w['text'])),
      )
      .map((w) => w['y'] as double)
      .fold<double>(1, (a, b) => a < b ? a : b);
  int column(Map<String, dynamic> w) {
    var nearest = 0;
    for (var i = 1; i < headers.length; i++) {
      if ((center(w) - center(headers[i])).abs() <
          (center(w) - center(headers[nearest])).abs()) {
        nearest = i;
      }
    }
    return nearest;
  }

  final body = words
      .where(
        (w) =>
            (w['y'] as double) > y + headerWindow &&
            (w['y'] as double) < bottom,
      )
      .toList();
  final anchors =
      body
          .where(
            (w) =>
                headers[column(w)]['text'] == '원점수' &&
                RegExp(r'^\d+(?:\.\d+)?$').hasMatch(compact(w['text'])),
          )
          .toList()
        ..sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
  if (anchors.isEmpty) return null;
  final rows = List.generate(anchors.length, (_) => <Map<String, dynamic>>[]);
  for (final word in body) {
    var nearest = 0;
    for (var i = 1; i < anchors.length; i++) {
      if (((word['y'] as double) - (anchors[i]['y'] as double)).abs() <
          ((word['y'] as double) - (anchors[nearest]['y'] as double)).abs()) {
        nearest = i;
      }
    }
    final distance = ((word['y'] as double) - (anchors[nearest]['y'] as double))
        .abs();
    final before = nearest > 0
        ? (anchors[nearest]['y'] as double) -
              (anchors[nearest - 1]['y'] as double)
        : double.infinity;
    final after = nearest + 1 < anchors.length
        ? (anchors[nearest + 1]['y'] as double) -
              (anchors[nearest]['y'] as double)
        : double.infinity;
    final window = math.min(before, after) * .48;
    if (distance < math.max(.014, window.isFinite ? window : .014)) {
      rows[nearest].add(word);
    }
  }
  final lines = <Map<String, dynamic>>[
    {'text': headers.map((w) => w['text']).join(' '), 'words': headers},
  ];
  for (final row in rows) {
    final cells = <Map<String, dynamic>>[];
    for (var c = 0; c < headers.length; c++) {
      final fragments = row.where((w) => column(w) == c).toList()
        ..sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
      if (fragments.isEmpty) continue;
      cells.add({
        'text': fragments.map((w) => w['text']).join(' '),
        'x': headers[c]['x'],
        'w': 2.0,
        'confidence': fragments
            .map((w) => (w['confidence'] as num).toDouble())
            .reduce((a, b) => a < b ? a : b),
      });
    }
    lines.add({'text': cells.map((w) => w['text']).join(' '), 'words': cells});
  }
  return lines;
}

/// Converts normalized NVIDIA detections into the existing review parser format.
String normalizeNvidiaOcr(Map<String, dynamic> response) {
  final data = response['data'];
  if (data is! List || data.length != 1) {
    throw const FormatException('인식 응답 형식이 올바르지 않습니다.');
  }
  final words = <Map<String, dynamic>>[];
  for (final detection in data.single['text_detections'] as List) {
    final prediction = detection['text_prediction'];
    final points = detection['bounding_box']['points'] as List;
    if (points.isEmpty) continue;
    final xs = points.map((p) => (p['x'] as num).toDouble()).toList()..sort();
    final ys = points.map((p) => (p['y'] as num).toDouble()).toList()..sort();
    if (![...xs, ...ys].every((v) => v.isFinite && v >= 0 && v <= 1)) {
      throw const FormatException('인식 좌표가 올바르지 않습니다.');
    }
    words.add({
      'text': prediction['text'] as String,
      'confidence': ((prediction['confidence'] as num?) ?? 0) * 100,
      'x': xs.first * 10000,
      'w': (xs.last - xs.first) * 10000,
      'y': (ys.first + ys.last) / 2,
      'h': ys.last - ys.first,
    });
  }
  words.sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));
  final rows = <List<Map<String, dynamic>>>[];
  for (final word in words) {
    if (rows.isEmpty ||
        ((word['y'] as double) - (rows.last.first['y'] as double)).abs() >
            ((word['h'] as double) + (rows.last.first['h'] as double)) * .25) {
      rows.add([word]);
    } else {
      rows.last.add(word);
    }
  }
  final reportLines = _reportLines(words);
  final lines =
      reportLines ??
      rows.map((row) {
        row.sort((a, b) => (a['x'] as double).compareTo(b['x'] as double));
        return {'text': row.map((w) => w['text']).join(' '), 'words': row};
      }).toList();
  return jsonEncode({
    'pages': [
      {
        'page': 1,
        'method': 'ocr',
        'text': rows
            .map((row) => row.map((w) => w['text']).join(' '))
            .join('\n'),
        'provider': 'NVIDIA Nemotron OCR v2',
        'reportTable': reportLines != null,
        'lines': lines,
      },
    ],
  });
}

Future<String> recognizeNvidiaImage(
  Uint8List bytes,
  String mime, {
  SupabaseClient? client,
  bool mockExam = false,
  Future<String?> Function(
    Uint8List,
    String,
    String, {
    void Function(String)? onProgress,
  })?
  mockRecovery,
  bool Function()? isCancelled,
  void Function(String)? onProgress,
}) async {
  void checkCancellation() {
    if (isCancelled?.call() == true) throw const _NvidiaCancelled();
  }

  try {
    checkCancellation();
    final caller = client ?? Supabase.instance.client;
    final response = await caller.functions.invoke(
      'nemotron-ocr',
      body: bytes,
      headers: {'Content-Type': mime},
    );
    if (response.status != 200) throw const FormatException();
    checkCancellation();
    var data = Map<String, dynamic>.from(response.data as Map);
    final originalData = data;
    final originalText =
        (jsonDecode(normalizeNvidiaOcr(data)) as Map)['pages'][0]['text']
            as String;
    if (mockExam) {
      final normalized = normalizeNvidiaOcr(data);
      String? recovery;
      try {
        recovery = await (mockRecovery ?? recoverMockGrades)(
          bytes,
          mime,
          jsonEncode(data),
          onProgress: onProgress,
        );
      } catch (_) {
        /* Optional pass failed: preserve the original OCR. */
      }
      checkCancellation();
      return applyMockGradeRecovery(normalized, recovery);
    }
    final detections = (data['data'] as List).first['text_detections'] as List;
    final headers = detections
        .where(
          (d) =>
              (d['text_prediction']['text'] as String).replaceAll(
                RegExp(r'\s'),
                '',
              ) ==
              '과목명',
        )
        .toList();
    headers.sort((a, b) {
      double top(dynamic d) => (d['bounding_box']['points'] as List)
          .map((p) => (p['y'] as num).toDouble())
          .reduce(math.min);
      return top(a).compareTo(top(b));
    });
    final headerXs = headers
        .map(
          (d) =>
              (d['bounding_box']['points'] as List)
                  .map((p) => (p['x'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              4,
        )
        .toList();
    final singleColumn =
        headerXs.isNotEmpty &&
        headerXs.reduce(math.max) - headerXs.reduce(math.min) < .25;
    // Cropping the first of several recognized tables would discard later sections.
    final originalPage =
        (jsonDecode(normalizeNvidiaOcr(data)) as Map)['pages'][0];
    final preserveTables =
        headers.length > 1 && originalPage['reportTable'] == true;
    var retryNote = preserveTables
        ? ''
        : '전체 이미지 인식 결과입니다. 표 영역을 확실하게 찾지 못해 확대 재인식을 생략했습니다.';
    if (singleColumn && !preserveTables) {
      final points = headers.first['bounding_box']['points'] as List;
      final top = points
          .map((p) => (p['y'] as num).toDouble())
          .reduce(math.min);
      var bottom = 1.0;
      for (final d in detections) {
        if (!RegExp(r'체육.?예술|교양교과|출석상황')
            .hasMatch(d['text_prediction']['text'])) {
          continue;
        }
        final p = d['bounding_box']['points'] as List;
        final dy = p.map((p) => (p['y'] as num).toDouble()).reduce(math.min);
        if (dy > top + .05) bottom = math.min(bottom, dy);
      }
      if (bottom < 1 && bottom - top > .08) {
        final cropped = await cropOcrTable(
          bytes,
          mime,
          math.max(0, top - .035),
          math.min(1, bottom + .005),
        );
        checkCancellation();
        retryNote = '표 확대 재인식을 준비하지 못했습니다. 전체 이미지 결과를 원본과 대조하세요.';
        if (cropped != null) {
          onProgress?.call('표 영역을 확대해 추가 인식하고 있습니다.');
          retryNote = '표 확대 재인식을 완료하지 못했습니다. 전체 이미지 결과를 원본과 대조하세요.';
          try {
            final retry = await caller.functions.invoke(
              'nemotron-ocr',
              body: cropped,
              headers: {'Content-Type': 'image/jpeg'},
            );
            if (retry.status == 200) {
              final candidate = Map<String, dynamic>.from(retry.data as Map);
              final parsed = jsonDecode(normalizeNvidiaOcr(candidate)) as Map;
              if (parsed['pages'][0]['reportTable'] == true) {
                data = candidate;
                retryNote = '';
              }
            }
          } catch (_) {
            /* Preserve the first result on optional retry failure. */
          }
        }
      }
    }
    checkCancellation();
    final normalized =
        jsonDecode(normalizeNvidiaOcr(data)) as Map<String, dynamic>;
    normalized['pages'][0]['text'] =
        '$originalText\n\n표 영역 재인식:\n${normalized['pages'][0]['text']}';
    normalized['pages'][0]['provider'] = identical(originalData, data)
        ? 'NVIDIA OCR v2 · 전체 이미지'
        : 'NVIDIA OCR v2 · 표 확대 재인식';
    normalized['pages'][0]['warnings'] = retryNote.isEmpty
        ? <String>[]
        : [retryNote];
    if (!identical(originalData, data)) {
      final first = GradeImportParser()
          .parse(
            normalizeNvidiaOcr(originalData),
            kind: StudentDocumentKind.midterm,
            schoolYear: 1,
            semester: 1,
          )
          .result
          .subjects;
      final second = GradeImportParser()
          .parse(
            jsonEncode(normalized),
            kind: StudentDocumentKind.midterm,
            schoolYear: 1,
            semester: 1,
          )
          .result
          .subjects;
      final differences = <String>[];
      if (first.length == second.length) {
        for (var i = 0; i < first.length; i++) {
          final fields = <String>[];
          if (first[i].subjectName != second[i].subjectName) fields.add('과목명');
          if (first[i].credit != second[i].credit) fields.add('학점');
          if (first[i].gradeRank != second[i].gradeRank) fields.add('석차등급');
          if (first[i].achievement != second[i].achievement) fields.add('성취도');
          if (first[i].rawScore != second[i].rawScore) fields.add('원점수');
          if (first[i].subjectAverage != second[i].subjectAverage) {
            fields.add('과목평균');
          }
          if (fields.isNotEmpty) {
            differences.add(
              '${i + 1}번째 과목: 원본 전체와 표 확대 인식의 ${fields.join("·")} 결과가 다릅니다. 원본과 대조해 수정하세요.',
            );
          }
        }
      } else {
        differences.add('전체 사진과 표 확대 인식의 과목 수가 다릅니다. 누락·추가 과목을 원본과 대조하세요.');
      }
      normalized['pages'][0]['warnings'] = differences;
    }
    return jsonEncode(normalized);
  } catch (error) {
    if (error is _NvidiaCancelled) throw StateError('인식을 취소했습니다.');
    throw StateError(
      'NVIDIA 인식에 연결하지 못했습니다. 서버 배포·키 설정과 로그인 상태를 확인하고 잠시 후 다시 시도해 주세요.',
    );
  }
}

class _NvidiaCancelled implements Exception {
  const _NvidiaCancelled();
}

/// Recovery adds labelled suggestions and preserves the original OCR text.
String applyMockGradeRecovery(String normalized, String? recovery) {
  final result = jsonDecode(normalized) as Map<String, dynamic>;
  final page = result['pages'][0] as Map<String, dynamic>;
  final candidates = <String, List<Map<String, dynamic>>>{};
  try {
    final extra = recovery == null ? null : jsonDecode(recovery);
    for (final item in (extra?['recovered'] as List? ?? [])) {
      if (item is! Map ||
          !['영어', '한국사'].contains(item['subject']) ||
          item['grade'] is! int ||
          item['grade'] < 1 ||
          item['grade'] > 9 ||
          item['confidence'] is! num ||
          !(item['confidence'] as num).isFinite ||
          item['confidence'] < 65 ||
          item['confidence'] > 100) {
        continue;
      }
      candidates
          .putIfAbsent(item['subject'] as String, () => [])
          .add(Map<String, dynamic>.from(item));
    }
  } catch (_) {
    candidates.clear();
  }
  final accepted = <Map<String, dynamic>>[];
  for (final values in candidates.values) {
    if (values.map((v) => v['grade']).toSet().length == 1) {
      accepted.add(values.first);
    }
  }
  page['mockGradeRecoveries'] = accepted;
  if (accepted.isNotEmpty) {
    page['text'] =
        '${page['text']}\n\n부분 등급 재인식 (원본 대조 필요):\n${accepted.map((r) => "${r['subject']} 등급: ${r['grade']}").join("\n")}';
    page['provider'] = 'NVIDIA OCR v2 · 누락 등급 로컬 보완';
  }
  page['warnings'] = [
    if (accepted.isNotEmpty) '누락 등급을 기기에서 부분 재인식했습니다. 원본과 대조한 뒤 사용하세요.',
    '영어·한국사 등급은 원본의 괄호 안 숫자와 대조하세요.',
  ];
  return jsonEncode(result);
}
