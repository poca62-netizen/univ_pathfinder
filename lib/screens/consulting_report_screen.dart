import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/reference_results.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/services/application_portfolio_service.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';
import 'package:univ_pathfinder/services/percentile_csat_conversions.dart';
import 'package:univ_pathfinder/services/record_evidence_summary.dart';
import 'package:univ_pathfinder/services/report_html.dart';
import 'package:univ_pathfinder/services/report_print.dart';
import 'package:univ_pathfinder/services/snu_csat_conversion.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:univ_pathfinder/services/yonsei_csat_conversion.dart';

/// 성적·관심 분야로 대학 목록을 전형별 안정·적정·상향으로 나눠 보여주는 진학 컨설팅 리포트.
class ConsultingReportScreen extends StatefulWidget {
  const ConsultingReportScreen({
    super.key,
    this.loadSummary,
    this.loadResults,
    this.loadCatalog,
    this.loadComparison,
    this.loadTuition,
    this.loadAliases,
    this.loadReference,
    this.printHtml,
  });

  /// 테스트에서 주입. 기본은 브라우저 인쇄 창(웹이 아니면 false).
  final bool Function(String html)? printHtml;
  final Future<CounselingSummary> Function()? loadSummary;
  final Future<AdmissionResults> Function()? loadResults;
  final Future<AdmissionCatalog> Function()? loadCatalog;
  final Future<Map<String, dynamic>> Function()? loadComparison;
  final Future<TuitionCatalog> Function()? loadTuition;
  final Future<AdmissionAliases> Function()? loadAliases;

  /// 참고 입결(예측에 쓰지 않음). 없어도 리포트는 된다.
  final Future<ReferenceResults> Function()? loadReference;

  @override
  State<ConsultingReportScreen> createState() => _ConsultingReportState();
}

class _ConsultingReportState extends State<ConsultingReportScreen> {
  final _interest = TextEditingController();
  final _service = AdmissionPredictionService();
  final _recommend = UniversityRecommendationService();
  final _minimum = CsatMinimumService();
  CounselingSummary? _summary;
  AdmissionResults? _results;
  AdmissionAliases? _aliases;
  ReferenceResults? _reference;
  AdmissionCatalog? _catalog;
  Map<String, dynamic>? _comparison;
  TuitionCatalog? _tuition;
  String? _error, _mockId;
  bool _loading = true;
  List<AdmissionPrediction>? _predictions;
  StudentProfile? _student;

  /// 수능 최저 기준이 계열별로 나뉠 때만 쓰는 학생 선택(인문·자연). 관심 분야로 추정하지 않는다.
  String? _field;
  Map<AdmissionPrediction, MinimumCheck> _checks = const {};
  SusiSplit _split = SusiSplit.balanced;

  /// null이면 생기부 근거 조회 실패.
  RecordEvidenceSummary? _records;

  /// 관심 분야 대학의 2028 교과·종합 전형 중 과거 입결과 이어지지 않은 것(판단 보류).
  List<({String university, String track, String type, String? note})>
  _untracked = const [];

  static final _priority = UniversityRecommendationService.defaultPriority
      .split(',');
  static int rank(String university) {
    final i = _priority.indexOf(university);
    return i < 0 ? _priority.length : i;
  }

