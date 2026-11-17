import 'dart:math' as math;

import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// 상향·적정·안정 판정. 합격 확정이 아니라 과거 입결과의 비교 결과다.
enum PredictionLevel {
  safe('안정'),
  fit('적정'),
  reach('상향'),
  hard('어려움'),
  unknown('판단 보류');

  const PredictionLevel(this.label);
  final String label;
}

enum PredictionKind {
  subject('학생부교과'),
  comprehensive('학생부종합'),
  regular('정시');

  const PredictionKind(this.label);
  final String label;
}

class SusiResult {
  const SusiResult({
    required this.university,
    required this.year,
    required this.type,
    required this.track,
    required this.department,
    required this.quota,
    this.competition,
    this.cut50,
    this.cut70,
    this.cut80,
    this.cut90,
    this.metric,
  });
  final String university, type, track, department;
  final int year;
  final num quota;
  final double? competition, cut50, cut70, cut80, cut90;
  final String? metric;

  factory SusiResult.fromJson(Map<String, dynamic> j) => SusiResult(
    university: j['university'] as String,
    year: j['year'] as int,
    type: j['type'] as String,
    track: j['track'] as String,
    department: j['department'] as String,
    quota: j['quota'] as num,
    competition: (j['competition'] as num?)?.toDouble(),
    cut50: (j['cut50'] as num?)?.toDouble(),
    cut70: (j['cut70'] as num?)?.toDouble(),
    cut80: (j['cut80'] as num?)?.toDouble(),
    cut90: (j['cut90'] as num?)?.toDouble(),
    metric: j['metric'] as String?,
  );
}

class RegularResult {
  const RegularResult({
    required this.university,
    required this.year,
    required this.group,
    required this.department,
    required this.quota,
    this.competition,
    this.convert50,
    this.convert70,
    this.convertTotal,
    this.pctAvg70,
    this.pctAvgMethod,
    this.english70,
  });
  final String university, group, department;
  final int year;
  final num quota;
  final double? competition, convert50, convert70, convertTotal, pctAvg70;
  final String? pctAvgMethod;
  final int? english70;

  factory RegularResult.fromJson(Map<String, dynamic> j) => RegularResult(
    university: j['university'] as String,
    year: j['year'] as int,
    group: j['group'] as String,
    department: j['department'] as String,
    quota: j['quota'] as num,
    competition: (j['competition'] as num?)?.toDouble(),
    convert50: (j['convert50'] as num?)?.toDouble(),
    convert70: (j['convert70'] as num?)?.toDouble(),
    convertTotal: (j['convertTotal'] as num?)?.toDouble(),
    pctAvg70: (j['pctAvg70'] as num?)?.toDouble(),
    pctAvgMethod: j['pctAvgMethod'] as String?,
    english70: (j['english70'] as num?)?.toInt(),
  );
}

class AdmissionResults {
  const AdmissionResults({
    required this.source,
    required this.susi,
    required this.regular,
  });
  final String source;
  final List<SusiResult> susi;
  final List<RegularResult> regular;

