import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/widgets/official_admission_source.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';
import 'package:univ_pathfinder/widgets/university_selection_controls.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';
import 'package:univ_pathfinder/services/yonsei_csat_conversion.dart';
import 'package:univ_pathfinder/services/snu_csat_conversion.dart';
import 'package:univ_pathfinder/services/percentile_csat_conversions.dart';
import 'package:univ_pathfinder/services/admission_condition_store.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:univ_pathfinder/services/admission_comparison_service.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

class UniversityRecommendationScreen extends StatefulWidget {
  const UniversityRecommendationScreen({
    super.key,
    this.loadSummary,
    this.loadCatalog,
    this.loadTuition,
    this.loadComparison,
    this.conditionStore,
    this.selectionStore,
  });
  final Future<CounselingSummary> Function()? loadSummary;
  final Future<AdmissionCatalog> Function()? loadCatalog;
  final Future<TuitionCatalog> Function()? loadTuition;
  final Future<Map<String, dynamic>> Function()? loadComparison;
  final AdmissionConditionStore? conditionStore;
  final UniversitySelectionStore? selectionStore;
  @override
  State<UniversityRecommendationScreen> createState() => _RecommendationState();
}

class _RecommendationState extends State<UniversityRecommendationScreen> {
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  final _filtersKey = GlobalKey();
  final _interest = TextEditingController();
  final _priority = TextEditingController(
    text: UniversityRecommendationService.defaultPriority,
  );
  final _service = UniversityRecommendationService();
  CounselingSummary? _summary;
  AdmissionCatalog? _catalog;
  TuitionCatalog? _tuition;
  Map<String, dynamic>? _comparisonData;
  bool _busy = false, _generated = false, _special = false;
  bool _comparisonOnly = false;
  bool _cumulativeConfirmed = false;
  final Map<String, bool> _conditionChecks = {};
  final _minimumService = CsatMinimumService();
  final Map<String, String> _minimumBranches = {};
  String? _mockSessionId;
  AdmissionConditionStore? _conditionStore;
  bool _checksLoading = true, _checksSaving = false;
  String? _checksMessage;
  String? _error;
  String _type = '전체';
  int _count = 10;

  @override
  void initState() {
    super.initState();
    _load();
    _loadChecks();
  }

