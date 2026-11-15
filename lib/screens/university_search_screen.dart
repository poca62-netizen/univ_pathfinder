import 'package:flutter/material.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/widgets/official_admission_source.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/services/university_comparison_memo.dart';
import 'package:univ_pathfinder/widgets/university_selection_controls.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';

class UniversitySearchScreen extends StatefulWidget {
  const UniversitySearchScreen({
    super.key,
    this.compare = false,
    this.loadCatalog,
    this.loadTuition,
    this.selectionStore,
  });
  final bool compare;
  final UniversitySelectionStore? selectionStore;
  final Future<AdmissionCatalog> Function()? loadCatalog;
  final Future<TuitionCatalog> Function()? loadTuition;
  @override
  State<UniversitySearchScreen> createState() => _UniversitySearchScreenState();
}

class _UniversitySearchScreenState extends State<UniversitySearchScreen> {
  final _session = CounselingSession.instance;
  AdmissionCatalog? _catalog;
  TuitionCatalog? _tuition;
  bool _loading = true, _special = false;
  String? _error, _tuitionError;
  String _query = '', _type = '전체';
  bool _copying = false;
  bool _historyBusy = false;

  String? get _historyKey {
    var userId = widget.selectionStore?.userId;
    if (userId == null) {
      try {
        userId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {
        // Offline previews have no authenticated client.
      }
    }
    return userId == null || userId.isEmpty
        ? null
        : 'comparison_history_v1/$userId';
  }

  Future<void> _comparisonHistory({required bool save}) async {
    final key = _historyKey;
    if (key == null || _historyBusy) return;
    final catalog = _catalog;
    final selected = _session.catalogSelection;
    if (save && (catalog == null || selected.isEmpty)) return;
    final memo = save
        ? UniversityComparisonMemo().build(
            catalog: catalog!,
            selected: selected,
            tuition: _tuition,
            query: _query,
            type: _type,
            includeSpecial: _special,
          )
        : null;
    setState(() => _historyBusy = true);
    try {
      final preferences = SharedPreferencesAsync();
      var history = await preferences.getStringList(key) ?? <String>[];
      if (!mounted || _historyKey != key) return;
      if (memo != null) {
        final date = MaterialLocalizations.of(context)
            .formatShortDate(DateTime.now());
        final label =
            '$date · ${selected.take(3).join(', ')}${selected.length > 3 ? ' 외 ${selected.length - 3}곳' : ''}';
        await preferences.setStringList(
          key,
          ['$label\n$memo', ...history].take(10).toList(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 브라우저에 비교 결과를 저장했습니다.')),
          );
        }
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          var deleting = false;
          String? deleteError;

          Future<void> deleteEntry(
            BuildContext context,
            StateSetter update,
            String entry,
          ) async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('비교 기록을 삭제할까요?'),
                content: Text(entry.split('\n').first),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            );
            if (confirmed != true ||
                !context.mounted ||
                !mounted ||
                _historyKey != key) {
              return;
            }
            update(() {
              deleting = true;
              deleteError = null;
            });
            try {
              final latest = await preferences.getStringList(key) ?? <String>[];
              if (!context.mounted || !mounted || _historyKey != key) return;
              if (latest.remove(entry)) {
                await preferences.setStringList(key, latest);
              }
              if (context.mounted) update(() => history = latest);
            } catch (_) {
              if (context.mounted) {
                update(() => deleteError = '비교 기록을 삭제하지 못했습니다. 다시 시도하세요.');
              }
            } finally {
              if (context.mounted) update(() => deleting = false);
            }
          }

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('저장한 대학 비교'),
              content: SizedBox(
                width: 500,
                child: history.isEmpty
                    ? const Text('저장한 비교 결과가 없습니다.')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (deleteError != null)
                              Text(
                                deleteError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            for (final entry in history)
                              ExpansionTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(entry.split('\n').first),
                                    ),
                                    IconButton(
                                      tooltip: '비교 기록 삭제',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: deleting
                                          ? null
                                          : () => deleteEntry(
                                              context,
                                              setDialogState,
                                              entry,
                                            ),
                                    ),
                                  ],
                                ),
                                children: [
                                  SelectableText(
                                    entry.substring(entry.indexOf('\n') + 1),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting ? null : () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비교 기록을 처리하지 못했습니다. 다시 시도하세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  Future<void> _copyMemo() async {
    final catalog = _catalog;
    if (catalog == null || _session.catalogSelection.isEmpty) return;
    final memo = UniversityComparisonMemo().build(
      catalog: catalog,
      selected: _session.catalogSelection,
      tuition: _tuition,
      query: _query,
      type: _type,
      includeSpecial: _special,
    );
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: memo));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 조건의 전형·등록금·출처를 비교 메모로 복사했습니다.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메모를 복사하지 못했습니다. 다시 시도하세요.')),
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _tuitionError = null;
      _catalog = null;
      _tuition = null;
    });
    final service = UniversityRecommendationService();
    await Future.wait([
      () async {
        try {
          final value = await (widget.loadCatalog ?? service.loadCatalog)();
          if (mounted) setState(() => _catalog = value);
        } catch (_) {
          if (mounted) setState(() => _error = '전형 자료를 불러오지 못했습니다.');
        }
      }(),
      () async {
        try {
          final value = await (widget.loadTuition ?? service.loadTuition)();
          if (mounted) setState(() => _tuition = value);
        } catch (_) {
          if (mounted) setState(() => _tuitionError = '등록금 자료를 불러오지 못했습니다.');
        }
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  void _toggle(String name) {
    if (!_session.toggleCatalogUniversity(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('최대 10개 대학까지 선택할 수 있습니다. 기존 선택을 해제해 주세요.'),
        ),
      );
    }
  }

  Widget _details(String name, List<AdmissionTrack> tracks) => ExpansionTile(
    title: const Text('전형 원문·등록금 출처 확인'),
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: OfficialAdmissionSource(university: name, year: _catalog?.year),
      ),
      if (_tuition != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in _tuition!.forUniversity(name))
                Text(
                  '${r.officialName} ${r.campus} · ${r.year}년 연간 평균 ${r.amountLabel}\n기준일 ${r.asOf} · ${r.scope}',
                ),
              Text(_tuition!.note),
              SelectableText(
                '등록금 출처: ${_tuition!.source}\n${_tuition!.sourceUrl}',
              ),
            ],
          ),
        ),
      for (final t in tracks)
        ExpansionTile(
          title: Text('${t.type} · ${t.name}'),
          subtitle: Text(
            '모집단위: ${t.department.isEmpty ? "자료 미기재" : t.department}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('모집 인원 원문: ${t.quota.isEmpty ? "자료 미기재" : t.quota}'),
                  Text('지원자격: ${t.eligibility}'),
                  Text('추천: ${t.recommendation} · 추천 주체: ${t.recommender}'),
                  Text('선발 방법: ${t.selection}'),
                  Text('수능 최저: ${t.minimum}'),
                  if (t.requiresSpecialEligibility)
                    const Text('특별 지원자격 확인이 필요한 전형입니다.'),
                  AdmissionTrackReview(track: t),
                ],
              ),
            ),
          ],
        ),
    ],
  );

  void _open(bool compare) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UniversitySearchScreen(
        compare: compare,
        loadCatalog: widget.loadCatalog,
        loadTuition: widget.loadTuition,
        selectionStore: widget.selectionStore,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.compare ? '모집정보·등록금 비교' : '수도권 대학 탐색')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListenableBuilder(
            listenable: _session,
            builder: (context, _) {
              final catalog = _catalog;
              final query = _query.trim().toLowerCase();
              final grouped = <String, List<AdmissionTrack>>{};
              for (final track in catalog?.tracks ?? <AdmissionTrack>[]) {
                if (widget.compare &&
                    !_session.catalogSelection.contains(track.university)) {
                  continue;
                }
                if (_type != '전체' && track.type != _type) continue;
                if (!_special && track.requiresSpecialEligibility) continue;
                if (query.isNotEmpty &&
                    !'${track.university} ${track.department} ${track.name}'
                        .toLowerCase()
                        .contains(query)) {
                  continue;
                }
                grouped.putIfAbsent(track.university, () => []).add(track);
              }
              final names = grouped.keys.toList()..sort();
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.sizeOf(context).width < 600
                            ? 16
                            : 28,
                        vertical: 20,
                      ),
                      itemCount: names.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _overview(context, catalog),
                              const SizedBox(height: 16),
                              UniversitySelectionControls(
                                store: widget.selectionStore,
                              ),
                              if (catalog != null)
                                for (final name
                                    in _session.catalogSelection.where(
                                      (name) => !catalog.tracks.any(
                                        (t) => t.university == name,
                                      ),
                                    ))
                                  InputChip(
                                    label: Text('$name · 현재 자료 없음'),
                                    onDeleted:
                                        _session.selectionBusy ||
                                            _session.selectionError != null
                                        ? null
                                        : () => _toggle(name),
                                  ),
                              const SizedBox(height: 16),
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: '대학명·학과명·전형명 검색',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: (v) => setState(() => _query = v),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children:
                                    [
                                          '전체',
                                          '학생부교과',
                                          '학생부종합',
                                          '논술',
                                          '수능위주',
                                          '실기/실적',
                                        ]
                                        .map(
                                          (type) => ChoiceChip(
                                            label: Text(type),
                                            selected: _type == type,
                                            onSelected: (_) =>
                                                setState(() => _type = type),
                                          ),
                                        )
                                        .toList(),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('특별 지원자격 전형 포함'),
                                value: _special,
                                onChanged: (v) => setState(() => _special = v),
                              ),
                              Text(
                                '검색 결과 ${names.length}개 대학 · 선택 ${_session.catalogSelection.length}/10',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_loading) const LinearProgressIndicator(),
                              if (_error != null) Text(_error!),
                              if (_tuitionError != null) Text(_tuitionError!),
                              if (_error != null || _tuitionError != null)
                                TextButton(
                                  onPressed: _loading ? null : _load,
                                  child: const Text('자료 다시 불러오기'),
                                ),
                              if (!_loading && catalog != null && names.isEmpty)
                                Text(
                                  widget.compare &&
                                          _session.catalogSelection.isEmpty
                                      ? '대학 탐색에서 비교할 대학을 선택하세요.'
                                      : '조건에 맞는 전형이 없습니다. 검색어와 필터를 확인하세요. 선택한 대학은 유지됩니다.',
                                ),
                              if (widget.compare) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      icon: const Icon(
                                        Icons.bookmark_add_outlined,
                                      ),
                                      onPressed:
                                          _historyKey == null ||
                                              _historyBusy ||
                                              _loading ||
                                              catalog == null ||
                                              _session
                                                  .catalogSelection
                                                  .isEmpty ||
                                              _session.selectionBusy ||
                                              _session.selectionError != null
                                          ? null
                                          : () =>
                                                _comparisonHistory(save: true),
                                      label: const Text('비교 결과 저장'),
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.history),
                                      onPressed:
                                          _historyKey == null || _historyBusy
                                          ? null
                                          : () =>
                                                _comparisonHistory(save: false),
                                      label: const Text('저장한 비교 보기'),
                                    ),
                                  ],
                                ),
                                Text(
                                  _historyKey == null
                                      ? '로그인하면 비교 결과를 저장할 수 있습니다.'
                                      : '비교 결과는 현재 계정의 브라우저에 최근 10건까지 저장됩니다.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (widget.compare)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 8,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text('선택 대학 직선거리 지도'),
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UniversityMapScreen(
                                              selectionStore:
                                                  widget.selectionStore,
                                            ),
                                          ),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.copy_outlined),
                                        label: Text(
                                          _copying ? '복사 중…' : '선택 대학 비교 메모 복사',
                                        ),
                                        onPressed:
                                            _copying ||
                                                _loading ||
                                                catalog == null ||
                                                _session.selectionBusy ||
                                                _session.selectionError !=
                                                    null ||
                                                _session
                                                    .catalogSelection
                                                    .isEmpty
                                            ? null
                                            : _copyMemo,
                                      ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.add),
                                        label: const Text('후보 추가·변경'),
                                        onPressed: () => _open(false),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.compare)
                                Text(
                                  '비교 메모에는 현재 검색·전형 조건이 적용됩니다.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (widget.compare &&
                                  _session.catalogSelection.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  children: _session.catalogSelection
                                      .map(
                                        (name) => InputChip(
                                          label: Text(name),
                                          onDeleted:
                                              _session.selectionBusy ||
                                                  _session.selectionError !=
                                                      null
                                              ? null
                                              : () => _toggle(name),
                                        ),
                                      )
                                      .toList(),
                                ),
                              const SizedBox(height: 16),
                            ],
                          );
                        }
                        final name = names[index - 1];
                        final tracks = grouped[name]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  title: Text(
                                    name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  value: _session.catalogSelection.contains(
                                    name,
                                  ),
                                  onChanged:
                                      _session.selectionBusy ||
                                          _session.selectionError != null
                                      ? null
                                      : (_) => _toggle(name),
                                  subtitle: Text(
                                    '${tracks.length}개 전형 · ${_tuition?.labelFor(name) ?? (_tuitionError == null ? "등록금 자료 확인 대기" : "등록금 조회 실패")}',
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                _details(name, tracks),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (!widget.compare)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _session.catalogSelection.isEmpty
                              ? null
                              : () => _open(true),
                          child: Text(
                            '선택한 ${_session.catalogSelection.length}개 대학 비교',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _overview(BuildContext context, AdmissionCatalog? catalog) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PathfinderTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${catalog?.year ?? 2028}학년도 입학전형',
            style: theme.textTheme.labelLarge?.copyWith(
              color: PathfinderTheme.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.compare
                ? '관심 대학 ${_session.catalogSelection.length}/10개'
                : '실제 대학 자료에서 후보 찾기',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.compare
                ? '대학별 전형과 공시 등록금을 한곳에서 확인하세요.'
                : '대학, 모집단위, 전형 이름으로 수도권 대학을 찾아보세요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            catalog == null
                ? '전형계획 자료 확인 중'
                : catalog.status,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '등록금은 공시된 연간 평균입니다. 학과별 금액과 최종 전형 조건은 대학 공식 자료에서 확인하세요.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