  factory AdmissionResults.fromJson(Map<String, dynamic> j) => AdmissionResults(
    source: j['source'] as String? ?? '',
    susi: (j['susi'] as List)
        .map((e) => SusiResult.fromJson(e as Map<String, dynamic>))
        .toList(),
    regular: (j['jeongsi'] as List)
        .map((e) => RegularResult.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Student metrics used for comparison, with the basis spelled out.
class StudentProfile {
  const StudentProfile({
    this.gradeAverage5,
    this.grade9Optimistic,
    this.grade9Conservative,
    this.gradeBasis = '',
    this.mockPercentile,
    this.mockEnglish,
    this.mockLabel,
    this.mockSession,
  });
  final double? gradeAverage5, grade9Optimistic, grade9Conservative;
  final String gradeBasis;
  final double? mockPercentile;
  final int? mockEnglish;
  final String? mockLabel;
  final MockExamSession? mockSession;
  bool get hasGrades => grade9Optimistic != null && grade9Conservative != null;
  bool get hasMock => mockPercentile != null;
}

class AdmissionPrediction {
  const AdmissionPrediction({
    required this.university,
    required this.kind,
    required this.track,
    required this.department,
    required this.level,
    required this.confidence,
    required this.reason,
    required this.evidence,
    this.group,
    this.minimum,
  });
  final String university, track, department;
  final PredictionKind kind;
  final PredictionLevel level;
  final String confidence, reason;
  final List<String> evidence;
  final String? group;

  /// 2028 전형 자료의 수능 최저 원문(모집단위별 행이 있으면 그 행). 정시는 null.
  final String? minimum;

  AdmissionPrediction withMinimum(String? text) => AdmissionPrediction(
    university: university,
    kind: kind,
    track: track,
    department: department,
    level: level,
    confidence: confidence,
    reason: reason,
    evidence: evidence,
    group: group,
    minimum: text,
  );

  /// 판정 사유 끝에 설명을 덧붙인다(판정·신뢰도는 그대로).
  AdmissionPrediction withNotes(Iterable<String> notes) => notes.isEmpty
      ? this
      : AdmissionPrediction(
          university: university,
          kind: kind,
          track: track,
          department: department,
          level: level,
          confidence: confidence,
          reason: '$reason · ${notes.join(" · ")}',
          evidence: evidence,
          group: group,
          minimum: minimum,
        );

  /// 비교 근거의 한계(예: 교과 성적 산출 방식 변경)를 밝히고 신뢰도를 한 단계 낮춘다.
  AdmissionPrediction withCaution(Iterable<String> notes) {
    if (notes.isEmpty) return this;
    const levels = ['낮음', '보통', '높음'];
    final i = levels.indexOf(confidence);
    return AdmissionPrediction(
      university: university,
      kind: kind,
      track: track,
      department: department,
      level: level,
      confidence: i <= 0 ? confidence : levels[i - 1],
      reason: '$reason · ${notes.join(" · ")}',
      evidence: evidence,
      group: group,
      minimum: minimum,
    );
  }
}

/// 공식 자료로 확인한 과거 전형명 변경(assets/data/admission_aliases.json).
class TrackAlias {
  const TrackAlias({
    required this.university,
    required this.fromYear,
    required this.from,
    required this.toYear,
    required this.to,
    required this.apply,
    this.change = '',
    this.exceptDepartments = const [],
    this.departments = const [],
    this.block = false,
    this.caution = false,
  });

  /// 비어 있지 않으면 block·caution을 이 학과에만 적용한다
  /// (예: 같은 전형에서 약학과만 수능 최저가 새로 생긴 경우).
  final List<String> departments;

  /// true면 이름이 같은 전형을 계속 잇되, [fromYear] 이전 입결은 근거 한계(교과 성적 산출 방식 변경 등)를
  /// 사유에 밝히고 신뢰도를 한 단계 낮춘다.
  final bool caution;

  /// true면 이름이 같아도 [fromYear] 이전 입결을 잇지 않는다(유형·선발 방법이 바뀐 같은 이름 전형).
  final bool block;
  final String university, from, to, change;
  final int fromYear, toYear;

  /// 이 학과들은 묶지 않는다(예: 해당 학과만 수능 최저가 생겼거나 다른 전형으로 옮겨 간 경우).
  final List<String> exceptDepartments;

  /// false면 근거가 부족하거나 선발 방법이 바뀌어 묶지 않는다(기록만).
  final bool apply;

  factory TrackAlias.fromJson(Map<String, dynamic> j) => TrackAlias(
    university: j['university'] as String,
    fromYear: j['fromYear'] as int,
    from: j['from'] as String,
    toYear: j['toYear'] as int,
    to: j['to'] as String,
    apply: j['apply'] as bool? ?? false,
    change: j['change'] as String? ?? '',
    block: j['block'] as bool? ?? false,
    caution: j['caution'] as bool? ?? false,
    exceptDepartments: [
      for (final d in j['exceptDepartments'] as List? ?? const []) d as String,
    ],
    departments: [
      for (final d in j['departments'] as List? ?? const []) d as String,
    ],
  );
}

class AdmissionAliases {
  const AdmissionAliases({this.tracks = const []});
  final List<TrackAlias> tracks;
  factory AdmissionAliases.fromJson(Map<String, dynamic> j) => AdmissionAliases(
    tracks: [
      for (final t in j['tracks'] as List? ?? const [])
        TrackAlias.fromJson(t as Map<String, dynamic>),
    ],
  );
}

/// 수시 예측 한 건의 수능 최저 판정과 적용한 기준.
class MinimumCheck {
  const MinimumCheck(this.result, {this.branch, this.byField = false});
  final MinimumResult result;

  /// 학과명이 아니라 학생이 고른 계열로 기준을 정했는지. 대학마다 계열 분류가 달라 확인이 필요하다.
  final bool byField;

  /// 원문이 계열·모집단위별로 나뉠 때 적용한 기준 이름.
  final String? branch;
}

typedef ConversionFor = Map<String, double> Function(MockExamSession session);

class AdmissionPredictionService {
  static const susiMargin = {
    PredictionKind.subject: 0.3,
    PredictionKind.comprehensive: 0.5,
  };
  static const regularBand = 3.0;

  static final _special = RegExp(
    r'농어촌|기회균형|기회균등|특성화|재직자|장애|특수교육|사회배려|사회통합|국가보훈|보훈|서해|북한|기초생활|차상위|한부모|다문화|고른기회|사배자|만학도|군위탁|체육특기|특기자|실기|예체능|이웃사랑|소외|저소득|배려대상|교육기회배려|지역의사|계약학과|국방|배려자|사회기여|고운사회|지역의료|정원\s*외|목회자|지도자|어울림|사회공헌|밝은사회|군사학과',
  );

  String compact(String s) =>
      s.replaceAll(RegExp(r'[\s·ㆍ・]'), '').toLowerCase();

  static const _generic = {'공통기준', '전모집단위', '그외', '그외모집단위', '나머지모집단위'};
  static final _fieldLabel = RegExp(r'인문|자연|계열|자유|예술|체육|예체능');

  /// 수시 예측의 수능 최저를 같은 모의고사로 판정한다.
  /// 원문이 모집단위·계열별로 나뉘면 학과명 앞부분 일치 → 학생이 고른 계열 → "그 외"류 순으로
  /// 한 기준만 정해질 때 적용하고, 정해지지 않으면 원문 확인 필요로 둔다(관심 분야로 추정하지 않는다).
  MinimumCheck checkMinimum(
    AdmissionPrediction p,
    MockExamSession? session, {
    String? field,
    bool failed = false,
  }) {
    final service = CsatMinimumService();
    final text = p.minimum?.trim() ?? '';
    if (p.kind == PredictionKind.regular) {
      return const MinimumCheck(
        MinimumResult(MinimumStatus.none, '정시는 수능 최저를 적용하지 않습니다.'),
      );
    }
    if (text.isEmpty) {
      return const MinimumCheck(
        MinimumResult(
          MinimumStatus.manual,
          '2028 전형 자료에 수능 최저 정보가 없습니다. 모집요강을 확인하세요.',
        ),
      );
    }
    final branches = service.branches(text);
    MinimumCheck apply(
      MinimumBranch b, {
      bool labeled = true,
      bool byField = false,
    }) => MinimumCheck(
      service.evaluate(b.text, session, failed: failed),
      branch: labeled ? b.label : null,
      byField: byField,
    );
    if (branches.length == 1 &&
        const {'공통 기준', '원문 전체'}.contains(branches.single.label)) {
      return apply(branches.single, labeled: false);
    }
    List<String> tokens(MinimumBranch b) => b.label
        .split(RegExp(r'[/,·ㆍ]'))
        .map(compact)
        .where((t) => t.isNotEmpty)
        .toList();
    final dept = compact(p.department);
    final byDept = branches
        .where(
          (b) => tokens(b).any(
            (t) => t.length >= 2 && !_generic.contains(t) && dept.startsWith(t),
          ),
        )
        .toList();
    if (byDept.length == 1) return apply(byDept.single);
    if (byDept.isEmpty && field != null) {
      final byField = branches
          .where((b) => tokens(b).any((t) => t == field || t == '$field계열'))
          .toList();
      if (byField.length == 1) return apply(byField.single, byField: true);
    }
    if (byDept.isEmpty) {
      final generic = branches
          .where((b) => tokens(b).any(_generic.contains))
          .toList();
      final fieldSplit = branches.any(
        (b) => !generic.contains(b) && _fieldLabel.hasMatch(b.label),
      );
      if (generic.length == 1 && !fieldSplit) return apply(generic.single);
    }
    return MinimumCheck(
      MinimumResult(
        MinimumStatus.manual,
        '기준이 ${branches.map((b) => b.label).join(" · ")}별로 나뉩니다. '
        '${field == null ? "계열을 선택하거나 " : ""}원문에서 지원 모집단위의 기준을 확인하세요.',
      ),
    );
  }

  /// Track name without notes in parentheses that describe a year or selection detail, and without "전형".
  String trackKey(String name) {
    final base = compact(name)
        // 표 제목의 "[수시]" 같은 구분 접두어와 "*일부 학과의 경우…" 같은 끝 주석은 전형명이 아니다.
        // 서울대처럼 괄호 없이 "수시지역균형전형"으로 쓴 경우도 같다.
        .replaceFirst(RegExp(r'^\[?(?:수시|정시)(?:모집)?\]?'), '')
        .replaceFirst(RegExp(r'\*.*$'), '')
        // 학년도·선발 인원·단계 같은 주석 괄호만 지운다. "(지역균형선발)"처럼 전형명 자체인 괄호는 남긴다.
        .replaceAll(
          RegExp(r'\((?:20\d{2}[^)]*|[^)]*(?:선발인원|미선발|단계|반영|인원|없음)[^)]*)\)'),
          '',
        )
        .replaceAll(RegExp(r'\((?:가|나|다)군\)|(?:가|나|다)군'), '')
        .replaceAll('(정원외)', '')
        .replaceAll('전형', '');
    final key = base
        // 유형 이름은 괄호·줄표가 뒤따르거나 이름 전체일 때만 뗀다. "학생부교과우수자"는
        // "학생부 교과우수자"(→ 교과우수자)이지 "학생부교과 + 우수자"가 아니다.
        .replaceFirst(RegExp(r'^(?:학생부교과|학생부종합)(?=[(\-–—_:]|$)|^학생부'), '')
        // 단국대 "학생부종합전형–DKU인재(서류형)"처럼 유형과 전형명 사이의 줄표.
        .replaceFirst(RegExp(r'^[-–—_:]+'), '')
        .replaceAll(RegExp(r'[()]'), '');
    // "학생부종합전형"처럼 유형 이름만 있으면 유형 이름을 키로 쓴다(빈 키로 서로 섞이지 않게).
    return key.isNotEmpty ? key : base.replaceAll(RegExp(r'[()]'), '');
  }

  /// 5등급 내신 → 9등급 대응 구간 (교육청 공개 대응표, 근사).
  StudentProfile profile({
    required List<GradeRecord> confirmedGrades,
    required Map<String, dynamic> comparisonData,
    MockExamSession? mock,
  }) {
    const kinds = ['semesterSummary', 'finalExam', 'midterm'];
    List<GradeRecord> chosen = const [];
    String basis = '';
    for (final kind in kinds) {
      final rows = confirmedGrades
          .where(
            (r) =>
                r.examKind == kind &&
                r.gradeRank != null &&
                r.gradeRank! >= 1 &&
                r.gradeRank! <= 5 &&
                r.credit.isFinite &&
                r.credit > 0,
          )
          .toList();
      if (rows.isNotEmpty) {
        chosen = rows;
        basis = switch (kind) {
          'semesterSummary' => '학기 종합 성적',
          'finalExam' => '기말고사 성적(학기 종합 없음)',
          _ => '중간고사 성적(학기 종합·기말 없음)',
        };
        break;
      }
    }
    double? avg, low, high;
    if (chosen.isNotEmpty) {
      final credits = chosen.fold<double>(0, (s, r) => s + r.credit);
      avg =
          chosen.fold<double>(0, (s, r) => s + r.gradeRank! * r.credit) /
          credits;
      final nodes =
          ((comparisonData['bridge'] as Map?)?['nineGradeByRankSum'] as List?)
              ?.map((v) => (v as num).toDouble())
              .toList();
      if (nodes != null && nodes.length == 25) {
        final lo = (avg * 6 - 6 + 1e-8).floor().clamp(0, 24);
        final hi = (avg * 6 - 6 - 1e-8).ceil().clamp(0, 24);
        low = nodes[lo];
        high = nodes[hi];
      }
      basis =
          '$basis ${chosen.length}과목 학점가중 5등급 평균 ${avg.toStringAsFixed(2)} → 9등급 대응 ${low?.toStringAsFixed(2)}~${high?.toStringAsFixed(2)} (교육청 공개 대응표 근사)';
    }
    double? pct;
    int? english;
    if (mock != null) {
      double? p(String s) {
        final rows = mock.records.where((r) => r.subject.trim() == s);
        if (rows.length != 1) return null;
        final v = rows.single.percentile;
        return v != null && v >= 0 && v <= 100 ? v : null;
      }

      final k = p('국어'), m = p('수학'), so = p('통합사회'), sc = p('통합과학');
      if (k != null && m != null && so != null && sc != null) {
        pct = (k + m + (so + sc) / 2) / 3;
      }
      final e = mock.records.where((r) => r.subject.trim() == '영어');
      english = e.length == 1 ? e.single.gradeRank : null;
    }
    return StudentProfile(
      gradeAverage5: avg,
      grade9Optimistic: low,
      grade9Conservative: high,
      gradeBasis: basis,
      mockPercentile: pct,
      mockEnglish: english,
      mockLabel: mock?.label,
      mockSession: mock,
    );
  }

  /// 관심 분야 학과의 입결이 있는 대학인데, 2028 교과·종합 전형 중 과거 입결과 이어지지 않아
  /// 예측에서 빠진 전형(신설·통합·이름 변경 미확인). 판단 보류 사유와 함께 보여 주기 위한 목록.
  /// [note]는 대응표에 기록된 변경 내용(있을 때만).
  List<({String university, String track, String type, String? note})>
  untrackedTracks({
    required List<AdmissionPrediction> predictions,
    required AdmissionResults results,
    required AdmissionCatalog catalog,
    required String interest,
    required bool Function(String text, String interest) matches,
    AdmissionAliases? aliases,
    bool includeSpecial = false,
  }) {
    final relevant = {
      for (final r in results.susi)
        if (matches(r.department, interest)) r.university,
    };
    final predicted = {
      for (final p in predictions)
        if (p.kind != PredictionKind.regular)
          '${p.university}|${trackKey(p.track)}',
    };
    // 같은 2028 전형에 여러 항목(묶음·경고·끊음)이 있으면 판단 보류의 직접 이유인 끊음(block)의 사유를 쓴다.
    final notes = <String, String>{};
    final fromBlock = <String>{};
    for (final a in aliases?.tracks ?? const <TrackAlias>[]) {
      final k = '${a.university}|${trackKey(a.to)}';
      if (fromBlock.contains(k) && !a.block) continue;
      notes[k] = a.change;
      if (a.block) fromBlock.add(k);
    }
    final seen = <String>{};
    final out =
        <({String university, String track, String type, String? note})>[];
    for (final t in catalog.tracks) {
      if (t.type != '학생부교과' && t.type != '학생부종합') continue;
      if (!includeSpecial && _special.hasMatch(t.name)) continue;
      // predict()처럼 캠퍼스 표기를 뗀 이름으로도 입결 대학을 찾는다(한국외대(서울)·(글로벌) → 한국외대).
      final base = t.university.replaceAll(RegExp(r'\((서울|글로벌)\)$'), '');
      final university = relevant.contains(t.university)
          ? t.university
          : relevant.contains(base)
          ? base
          : null;
      if (university == null) continue;
      final key = '$university|${trackKey(t.name)}';
      if (predicted.contains(key) || !seen.add(key)) continue;
      out.add((
        university: university,
        track: t.name,
        type: t.type,
        note: notes[key],
      ));
    }
    return out;
  }

  List<AdmissionPrediction> predict({
    required AdmissionResults results,
    required AdmissionCatalog catalog,
    required StudentProfile student,
    required String interest,
    required bool Function(String text, String interest) matches,
    Map<String, ConversionFor> conversions = const {},
    bool includeSpecial = false,
    AdmissionAliases? aliases,
  }) {
    final out = <AdmissionPrediction>[];
    // 2028 tracks per university, keyed by normalized name → catalog type.
    final offered = <String, Map<String, ({String type, String name})>>{};
    // 수능 최저 원문: 모집단위 없는 일반 행과 모집단위별 행(의약계열 등)을 따로 둔다.
    final generalMinimum = <String, String>{};
    final deptMinimum = <String, String>{};
    for (final t in catalog.tracks) {
      // 수시 비교용: 교과·종합만 넣는다. "일반전형"(종합)과 "일반전형 (나군)"(수능)처럼
      // 군 표기를 떼면 키가 같아져 수능위주가 덮어쓰는 일을 막는다.
      if (t.type != '학생부교과' && t.type != '학생부종합') continue;
      final base = t.university.replaceAll(RegExp(r'\((서울|글로벌)\)$'), '');
      for (final u in {t.university, base}) {
        (offered[u] ??= {})[trackKey(t.name)] = (type: t.type, name: t.name);
        final key = '$u|${trackKey(t.name)}';
        if (t.department.trim().isEmpty) {
          generalMinimum.putIfAbsent(key, () => t.minimum);
        } else {
          deptMinimum.putIfAbsent(
            '$key|${compact(t.department)}',
            () => t.minimum,
          );
        }
      }
    }
    // 공식 근거로 확인한 전형명 변경만 같은 전형으로 묶는다(apply=true).
    // 이름은 같지만 유형·선발 방법이 바뀌어 잇지 않는 전형(block).
    final blocked = [
      for (final a in aliases?.tracks ?? const <TrackAlias>[])
        if (a.block) a,
    ];
    final cautions = [
      for (final a in aliases?.tracks ?? const <TrackAlias>[])
        if (a.caution) a,
    ];
    final renamed = {
      for (final a in aliases?.tracks ?? const <TrackAlias>[])
        if (a.apply && !a.block) '${a.university}|${trackKey(a.from)}': a,
    };
    TrackAlias? aliasOf(SusiResult r) {
      final a = renamed['${r.university}|${trackKey(r.track)}'];
      if (a == null) return null;
      final d = departmentKey(r.department);
      return a.exceptDepartments.any((x) => departmentKey(x) == d) ? null : a;
    }

    String tk(SusiResult r) {
      final a = aliasOf(r);
      return a == null ? trackKey(r.track) : trackKey(a.to);
    }

    // block·caution 항목이 이 입결 행에 해당하는지(대학·연도·전형, 학과 지정 시 학과까지).
    bool hits(TrackAlias a, SusiResult r) =>
        a.university == r.university &&
        r.year <= a.fromYear &&
        // 이름 변경으로 묶인 옛 전형명 입결도 새 이름 기준으로 끊는다.
        {trackKey(r.track), tk(r)}.contains(trackKey(a.from)) &&
        (a.departments.isEmpty ||
            a.departments.any(
              (d) => departmentKey(d) == departmentKey(r.department),
            ));

    String? minimumFor(SusiResult r) {
      final key = '${r.university}|${tk(r)}';
      final dept = compact(r.department);
      final exact = deptMinimum['$key|$dept'];
      if (exact != null) return exact;
      // 2028 번들의 모집단위명이 입결 학과명과 조금 다를 때(예: 한의예과(자연)) 앞부분 일치만 허용.
      final near = deptMinimum.entries
          .where((e) => e.key.startsWith('$key|'))
          .where((e) {
            final d = e.key.substring(key.length + 1);
            return d.startsWith(dept) || dept.startsWith(d);
          })
          .map((e) => e.value)
          .toSet();
      if (near.length == 1) return near.single;
      return generalMinimum[key];
    }

    // 수시: group by university + track + department (학과명 변경은 departmentKey로 묶음).
    final susi = <String, List<SusiResult>>{};
    for (final r in results.susi) {
      if (!matches(r.department, interest)) continue;
      if (!includeSpecial && _special.hasMatch(r.track)) continue;
      if (blocked.any((a) => hits(a, r))) continue;
      final offer = offered[r.university]?[tk(r)];
      if (offer == null) continue;
      // 입결 전형명에 특별자격 표시가 없어도 2028 전형명에 있으면 뺀다.
      // 예: 세종대 입결 "학생부교과(항공시스템공학특별전형)" → 2028 "항공시스템공학특별전형 (정원 외)".
      if (!includeSpecial && _special.hasMatch(offer.name)) continue;
      final type = offer.type;
      if (type != '학생부교과' && type != '학생부종합') continue;
      // 입결 행의 유형이 알려져 있고 2028 전형 유형과 다르면(교과↔종합) 이름이 같아도 잇지 않는다.
      // 예: 한양대(서울) 2025 학생부종합(추천형) ↛ 2028 학생부교과 추천형전형.
      if ((r.type == '학생부교과' || r.type == '학생부종합') && r.type != type) {
        continue;
      }
      susi
          .putIfAbsent(
            '${r.university}|${tk(r)}|${departmentKey(r.department)}',
            () => [],
          )
          .add(r);
    }
    for (final rows in _splitAmbiguous(
      susi.values,
      (r) => r.year,
      (r) => r.department,
    )) {
      rows.sort((a, b) => b.year.compareTo(a.year));
      final latest = rows.first;
      final track = offered[latest.university]![tk(latest)]!;
      final aliasNotes = {
        for (final r in rows)
          if (aliasOf(r) case final a?)
            '${a.fromYear} 전형명 "${a.from}"을 ${a.toYear} "${a.to}"와 같은 전형으로 묶음(대학 공개 변경사항 근거${a.change == '없음' ? '' : ', ${a.change}'})',
      };
      out.add(
        _susi(
          rows,
          track.type == '학생부교과'
              ? PredictionKind.subject
              : PredictionKind.comprehensive,
          student,
          trackName: track.name,
        ).withMinimum(minimumFor(latest)).withNotes(aliasNotes).withCaution({
          for (final a in cautions)
            if (rows.any((r) => hits(a, r)))
              '${a.fromYear}학년도까지 입결 뒤 ${a.change}: 같은 기준의 성적 비교가 아니어서 신뢰도 한 단계 낮춤',
        }),
      );
    }

    // 정시: group by university + 군 + department (학과명 변경은 departmentKey로 묶음).
    final regular = <String, List<RegularResult>>{};
    for (final r in results.regular) {
      if (!matches(r.department, interest)) continue;
      regular
          .putIfAbsent(
            '${r.university}|${r.group}|${departmentKey(r.department)}',
            () => [],
          )
          .add(r);
    }
    for (final rows in _splitAmbiguous(
      regular.values,
      (r) => r.year,
      (r) => r.department,
    )) {
      out.add(_regular(rows, student, conversions[rows.first.university]));
    }
    return out;
  }

  /// 해마다 표기만 바뀐 같은 모집단위를 묶는 키.
  /// 띄어쓰기·가운뎃점·주간 표기 "(주)"·끝의 단위(학과·학부·전공·과·부)만 무시한다.
  /// 괄호 안 전공명은 남긴다(예: 디자인학과(시각디자인전공) ≠ 디자인학과(산업디자인전공)).
  String departmentKey(String department) =>
      compact(department)
          .replaceAll('(주)', '')
          // 끝 주석 표시(*)와 구분 기호(하이픈·밑줄·여러 종류의 가운뎃점)는 표기 차이다.
          .replaceFirst(RegExp(r'\*+$'), '')
          .replaceAll(RegExp(r'[\-_.,‧․∙•]'), '')
          // 괄호 기호만 지우고 안의 전공명은 남긴다: "경영학과-○○전공" = "경영학과(○○전공)",
          // "디자인학과(시각디자인전공)" ≠ "디자인학과(산업디자인전공)".
          .replaceAll(RegExp(r'[()]'), '')
          .replaceFirst(RegExp(r'(학과|학부|전공|과|부)$'), '')
          // "공학과"→"공", "공학전공"→"공학"이 어긋나지 않도록 끝의 "학"도 뗀다.
          .replaceFirst(RegExp(r'학$'), '');

  /// 같은 키로 묶였어도 한 해 안에 서로 다른 학과명이 둘 이상이면 묶지 않고 원래 이름대로 나눈다.
  Iterable<List<T>> _splitAmbiguous<T>(
    Iterable<List<T>> groups,
    int Function(T) year,
    String Function(T) department,
  ) sync* {
    for (final rows in groups) {
      final names = <int, Set<String>>{};
      for (final r in rows) {
        (names[year(r)] ??= {}).add(department(r));
      }
      if (names.values.every((s) => s.length == 1)) {
        yield rows;
        continue;
      }
      final byName = <String, List<T>>{};
      for (final r in rows) {
        (byName[department(r)] ??= []).add(r);
      }
      yield* byName.values;
    }
  }

  /// 해별 근거에 붙이는 "당시 학과명" 표시(최근 이름과 다를 때만).
  String _formerName(String department, String latest) =>
      department == latest ? '' : ' · 당시 $department';

  /// 학과명이 바뀐 해가 있으면 사유 끝에 붙이는 설명.
  String? _renameNote(Iterable<String> names, String latest) {
    final former = names.where((n) => n != latest).toSet();
    return former.isEmpty
        ? null
        : '학과명 변경(${former.join(", ")} → $latest)을 같은 모집단위로 묶음';
  }

  /// 해마다 움직인 폭 기준(한 단계 낮춤, '낮음'). 2024·2025 실제 입결 분포에서 정했다:
  /// 수시 70%컷 변동 상위 25% ≈ 0.5등급·상위 10% ≈ 1.0등급, 정시 같은 방식 백분위 상위 25% ≈ 5점·상위 10% ≈ 10점.
  static const susiSwing = (0.5, 1.0);
  static const regularSwing = (5.0, 10.0);

  /// 환산점수는 총점 대비 비율(2%, 4%).
  static const convertSwing = (0.02, 0.04);

  /// 앱이 학생 점수와 같은 공식(국·수·탐 평균)으로 계산한 입결 백분위.
  static const appPercentileMethod = '국·수·탐(평균) 70% cut 백분위의 평균(앱 계산)';

  /// 가장 이른 해와 가장 최근 해의 차이가 기준 이상이면 설명을 돌려준다.
  ({bool big, String note})? _swing(
    Iterable<(int, double?)> byYear, {
    required double step,
    required double big,
    required String unit,
    required String label,
    int digits = 2,
  }) {
    final v = byYear.where((e) => e.$2 != null).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    if (v.length < 2 || v.first.$1 == v.last.$1) return null;
    final d = (v.last.$2! - v.first.$2!).abs();
    if (d < step) return null;
    return (
      big: d >= big,
      note:
          '${v.first.$1}→${v.last.$1} $label ${d.toStringAsFixed(digits)}$unit 변동',
    );
  }

  double? _mean(Iterable<double?> v) {
    final x = v.whereType<double>().toList();
    return x.isEmpty ? null : x.reduce((a, b) => a + b) / x.length;
  }

  AdmissionPrediction _susi(
    List<SusiResult> rows,
    PredictionKind kind,
    StudentProfile s, {
    required String trackName,
  }) {
    rows.sort((a, b) => b.year.compareTo(a.year));
    final first = rows.first;
    final c50 = _mean(rows.map((r) => r.cut50));
    final c70 = _mean(rows.map((r) => r.cut70));
    final loose = _mean(rows.map((r) => r.cut80 ?? r.cut90));
    final evidence = [
      for (final r in rows)
        '${r.year}학년도${_formerName(r.department, first.department)} · 모집 ${r.quota}명${r.competition != null ? " · 경쟁률 ${r.competition}" : ""} · '
            '${r.cut50 != null ? "${r.metric ?? "50%컷"} ${r.cut50} · " : ""}'
            '${r.cut70 != null ? "70%컷 ${r.cut70}" : ""}'
            '${r.cut70 == null && (r.cut80 ?? r.cut90) != null ? "${r.cut80 != null ? 80 : 90}%컷 ${r.cut80 ?? r.cut90}" : ""}',
    ];
    var confidence = kind == PredictionKind.subject ? 2 : 1; // 2 높음, 1 보통, 0 낮음
    final notes = <String>[];
    if (rows.length < 2) {
      confidence--;
      notes.add('한 해 입결만 있음');
    }
    if (rows.any((r) => r.quota <= 3)) {
      confidence = 0;
      notes.add('소수 모집(3명 이하)');
    }
    if (rows.any(
      (r) => r.cut50 != null && r.cut70 != null && r.cut50! > r.cut70! + 0.01,
    )) {
      confidence = 0;
      notes.add('50%컷이 70%컷보다 불리한 역전');
    }
    final metrics = rows
        .where((r) => r.cut50 != null)
        .map((r) => r.metric ?? '50%컷')
        .toSet();
    if (metrics.length > 1) {
      confidence--;
      notes.add('해마다 공개 지표가 다름(${metrics.join("·")})');
    }
    final swing = _swing(
      rows.map((r) => (r.year, r.cut70 ?? r.cut50)),
      step: susiSwing.$1,
      big: susiSwing.$2,
      unit: '등급',
      label: rows.every((r) => r.cut70 != null) ? '70%컷' : '컷',
    );
    if (swing != null) {
      confidence = swing.big ? 0 : confidence - 1;
      notes.add(swing.note);
    }
    if (kind == PredictionKind.comprehensive) {
      notes.add('종합전형은 정성평가라 등급만으로 판단하기 어려움');
    }
    final renamed = _renameNote(
      rows.map((r) => r.department),
      first.department,
    );
    if (renamed != null) notes.add(renamed);
    PredictionLevel level;
    String reason;
    if (!s.hasGrades) {
      level = PredictionLevel.unknown;
      reason = '원본 대조가 확인된 내신 등급이 없어 비교하지 않았습니다.';
    } else if (c70 == null && c50 == null && loose == null) {
      level = PredictionLevel.unknown;
      reason = '공개된 등급 컷이 없습니다.';
    } else {
      final lo = s.grade9Optimistic!, hi = s.grade9Conservative!;
      final margin = susiMargin[kind]!;
      if (c70 != null) {
        if (c50 != null && hi <= c50) {
          level = PredictionLevel.safe;
        } else if (hi <= c70) {
          level = PredictionLevel.fit;
        } else if (lo <= c70 + margin) {
          level = PredictionLevel.reach;
        } else {
          level = PredictionLevel.hard;
        }
        reason =
            '내 9등급 대응 ${lo.toStringAsFixed(2)}~${hi.toStringAsFixed(2)} vs '
            '${c50 != null ? "50%컷 평균 ${c50.toStringAsFixed(2)}, " : ""}70%컷 평균 ${c70.toStringAsFixed(2)}';
      } else if (c50 != null) {
        level = hi <= c50
            ? PredictionLevel.fit
            : (lo <= c50 + margin
                  ? PredictionLevel.reach
                  : PredictionLevel.hard);
        confidence = math.min(confidence, 0);
        notes.add('70%컷 미공개, 50%컷만으로 판단');
        reason =
            '내 9등급 대응 ${lo.toStringAsFixed(2)}~${hi.toStringAsFixed(2)} vs 50%컷 평균 ${c50.toStringAsFixed(2)}';
      } else {
        level = lo <= loose! ? PredictionLevel.reach : PredictionLevel.hard;
        confidence = 0;
        notes.add('80·90%컷만 공개되어 상향 여부만 판단');
        reason =
            '내 9등급 대응 ${lo.toStringAsFixed(2)}~${hi.toStringAsFixed(2)} vs 하위 컷 평균 ${loose.toStringAsFixed(2)}';
      }
    }
    notes.add('5등급 내신을 9등급 입결과 비교한 근사치');
    return AdmissionPrediction(
      university: first.university,
      kind: kind,
      track: trackName,
      department: first.department,
      level: level,
      confidence: const ['낮음', '보통', '높음'][confidence.clamp(0, 2)],
      reason: '$reason. ${notes.join(" · ")}',
      evidence: evidence,
    );
  }

  AdmissionPrediction _regular(
    List<RegularResult> rows,
    StudentProfile s,
    ConversionFor? conversion,
  ) {
    rows.sort((a, b) => b.year.compareTo(a.year));
    final first = rows.first;
    final evidence = [
      for (final r in rows)
        '${r.year}학년도 ${r.group}${_formerName(r.department, first.department)} · 모집 ${r.quota}명${r.competition != null ? " · 경쟁률 ${r.competition}" : ""}'
            '${r.convert70 != null ? " · 환산 70%컷 ${r.convert70}${r.convertTotal != null ? "/${r.convertTotal!.toStringAsFixed(0)}" : ""}" : ""}'
            '${r.pctAvg70 != null ? " · 70%컷 평균 백분위 ${r.pctAvg70}(${r.pctAvgMethod == appPercentileMethod ? "국·수·탐 앱 계산" : "대학 공개"})" : ""}'
            '${r.english70 != null ? " · 영어 ${r.english70}등급" : ""}',
    ];
    var confidence = rows.length >= 2 ? 2 : 1;
    final notes = <String>['모의고사 성적과 실제 수능은 다를 수 있음'];
    final renamed = _renameNote(
      rows.map((r) => r.department),
      first.department,
    );
    if (renamed != null) notes.add(renamed);
    if (rows.any((r) => r.quota <= 3)) {
      confidence = 0;
      notes.add('소수 모집(3명 이하)');
    }
    if (!s.hasMock) {
      return AdmissionPrediction(
        university: first.university,
        kind: PredictionKind.regular,
        track: '정시 수능',
        department: first.department,
        group: first.group,
        level: PredictionLevel.unknown,
        confidence: '낮음',
        reason: '같은 시험의 국어·수학·통합사회·통합과학 백분위가 있는 모의고사가 없어 비교하지 않았습니다.',
        evidence: evidence,
      );
    }
    PredictionLevel? level;
    String reason = '';
    // 환산점수 우선: 같은 총점 척도의 예시 산식이 있을 때만.
    if (conversion != null && s.mockSession != null) {
      final total = rows.first.convertTotal;
      final scores = conversion(s.mockSession!);
      final natural = RegExp(
        r'공학|과학|의예|의학|약학|간호|수학|물리|화학|생명|컴퓨터|소프트|전자|전기|기계|건축|인공지능|데이터|반도체|ai',
        caseSensitive: false,
      ).hasMatch(first.department);
      final sameScale = scores.entries.where((e) {
        final m = RegExp(r'\(([\d,]+)점').firstMatch(e.key);
        return m != null &&
            total != null &&
            double.parse(m[1]!.replaceAll(',', '')) == total;
      }).toList();
      final pick = sameScale.length == 1
          ? sameScale.single
          : sameScale
                .where((e) => e.key.contains(natural ? '자연' : '인문'))
                .firstOrNull;
      final c70 = _mean(
        rows.where((r) => r.convertTotal == total).map((r) => r.convert70),
      );
      final c50 = _mean(
        rows.where((r) => r.convertTotal == total).map((r) => r.convert50),
      );
      if (pick != null && c70 != null) {
        final v = pick.value;
        final band = total! * 0.01;
        level = c50 != null && v >= c50
            ? PredictionLevel.safe
            : v >= c70
            ? PredictionLevel.fit
            : v >= c70 - band
            ? PredictionLevel.reach
            : PredictionLevel.hard;
        reason =
            '내 환산점수(${pick.key}) ${v.toStringAsFixed(2)} vs ${c50 != null ? "50%컷 평균 ${c50.toStringAsFixed(2)}, " : ""}70%컷 평균 ${c70.toStringAsFixed(2)}';
        notes.add('2028 산식으로 계산한 내 점수를 과거 학년도 산식의 컷과 비교(산식 변경 가능)');
        confidence = math.min(confidence, 1);
        final swing = _swing(
          rows
              .where((r) => r.convertTotal == total)
              .map((r) => (r.year, r.convert70)),
          step: total * convertSwing.$1,
          big: total * convertSwing.$2,
          unit: '점',
          label: '환산 70%컷',
        );
        if (swing != null) {
          confidence = swing.big ? 0 : confidence - 1;
          notes.add(swing.note);
        }
      }
    }
    if (level == null) {
      // 학생 점수와 같은 공식(국·수·탐 평균)으로 낸 해만 비교한다. 대학 공개 평균은 반영 영역이 다를 수 있어 섞지 않는다.
      final withPct = rows.where((r) => r.pctAvg70 != null).toList();
      final same = withPct
          .where((r) => r.pctAvgMethod == appPercentileMethod)
          .toList();
      final used = same.isNotEmpty ? same : withPct;
      if (same.isNotEmpty && same.length < withPct.length) {
        notes.add('대학 공개 평균 백분위인 해는 반영 영역이 달라 비교에서 뺌');
      }
      if (same.isEmpty && withPct.isNotEmpty) {
        confidence--;
        notes.add('대학 공개 평균 백분위는 반영 영역이 앱 계산(국·수·탐)과 다를 수 있음');
      }
      if (used.map((r) => r.year).toSet().length < 2 && rows.length >= 2) {
        confidence = math.min(confidence, 1);
      }
      final ref = _mean(used.map((r) => r.pctAvg70));
      final swing = _swing(
        used.map((r) => (r.year, r.pctAvg70)),
        step: regularSwing.$1,
        big: regularSwing.$2,
        unit: '점',
        label: '70%컷 백분위',
        digits: 1,
      );
      if (swing != null) {
        confidence = swing.big ? 0 : confidence - 1;
        notes.add(swing.note);
      }
      if (ref == null) {
        level = PredictionLevel.unknown;
        reason = '70%컷 백분위가 공개되지 않았습니다.';
        confidence = 0;
      } else {
        final p = s.mockPercentile!;
        level = p >= ref + regularBand
            ? PredictionLevel.safe
            : p >= ref
            ? PredictionLevel.fit
            : p >= ref - regularBand
            ? PredictionLevel.reach
            : PredictionLevel.hard;
        reason =
            '내 국·수·탐 평균 백분위 ${p.toStringAsFixed(1)} vs 70%컷 평균 백분위 ${ref.toStringAsFixed(1)}';
      }
    }
    final eng = _mean(rows.map((r) => r.english70?.toDouble()));
    if (s.mockEnglish != null &&
        eng != null &&
        s.mockEnglish! >= eng + 2 &&
        level.index < PredictionLevel.hard.index) {
      level = PredictionLevel.values[level.index + 1];
      notes.add('영어 등급이 입결보다 2등급 이상 낮아 한 단계 낮춤');
    }
    return AdmissionPrediction(
      university: first.university,
      kind: PredictionKind.regular,
      track: '정시 수능',
      department: first.department,
      group: first.group,
      level: level,
      confidence: const ['낮음', '보통', '높음'][confidence.clamp(0, 2)],
      reason: '$reason. ${notes.join(" · ")}',
      evidence: evidence,
    );
  }
}
