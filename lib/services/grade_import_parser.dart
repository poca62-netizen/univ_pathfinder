import 'package:univ_pathfinder/models/mock_exam_draft.dart';
import 'package:univ_pathfinder/services/mock_exam_import_parser.dart';
import 'package:univ_pathfinder/models/grade_scope.dart';
import 'package:univ_pathfinder/models/school_record_import.dart';
import 'package:univ_pathfinder/services/school_record_import_parser.dart';

import 'dart:convert';

import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';

class ImportPreview {
  const ImportPreview({
    required this.result,
    required this.rawText,
    required this.warnings,
    required this.pageCount,
    required this.usedOcr,
    this.canStoreGrades = false,
    this.engine = '브라우저 로컬 인식',
    this.recognizedMockGrades = const {},
    this.mockExamImport,
    this.schoolRecordImport,
  });
  final ExtractionResult result;
  final String rawText;
  final List<String> warnings;
  final int pageCount;
  final bool usedOcr;
  final bool canStoreGrades;
  final String engine;
  final Map<String, int> recognizedMockGrades;
  final MockExamImportResult? mockExamImport;
  final SchoolRecordImport? schoolRecordImport;
}

class _Word {
  _Word(Map<String, dynamic> json)
    : text = json['text'] as String,
      x = (json['x'] as num).toDouble(),
      width = (json['w'] as num).toDouble(),
      confidence = (json['confidence'] as num?)?.toDouble() ?? 100;
  final String text;
  final double x, width;
  final double confidence;
  double get center => x + width / 2;
}

class _Column {
  const _Column(this.field, this.center);
  final String field;
  final double center;
}

