import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/consulting_draft_store.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/services/consulting_service.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/screens/record_chat_screen.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';

class ConsultingScreen extends StatefulWidget {
  const ConsultingScreen({super.key, this.loadSummary, this.draftStore});
  final ConsultingDraftStore? draftStore;
  final Future<CounselingSummary> Function()? loadSummary;
  @override
  State<ConsultingScreen> createState() => _ConsultingScreenState();
}

class _ConsultingScreenState extends State<ConsultingScreen> {
  final _goal = TextEditingController();
  CounselingSummary? _summary;
  bool _busy = false;
  String? _error;
  final Set<String> _selected = {};
  bool _onlySelected = false;
  ConsultingDraftStore? _store;
  bool _restoring = true;
  bool _saving = false;
  String? _draftError;
  String? _draftStatus;

  @override
  void initState() {
    super.initState();
    _store = widget.draftStore;
    if (_store == null) {
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) _store = ConsultingDraftStore(uid);
      } catch (_) {
        // Supabase is not initialized in offline previews.
      }
    }
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _draftError = null;
    });
    try {
      final draft = await _store?.load();
      if (!mounted) return;
      if (draft != null) {
        _goal.text = draft.goal;
        _selected
          ..clear()
          ..addAll(draft.selected);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _draftError = '상담 준비를 복원하지 못했습니다. 다시 불러온 뒤 저장하세요.');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
    if (mounted) await _load();
  }

  Future<void> _saveDraft() async {
    setState(() {
      _saving = true;
      _draftStatus = null;
    });
    try {
      await _store!.save(ConsultingDraft(_goal.text, _selected));
      if (mounted) setState(() => _draftStatus = '이 기기에 상담 준비를 저장했습니다.');
    } catch (_) {
      if (mounted) {
        setState(() => _draftStatus = '저장하지 못했습니다. 입력 내용을 유지했으니 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _summary = null;
      _error = null;
    });
    try {
      final s =
          await (widget.loadSummary ?? CounselingSummaryService().fetch)();
      if (!mounted) return;
      setState(() {
        _summary = s;
        final ids = s.activitiesFor(null).map((e) => e.id).toSet();
        if (!s.activities.failed) {
          _selected.removeWhere((id) => !ids.contains(id));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '상담 자료를 불러오지 못했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final consultations = s == null
        ? <EvidenceConsultation>[]
        : ConsultingService().build(s);
    final visible = consultations.where(
      (c) => !_onlySelected || _selected.contains(c.source.id),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('생기부 컨설팅'),
        actions: [
          IconButton(
            tooltip: '최신 자료로 새로고침',
            onPressed: _busy || _restoring || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '나의 경험에서 다음 탐구로',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            '원문 키워드로 상담 질문을 제안합니다. 이 질문들은 문맥을 이해하는 AI 분석이 아니므로 실제 경험에 맞는지 확인하세요. 근거를 골라 AI 상담을 열면 대화로 더 깊이 정리할 수 있습니다. 적성·합격 가능성을 판정하지 않습니다.',
          ),
          const SizedBox(height: 16),
          TextField(
            enabled: !_restoring && !_saving,
            controller: _goal,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: '관심 진로·이번 상담 질문',
              hintText: '예: 생명과학 탐구를 어떤 주제로 이어갈까?',
            ),
            onChanged: (_) => setState(() => _draftStatus = null),
          ),
          const Text('목표 입력은 자동 학과 추천이나 근거 필터에 사용되지 않습니다.'),
          Text(
            _store == null ? '체험 모드의 목표와 선택은 이 화면에서만 유지됩니다.' : '상담 준비 저장을 누르면 목표와 선택을 현재 계정의 이 브라우저·기기에 저장합니다. 다른 기기에는 동기화되지 않으며 브라우저 데이터 삭제 시 사라집니다.',
          ),
          if (_restoring) const LinearProgressIndicator(),
          if (_draftError != null) ...[
            Text(_draftError!),
            TextButton(
              onPressed: _restoring ? null : _restore,
              child: const Text('상담 준비 다시 불러오기'),
            ),
          ],
          if (_store != null)
            OutlinedButton.icon(
              onPressed:
                  _restoring ||
                      _saving ||
                      _busy ||
                      _draftError != null ||
                      s == null ||
                      s.activities.failed
                  ? null
                  : _saveDraft,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? '저장 중…' : '상담 준비 저장'),
            ),
          if (_draftStatus != null) Text(_draftStatus!),
          if (_goal.text.trim().isNotEmpty) Text('상담 목표: ${_goal.text.trim()}'),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('다시 불러오기')),
          ],
          if (s != null) ...[
            FilledButton.icon(
              icon: const Icon(Icons.school_outlined),
              label: const Text('성적·생기부로 대학 후보 보기'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UniversityRecommendationScreen(
                    loadSummary: widget.loadSummary,
                  ),
                ),
              ),
            ),
            if (s.activities.failed) ...[
              const Text('생활기록부 조회에 실패해 상담 근거를 구성하지 못했습니다.'),
              TextButton(onPressed: _load, child: const Text('자료 다시 조회')),
            ] else if (consultations.isEmpty)
              const Text('상담에 활용할 생기부 근거가 없습니다. 근거 저장 여부와 상담 활용 설정을 확인하세요.'),
            if (s.grades.failed || s.mockExams.failed)
              const Text('일부 성적 조회에 실패했습니다. 생기부 질문은 조회된 근거로만 구성했습니다.'),
            Text(
              '확인된 내신 ${s.confirmedGrades.length}개 · 저장된 모의고사 ${s.mockExams.records.length}개 영역 · 활용 근거 ${consultations.length}개',
            ),
            const Text(
              '성적의 상세 수치는 상담 요약에서 확인하세요. 시험·학기·등급 체계가 다른 성적은 합산하지 않습니다.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('선택한 근거만 보기 (${_selected.length}개)'),
              value: _onlySelected,
              onChanged: (v) => setState(() => _onlySelected = v),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: const Text('선택 근거 상담 메모 복사'),
              onPressed: _selected.isEmpty || s.activities.failed
                  ? null
                  : () async {
                      try {
                        final memo = ConsultingService().memo(
                          s,
                          _selected,
                          _goal.text,
                        );
                        if (memo.isEmpty) return;
                        await Clipboard.setData(ClipboardData(text: memo));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('목표·선택 원문·출처·상담 질문을 복사했습니다.'),
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('복사하지 못했습니다. 다시 시도하세요.'),
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.forum_outlined),
              label: Text('선택한 근거로 AI 상담 (${_selected.length}개)'),
              onPressed:
                  _selected.isEmpty ||
                      _selected.length > RecordChatService.maxEvidence ||
                      s.activities.failed
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecordChatScreen(
                          evidence: [
                            for (final c in consultations)
                              if (_selected.contains(c.source.id)) c.source,
                          ],
                          goal: _goal.text,
                        ),
                      ),
                    ),
            ),
            Text(
              _selected.length > RecordChatService.maxEvidence
                  ? 'AI 상담은 근거를 ${RecordChatService.maxEvidence}개까지 고를 수 있습니다. 선택을 줄이세요.'
                  : '상담할 근거를 1~${RecordChatService.maxEvidence}개 고르면 AI와 대화하며 강점·다음 탐구를 정리할 수 있습니다. 시작 전에 외부 전송 동의를 받습니다.',
            ),
            if (_onlySelected && visible.isEmpty && consultations.isNotEmpty)
              const Text('선택한 근거가 없습니다. 전체 보기로 돌아가 상담할 근거를 선택하세요.'),
            for (final c in visible)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${c.source.calendarYear}년 ${c.source.schoolYear}학년 · ${c.source.category}',
                        ),
                        subtitle: const Text('이번 상담에서 다룰 근거 선택'),
                        value: _selected.contains(c.source.id),
                        onChanged: _saving || _restoring
                            ? null
                            : (v) => setState(() {
                                _draftStatus = null;
                                if (v == true) {
                                  _selected.add(c.source.id);
                                } else {
                                  _selected.remove(c.source.id);
                                }
                              }),
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('근거 원문·출처 확인'),
                        children: [
                          SelectableText(c.source.evidence),
                          Text('출처: ${c.source.sourceLocation}'),
                          Text('원본 대조: ${c.source.confirmedAt.toLocal()}'),
                          if (c.source.careerInterest?.trim().isNotEmpty ==
                              true)
                            Text('사용자 진로 메모: ${c.source.careerInterest}'),
                        ],
                      ),
                      for (final point in c.points) ...[
                        const SizedBox(height: 12),
                        Text(
                          point.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('상담 질문: ${point.question}'),
                        Text('다음 행동 제안: ${point.action}'),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