  static final Map<String, ConversionFor> _conversions = {
    '연세대(서울)': yonseiCsatComponents,
    '서울대': snuCsatComponents,
    '가톨릭대': catholicCsatComponents,
    '인천대': incheonCsatComponents,
    '상명대(서울)': sangmyungCsatComponents,
    '동덕여대': dongdukCsatComponents,
    '명지대': myongjiCsatComponents,
    '삼육대': sahmyookCsatComponents,
    '경기대': kyonggiCsatComponents,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _interest.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object?>([
        (widget.loadSummary ?? CounselingSummaryService().fetch)(),
        (widget.loadResults ??
            () async => AdmissionResults.fromJson(
              jsonDecode(
                await rootBundle.loadString(
                  'assets/data/admission_results.json',
                ),
              ) as Map<String, dynamic>,
            ))(),
        (widget.loadCatalog ?? _recommend.loadCatalog)(),
        (widget.loadComparison ?? _recommend.loadComparison)(),
        (widget.loadTuition ?? _recommend.loadTuition)()
            .then<TuitionCatalog?>((v) => v)
            .catchError((_) => null),
        // 전형명 변경 대응표는 없어도 예측은 된다(묶지 않을 뿐).
        (widget.loadAliases ??
                () async => AdmissionAliases.fromJson(
                  jsonDecode(
                    await rootBundle.loadString(
                      'assets/data/admission_aliases.json',
                    ),
                  ) as Map<String, dynamic>,
                ))()
            .then<AdmissionAliases?>((v) => v)
            .catchError((_) => null),
        // 판단 보류 전형에 붙이는 대학 공개 입결(참고용). 없어도 리포트는 된다.
        (widget.loadReference ??
                () async => ReferenceResults.fromJson(
                  jsonDecode(
                    await rootBundle.loadString(
                      'assets/data/admission_reference_results.json',
                    ),
                  ) as Map<String, dynamic>,
                ))()
            .then<ReferenceResults?>((v) => v)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as CounselingSummary;
        _results = values[1] as AdmissionResults;
        _catalog = values[2] as AdmissionCatalog;
        _comparison = values[3] as Map<String, dynamic>;
        _tuition = values[4] as TuitionCatalog?;
        _aliases = values[5] as AdmissionAliases?;
        _reference = values[6] as ReferenceResults?;
        final sessions = _sessions;
        _mockId = sessions.isEmpty ? null : sessions.first.id;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '성적 또는 입결 자료를 불러오지 못했습니다. 다시 시도하세요.';
        });
      }
    }
  }

  List<MockExamSession> get _sessions =>
      _summary == null || _summary!.mockExams.failed
      ? const []
      : _minimum.sessions(_summary!.mockExams.records);

  void _run() {
    final summary = _summary, results = _results, catalog = _catalog;
    if (summary == null || results == null || catalog == null) return;
    final mock = _sessions.where((s) => s.id == _mockId).firstOrNull;
    final student = _service.profile(
      confirmedGrades: summary.grades.failed
          ? const []
          : summary.confirmedGrades,
      comparisonData: _comparison ?? const {},
      mock: mock,
    );
    final predictions = _service.predict(
      results: results,
      catalog: catalog,
      student: student,
      interest: _interest.text,
      matches: _recommend.matches,
      conversions: _conversions,
      aliases: _aliases,
    );
    setState(() {
      _student = student;
      _predictions = predictions;
      _untracked = _service.untrackedTracks(
        predictions: predictions,
        results: results,
        catalog: catalog,
        interest: _interest.text,
        matches: _recommend.matches,
        aliases: _aliases,
      );
      _records = summary.activities.failed
          ? null
          : RecordEvidenceSummary.build(
              summary.activities.records,
              _interest.text.trim(),
              _recommend.matches,
            );
      _checks = {
        for (final p in predictions)
          if (p.kind != PredictionKind.regular)
            p: _service.checkMinimum(
              p,
              mock,
              field: _field,
              failed: summary.mockExams.failed,
            ),
      };
    });
  }

  void _rerun() {
    if (_predictions != null) _run();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('진학 컨설팅 리포트'),
        actions: [
          if (_predictions != null)
            IconButton(
              key: const Key('report-copy'),
              tooltip: '리포트 복사',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copy,
            ),
          if (_predictions != null)
            IconButton(
              key: const Key('report-print'),
              tooltip: '인쇄·PDF 저장',
              icon: const Icon(Icons.print_outlined),
              onPressed: _print,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('다시 시도')),
                  ],
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [..._inputs(), ..._report()],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _inputs() {
    final s = _summary!;
    final sessions = _sessions;
    return [
      const Text(
        '저장한 내신·모의고사와 관심 분야로, 과거 입결과 비교한 대학 목록을 전형별 안정·적정·상향으로 정리합니다.',
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('report-interest'),
        controller: _interest,
        decoration: const InputDecoration(
          labelText: '관심 학과·분야',
          hintText: '예: 컴퓨터공학, 경영, 간호',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        onSubmitted: (_) => _interest.text.trim().isEmpty ? null : _run(),
      ),
      if (s.careerInterests.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in s.careerInterests)
                ActionChip(
                  label: Text(v),
                  onPressed: () => setState(() => _interest.text = v),
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (sessions.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: _mockId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '비교할 모의고사 (정시 비교·수시 수능 최저 판정)',
          ),
          items: [
            for (final x in sessions)
              DropdownMenuItem(
                value: x.id,
                child: Text(x.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            setState(() => _mockId = v);
            _rerun();
          },
        )
      else
        const Text(
          '모의고사가 없어 정시는 판단 보류, 수시 수능 최저는 자료 부족으로 표시됩니다.',
          style: TextStyle(fontSize: 13),
        ),
      const SizedBox(height: 12),
      const Text('계열 (수능 최저가 계열별로 나뉠 때만 사용)', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        children: [
          for (final (value, label) in const [
            (null, '선택 안 함'),
            ('인문', '인문'),
            ('자연', '자연'),
          ])
            ChoiceChip(
              key: Key('report-field-${value ?? 'none'}'),
              label: Text(label),
              selected: _field == value,
              onSelected: (_) {
                setState(() => _field = value);
                _rerun();
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('report-run'),
        icon: const Icon(Icons.analytics_outlined),
        label: const Text('리포트 만들기'),
        onPressed: () {
          if (_interest.text.trim().isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('관심 학과·분야를 입력하세요.')));
            return;
          }
          _run();
        },
      ),
    ];
  }

  List<Widget> _report() {
    final predictions = _predictions, student = _student;
    if (predictions == null || student == null) return const [];
    return [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('내 성적 기준', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                student.hasGrades
                    ? '내신: ${student.gradeBasis}'
                    : '내신: 원본 대조가 확인된 등급이 없어 수시는 판단 보류입니다.',
              ),
              Text(
                student.hasMock
                    ? '모의고사: ${student.mockLabel} · 국·수·탐 평균 백분위 ${student.mockPercentile!.toStringAsFixed(1)}'
                          '${student.mockEnglish != null ? " · 영어 ${student.mockEnglish}등급" : ""}'
                    : '모의고사: 국어·수학·통합사회·통합과학 백분위가 모두 있는 시험이 없어 정시는 판단 보류입니다.',
              ),
              Text(
                '생기부: ${_records?.describe() ?? "생기부 근거를 불러오지 못했습니다. 다시 시도하세요."}',
                key: const Key('report-records'),
              ),
              if (_records?.matched.isNotEmpty ?? false)
                ExpansionTile(
                  key: const Key('report-records-list'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('연결된 생기부 근거 보기'),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in _records!.matched)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${r.schoolYear}학년 · ${r.category} · ${r.sourceLocation}'
                          '${r.careerInterest?.trim().isNotEmpty == true ? " · 진로 메모: ${r.careerInterest!.trim()}" : ""}\n'
                          '${r.evidence.length > 120 ? "${r.evidence.substring(0, 120)}…" : r.evidence}',
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            '이 리포트는 대입정보포털 어디가의 2024·2025학년도 최종등록자 입결과 내 성적을 비교한 예측입니다. 합격을 보장하지 않습니다. '
            '2028학년도부터 내신이 5등급제로 바뀌어 9등급 입결과의 비교는 근사치이고, 모의고사는 실제 수능과 다를 수 있습니다. '
            '수시 카드의 수능 최저는 고교 모의고사 등급으로 본 준비도이며, 안정·적정이어도 최저를 맞추지 못하면 불합격입니다. '
            '지원 전 수능 최저·지원 자격·최종 모집요강을 반드시 확인하세요.',
          ),
        ),
      ),
      if (predictions.isNotEmpty) _portfolio(predictions),
      if (predictions.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '관심 분야와 맞는 모집단위의 2028 전형·입결을 찾지 못했습니다. 다른 표현(예: 컴퓨터, 경영)으로 다시 시도하세요.',
          ),
        ),
      for (final kind in PredictionKind.values)
        ..._kindSection(
          kind,
          predictions.where((p) => p.kind == kind).toList(),
        ),
      if (_untracked.isNotEmpty) ...[
        const SizedBox(height: 20),
        ExpansionTile(
          key: const Key('report-untracked'),
          tilePadding: EdgeInsets.zero,
          title: Text('과거 입결과 비교하지 못한 2028 전형 (${_untracked.length})'),
          subtitle: const Text(
            '판단 보류: 신설·통합되었거나 이름 변경을 공식 근거로 확인하지 못해 비교할 입결이 없습니다. '
            '관심 학과가 이 전형에서 모집하는지는 모집요강에서 확인하세요.',
            style: TextStyle(fontSize: 12),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in _untrackedByUniversity.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${e.key}: ${e.value.join(", ")}',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            if (_referenceLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                '대학 공개 입결(참고): 어디가와 지표가 달라(예: 최초+충원 합격자 평균은 등록자 기준보다 좋게 나오는 경향) '
                '안정·적정 판정에 쓰지 않습니다. 2028 전형과 같은 기준인지도 확인되지 않았습니다.',
                key: Key('report-reference-note'),
                style: TextStyle(fontSize: 12),
              ),
              for (final line in _referenceLines)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    line,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
            ],
          ],
        ),
      ],
    ];
  }

  /// 판단 보류 전형에 붙일 대학 공개 입결(참고) 줄. 관심 분야 학과만.
  List<String> get _referenceLines => [
    for (final t in _untracked)
      for (final g
          in _reference?.forTrack(
                t.university,
                t.track,
                (d) => _recommend.matches(d, _interest.text),
              ) ??
              const <ReferenceGroup>[])
        '${t.university} ${t.track} → ${g.describe()}',
  ];

  /// 대학별로 묶은 "비교하지 못한 전형" 표시 문자열(변경 내용이 기록돼 있으면 함께).
  Map<String, List<String>> get _untrackedByUniversity {
    final out = <String, List<String>>{};
    for (final t in _untracked) {
      (out[t.university] ??= []).add(
        '${t.track}(${t.type == '학생부교과' ? '교과' : '종합'}'
        '${t.note != null ? ' · ${t.note}' : ''})',
      );
    }
    return out;
  }

  List<Widget> _kindSection(
    PredictionKind kind,
    List<AdmissionPrediction> items,
  ) {
    if (items.isEmpty) return const [];
    items.sort((a, b) {
      final r = rank(a.university).compareTo(rank(b.university));
      return r != 0
          ? r
          : '${a.university}${a.department}'.compareTo(
              '${b.university}${b.department}',
            );
    });
    final counts = {
      for (final l in PredictionLevel.values)
        l: items.where((p) => p.level == l).length,
    };
    return [
      const SizedBox(height: 20),
      Text(
        '${kind.label} · ${items.length}건',
        key: Key('report-kind-${kind.name}'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        PredictionLevel.values
            .where((l) => counts[l]! > 0)
            .map((l) => '${l.label} ${counts[l]}')
            .join(' · '),
        style: const TextStyle(fontSize: 13),
      ),
      if (kind != PredictionKind.regular)
        Text(
          '수능 최저: ${[for (final st in MinimumStatus.values) (st, items.where((p) => _checks[p]?.result.status == st).length)].where((e) => e.$2 > 0).map((e) => '${_short(e.$1)} ${e.$2}').join(' · ')}',
          key: Key('report-minimum-${kind.name}'),
          style: const TextStyle(fontSize: 13),
        ),
      if (kind == PredictionKind.comprehensive)
        Text(
          '학생부종합 판정은 교과 등급과 입결의 비교만 반영합니다. 서류 평가(생기부)는 대학별 정성 평가라 앱이 점수로 바꾸지 않습니다. '
          '관심 분야와 연결된 생기부 근거: ${_records == null ? "조회 실패" : "${_records!.matched.length}건"}.',
          key: const Key('report-comprehensive-records'),
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
      for (final level in PredictionLevel.values)
        if (counts[level]! > 0)
          ExpansionTile(
            key: Key('report-${kind.name}-${level.name}'),
            initiallyExpanded: level == PredictionLevel.fit,
            title: Text('${level.label} (${counts[level]})'),
            children: [
              for (final p in items.where((p) => p.level == level)) _card(p),
            ],
          ),
    ];
  }

  /// "최저 …" 뒤에 붙일 짧은 이름("수능 최저 없음" → "없음").
  static String _short(MinimumStatus s) =>
      s == MinimumStatus.none ? '없음' : s.label;

  ApplicationPortfolio _plan(List<AdmissionPrediction> predictions) =>
      ApplicationPortfolioService().build(
        predictions: predictions,
        minimums: _checks,
        universityRank: rank,
        split: _split,
      );

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: reportText()));
      messenger.showSnackBar(
        const SnackBar(content: Text('리포트를 복사했습니다. 생기부 원문은 넣지 않았습니다.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('복사하지 못했습니다.'),
          action: SnackBarAction(label: '다시 시도', onPressed: _copy),
        ),
      );
    }
  }

  void _print() {
    final opened = (widget.printHtml ?? printReportHtml)(
      reportHtml(reportText()),
    );
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('인쇄 창을 열지 못했습니다. 브라우저의 팝업 차단을 해제하거나 리포트 복사를 쓰세요.'),
        ),
      );
    }
  }

  /// 복사용 일반 텍스트. 화면과 같은 판정·근거를 담고, 생기부는 원문 없이 건수·분포만 넣는다.
  /// 어려움·판단 보류는 길어지지 않게 건수만 넣는다.
  @visibleForTesting
  String reportText() {
    final predictions = _predictions ?? const [];
    final student = _student;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    String pickLine(PortfolioPick pick) {
      final p = pick.prediction;
      final st = pick.minimum?.result.status;
      return '- ${pick.slot} ${p.university} · ${p.department} | ${p.track}'
          '${p.kind == PredictionKind.regular ? " | ${p.level.label}" : ""}'
          ' | 신뢰도 ${p.confidence}'
          '${st != null && st != MinimumStatus.none ? " | 최저 ${st.label}" : ""}'
          '${pick.note != null ? " | ${pick.note}" : ""}';
    }

    final plan = _plan(predictions);
    final b = StringBuffer()
      ..writeln(
        '진학 컨설팅 리포트 ($date 작성 · 관심 분야: ${_interest.text.trim()}'
        '${_field != null ? " · 계열: $_field" : ""})',
      )
      ..writeln(
        '※ 대입정보포털 어디가 2024·2025학년도 최종등록자 입결과 비교한 예측이며 합격을 보장하지 않습니다. '
        '2028 내신 5등급과 9등급 입결 비교는 근사치이고, 모의고사는 실제 수능과 다를 수 있습니다. '
        '지원 전 수능 최저·지원 자격·최종 모집요강을 확인하세요.',
      )
      ..writeln()
      ..writeln('[내 성적 기준]');
    if (student != null) {
      b
        ..writeln(
          '- 내신: ${student.hasGrades ? student.gradeBasis : "원본 대조가 확인된 등급 없음(수시 판단 보류)"}',
        )
        ..writeln(
          '- 모의고사: ${student.hasMock ? "${student.mockLabel} · 국·수·탐 평균 백분위 ${student.mockPercentile!.toStringAsFixed(1)}${student.mockEnglish != null ? " · 영어 ${student.mockEnglish}등급" : ""}" : "비교 가능한 시험 없음(정시 판단 보류)"}',
        );
    }
    b
      ..writeln('- 생기부: ${_records?.describe() ?? "조회 실패"}')
      ..writeln()
      ..writeln('[지원 조합 예시 · 수시 ${_split.label}]');
    if (plan.susi.isEmpty) b.writeln('- 넣을 수 있는 수시 후보 없음');
    for (final pick in plan.susi) {
      b.writeln(pickLine(pick));
    }
    if (plan.regular.isEmpty) b.writeln('- 넣을 수 있는 정시 후보 없음');
    for (final pick in plan.regular) {
      b.writeln(pickLine(pick));
    }
    for (final n in plan.notes) {
      b.writeln('• $n');
    }
    for (final kind in PredictionKind.values) {
      final items = predictions.where((p) => p.kind == kind).toList()
        ..sort((a, c) {
          final r = rank(a.university).compareTo(rank(c.university));
          return r != 0
              ? r
              : '${a.university}${a.department}'.compareTo(
                  '${c.university}${c.department}',
                );
        });
      if (items.isEmpty) continue;
      int count(PredictionLevel l) => items.where((p) => p.level == l).length;
      b
        ..writeln()
        ..writeln(
          '[${kind.label} ${items.length}건] '
          '${PredictionLevel.values.where((l) => count(l) > 0).map((l) => "${l.label} ${count(l)}").join(" · ")}',
        );
      for (final level in const [
        PredictionLevel.safe,
        PredictionLevel.fit,
        PredictionLevel.reach,
      ]) {
        final rows = items.where((p) => p.level == level).toList();
        if (rows.isEmpty) continue;
        b.writeln('〈${level.label}〉');
        for (final p in rows) {
          final check = _checks[p];
          b
            ..writeln(
              '- ${p.university} · ${p.department} | ${p.track}'
              '${p.group != null ? " | ${p.group}" : ""} | 신뢰도 ${p.confidence}'
              '${check != null ? " | 최저 ${_short(check.result.status)}${check.branch != null ? "(${check.branch} 기준)" : ""}" : ""}',
            )
            ..writeln('  ${p.reason}')
            ..writeln('  근거: ${p.evidence.join(" / ")}');
        }
      }
      final rest = count(PredictionLevel.hard) + count(PredictionLevel.unknown);
      if (rest > 0) {
        b.writeln('(어려움·판단 보류 $rest건은 앱 화면에서 확인)');
      }
    }
    if (_untracked.isNotEmpty) {
      b
        ..writeln()
        ..writeln('[과거 입결과 비교하지 못한 2028 전형 ${_untracked.length}건] 판단 보류')
        ..writeln(
          '※ 신설·통합되었거나 이름 변경을 공식 근거로 확인하지 못해 비교할 입결이 없습니다. 관심 학과 모집 여부는 모집요강에서 확인하세요.',
        );
      for (final e in _untrackedByUniversity.entries) {
        b.writeln('- ${e.key}: ${e.value.join(", ")}');
      }
      final refs = _referenceLines;
      if (refs.isNotEmpty) {
        b.writeln(
          '※ 대학 공개 입결(참고): 어디가와 지표가 달라 안정·적정 판정에 쓰지 않음. 2028 전형과 같은 기준인지 미확인.',
        );
        for (final line in refs) {
          b.writeln('- $line');
        }
      }
    }
    b
      ..writeln()
      ..writeln(
        '출처: 대입정보포털 어디가 대학별 전형결과, 2028학년도 대학별 전형계획 자료(공식 원문 대조 현황은 앱의 자료 출처 참고)',
      );
    return b.toString();
  }

  Widget _portfolio(List<AdmissionPrediction> predictions) {
    final plan = _plan(predictions);
    final theme = Theme.of(context);
    Widget row(PortfolioPick pick) {
      final p = pick.prediction;
      final status = pick.minimum?.result.status;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                pick.slot,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.university} · ${p.department}'),
                  Text(
                    [
                      p.track,
                      if (p.kind == PredictionKind.regular) p.level.label,
                      '신뢰도 ${p.confidence}',
                      if (status != null && status != MinimumStatus.none)
                        '최저 ${status.label}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (pick.note != null)
                    Text(
                      pick.note!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      key: const Key('report-portfolio'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('지원 조합 예시', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              '아래 목록에서 신뢰도·수능 최저 상태·대학 검토 순서로 고른 한 가지 예시입니다. '
              '어려움·판단 보류·최저 미달 수준은 넣지 않았고, 같은 대학은 한 번만 넣었습니다. '
              '실제 지원은 대학별 중복 지원 제한·전형 일정·면접 일정을 확인해 정하세요.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text('수시 6장', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final s in SusiSplit.values)
                  ChoiceChip(
                    key: Key('report-split-${s.name}'),
                    label: Text(
                      '${s.label} (상향${s.reach}·적정${s.fit}·안정${s.safe})',
                    ),
                    selected: _split == s,
                    onSelected: (_) => setState(() => _split = s),
                  ),
              ],
            ),
            if (plan.susi.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('넣을 수 있는 수시 후보가 없습니다.'),
              ),
            for (final pick in plan.susi) row(pick),
            const SizedBox(height: 10),
            Text('정시 가·나·다군', style: theme.textTheme.titleSmall),
            if (plan.regular.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('넣을 수 있는 정시 후보가 없습니다.'),
              ),
            for (final pick in plan.regular) row(pick),
            if (plan.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final n in plan.notes)
                Text('• $n', style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(AdmissionPrediction p) {
    final tuition = _tuition?.forUniversity(p.university) ?? const [];
    final fee = tuition.isEmpty
        ? null
        : '연간 평균 등록금 ${tuition.map((t) => '${(t.annualWon / 10000).round()}만원').toSet().join("~")} (2026 공시)';
    final check = _checks[p];
    final below = check?.result.status == MinimumStatus.below;
    final error = Theme.of(context).colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: below
            ? Icon(
                Icons.warning_amber_rounded,
                color: error,
                semanticLabel: '수능 최저 미달 수준',
              )
            : null,
        title: Text('${p.university} · ${p.department}'),
        subtitle: Text(
          '${p.track}${p.group != null ? " · ${p.group}" : ""} · 신뢰도 ${p.confidence}'
          '${check != null ? " · 최저 ${_short(check.result.status)}" : ""}',
          style: TextStyle(fontSize: 12, color: below ? error : null),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.reason, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 6),
          for (final e in p.evidence)
            Text('• $e', style: const TextStyle(fontSize: 12, height: 1.5)),
          if (check != null) ...[
            const SizedBox(height: 6),
            Text(
              '수능 최저: ${check.result.status.label}'
              '${check.branch != null ? " (${check.branch} 기준${check.byField ? ", 고른 계열로 적용 — 이 모집단위의 소속 계열을 원문에서 확인하세요" : ""})" : ""} — ${check.result.reason}',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: below ? error : null,
                fontWeight: below ? FontWeight.w600 : null,
              ),
            ),
            for (final d in check.result.details)
              Text('  · $d', style: const TextStyle(fontSize: 12, height: 1.5)),
            if (p.minimum != null)
              Text(
                '최저 원문(2028 전형 자료): ${p.minimum}',
                style: const TextStyle(fontSize: 11, height: 1.5),
              ),
          ],
          if (fee != null) ...[
            const SizedBox(height: 6),
            Text(fee, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 4),
          const Text('출처: 대입정보포털 어디가 대학별 전형결과', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