/// Conservative, header/position-based parser. Never guesses values or credit.
class GradeImportParser {
  ImportPreview parse(
    String json, {
    required StudentDocumentKind kind,
    required int schoolYear,
    required int semester,
  }) {
    final pages = (jsonDecode(json) as Map<String, dynamic>)['pages'] as List;
    if (kind == StudentDocumentKind.schoolRecord) {
      final school = SchoolRecordImportParser().parse(pages);
      return ImportPreview(
        result: const ExtractionResult(subjects: []),
        rawText: '',
        warnings: school.warnings,
        pageCount: pages.length,
        usedOcr: pages.any((p) => p['method'] == 'ocr'),
        schoolRecordImport: school,
      );
    }
    final text = pages.map((p) => '[${p['page']}쪽]\n${p['text']}').join('\n\n');
    final warnings = <String>[];
    for (final page in pages) {
      if (page['warnings'] is List) {
        warnings.addAll((page['warnings'] as List).whereType<String>());
      }
    }
    final mockImport = kind == StudentDocumentKind.mockExam
        ? MockExamImportParser().parse(pages)
        : null;
    if (mockImport != null) warnings.addAll(mockImport.warnings);
    final drafts = <GradeDraft>[];
    final compactText = text.replaceAll(RegExp(r'\s'), '');
    var canStoreGrades = false;
    if (kind == StudentDocumentKind.mockExam ||
        kind == StudentDocumentKind.schoolRecord) {
      warnings.add('이 자료는 내신에 저장하지 않습니다. 전용 검토 화면에서 원본을 대조한 뒤 저장하세요.');
    } else if (kind == StudentDocumentKind.semesterSummary ||
        (compactText.contains('중간고사') && compactText.contains('기말고사'))) {
      warnings.add(
        '중간·기말·수행평가가 합산된 학기 종합표입니다. 현재 이 형식의 자동 성적 추출은 지원하지 않습니다. 개별 시험 점수와 합산 성적을 섞지 않도록 자동 저장을 차단했습니다. 원본을 보며 직접 입력해 주세요.',
      );
    } else if (RegExp(r'백분위|표준점수|전국연합학력평가|대학수학능력시험|모의고사')
        .hasMatch(compactText)) {
      warnings.add('모의고사로 보이는 지표를 발견했습니다. 자료 종류를 확인하세요. 내신으로 자동 저장하지 않습니다.');
    } else if (RegExp(r'9등급(제|체계)').hasMatch(compactText)) {
      warnings.add('9등급 체계 자료는 현재 5등급 내신 DB와 호환되지 않습니다. 자동 저장을 중단했습니다.');
    } else {
      canStoreGrades = true;
      for (final page in pages) {
        List<_Column>? columns;
        var embeddedCredit = false;
        var includedSection = true;
        final report =
            page['reportTable'] == true ||
            (page['text'] as String)
                .replaceAll(RegExp(r'\s'), '')
                .contains('성적통지표');
        final compactPage = (page['text'] as String).replaceAll(
          RegExp(r'\s'),
          '',
        );
        final printedYear = int.tryParse(
          RegExp(r'([1-3])학년(?!도)').firstMatch(compactPage)?[1] ?? '',
        );
        final printedSemester = int.tryParse(
          RegExp(r'([12])학기').firstMatch(compactPage)?[1] ?? '',
        );
        if ((printedYear != null && printedYear != schoolYear) ||
            (printedSemester != null && printedSemester != semester)) {
          warnings.add('원문에서 읽은 학년·학기가 선택한 값과 다릅니다. 과목별 학년·학기를 원본과 대조하세요.');
        }
        final lines = page['lines'] as List;
        for (var i = 0; i < lines.length; i++) {
          final words = (lines[i]['words'] as List)
              .map((w) => _Word(Map<String, dynamic>.from(w as Map)))
              .toList();
          final lineText = words.map((w) => w.text).join(' ');
          if (GradeScope.isExcludedSection(lineText)) {
            includedSection = false;
            columns = null;
            continue;
          }
          if (GradeScope.isIncludedSection(lineText)) {
            includedSection = true;
            columns = null;
            continue;
          }
          if (!includedSection) continue;
          final header = _header(words);
          if (header != null) {
            columns = header;
            final headerText = words
                .map((w) => w.text)
                .join()
                .replaceAll(RegExp(r'\s'), '');
            embeddedCredit =
                report ||
                headerText.contains('만점') &&
                    (headerText.contains('받은점수') || headerText.contains('합계'));
            continue;
          }
          // Headers such as 원점수 / 과목평균 may wrap onto a second line.
          if (columns == null && i + 1 < lines.length) {
            final next = (lines[i + 1]['words'] as List)
                .map((w) => _Word(Map<String, dynamic>.from(w as Map)))
                .toList();
            final combined = _header(
              [...words, ...next]..sort((a, b) => a.x.compareTo(b.x)),
            );
            if (combined != null) {
              columns = combined;
              final headerText = [
                ...words,
                ...next,
              ].map((w) => w.text).join().replaceAll(RegExp(r'\s'), '');
              embeddedCredit =
                  report ||
                  headerText.contains('만점') &&
                      (headerText.contains('받은점수') ||
                          headerText.contains('합계'));
              i++;
              continue;
            }
          }
          if (columns == null || words.isEmpty) continue;
          final cells = <String, List<String>>{};
          for (final word in words) {
            var nearest = columns.first;
            for (final col in columns.skip(1)) {
              if ((col.center - word.center).abs() <
                  (nearest.center - word.center).abs()) {
                nearest = col;
              }
            }
            cells.putIfAbsent(nearest.field, () => []).add(word.text);
          }
          String cell(String field) => (cells[field] ?? []).join(' ').trim();
          var subject = cell('subject');
          if (GradeScope.isExcludedSubject(subject)) continue;
          if (subject.isEmpty ||
              !RegExp(r'[가-힣A-Za-z]').hasMatch(subject) ||
              RegExp(r'합계|평균|과목명|이수단위|출결|학적|행동특성|총점').hasMatch(subject)) {
            continue;
          }
          if (words.any((w) => w.confidence < 70)) {
            warnings.add('$subject: 인식 신뢰도가 낮은 글자가 있습니다. 원본 대조가 필요합니다.');
          }
          final metrics = cells.entries
              .where((e) => e.key != 'subject' && e.key != 'ignore')
              .map((e) => e.value.join())
              .join();
          if (!RegExp(r'[0-9A-E]').hasMatch(metrics)) continue;
          double? number(String v) {
            final clean = v.replaceAll(' ', '');
            if (clean.isEmpty || clean == '-' || clean == '—') return null;
            final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)(?:\([^)]*\))?$')
                .firstMatch(clean);
            return m == null ? null : double.tryParse(m[1]!);
          }

          final pair = cell('scoreAverage').replaceAll(' ', '').split('/');
          final achievementMatch = RegExp(r'^([A-EP])(?:\s*\([^)]*\))?$')
              .firstMatch(cell('achievement'));
          final rankText = cell('rank').replaceAll(' ', '');
          final rank = RegExp(r'^\d+$').hasMatch(rankText)
              ? int.tryParse(rankText)
              : null;
          final raw =
              number(cell('score')) ??
              (pair.length == 2 ? number(pair[0]) : null);
          final average =
              number(cell('average')) ??
              (pair.length == 2 ? number(pair[1]) : null);
          var credit = number(cell('credit'));
          if ((raw != null && (raw < 0 || raw > 100)) ||
              (average != null && (average < 0 || average > 100))) {
            warnings.add(
              '$subject: 점수 또는 평균이 0~100 범위를 벗어났습니다. 소수점·표 선 오인식을 원본과 대조해 수정하세요.',
            );
          }
          if (embeddedCredit) {
            final match = RegExp(r'^(.+?)\s*[(（]\s*(\d+(?:\.\d+)?)?\s*[)）]$')
                .firstMatch(subject.trim());
            if (match != null) {
              subject = match[1]!.trim().replaceAll(RegExp(r'\s+'), ' ');
              final suffixCredit = double.tryParse(match[2] ?? '');
              if (credit != null &&
                  suffixCredit != null &&
                  credit != suffixCredit) {
                warnings.add('$subject: 학점 열과 과목명 괄호의 학점이 다릅니다. 원본을 확인하세요.');
              }
              credit ??= suffixCredit;
              if (suffixCredit != null) {
                warnings.add(
                  '과목명 끝 괄호의 숫자를 학점으로 분리했습니다. 과목명 안의 숫자는 그대로 보존하며 등급으로 사용하지 않습니다.',
                );
              }
            }
          }
          if (cell('achievement').isNotEmpty &&
              cell('achievement') != '-' &&
              achievementMatch == null) {
            warnings.add('$subject: 성취도 인식값을 확인하세요 (${cell('achievement')}).');
          }
          if (cell('subjectScore').isNotEmpty &&
              !columns.any((c) => c.field == 'score')) {
            warnings.add('$subject: 과목점수는 원점수와 구분합니다. 원점수·성취도는 원본을 보고 확인하세요.');
          }
          if (credit == null) {
            warnings.add(
              '$subject: 학점/단위를 확인하지 못했습니다. 원본을 보고 입력해야 저장할 수 있습니다.',
            );
          }
          for (final entry in {
            '원점수': cell('score'),
            '과목평균': cell('average'),
            '석차등급': cell('rank'),
          }.entries) {
            if (entry.value.isNotEmpty &&
                entry.value != '-' &&
                (entry.key == '석차등급'
                    ? rank == null
                    : number(entry.value) == null)) {
              warnings.add(
                '$subject: ${entry.key}의 인식값을 확인하세요 (${entry.value}).',
              );
            }
          }
          if (rank != null && rank > 5) {
            warnings.add(
              '$subject: 석차등급 $rank 은 현재 DB의 1~5 범위 밖입니다. 자료 체계를 확인하세요.',
            );
          }
          drafts.add(
            GradeDraft(
              schoolYear:
                  int.tryParse(cell('year')) ?? printedYear ?? schoolYear,
              semester:
                  int.tryParse(cell('semester')) ?? printedSemester ?? semester,
              subjectName: subject,
              credit: credit,
              rawScore: raw,
              subjectAverage: average,
              achievement: achievementMatch?[1],
              gradeRank: rank,
            ),
          );
        }
      }
      if (drafts.isEmpty) {
        warnings.add(
          '과목과 점수 열을 확실하게 구분하지 못했습니다. 추출 원문을 확인하고 과목을 직접 추가하거나 PDF 이미지 인식을 다시 시도하세요.',
        );
      }
    }
    return ImportPreview(
      mockExamImport: mockImport,
      recognizedMockGrades: kind == StudentDocumentKind.mockExam
          ? {
              for (final page in pages)
                for (final r in (page['mockGradeRecoveries'] as List? ?? []))
                  if (r is Map &&
                      ['영어', '한국사'].contains(r['subject']) &&
                      r['grade'] is int &&
                      r['grade'] >= 1 &&
                      r['grade'] <= 9)
                    r['subject'] as String: r['grade'] as int,
            }
          : const {},
      result: ExtractionResult(subjects: drafts),
      rawText: text,
      warnings: warnings.toSet().toList(),
      pageCount: pages.length,
      usedOcr: pages.any((p) => p['method'] == 'ocr'),
      canStoreGrades: canStoreGrades,
      engine: pages.isNotEmpty && pages.first['provider'] is String
          ? pages.first['provider'] as String
          : '브라우저 로컬 인식',
    );
  }

  String? _field(String raw) {
    final text = raw.replaceAll(RegExp(r'\s'), '');
    if (text == '과목' || text == '과목명') return 'subject';
    if (RegExp(r'^(이수)?(학점|단위)(수)?$').hasMatch(text)) return 'credit';
    if (RegExp(r'^원점수(?:/과목평균|\(과목평균\))(?:\(표준편차\))?$').hasMatch(text)) {
      return 'scoreAverage';
    }
    if (text == '원점수') return 'score';
    if (text == '과목점수') return 'subjectScore';
    if (RegExp(r'^과목평균(?:\(표준편차\))?$').hasMatch(text)) return 'average';
    if (RegExp(r'^성취도(?:\(수강자수\))?$').hasMatch(text)) return 'achievement';
    if (text == '석차등급' || text == '등급') return 'rank';
    if (text == '학년') return 'year';
    if (text == '학기') return 'semester';
    if (RegExp(
      r'^(교과|구분|만점|받은점수|합계|고사/영역명(?:\(반영비율\))?|반영비율|수강자수|비고|표준편차|성취도별분포비율|성취도분포|석차\(동석차수\)|동석차수)$',
    ).hasMatch(text)) {
      return 'ignore';
    }
    return null;
  }

  List<_Column>? _header(List<_Word> words) {
    final cols = <_Column>[];
    for (var i = 0; i < words.length; i++) {
      String? field;
      var end = i;
      for (var n = 1; n <= 4 && i + n <= words.length; n++) {
        final candidate = _field(
          words.sublist(i, i + n).map((w) => w.text).join(),
        );
        if (candidate != null) {
          field = candidate;
          end = i + n - 1;
        }
      }
      if (field != null) {
        cols.add(
          _Column(field, (words[i].x + words[end].x + words[end].width) / 2),
        );
        i = end;
      }
    }
    final fields = cols.map((c) => c.field).toSet();
    if (!fields.contains('subject') ||
        !fields.any(
          (f) => const [
            'credit',
            'score',
            'scoreAverage',
            'subjectScore',
            'achievement',
            'average',
            'rank',
          ].contains(f),
        )) {
      return null;
    }
    return cols..sort((a, b) => a.center.compareTo(b.center));
  }
}
