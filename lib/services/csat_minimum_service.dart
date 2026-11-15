import 'package:univ_pathfinder/models/mock_exam_record.dart';

enum MinimumStatus {
  met('충족 수준'),
  below('미달 수준'),
  insufficient('자료 부족'),
  manual('원문 확인 필요'),
  none('수능 최저 없음');

  const MinimumStatus(this.label);
  final String label;
}

class MockExamSession {
  MockExamSession(this.records);
  final List<MockExamRecord> records;
  MockExamRecord get first => records.first;
  String get id => sessionId(first);
  String get label =>
      '${first.calendarYear}년 ${first.schoolYear}학년 ${first.examMonth}월 · ${first.institution?.trim().isNotEmpty == true ? first.institution!.trim() : "시행기관 미상"}';
  static String sessionId(MockExamRecord r) =>
      '${r.calendarYear}/${r.schoolYear}/${r.examMonth}/${r.institution?.trim() ?? ""}';
}

class MinimumBranch {
  const MinimumBranch(this.label, this.text);
  final String label, text;
  String get id => '$label:$text';
}

class MinimumResult {
  const MinimumResult(
    this.status,
    this.reason, {
    this.details = const [],
    this.shortfall,
  });
  final MinimumStatus status;
  final String reason;
  final List<String> details;
  final double? shortfall;
}

class MinimumRule {
  const MinimumRule({
    required this.areas,
    required this.count,
    required this.limit,
    required this.each,
    this.requiredArea,
    this.historyLimit,
    this.englishLimit,
  });
  final List<String> areas;
  final int count;
  final double limit;
  final bool each;
  final String? requiredArea;
  final int? historyLimit, englishLimit;
}

/// Parses only whole supported sentences. Never discard unknown qualifiers.
class CsatMinimumService {
  List<MockExamSession> sessions(Iterable<MockExamRecord> records) {
    final grouped = <String, List<MockExamRecord>>{};
    for (final r in records) {
      grouped.putIfAbsent(MockExamSession.sessionId(r), () => []).add(r);
    }
    return grouped.values.map(MockExamSession.new).toList()..sort((a, b) {
      final year = b.first.calendarYear.compareTo(a.first.calendarYear);
      if (year != 0) return year;
      final month = b.first.examMonth.compareTo(a.first.examMonth);
      return month != 0 ? month : a.id.compareTo(b.id);
    });
  }

  List<MinimumBranch> branches(String source) {
    final lines = source.split('\n').where((s) => s.trim().isNotEmpty).toList();
    // A footnote may alter every branch; never silently detach it.
    if (lines.length > 1 &&
        lines.any((s) => !s.contains(':') || s.trim().startsWith('※'))) {
      return [MinimumBranch('원문 전체', source.trim())];
    }
    return source.split('\n').where((s) => s.trim().isNotEmpty).map((line) {
      final colon = line.indexOf(':');
      return colon < 0
          ? MinimumBranch('공통 기준', line.trim())
          : MinimumBranch(
              line.substring(0, colon).trim(),
              line.substring(colon + 1).trim(),
            );
    }).toList();
  }

