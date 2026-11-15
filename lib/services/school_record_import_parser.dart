import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/models/grade_scope.dart';
import 'package:univ_pathfinder/models/school_record_import.dart';

class _Token {
  _Token(Map w)
    : text = w['text'] as String,
      x = (w['x'] as num).toDouble(),
      y = (w['y'] as num).toDouble(),
      width = (w['w'] as num).toDouble();
  final String text;
  final double x, y, width;
  double get center => x + width / 2;
}

/// Only recognized curriculum tables and narrative sections become candidates.
/// Identity sections and page furniture are never exposed as source text.
class SchoolRecordImportParser {
  String compact(String s) => s.replaceAll(RegExp(r'\s'), '');
  String clean(String s) => s
      .replaceAll(RegExp(r'\d{6}\s*[-–]\s*[1-4]\d{6}'), '[식별정보 제거]')
      .replaceAll(RegExp(r'01[016789][- .]?\d{3,4}[- .]?\d{4}'), '[연락처 제거]')
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[이메일 제거]');

  SchoolRecordImport parse(List pages) {
    final grades = <SchoolGradeCandidate>[];
    final evidence = <SchoolEvidenceCandidate>[];
    final warnings = <String>{'추출 후보입니다. 연도·학년과 개인정보를 포함해 원본을 대조한 뒤 저장하세요.'};
    int? year;
    var narrative = false;
    String? category;
    SchoolEvidenceCandidate? active;
    void flush() {
      if (active != null && active!.text.trim().length > 12) {
        evidence.add(active!);
      }
      active = null;
    }

    for (final page in pages) {
      final pageNumber = page['page'];
      final scale = 595 / ((page['width'] as num?)?.toDouble() ?? 595);
      final lines = (page['lines'] as List? ?? [])
          .cast<Map>()
          .map(
            (line) => {
              ...line,
              'words': [
                for (final w in (line['words'] as List? ?? []).cast<Map>())
                  {
                    ...w,
                    for (final key in ['x', 'y', 'w', 'h'])
                      key: ((w[key] as num?) ?? 0) * scale,
                  },
              ],
            },
          )
          .toList();
      final all = lines
          .expand((l) => (l['words'] as List? ?? []).cast<Map>())
          .map(_Token.new)
          .toList();
      if (all.isEmpty) continue;
      final height = page['height'] is num
          ? (page['height'] as num).toDouble() * scale
          : 842.0;
      final footerLines = lines.where((l) {
        final t = compact(l['text'] as String? ?? '');
        return RegExp(r'\d{1,2}/\d{1,2}').hasMatch(t) &&
            t.contains('번호') &&
            t.contains('이름');
      }).toList();
      final footerY = footerLines.isEmpty
          ? height * .85
          : (((footerLines.first['words'] as List).first as Map)['y'] as num)
                    .toDouble() -
                4;
      final body = lines.where((l) {
        final ws = (l['words'] as List? ?? []).cast<Map>();
        if (ws.isEmpty) return false;
        final y = (ws.first['y'] as num).toDouble();
        return y > height * .105 && y < footerY && y < height * .85;
      }).toList();
      // A new grade marker may follow a continuation from the previous year.
      for (var i = 0; i < body.length; i++) {
        final line = body[i];
        final text = (line['text'] as String? ?? '');
        final c = compact(text);
        if (c == '창의적체험활동상황' ||
            c == '특기사항' ||
            RegExp(r'(이름|성명|학번|주민등록번호)[:：]').hasMatch(c) ||
            c.contains('전자정부') ||
            c.contains('위·변조')) {
          continue;
        }
        final marker = RegExp(r'^\[([1-3])학년\]$').firstMatch(c);
        if (marker != null) {
          flush();
          year = int.parse(marker[1]!);
          narrative = false;
          category = null;
          continue;
        }
        if (c.contains('이수학점합계') || c.startsWith('※')) {
          flush();
          narrative = false;
          continue;
        }
        if (c.contains('학기') && c.contains('학점') && c.contains('과목')) {
          flush();
          narrative = false;
          if (c.contains('성취도별') && year != null) {
            final header = (line['words'] as List)
                .cast<Map>()
                .map(_Token.new)
                .toList();
            double? col(String s) {
              for (final w in header) {
                if (compact(w.text) == s) return w.center;
              }
              return null;
            }

            final sx = col('과목'),
                cx = col('학점'),
                ax = col('성취도'),
                dx = col('성취도별');
            if (sx != null && cx != null && ax != null && dx != null) {
              final hy = (header.first.y);
              final end = body
                  .skip(i + 1)
                  .where(
                    (l) =>
                        compact(l['text'] as String).contains('이수학점合計') ||
                        compact(l['text'] as String).contains('이수학점합계'),
                  )
                  .firstOrNull;
              final ey = end == null
                  ? height * .85
                  : (((end['words'] as List).first as Map)['y'] as num)
                        .toDouble();
              final ws = all.where((w) => w.y > hy + 12 && w.y < ey).toList();
              final creditWords =
                  ws
                      .where(
                        (w) =>
                            (w.center - cx).abs() < 12 &&
                            RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(w.text),
                      )
                      .toList()
                    ..sort((a, b) => a.y.compareTo(b.y));
              final semX = col('학기');
              final rankHeaders = all
                  .where(
                    (w) =>
                        (w.y - hy).abs() < 16 &&
                        ['석차', '등급', '석차등급'].contains(compact(w.text)) &&
                        w.center > dx,
                  )
                  .toList();
              final rankX = rankHeaders.isEmpty
                  ? null
                  : rankHeaders.first.center;
              final semesterWords = ws
                  .where(
                    (w) =>
                        semX != null &&
                        (w.center - semX).abs() < 12 &&
                        RegExp(r'^[12]$').hasMatch(w.text),
                  )
                  .toList();
              for (var r = 0; r < creditWords.length; r++) {
                final anchor = creditWords[r];
                final top = r == 0
                    ? anchor.y - 12
                    : (creditWords[r - 1].y + anchor.y) / 2;
                final bottom = r == creditWords.length - 1
                    ? anchor.y + 12
                    : (anchor.y + creditWords[r + 1].y) / 2;
                final row = ws.where((w) => w.y >= top && w.y < bottom).toList()
                  ..sort(
                    (a, b) => (a.y - b.y).abs() < 4
                        ? a.x.compareTo(b.x)
                        : a.y.compareTo(b.y),
                  );
                String cell(double left, double right) => row
                    .where((w) => w.center > left && w.center < right)
                    .map((w) => w.text)
                    .join(' ');
                final name = cell(sx - (cx - sx) * .7, (sx + cx) / 2).trim();
                if (name.isEmpty || GradeScope.isExcludedSubject(name)) {
                  continue;
                }
                final score = cell(
                  (cx + (cx + ax) / 2) / 2,
                  ((cx + ax) / 2 + ax) / 2,
                ).replaceAll(' ', '').replaceAll(',', '.');
                final m = RegExp(r'^(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)$')
                    .firstMatch(score);
                if (m == null) {
                  warnings.add('$pageNumber쪽: 점수 열을 확인하지 못한 행은 자동 추출하지 않았습니다.');
                  continue;
                }
                final raw = double.parse(m[1]!);
                final average = double.parse(m[2]!);
                if (raw > 100 || average > 100) {
                  warnings.add(
                    '$pageNumber쪽 · $name: 점수의 소수점이 불명확합니다. 빈 점수 칸을 원본과 대조해 입력하세요.',
                  );
                }
                final near = semesterWords.toList()
                  ..sort(
                    (a, b) => (a.y - anchor.y).abs().compareTo(
                      (b.y - anchor.y).abs(),
                    ),
                  );
                final rankWords = row
                    .where(
                      (w) =>
                          rankX != null &&
                          (w.center - rankX).abs() < 12 &&
                          (w.y - anchor.y).abs() < 7,
                    )
                    .toList();
                final rankText = rankWords.map((w) => w.text).join();
                final rank = int.tryParse(rankText);
                final achievement = cell(
                  ((cx + ax) / 2 + ax) / 2,
                  (ax + dx) / 2,
                ).trim();
                grades.add(
                  SchoolGradeCandidate(
                    grade: GradeDraft(
                      schoolYear: year,
                      semester: near.isEmpty
                          ? null
                          : int.tryParse(near.first.text),
                      subjectName: name,
                      credit: double.tryParse(anchor.text.replaceAll(',', '.')),
                      rawScore: raw <= 100 ? raw : null,
                      subjectAverage: average <= 100 ? average : null,
                      achievement: RegExp(r'^[A-E]$').hasMatch(achievement)
                          ? achievement
                          : null,
                      gradeRank: rank != null && rank >= 1 && rank <= 5
                          ? rank
                          : null,
                    ),
                    source: '$pageNumber쪽 · 교과학습발달상황 · ${r + 1}행',
                  ),
                );
              }
            }
          }
          continue;
        }
        if (c.contains('과목') && c.contains('세부능력') && c.contains('특기사항')) {
          narrative = true;
          category = '세부능력 및 특기사항';
          continue;
        }
        if (c.contains('영역') && c.contains('특기사항')) {
          flush();
          narrative = true;
          category = '창의적 체험활동';
          continue;
        }
        if (c.contains('행동특성') && c.contains('종합의견')) {
          flush();
          narrative = true;
          category = '행동특성 및 종합의견';
          continue;
        }
        if (RegExp(r'^\d+\.').hasMatch(c) ||
            c.startsWith('<') ||
            c.contains('봉사활동실적')) {
          flush();
          narrative = false;
          category = null;
          continue;
        }
        if (!narrative || category == null) continue;
        if (c.contains('공공기관의정보공개') ||
            c.contains('당해학년도') ||
            c.contains('해당학년도') ||
            c.contains('제공하지않')) {
          flush();
          narrative = false;
          warnings.add('$pageNumber쪽: 당해 연도 미제공 안내는 활동 근거에서 제외했습니다.');
          continue;
        }
        final tokens = (line['words'] as List)
            .cast<Map>()
            .map(_Token.new)
            .toList();
        // Drop left table labels (year/area/hours) from creative/behavior prose.
        final content = category == '창의적 체험활동'
            ? tokens.where((w) => w.x > 190).map((w) => w.text).join(' ')
            : category == '행동특성 및 종합의견'
            ? tokens.where((w) => w.x > 75).map((w) => w.text).join(' ')
            : text;
        if (content.trim().isEmpty) continue;
        var subject = RegExp(r'^([^:：]{1,55})[:：]\s*(.*)$').firstMatch(content);
        if (subject == null && content.startsWith('진로와 직업 ')) {
          subject = RegExp(r'^(진로와 직업)\s+(.*)$').firstMatch(content);
        }
        if (subject != null && category == '세부능력 및 특기사항') {
          flush();
          active = SchoolEvidenceCandidate(
            category: '세특 · ${clean(subject[1]!)}',
            text: clean(subject[2]!),
            source: '$pageNumber쪽 · 세부능력 및 특기사항',
            schoolYear: year,
          );
        } else if (active != null) {
          active!.text += ' ${clean(content)}';
          if (!active!.source.contains('$pageNumber쪽')) {
            active!.source += ' / $pageNumber쪽';
          }
        } else {
          active = SchoolEvidenceCandidate(
            category: category,
            text: clean(content),
            source: '$pageNumber쪽 · $category',
            schoolYear: category == '세부능력 및 특기사항' ? year : null,
          );
        }
      }
    }
    flush();
    if (grades.isEmpty) {
      warnings.add('학기 종합 표를 읽지 못했습니다. 원본 표 형식·학년 표기를 확인하세요.');
    }
    return SchoolRecordImport(
      grades: grades,
      evidence: evidence,
      warnings: warnings.toList(),
    );
  }
}