  Future<void> _loadChecks() async {
    _conditionStore = widget.conditionStore;
    if (_conditionStore == null) {
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) _conditionStore = AdmissionConditionStore(uid);
      } catch (_) {
        /* Synthetic previews have no authenticated client. */
      }
    }
    try {
      final checks = await _conditionStore?.load() ?? <String, bool>{};
      if (mounted) {
        setState(() {
          _conditionChecks.addAll(checks);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _checksMessage =
              '저장된 확인 표시를 불러오지 못했습니다. 기존 표시 보호를 위해 새 저장은 잠시 막았습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _checksLoading = false);
    }
  }

  Future<void> _saveCheck(
    AdmissionTrack t,
    String condition,
    bool value,
  ) async {
    final key = AdmissionConditionStore.checkKey(t, condition);
    if (_conditionStore == null) {
      setState(() => _conditionChecks[key] = value);
      return;
    }
    setState(() => _checksSaving = true);
    try {
      final next = {..._conditionChecks, key: value};
      await _conditionStore!.save(next);
      if (mounted) {
        setState(() {
          _conditionChecks.clear();
          _conditionChecks.addAll(next);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('확인 표시를 저장하지 못했습니다. 다시 선택해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checksSaving = false);
    }
  }

  MockExamSession? get _selectedMock {
    final sessions = _minimumService.sessions(
      _summary?.mockExams.records ?? [],
    );
    if (sessions.isEmpty) return null;
    return sessions.where((s) => s.id == _mockSessionId).firstOrNull ??
        sessions.first;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _interest.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _generated = false;
      _summary = null;
      _catalog = null;
      _tuition = null;
      _comparisonData = null;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        (widget.loadSummary ?? CounselingSummaryService().fetch)(),
        (widget.loadCatalog ?? _service.loadCatalog)(),
        (widget.loadTuition ?? _service.loadTuition)()
            .then<TuitionCatalog?>((v) => v)
            .catchError((_) => null),
        (widget.loadComparison ?? _service.loadComparison)()
            .then<Map<String, dynamic>?>((v) => v)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as CounselingSummary;
        _catalog = results[1] as AdmissionCatalog;
        _tuition = results[2] as TuitionCatalog?;
        _comparisonData = results[3] as Map<String, dynamic>?;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '성적·생기부 또는 전형 자료를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void change(VoidCallback action) => setState(() {
    action();
    _generated = false;
  });

  @override
  Widget build(BuildContext context) {
    final s = _summary, catalog = _catalog;
    final result = !_generated || s == null || catalog == null
        ? null
        : _service.recommend(
            catalog: catalog,
            summary: s,
            interest: _interest.text,
            count: _count,
            type: _type,
            includeSpecial: _special,
            priority: _priority.text,
            comparisonData: _comparisonData,
            comparisonOnly: _comparisonOnly,
            cumulativeConfirmed: _cumulativeConfirmed,
          );
    final max = catalog == null
        ? 10
        : catalog.tracks.map((t) => t.university).toSet().length;
    return Scaffold(
      backgroundColor: PathfinderTheme.canvas,
      appBar: AppBar(
        title: const Text('대학 후보 찾기'),
        actions: [
          IconButton(
            tooltip: '등록 자료 새로고침',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final filters = KeyedSubtree(
            key: _filtersKey,
            child: _filters(s, max),
          );
          final results = _results(s, catalog, result);
          return SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              wide ? 32 : 16,
              24,
              wide ? 32 : 16,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(s, catalog),
                    const SizedBox(height: 24),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 330, child: filters),
                          const SizedBox(width: 24),
                          Expanded(child: results),
                        ],
                      )
                    else ...[
                      filters,
                      const SizedBox(height: 24),
                      results,
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hero(CounselingSummary? s, AdmissionCatalog? catalog) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: [Color(0xFF1B8A76), Color(0xFF0F5A4D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '2028학년도 대학 후보',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
            color: Color(0xFFCDEBE0),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '나에게 맞는 대학,\n근거를 보고 선택하세요.',
          style: TextStyle(
            fontSize: 28,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '성적과 생기부를 연결해 관심 분야의 수도권 대학을 살펴보세요.',
          style: TextStyle(color: Color(0xFFD1E7DD), height: 1.6, fontSize: 14),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(
              Icons.school_outlined,
              '수도권 ${catalog?.tracks.map((t) => t.university).toSet().length ?? "—"}개 대학',
              inverse: true,
            ),
            _pill(
              Icons.fact_check_outlined,
              s == null
                  ? '자료 불러오는 중'
                  : s.grades.failed
                  ? '내신 조회 실패'
                  : '확인 내신 ${s.confirmedGrades.length}개',
              inverse: true,
            ),
            _pill(
              Icons.article_outlined,
              s == null
                  ? '생기부 확인 중'
                  : s.activities.failed
                  ? '생기부 조회 실패'
                  : '생기부 ${s.activitiesFor(null).length}개 근거',
              inverse: true,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _pill(IconData icon, String text, {bool inverse = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: inverse
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFFEDF4F0),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: inverse ? const Color(0xFFD5ECDD) : PathfinderTheme.accent,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: inverse ? Colors.white : PathfinderTheme.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: PathfinderTheme.line),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  Widget _notice(String text, {bool error = false}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFF0E8) : const Color(0xFFEDF4F0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: error ? const Color(0xFF934522) : PathfinderTheme.accent,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: PathfinderTheme.ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _filters(CounselingSummary? s, int max) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.tune_rounded,
              color: PathfinderTheme.accent,
              size: 20,
            ),
            const SizedBox(width: 9),
            Text('나의 탐색 조건', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '관심 분야부터 시작해보세요.',
          style: TextStyle(fontSize: 12, color: PathfinderTheme.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _interest,
          decoration: const InputDecoration(
            labelText: '관심 학과·분야',
            hintText: '예: 컴퓨터공학, 경영',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (_) => change(() {}),
        ),
        if (s != null && s.careerInterests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in s.careerInterests)
                  ActionChip(
                    label: Text(v),
                    onPressed: () => change(() => _interest.text = v),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
          initialValue: _count,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '보고 싶은 대학 개수'),
          items: [
            for (var i = 1; i <= (max < 10 ? 10 : max); i++)
              DropdownMenuItem(value: i, child: Text('$i개')),
          ],
          onChanged: (v) {
            if (v != null) change(() => _count = v);
          },
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '검토할 전형'),
          items: [
            '전체',
            '학생부교과',
            '학생부종합',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) {
            if (v != null) change(() => _type = v);
          },
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            '입결 비교를 지원하는 대학만 보기',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            '비교 근거가 연결된 후보를 모아봅니다.',
            style: TextStyle(fontSize: 12),
          ),
          value: _comparisonOnly,
          onChanged: (v) => change(() => _comparisonOnly = v ?? false),
        ),
        const Divider(),
        const SizedBox(height: 8),
        _mockSelector(),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _cumulativeConfirmed,
          title: const Text('고2 1학기까지 누적 비교', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '2025년 고1 두 학기와 2026년 고2 1학기의 석차등급 과목을 빠짐없이 등록·대조했을 때 선택하세요. 부산교육청 3학기 누적표를 사용합니다.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (v) => change(() => _cumulativeConfirmed = v ?? false),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: const Text(
            '상세 조건',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '특별 지원자격 전형도 검토',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '농어촌·기회균형 등은 지원자격 확인이 필요합니다.',
                style: TextStyle(fontSize: 12),
              ),
              value: _special,
              onChanged: (v) => change(() => _special = v ?? false),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '정렬 기준·우선 검토 대학 순서',
                style: TextStyle(fontSize: 12),
              ),
              children: [
                const Text(
                  '2028 학과 일치 → 분야 일치 과거 입결 확보 → 준비 자료 연결 → 아래 우선 순서입니다. 공인 대학 순위나 합격 가능성 순위가 아닙니다.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priority,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '동점일 때 먼저 볼 대학 (쉼표로 구분)',
                  ),
                  onChanged: (_) => change(() {}),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || _summary == null || _catalog == null
              ? null
              : _generate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text('등록 자료로 $_count개 대학 보기')),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '학업 비교는 참고 추정이며 합격을 확정하지 않습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: PathfinderTheme.muted,
            height: 1.6,
          ),
        ),
      ],
    ),
  );

  void _generate() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _generated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultsKey.currentContext;
      if (mounted &&
          target != null &&
          MediaQuery.sizeOf(context).width < 1000) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          alignment: 0,
        );
      }
    });
  }

  Widget _results(
    CounselingSummary? s,
    AdmissionCatalog? catalog,
    UniversityRecommendation? result,
  ) => Column(
    key: _resultsKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('관심 대학 비교 목록'),
            UniversitySelectionControls(store: widget.selectionStore),
            ListenableBuilder(
              listenable: CounselingSession.instance,
              builder: (context, _) {
                final session = CounselingSession.instance;
                return FilledButton.icon(
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(
                    '선택한 ${session.catalogSelection.length}개 대학 모집정보 비교',
                  ),
                  onPressed:
                      session.catalogSelection.isEmpty ||
                          session.selectionBusy ||
                          session.selectionError != null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UniversitySearchScreen(
                              compare: true,
                              loadCatalog: widget.loadCatalog,
                              loadTuition: widget.loadTuition,
                              selectionStore: widget.selectionStore,
                            ),
                          ),
                        ),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: LinearProgressIndicator(),
        ),
      if (_error != null) ...[
        _notice(_error!, error: true),
        TextButton(onPressed: _load, child: const Text('다시 불러오기')),
      ],
      if (s != null &&
          !s.grades.failed &&
          s.confirmedGrades.isEmpty &&
          s.unconfirmedGradeCount == 0) ...[
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '내신 성적표를 업로드해 주세요',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('성적표를 업로드하고 추출한 성적을 확인하면 대학 추천 분석에 사용할 수 있습니다.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('성적표 업로드'),
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CounselingDocumentsScreen(),
                    ),
                  );
                  if (mounted) await _load();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (result == null)
        _panel(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF4EF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    size: 44,
                    color: PathfinderTheme.accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '가능성을 탐색할 준비가 됐나요?',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  '관심 분야와 대학 개수를 선택하면\n성적·생기부 근거와 등록금을 함께 보여드려요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PathfinderTheme.muted, height: 1.8),
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _pill(Icons.fact_check_outlined, '원문 근거'),
                    _pill(Icons.analytics_outlined, '학업 비교'),
                    _pill(Icons.payments_outlined, '연간 등록금'),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (result != null) ...[
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '내 조건으로 고른 후보',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: .2,
                      fontWeight: FontWeight.w600,
                      color: PathfinderTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '관심 분야의 대학 후보',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            _pill(Icons.school_outlined, '${result.candidates.length}개'),
            IconButton(
              tooltip: '탐색 조건으로 이동',
              icon: const Icon(Icons.tune_rounded, size: 20),
              onPressed: () {
                final target = _filtersKey.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 250),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '지원 검토 대학 ${result.candidates.length}개 / 조건에 맞는 ${result.total}개',
          style: const TextStyle(fontSize: 12, color: PathfinderTheme.muted),
        ),
        const SizedBox(height: 20),
        for (final issue in result.issues) _notice(issue, error: true),
        if (result.issues.isEmpty) ...[
          if (result.total < _count)
            _notice('조건에 맞는 대학이 $_count개보다 적어 ${result.total}개만 표시합니다.'),
          if (_comparisonData == null)
            _notice('학업 비교 자료를 불러오지 못했습니다. 새로고침으로 다시 시도하세요.', error: true),
          if (_tuition == null)
            _notice(
              '등록금 자료를 불러오지 못했습니다. 대학 후보는 계속 볼 수 있습니다. 새로고침으로 다시 시도하세요.',
              error: true,
            ),
          _notice(
            '약·중·강은 과거 입결 대비 학업 참고 비교입니다. 현재 ${((_comparisonData?["benchmarks"] as List?) ?? []).map((b) => b["university"]).toSet().length}개 대학·${((_comparisonData?["benchmarks"] as List?) ?? []).length}개 모집단위 자료를 연결하며 최종 합격 판단과 구분합니다.',
          ),
          if (result.candidates.isEmpty)
            _panel(
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 36,
                      color: PathfinderTheme.muted,
                    ),
                    SizedBox(height: 12),
                    Text('조건에 맞는 후보가 없어요.'),
                    SizedBox(height: 8),
                    Text(
                      '분야를 바꾸거나 입결 비교 필터를 해제해보세요.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < result.candidates.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _candidate(i + 1, result.candidates[i]),
            ),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    '비교 범위와 자료 안내',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    const Text(
                      '학업 비교 범례: 약(과거 입결 대비 불리) · 중(겹침·혼재) · 강(유리) · 자료 부족',
                    ),
                    const Text(
                      '기본 비교에는 2025년 고1 1학기 6개 공통과목이 필요합니다. 3학기 성적을 모두 등록했다면 누적 비교를 선택하세요. 학종에는 적용하지 않습니다. 학과 미명시 대학은 실제 모집 여부를 확인하세요.',
                    ),
                    if (s!.mockExams.failed)
                      const Text('모의고사 조회에 실패했습니다. 수능 최저 검토를 위해 다시 조회하세요.'),
                    if (!s.mockExams.failed && s.mockExams.records.isEmpty)
                      const Text('모의고사가 없어 수능 최저와 비교할 성적이 없습니다.'),
                    if (catalog != null)
                      Text('${catalog.year}학년도 전형계획\n${catalog.status}'),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '비교에 사용한 내신 ${s.confirmedGrades.length}개 · 생기부 관심 분야 연결 근거 ${result.evidence.length}개',
                    style: const TextStyle(fontSize: 13),
                  ),
                  children: [
                    const Text(
                      '분야 연결은 원문 키워드 일치이며 적성을 확정하지 않습니다. 내신은 시험별로 구분합니다.',
                    ),
                    for (final g in s.confirmedGrades)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${g.subjectName} · ${g.calendarYear ?? "연도 미상"}년 ${g.schoolYear}학년 ${g.semester}학기 ${g.examLabel}',
                        ),
                        subtitle: Text(
                          '등급 ${g.gradeRank ?? "공란"} · 원점수 ${g.rawScore ?? "공란"} · ${g.sourceLocation ?? "출처 위치 미등록"}',
                        ),
                      ),
                    if (result.evidence.isEmpty)
                      const Text(
                        '관심 분야와 키워드가 일치하는 생기부 근거는 없습니다. 미일치는 역량 부족을 뜻하지 않습니다.',
                      ),
                    for (final e in result.evidence)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${e.calendarYear}년 · ${e.category}'),
                        subtitle: Text(
                          '${e.evidence}\n출처: ${e.sourceLocation}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    ],
  );

  Widget _comparison(AcademicComparison c) {
    final color = switch (c.level) {
      AdmissionLikelihood.weak => Colors.red.shade800,
      AdmissionLikelihood.medium => Colors.brown.shade700,
      AdmissionLikelihood.strong => Colors.green.shade800,
      AdmissionLikelihood.insufficient => Colors.grey.shade700,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .035),
        border: Border.all(color: PathfinderTheme.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.department} · ${c.track}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '과거 입결 대비 학업 비교: ${c.level.label}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '참고 추정 · 근거 신뢰도 낮음 · 최종 합격 판단은 미확인',
              style: TextStyle(
                fontSize: 12,
                color: PathfinderTheme.muted,
                height: 1.6,
              ),
            ),
            if (c.level == AdmissionLikelihood.insufficient)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.reason,
                  style: const TextStyle(fontSize: 12, height: 1.65),
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('학업 비교 계산·입결·출처 확인'),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.level != AdmissionLikelihood.insufficient) Text(c.reason),
                if (c.weightedAverage != null || c.optimistic != null)
                  _comparisonHeading('성적 계산'),
                if (c.simpleAverage != null)
                  Text(
                    '2025년 1학년 1학기 6과목 단순평균 ${c.simpleAverage!.toStringAsFixed(3)} · 학점평균 ${c.weightedAverage!.toStringAsFixed(3)}',
                  ),
                if (c.simpleAverage == null && c.weightedAverage != null)
                  Text(
                    '고2 1학기까지 3학기 누적 학점평균 ${c.weightedAverage!.toStringAsFixed(3)}',
                  ),
                if (c.optimistic != null)
                  Text(
                    '공개표 9등급 대응 범위 ${c.optimistic!.toStringAsFixed(2)}~${c.conservative!.toStringAsFixed(2)} · 통계적 신뢰구간이나 2028 대학 환산점수가 아닙니다.',
                  ),
                if (c.history.isNotEmpty) ...[
                  _comparisonHeading('연도별 입결'),
                  Table(
                    children: [
                      _comparisonRow([
                        '학년도',
                        c.centralMetric,
                        '70%컷',
                      ], header: true),
                      for (final h in c.history)
                        _comparisonRow([
                          h['year'].toString(),
                          h['central'].toString(),
                          h['cut70'].toString(),
                        ]),
                    ],
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: const Text('계산 기준과 해석'),
                  children: [
                    Text(c.mappingNote),
                    Text(
                      '강: 범위 전체가 두 해 ${c.centralMetric}보다 유리 / 약: 범위 전체가 두 해 70%컷보다 불리 / 중: 그 외 겹침·혼재. 앱의 시범 규칙이며 대학 공식 판정 기준이 아닙니다. 70%컷은 합격확률 70%가 아닙니다.',
                    ),
                    const Text(
                      '과거 입결과 부산 지역의 참고분포를 대조합니다. 향후 성적·선택과목·전형 변경을 반영한 예측은 아닙니다. 표 사이 값은 양쪽 공개값으로 감싸며 확률이나 대학 공식 환산점수로 해석하지 않습니다.',
                    ),
                  ],
                ),
                if (_comparisonData != null)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: const Text('공개 자료 출처'),
                    children: [
                      Text(
                        (_comparisonData![_cumulativeConfirmed
                                    ? 'cumulativeBridge'
                                    : 'bridge']
                                as Map)['source']
                            as String,
                      ),
                      SelectableText(
                        (_comparisonData![_cumulativeConfirmed
                                    ? 'cumulativeBridge'
                                    : 'bridge']
                                as Map)['url']
                            as String,
                      ),
                      for (final source
                          in (_comparisonData!['sources'] as List)
                              .cast<Map>()
                              .where((s) => s['university'] == c.university))
                        SelectableText(
                          '${source["year"]}: ${source["url"]}\n${source["note"]}',
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonHeading(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );

  TableRow _comparisonRow(List<String> cells, {bool header = false}) =>
      TableRow(
        decoration: BoxDecoration(
          color: header
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          border: const Border(bottom: BorderSide(color: PathfinderTheme.line)),
        ),
        children: [
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                cell,
                style: header ? Theme.of(context).textTheme.labelMedium : null,
              ),
            ),
        ],
      );

  String _comparisonLabel(UniversityCandidate u) {
    if (u.comparisons.isEmpty) return '학업 비교: 미지원 학과·전형';
    final valid = u.comparisons
        .where((c) => c.level != AdmissionLikelihood.insufficient)
        .toList();
    if (valid.isEmpty) return '학업 비교: 성적·비교 자료 확인 필요';
    if (u.comparisons.length == 1) {
      return '학업 비교(참고): ${valid.single.level.label}';
    }
    final labels = [
      for (final level in [
        AdmissionLikelihood.strong,
        AdmissionLikelihood.medium,
        AdmissionLikelihood.weak,
      ])
        if (valid.any((c) => c.level == level))
          '${level.label} ${valid.where((c) => c.level == level).length}개',
    ];
    final missing = u.comparisons.length - valid.length;
    if (missing > 0) labels.add('확인 필요 $missing개');
    return '학과별 학업 비교: ${labels.join(" · ")}';
  }

  Widget _candidate(int index, UniversityCandidate u) {
    final matchingDepartments =
        u.tracks
            .map((track) => track.department.trim())
            .where((department) => department.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final tuitionLabel = _tuition?.labelFor(u.name) ?? '연간 평균 등록금: 조회 실패';
    final amount = tuitionLabel
        .replaceFirst('연간 평균 등록금: ', '')
        .split(' (')
        .first;
    final years =
        _tuition?.forUniversity(u.name).map((r) => r.year).toSet().join('/') ??
        '';
    final valid = u.comparisons
        .where((c) => c.level != AdmissionLikelihood.insufficient)
        .toList();
    final levels = valid.map((c) => c.level).toSet();
    final tone = levels.length == 1
        ? switch (levels.single) {
            AdmissionLikelihood.strong => const Color(0xFF187D6B),
            AdmissionLikelihood.medium => const Color(0xFF93632D),
            AdmissionLikelihood.weak => const Color(0xFFA85242),
            _ => PathfinderTheme.muted,
          }
        : PathfinderTheme.muted;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF4F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: PathfinderTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          u.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        ListenableBuilder(
                      listenable: CounselingSession.instance,
                      builder: (context, _) {
                        final session = CounselingSession.instance;
                        final selected = session.catalogSelection.contains(
                          u.name,
                        );
                        return TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                          ),
                          icon: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            size: 20,
                          ),
                          label: Text(selected ? '관심 대학 선택 해제' : '관심 대학에 추가'),
                          onPressed:
                              session.selectionBusy ||
                                  session.selectionError != null
                              ? null
                              : () {
                                  if (!session.toggleCatalogUniversity(
                                    u.name,
                                  )) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '최대 10개 대학까지 선택할 수 있습니다. 기존 선택을 해제해 주세요.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        );
                      },
                    ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      u.departmentMatch
                          ? '관심 분야와 연결된 모집단위 · ${matchingDepartments.join(', ')}'
                          : '관심 학과 모집 여부 확인 필요',
                      style: const TextStyle(
                        color: PathfinderTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, size) {
              final academic = _metric(
                '학업 비교 · 참고',
                _comparisonLabel(u),
                Icons.analytics_outlined,
                tone,
              );
              final tuition = _metric(
                '연간 평균 등록금',
                amount,
                Icons.payments_outlined,
                PathfinderTheme.ink,
                caption: years.isEmpty
                    ? '공시 자료 확인 필요'
                    : '$years년 공시 · 학과별 금액은 다를 수 있음',
              );
              if (size.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [academic, const SizedBox(height: 10), tuition],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: academic),
                  const SizedBox(width: 12),
                  Expanded(child: tuition),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (u.comparisons.isEmpty)
            const Text(
              '현재 관심 분야의 과거 입결은 아직 연결되지 않았어요. 성적이 부족하다는 뜻은 아닙니다.',
              style: TextStyle(
                fontSize: 12,
                color: PathfinderTheme.muted,
                height: 1.6,
              ),
            ),
          for (final c in u.comparisons) _comparison(c),
          _minimumOverview(u),
          const Divider(height: 28),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '전형 ${u.tracks.length}개 · 지원조건',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              OfficialAdmissionSource(university: u.name, year: _catalog?.year),
              for (final t in u.tracks)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${t.type} · ${t.name}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${t.department.isEmpty ? "학과 미명시" : t.department} · ${t.quota}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    _notice(
                      '선발 방법: ${t.selection}\n지원자격: ${t.eligibility}\n추천: ${t.recommendation} ${t.recommender}\n수능 최저 요약: ${t.minimum}',
                    ),
                    AdmissionTrackReview(track: t),
                    _minimumPanel(t),
                    for (final condition in ['지원자격', '학교장 추천'])
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value:
                            _conditionChecks[AdmissionConditionStore.checkKey(
                              t,
                              condition,
                            )] ??
                            false,
                        title: Text(
                          '$condition · ${(_conditionChecks[AdmissionConditionStore.checkKey(t, condition)] ?? false) ? "본인 확인" : "확인 필요"}',
                        ),
                        onChanged:
                            _checksLoading ||
                                _checksSaving ||
                                _checksMessage != null
                            ? null
                            : (v) => _saveCheck(t, condition, v ?? false),
                      ),
                    Text(
                      _checksMessage ??
                          (_checksLoading
                              ? '확인 표시 불러오는 중…'
                              : _checksSaving
                              ? '확인 표시 저장 중…'
                              : _conditionStore == null
                              ? '본인 확인 표시는 이번 화면에서만 유지됩니다. 로그인하면 이 브라우저에 저장됩니다.'
                              : '본인 확인 표시를 현재 계정의 이 브라우저·기기에 저장합니다. 다른 기기에는 동기화되지 않습니다. 자격 충족·추천 확정을 판정한 결과는 아닙니다.'),
                      style: TextStyle(fontSize: 12),
                    ),
                    if (_checksMessage != null)
                      TextButton(
                        onPressed: _checksLoading
                            ? null
                            : () {
                                setState(() {
                                  _checksMessage = null;
                                  _checksLoading = true;
                                });
                                _loadChecks();
                              },
                        child: const Text('확인 표시 다시 불러오기'),
                      ),
                  ],
                ),
              const Text(
                '지원자격·추천·수능 최저는 최종 모집요강과 대조하세요.',
                style: TextStyle(fontSize: 12, color: PathfinderTheme.muted),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              '등록금 기준·출처 확인',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              const Text(
                '2028 확정 등록금·장학금 반영 실부담액이 아닙니다. 학과별 금액은 다를 수 있습니다.',
                style: TextStyle(fontSize: 12),
              ),
              if (u.name == '한국외대(글로벌)')
                const Text('글로벌 캠퍼스 별도 금액은 미확보이며 학교 본교 공시를 참고로 표시합니다.'),
              if ((_tuition?.forUniversity(u.name).length ?? 0) > 1)
                const Text('복수 캠퍼스는 공시 최저~최고 범위입니다. 아래 본분교를 확인하세요.'),
              if (_tuition != null) ...[
                for (final r in _tuition!.forUniversity(u.name))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${r.officialName} · ${r.campus} · ${r.amountLabel}',
                    ),
                    subtitle: Text(
                      '${r.year}년 · ${r.region} · 기준일 ${r.asOf}\n${r.scope}',
                    ),
                  ),
                Text(_tuition!.source, style: const TextStyle(fontSize: 12)),
                SelectableText(
                  _tuition!.sourceUrl,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PathfinderTheme.muted,
                  ),
                ),
              ],
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              '최종 합격 판단: 미검증',
              style: TextStyle(fontSize: 12, color: PathfinderTheme.muted),
            ),
            children: [
              Text(
                u.assessment.reason,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockSelector() {
    final section = _summary?.mockExams;
    final sessions = _minimumService.sessions(section?.records ?? []);
    final selected = _selectedMock;
    final conversion = selected == null
        ? const <String, double>{}
        : yonseiCsatComponents(selected);
    final snuConversion = selected == null
        ? const <String, double>{}
        : snuCsatComponents(selected);
    if (section?.failed == true) {
      return _notice('모의고사 조회 실패 · 수능 최저 준비도는 다시 조회한 뒤 확인하세요.');
    }
    if (sessions.isEmpty) {
      return const Text(
        '수능 최저 준비도 · 모의고사를 등록하면 같은 시험의 등급으로 비교합니다.',
        style: TextStyle(fontSize: 12, height: 1.6),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('mock/${_selectedMock?.id}'),
          initialValue: _selectedMock?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '수능 최저 비교할 모의고사'),
          items: [
            for (final session in sessions)
              DropdownMenuItem(
                value: session.id,
                child: Text(
                  session.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
          onChanged: (v) => setState(() => _mockSessionId = v),
        ),
        const SizedBox(height: 8),
        const Text(
          '처음에는 최신 시험을 선택합니다. 시험 간 최고 등급을 합치지 않으며 실제 수능 충족·합격 판정과 구분합니다.',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
        _conversionTile(
          title: '연세대 서울 정시 수능 환산 예시',
          note:
              '2028 시행계획 20·25쪽 · 선택한 모의고사의 수능 배점 예시. 한국사 감점을 반영한 수능 점수이며, 서류·면접 및 기타 감점은 합산하지 않습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 표준점수와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: conversion,
        ),
        _conversionTile(
          title: '서울대 정시 수능 환산 예시',
          note:
              '2028 시행계획 15·16·18쪽 · 1단계는 등급 환산(국어·수학·영어·한국사 각 1등급 10점~9등급 2점, 탐구는 통합사회·통합과학 평균), '
              '2단계는 백분위 반영 비율과 영어 감점 후 ×60/300입니다. 교과역량평가·면접은 합산하지 않으며 실제 지원 모집단위의 반영 비율을 확인하세요.',
          missing:
              '같은 시험의 국어·수학·영어·한국사·통합사회·통합과학 등급(1단계)과 국어·수학·통합사회·통합과학 백분위(2단계)를 영역별 한 건씩 등록해 주세요.',
          scores: snuConversion,
        ),
        _conversionTile(
          title: '가톨릭대 정시 수능 환산 예시',
          note:
              '2028 시행계획 28–29쪽 · 백분위 활용 전형(의예·약학·간호학과 제외). 일반전형Ⅰ은 국어·수학 우수 순 40·20%, 영어 환산점수 20%, '
              '통합사회·통합과학 상위 1과목 20%, 일반전형Ⅱ는 국어·수학 우수 1개 50%, 영어 20%, 탐구 30%이며 한국사 등급별 감점을 뺍니다. '
              '원문에 총점 척도가 없어 반영 비율 그대로의 100점 기준 값입니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : catholicCsatComponents(selected),
        ),
        _conversionTile(
          title: '인천대 정시 수능 환산 예시',
          note:
              '2028 시행계획 5·35–36쪽 · 국어·수학·탐구(사회·과학 상위 1과목) 백분위와 영어 등급별 점수(2028 변경표)로 계산한 1,000점 만점 점수입니다. '
              '한국사는 반영하지 않으며 예체능 모집단위 산식은 제외했습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : incheonCsatComponents(selected),
        ),
        _conversionTile(
          title: '상명대(서울) 정시 수능 환산 예시',
          note:
              '2028 시행계획 27–28쪽 · 백분위×반영비율×10(인문 국35·수30·영25·탐10, 자연 국30·수35·영25·탐10), '
              '영어 등급 점수, 탐구 상위 1과목(인문은 사회·자연은 과학탐구 5% 가산), 한국사 등급별 가산점. 원문 예시대로 소수점 셋째 자리까지 계산합니다. 예체능·실기 모집단위는 제외했습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : sangmyungCsatComponents(selected),
        ),
        _conversionTile(
          title: '동덕여대 정시 수능 환산 예시',
          note:
              '2028 시행계획 37–38쪽 · 일반 모집단위는 국어·수학 우수 순 35·25%, 영어 등급 점수 20%, 탐구 1과목 20%, '
              '약학과는 국25·수35·영20·과학탐구20%입니다. 총점 1,000점 기준으로 환산하고 한국사 가산점(최대 3점)을 별도로 더합니다. 예체능 모집단위는 제외했습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : dongdukCsatComponents(selected),
        ),
        _conversionTile(
          title: '명지대 정시 수능 환산 예시',
          note:
              '2028 시행계획 40쪽 · 백분위, 총점 900점(인문 국35·수25, 경영 30·30, 자연 25·35, 영어·탐구 각 20%). '
              '탐구는 계열에 맞는 탐구 10% 가산 후 상위 1과목, 한국사 가산점(3.0~1.4)을 총점 환산 뒤 더합니다. 실기 전형은 제외했습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : myongjiCsatComponents(selected),
        ),
        _conversionTile(
          title: '삼육대 정시 수능 환산 예시',
          note:
              '2028 시행계획 8쪽 · 백분위, 국어·수학·영어 환산·탐구 1과목 중 우수한 4개 영역 순 35/25/25/15%(약학과는 국25·수35·영25·과탐15). '
              '원문에 총점 척도가 없어 100점 기준 값이며 한국사는 반영하지 않습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : sahmyookCsatComponents(selected),
        ),
        _conversionTile(
          title: '경기대 정시 수능 환산 예시',
          note:
              '2028 시행계획 30쪽 · 백분위(인문 등 국40·수25·영20·탐15, 소프트웨어경영·융합과학·창의공과 국30·수35·영20·탐15), '
              '탐구 상위 1과목, 한국사 6등급부터 감점. 원문에 총점 척도가 없어 100점 기준 값입니다. 일반학생Ⅱ·실기 전형은 제외했습니다.',
          missing:
              '같은 시험의 국어·수학·통합사회·통합과학 백분위와 영어·한국사 등급을 영역별 한 건씩 등록해 주세요.',
          scores: selected == null
              ? const <String, double>{}
              : kyonggiCsatComponents(selected),
        ),
      ],
    );
  }

  Widget _conversionTile({
    required String title,
    required String note,
    required String missing,
    required Map<String, double> scores,
  }) {
    return ExpansionTile(
      title: Text(title),
      children: [
        ListTile(subtitle: Text(note)),
        if (scores.isEmpty) ListTile(subtitle: Text(missing)),
        for (final entry in scores.entries)
          ListTile(
            title: Text(entry.key),
            trailing: Text(entry.value.toStringAsFixed(2)),
          ),
      ],
    );
  }

  String _minimumTrackKey(AdmissionTrack t) =>
      AdmissionConditionStore.checkKey(t, '적용 기준');

  MinimumResult _minimumResult(AdmissionTrack t) {
    final branches = _minimumService.branches(t.minimum);
    final chosen = branches.length == 1
        ? branches.single
        : branches
              .where((b) => b.id == _minimumBranches[_minimumTrackKey(t)])
              .firstOrNull;
    if (chosen == null) {
      return const MinimumResult(
        MinimumStatus.manual,
        '학과·계열별 기준이 다릅니다. 전형 상세에서 실제 지원할 모집단위의 기준을 선택하세요. 관심 분야만으로 기준을 추정하지 않습니다.',
      );
    }
    return _minimumService.evaluate(
      chosen.text,
      _selectedMock,
      failed: _summary?.mockExams.failed ?? false,
    );
  }

  Widget _minimumOverview(UniversityCandidate u) {
    final counts = <MinimumStatus, int>{};
    for (final t in u.tracks) {
      final status = _minimumResult(t).status;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '수능 최저 준비도 · 모의고사 참고',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in counts.entries)
                Text(
                  '${e.key.label} ${e.value}개',
                  style: TextStyle(
                    fontSize: 12,
                    color: e.key == MinimumStatus.below
                        ? const Color(0xFF985A35)
                        : PathfinderTheme.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '전형·지원조건을 펼치면 적용 기준과 부족한 영역을 확인할 수 있어요.',
            style: TextStyle(fontSize: 12, color: PathfinderTheme.muted),
          ),
        ],
      ),
    );
  }

  Widget _minimumPanel(AdmissionTrack t) {
    final branches = _minimumService.branches(t.minimum);
    final result = _minimumResult(t);
    final color = result.status == MinimumStatus.met
        ? PathfinderTheme.accent
        : result.status == MinimumStatus.below
        ? const Color(0xFF985A35)
        : PathfinderTheme.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (branches.length > 1) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_minimumTrackKey(t)),
              initialValue: _minimumBranches[_minimumTrackKey(t)],
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '실제 지원할 학과·계열의 최저 기준',
              ),
              items: [
                for (final b in branches)
                  DropdownMenuItem(
                    value: b.id,
                    child: Text(
                      b.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                if (v != null) _minimumBranches[_minimumTrackKey(t)] = v;
              }),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            '모의고사 대비 수능 최저: ${result.status.label}',
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (result.status == MinimumStatus.met ||
              result.status == MinimumStatus.below ||
              result.status == MinimumStatus.insufficient)
            Text(
              _selectedMock?.label ?? '선택된 시험 없음',
              style: const TextStyle(
                fontSize: 12,
                color: PathfinderTheme.muted,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            result.reason,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          for (final detail in result.details)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                detail,
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          if (branches.length > 1 &&
              _minimumBranches[_minimumTrackKey(t)] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '선택 기준 원문: ${branches.firstWhere((b) => b.id == _minimumBranches[_minimumTrackKey(t)]).text}',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(
    String title,
    String value,
    IconData icon,
    Color tone, {
    String? caption,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8F6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: PathfinderTheme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: PathfinderTheme.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 12,
              color: PathfinderTheme.muted,
              height: 1.6,
            ),
          ),
        ],
      ],
    ),
  );
}