  MinimumRule? parse(String source) {
    var s = source.replaceAll(RegExp(r'\s'), '');
    int? history, english;
    // Ancillary minimums must be explicit and terminal; no unconsumed text allowed.
    for (final area in ['한국사', '영어']) {
      final match = RegExp(
        '(?:및|,)$area'
        r'(\d+)등급이내$',
      ).firstMatch(s);
      if (match != null) {
        final grade = int.parse(match[1]!);
        if (grade < 1 || grade > 9) return null;
        if (area == '한국사') {
          history = grade;
        } else {
          english = grade;
        }
        s = s.substring(0, match.start);
      }
    }
    // An English clause can precede the history clause in the source.
    final eng = RegExp(r'(?:및|,)영어(\d+)등급이내$').firstMatch(s);
    if (eng != null && english == null) {
      english = int.parse(eng[1]!);
      if (english < 1 || english > 9) return null;
      s = s.substring(0, eng.start);
    }
    String? requiredArea;
    final suffix = RegExp(r'\((국어|수학|탐구)(?:필수)?포함\)$').firstMatch(s);
    if (suffix != null) {
      requiredArea = {'국어': '국어', '수학': '수학', '탐구': '탐구'}[suffix[1]];
      s = s.substring(0, suffix.start);
    }
    final prefix = RegExp(r'중(국어|수학|탐구)(?:필수)?포함').firstMatch(s);
    if (prefix != null) {
      if (requiredArea != null) return null;
      requiredArea = prefix[1];
      s = s.replaceRange(prefix.start, prefix.end, '중');
    }
    s = s.replaceAll('통사/통과(상위1과목)', '탐구상위').replaceAll('통사/통과(2과목평균)', '탐구평균');
    final match = RegExp(
      r'^(.+?)(?:중)?(\d+)개(?:영역)?(?:등급)?(?:(?:합|등급합)(\d+)(?:등급)?이내|각(\d+)등급(?:이내)?)$',
    ).firstMatch(s);
    if (match == null) return null;
    var pool = match[1]!;
    if (pool.endsWith('중')) pool = pool.substring(0, pool.length - 1);
    final areas = <String>[];
    const aliases = {
      '국': '국어',
      '수': '수학',
      '영': '영어',
      '한국사': '한국사',
      '통사': '통합사회',
      '통과': '통합과학',
      '탐구상위': '탐구상위',
      '탐구평균': '탐구평균',
    };
    for (final token in pool.split(',')) {
      final area = aliases[token];
      if (area == null || areas.contains(area)) return null;
      areas.add(area);
    }
    final count = int.parse(match[2]!);
    final limit = double.parse(match[3] ?? match[4]!);
    final each = match[4] != null;
    if (count < 1 ||
        count > areas.length ||
        limit < count * (each ? 0 : 1) ||
        limit < 1 ||
        limit > (each ? 9 : count * 9)) {
      return null;
    }
    if (requiredArea != null &&
        !areas.any(
          (a) =>
              a == requiredArea || (requiredArea == '탐구' && a.startsWith('탐구')),
        )) {
      return null;
    }
    return MinimumRule(
      areas: areas,
      count: count,
      limit: limit,
      each: each,
      requiredArea: requiredArea,
      historyLimit: history,
      englishLimit: english,
    );
  }

