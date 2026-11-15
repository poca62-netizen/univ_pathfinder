import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/screens/grade_extraction_review_screen_v2.dart';

class GradeAnalysisScreen extends StatefulWidget {
  const GradeAnalysisScreen({
    super.key,
    this.loadGrades,
    this.deleteGrade,
    this.updateGrade,
    this.initialSchoolYear,
    this.initialSemester,
    this.initialCalendarFilter,
    this.initialExamFilter,
  });
  final int? initialSchoolYear;
  final int? initialSemester;
  final String? initialCalendarFilter;
  final String? initialExamFilter;
  final Future<List<GradeRecord>> Function()? loadGrades;
  final Future<void> Function(String)? deleteGrade;
  final Future<void> Function(String, Map<String, dynamic>)? updateGrade;

  @override
  State<GradeAnalysisScreen> createState() => _GradeAnalysisState();
}

class _GradeAnalysisState extends State<GradeAnalysisScreen> {
  List<GradeRecord> _records = [];
  bool _loading = true;
  String? _deleting;
  String? _error;
  int? _year;
  int? _semester;
  String? _calendarFilter;
  String? _examFilter;

  @override
  void initState() {
    super.initState();
    _year = widget.initialSchoolYear;
    _semester = widget.initialSemester;
    _calendarFilter = widget.initialCalendarFilter;
    _examFilter = widget.initialExamFilter;
    _load();
  }

  Future<void> _load() async {
    if (_deleting != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records =
          await (widget.loadGrades ?? GradeService.instance.fetchMyGrades)();
      if (mounted) {
        setState(
          () => _records = records.where((r) => r.isInGradeScope).toList(),
        );
      }
    } on GradeServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '성적을 불러오지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(GradeRecord record) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GradeExtractionReviewScreenV2(
          isEditing: true,
          sourceLabel:
              '${record.calendarYear ?? "연도 미상"} · ${record.examLabel}',
          result: ExtractionResult(
            subjects: [
              GradeDraft(
                schoolYear: record.schoolYear,
                semester: record.semester,
                subjectName: record.subjectName,
                credit: record.credit,
                rawScore: record.rawScore,
                subjectAverage: record.subjectAverage,
                achievement: record.achievement,
                gradeRank: record.gradeRank,
                achievementDistribution: record.achievementDistribution,
              ),
            ],
          ),
          saveGrades: (rows) =>
              (widget.updateGrade ?? GradeService.instance.updateMyGrade)(
                record.id,
                rows.single,
              ),
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(GradeRecord record) async {
    if (_deleting != null || _loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장된 성적 삭제'),
        content: Text(
          '${record.schoolYear}학년 ${record.semester}학기 ${record.subjectName} 성적을 DB에서 삭제합니다. 삭제한 성적은 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = record.id);
    try {
      await (widget.deleteGrade ?? GradeService.instance.deleteMyGrade)(
        record.id,
      );
      if (!mounted) return;
      setState(() => _records.removeWhere((r) => r.id == record.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('성적을 삭제했습니다.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _records
        .where(
          (r) =>
              (_year == null || r.schoolYear == _year) &&
              (_semester == null || r.semester == _semester) &&
              (_calendarFilter == null ||
                  (r.calendarYear?.toString() ?? 'unknown') ==
                      _calendarFilter) &&
              (_examFilter == null || (r.examKind ?? 'unknown') == _examFilter),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('성적 분석'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading || _deleting != null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('재시도')),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'DB에 저장된 내 성적 ${_records.length}개',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('전체 학년'),
                          selected: _year == null,
                          onSelected: (_) => setState(() => _year = null),
                        ),
                        for (final year in [1, 2, 3])
                          ChoiceChip(
                            label: Text('$year학년'),
                            selected: _year == year,
                            onSelected: (_) => setState(() => _year = year),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('전체 학기'),
                          selected: _semester == null,
                          onSelected: (_) => setState(() => _semester = null),
                        ),
                        for (final semester in [1, 2])
                          ChoiceChip(
                            label: Text('$semester학기'),
                            selected: _semester == semester,
                            onSelected: (_) =>
                                setState(() => _semester = semester),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('전체 연도'),
                          selected: _calendarFilter == null,
                          onSelected: (_) =>
                              setState(() => _calendarFilter = null),
                        ),
                        for (final year
                            in (_records
                                .map((r) => r.calendarYear)
                                .whereType<int>()
                                .toSet()
                                .toList()
                              ..sort()))
                          ChoiceChip(
                            label: Text('$year년'),
                            selected: _calendarFilter == '$year',
                            onSelected: (_) =>
                                setState(() => _calendarFilter = '$year'),
                          ),
                        ChoiceChip(
                          label: const Text('연도 미상'),
                          selected: _calendarFilter == 'unknown',
                          onSelected: (_) =>
                              setState(() => _calendarFilter = 'unknown'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('전체 시험'),
                          selected: _examFilter == null,
                          onSelected: (_) => setState(() => _examFilter = null),
                        ),
                        for (final entry in const {
                          'midterm': '중간고사',
                          'finalExam': '기말고사',
                          'semesterSummary': '학기 종합',
                          'unknown': '시험 미상',
                        }.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _examFilter == entry.key,
                            onSelected: (_) =>
                                setState(() => _examFilter = entry.key),
                          ),
                      ],
                    ),
                    Text('조회 결과 ${visible.length}개 과목'),
                    if (_records.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('저장된 성적이 없습니다. 홈에서 성적을 입력하세요.'),
                      )
                    else if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('선택한 학년·학기에 저장된 성적이 없습니다.'),
                      ),
                    for (final record in visible)
                      Card(
                        key: ValueKey(record.id),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${record.schoolYear}학년 ${record.semester}학기 · ${record.subjectName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '${record.subjectName} 성적 수정',
                                    onPressed: _deleting != null
                                        ? null
                                        : () => _edit(record),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '${record.subjectName} 성적 삭제',
                                    onPressed: _deleting != null
                                        ? null
                                        : () => _delete(record),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Text(
                                '${record.calendarYear == null ? "연도 미상" : "${record.calendarYear}년"} · ${record.examLabel}',
                              ),
                              if (record.sourceLocation != null)
                                Text('출처: ${record.sourceLocation}'),
                              if (record.sourceConfirmedAt != null)
                                Text(
                                  '원본 대조 확인 ${record.sourceConfirmedAt!.toLocal().toIso8601String().substring(0, 10)}',
                                )
                              else
                                const Text('현재 값의 원본 대조 확인 기록 없음'),
                              Text(
                                '학점 ${record.credit} · 원점수 ${record.rawScore ?? "-"} · 평균 ${record.subjectAverage ?? "-"}',
                              ),
                              Text(
                                '성취도 ${record.achievement ?? "-"} · 석차등급 ${record.gradeRank ?? "-"}',
                              ),
                              if (record.achievementDistribution?.isNotEmpty ??
                                  false)
                                Text(
                                  '성취도 분포: ${record.achievementDistribution!.entries.map((e) => '${e.key} ${e.value}%').join(', ')}',
                                ),
                              Text(
                                '저장일 ${record.createdAt.toLocal().toIso8601String().substring(0, 10)}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Text(
                      '연도·시험 구분이 없는 기존 기록은 미상으로 표시합니다. 서로 다른 시험을 합산하지 않습니다.',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