  MinimumResult evaluate(
    String text,
    MockExamSession? session, {
    bool failed = false,
  }) {
    if (['없음', '적용하지 않음', '수능최저학력기준 미적용'].contains(text.trim())) {
      return const MinimumResult(
        MinimumStatus.none,
        '제공된 전형 자료에 최저 없음으로 표시되어 있습니다. 최종 모집요강은 별도로 확인하세요.',
      );
    }
    final rule = parse(text);
    if (rule == null) {
      return const MinimumResult(
        MinimumStatus.manual,
        '탐구 반영 방식·예외·대체·복합 조건을 자동으로 확정할 수 없습니다. 원문을 확인하세요.',
      );
    }
    if (failed) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '모의고사 조회에 실패했습니다. 다시 조회하세요.',
      );
    }
    if (session == null) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '비교할 모의고사를 등록하거나 시험을 선택하세요.',
      );
    }
    if (session.records.isEmpty) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '선택한 시험에 영역 기록이 없습니다.',
      );
    }
    if (session.records.any(
      (r) => MockExamSession.sessionId(r) != session.id,
    )) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '서로 다른 시험의 성적이 섞여 비교하지 않았습니다.',
      );
    }
    if (session.first.institution?.trim().isNotEmpty != true) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '동일 시험 확인을 위해 시행기관을 등록하세요.',
      );
    }
    if (session.first.calendarYear - session.first.schoolYear != 2024 ||
        session.first.examMonth < 1 ||
        session.first.examMonth > 12 ||
        session.first.schoolYear < 1 ||
        session.first.schoolYear > 3) {
      return const MinimumResult(
        MinimumStatus.insufficient,
        '2028 대입 학년에 해당하는 시험(2025 고1·2026 고2·2027 고3)만 비교합니다. 이전 수능 체계의 등급을 대신 사용하지 않습니다.',
      );
    }
    const aliases = {
      '국어': '국어',
      '수학': '수학',
      '영어': '영어',
      '한국사': '한국사',
      '통합사회': '통합사회',
      '통합과학': '통합과학',
    };
    final grades = <String, List<int?>>{};
    for (final r in session.records) {
      final area = aliases[r.subject.replaceAll(RegExp(r'\s'), '')];
      if (area != null) grades.putIfAbsent(area, () => []).add(r.gradeRank);
    }
    final needed = <String>{
      for (final a in rule.areas)
        ...a.startsWith('탐구') ? ['통합사회', '통합과학'] : [a],
      if (rule.historyLimit != null) '한국사',
      if (rule.englishLimit != null) '영어',
    };
    final missing = needed.where((a) => !grades.containsKey(a)).toList();
    final duplicate = needed
        .where((a) => (grades[a]?.length ?? 0) > 1)
        .toList();
    final invalid = needed
        .where(
          (a) => grades[a]?.any((g) => g == null || g < 1 || g > 9) == true,
        )
        .toList();
    if (missing.isNotEmpty || duplicate.isNotEmpty || invalid.isNotEmpty) {
      return MinimumResult(
        MinimumStatus.insufficient,
        [
          if (missing.isNotEmpty) '${missing.join("·")} 누락',
          if (duplicate.isNotEmpty) '${duplicate.join("·")} 중복',
          if (invalid.isNotEmpty) '${invalid.join("·")} 유효 등급 없음',
        ].join(' / '),
        details: [
          '선택한 시험의 1~9등급과 영역명을 원본과 대조하세요. 통합사회·통합과학은 이름이 명확한 기록만 사용하며 옛 선택탐구로 채우지 않습니다.',
        ],
      );
    }
    double grade(String a) => grades[a]!.single!.toDouble();
    double value(String a) => switch (a) {
      '탐구상위' => grade('통합사회') < grade('통합과학') ? grade('통합사회') : grade('통합과학'),
      '탐구평균' => (grade('통합사회') + grade('통합과학')) / 2,
      _ => grade(a),
    };
    final combinations = <List<String>>[];
    void choose(int start, List<String> current) {
      if (current.length == rule.count) {
        if (rule.requiredArea == null ||
            current.any(
              (a) =>
                  a == rule.requiredArea ||
                  (rule.requiredArea == '탐구' && a.startsWith('탐구')),
            )) {
          combinations.add([...current]);
        }
        return;
      }
      for (var i = start; i < rule.areas.length; i++) {
        choose(i + 1, [...current, rule.areas[i]]);
      }
    }

    choose(0, []);
    double score(List<String> c) => rule.each
        ? c.map(value).reduce((a, b) => a > b ? a : b)
        : c.fold<double>(0, (s, a) => s + value(a));
    combinations.sort((a, b) => score(a).compareTo(score(b)));
    final best = combinations.first;
    final total = score(best);
    final deficits = <String>[];
    if (total > rule.limit) {
      deficits.add(
        rule.each
            ? '선택 영역이 각각 ${rule.limit.toStringAsFixed(0)}등급 이내가 되도록 개선 필요'
            : '등급 합 ${(total - rule.limit).toStringAsFixed(1)} 개선 필요',
      );
    }
    for (final extra in [
      ('한국사', rule.historyLimit),
      ('영어', rule.englishLimit),
    ]) {
      if (extra.$2 != null && grade(extra.$1) > extra.$2!) {
        deficits.add(
          '${extra.$1} ${grade(extra.$1).toStringAsFixed(0)} → ${extra.$2}등급 이내 필요',
        );
      }
    }
    return MinimumResult(
      deficits.isEmpty ? MinimumStatus.met : MinimumStatus.below,
      deficits.isEmpty
          ? '선택한 모의고사 등급이 제공된 조건 범위에 들어갑니다.'
          : deficits.join(' / '),
      shortfall: total > rule.limit ? total - rule.limit : 0,
      details: [
        '선택 영역: ${best.map((a) => "$a ${value(a).toStringAsFixed(value(a) % 1 == 0 ? 0 : 1)}등급").join(" · ")}',
        '${rule.each ? "선택 영역 중 가장 불리한 등급" : "등급 합"} ${total.toStringAsFixed(total % 1 == 0 ? 0 : 1)} / 기준 ${rule.limit.toStringAsFixed(0)} 이내',
        if (rule.historyLimit != null)
          '한국사 ${grade("한국사").toInt()} / ${rule.historyLimit}등급 이내',
        if (rule.englishLimit != null)
          '영어 ${grade("영어").toInt()} / ${rule.englishLimit}등급 이내',
        if (best.contains('탐구평균')) '통합사회·통합과학 평균은 반올림하지 않았습니다.',
        '학년별 모의고사 참고 비교입니다. 실제 수능 충족·합격을 확정하지 않습니다. 최종 모집요강 대조 전입니다.',
      ],
    );
  }
}
