import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/models/school_record_import.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';

class SchoolRecordReviewScreen extends StatefulWidget {
  const SchoolRecordReviewScreen({
    super.key,
    required this.result,
    required this.saveAllowed,
    this.loadGrades,
    this.saveBatch,
  });
  final SchoolRecordImport result;
  final bool saveAllowed;
  final Future<List<GradeRecord>> Function()? loadGrades;
  final Future<Map<String, dynamic>> Function(
    List<Map<String, dynamic>>,
    List<SchoolRecordEvidence>,
  )?
  saveBatch;
  @override
  State<SchoolRecordReviewScreen> createState() => _SchoolReviewState();
}

class _SchoolReviewState extends State<SchoolRecordReviewScreen> {
  final _form = GlobalKey<FormState>();
  final _base = TextEditingController();
  bool _confirmed = false, _busy = false, _loaded = false;
  String? _error;
  Set<String> _periods = {};
  final _numericErrors = <String, String>{};
  late final Map<String, String> _original;
  int _unknownYear = 1;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _original = {for (final e in widget.result.evidence) e.id: e.text};
    _load();
  }

  @override
  void dispose() {
    _base.dispose();
    super.dispose();
  }

  String period(int? y, int? grade, int? sem) => '$y/$grade/$sem';
  bool exists(SchoolGradeCandidate g) => _periods.contains(
    period(g.calendarYear, g.grade.schoolYear, g.grade.semester),
  );
  Future<void> _load() async {
    if (!widget.saveAllowed) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final rows =
          await (widget.loadGrades ?? GradeService.instance.fetchMyGrades)();
      if (mounted) {
        setState(() {
          _periods = rows
              .where((r) => r.examKind == 'semesterSummary')
              .map((r) => period(r.calendarYear, r.schoolYear, r.semester))
              .toSet();
          _loaded = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'DB 비교에 실패했습니다. 다시 조회한 뒤 저장하세요.');
    }
  }

  void changed(VoidCallback f) => setState(() {
    f();
    _confirmed = false;
  });
  void _applyYears() {
    final y = int.tryParse(_base.text);
    if (y == null || y < 2000 || y > 2098) {
      setState(() => _error = '1학년 연도는 2000~2098로 입력하세요.');
      return;
    }
    changed(() {
      _revision++;
      for (final g in widget.result.grades) {
        g.calendarYear = y + (g.grade.schoolYear ?? 1) - 1;
      }
      for (final e in widget.result.evidence) {
        e.schoolYear ??= _unknownYear;
        e.calendarYear = y + e.schoolYear! - 1;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy ||
        !_confirmed ||
        !_loaded ||
        !widget.saveAllowed ||
        !_form.currentState!.validate()) {
      return;
    }
    final now = DateTime.now();
    final grades = widget.result.grades
        .where((g) => g.selected && !exists(g))
        .toList();
    final evidence = widget.result.evidence
        .where((e) => e.selected)
        .map((e) => e.record(now))
        .toList();
    final errors = [
      for (final entry in _numericErrors.entries)
        if (grades.any((g) => entry.key.startsWith('${g.id}/')) ||
            widget.result.evidence.any(
              (e) => e.selected && entry.key.startsWith('${e.id}/'),
            ))
          entry.value,
      for (final g in grades) ...g.grade.validationErrors(),
      if (grades.any(
        (g) => (g.calendarYear ?? 0) - (g.grade.schoolYear ?? 1) + 1 < 2025,
      ))
        '현재 내신 DB는 2025년 이후 1학년 입학생의 5등급 자료만 지원합니다.',
      for (final e in evidence) ...e.validationErrors(),
    ];
    if (errors.isNotEmpty) {
      setState(() => _error = errors.toSet().join(' '));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await (widget.saveBatch?.call(
                grades.map((g) => g.toMap(now)).toList(),
                evidence,
              ) ??
              SchoolRecordService.instance.importReviewed(
                grades: grades.map((g) => g.toMap(now)).toList(),
                evidence: evidence,
              ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('생기부 저장 완료'),
          content: Text(
            '학기 종합 성적 ${result['grades']}과목 · 상담 근거 ${result['evidence']}개 저장\n기존 학기 성적은 유지했습니다. 중복 근거 ${result['skipped_evidence']}개는 건너뛰었습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '저장하지 못했습니다. 입력은 유지됩니다. 다시 시도하면 기존 학기·중복 근거를 건너뜁니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget field(
    String label,
    String value,
    ValueChanged<String> edit, {
    bool required = true,
    int lines = 1,
    String? Function(String?)? validate,
  }) => TextFormField(
    key: ValueKey('$label/$_revision'),
    initialValue: value,
    enabled: !_busy,
    decoration: InputDecoration(labelText: label),
    minLines: lines,
    maxLines: lines == 1 ? 1 : null,
    onChanged: edit,
    validator:
        validate ??
        (v) => required && (v?.trim().isEmpty ?? true)
            ? '필수 항목입니다.'
            : label == '성취도' &&
                  (v?.isNotEmpty ?? false) &&
                  !RegExp(r'^[A-E]$').hasMatch(v!.trim())
            ? 'A~E로 입력하세요.'
            : null,
  );
  Widget number(
    String owner,
    String label,
    num? value,
    ValueChanged<String> edit, {
    bool required = true,
  }) => field(
    label,
    value?.toString() ?? '',
    (v) {
      final n = num.tryParse(v);
      final key = '$owner/$label';
      if (v.trim().isNotEmpty &&
          (n == null ||
              !n.isFinite ||
              (!label.contains('점수') &&
                  !label.contains('평균') &&
                  !label.contains('학점') &&
                  n != n.roundToDouble()))) {
        _numericErrors[key] = '$label: 올바른 숫자·정수를 입력하세요.';
      } else {
        _numericErrors.remove(key);
      }
      edit(v);
    },
    required: required,
    validate: (v) {
      if (v == null || v.trim().isEmpty) return required ? '필수 항목입니다.' : null;
      final n = num.tryParse(v);
      if (n == null || !n.isFinite) return '숫자를 입력하세요.';
      if (label.contains('학점')) return n <= 0 ? '0보다 커야 합니다.' : null;
      if (label.contains('점수') || label.contains('평균')) {
        return n < 0 || n > 100 ? '0~100 범위를 확인하세요.' : null;
      }
      final max = label.contains('연도')
          ? 2100
          : label.contains('등급')
          ? 5
          : label == '학기'
          ? 2
          : 3;
      final min = label.contains('연도') ? 2000 : 1;
      return n != n.roundToDouble() || n < min || n > max
          ? '$min~$max 정수로 입력하세요.'
          : null;
    },
  );
  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final selected =
        r.grades.where((g) => g.selected && !exists(g)).length +
        r.evidence.where((e) => e.selected).length;
    return Scaffold(
      appBar: AppBar(title: const Text('생기부 추출 결과 확인')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '원본 PDF를 옆에 열어 연도·학년·수치·문장을 대조하세요. 이름·학교·학번·연락처는 삭제하세요. 원본 파일은 업로드하지 않습니다.',
            ),
            const Text('체육·예술·과학탐구실험·교양: 숫자 성적은 제외하고 세특·활동은 진로 상담 근거로 검토합니다.'),
            for (final w in r.warnings) Text(w),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_loaded)
              TextButton(onPressed: _load, child: const Text('DB 다시 비교')),
            TextFormField(
              controller: _base,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '1학년의 연도 (예: 2025)'),
              keyboardType: TextInputType.number,
            ),
            DropdownButtonFormField<int>(
              initialValue: _unknownYear,
              decoration: const InputDecoration(
                labelText: '학년을 읽지 못한 활동에 적용할 학년',
              ),
              items: [1, 2, 3]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v학년')))
                  .toList(),
              onChanged: _busy ? null : (v) => changed(() => _unknownYear = v!),
            ),
            TextButton(
              onPressed: _busy ? null : _applyYears,
              child: const Text('연도·미확인 학년 적용'),
            ),
            Text('학기 종합 성적 ${r.grades.length}과목'),
            const Text('5등급 내신만 지원합니다. 과목명과 로마숫자·소수점은 원본과 대조하세요.'),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => changed(
                      () => r.grades.add(
                        SchoolGradeCandidate(
                          grade: GradeDraft(),
                          source: '사용자 추가 · 원본 표 대조',
                        ),
                      ),
                    ),
              child: const Text('누락 과목 추가'),
            ),
            const Text(
              '이미 DB에 학기 종합 성적이 있는 학기는 통째로 건너뜁니다. 중간·기말은 유지됩니다. 일부 과목만 저장하면 나머지는 성적 화면에서 직접 입력해야 합니다.',
            ),
            for (final g in r.grades)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        title: Text(
                          '${g.grade.subjectName ?? "과목 미상"} · ${g.source}',
                        ),
                        subtitle: exists(g)
                            ? const Text('기존 학기 종합 성적 있음 · 저장 제외')
                            : null,
                        value: g.selected && !exists(g),
                        onChanged: _busy || exists(g)
                            ? null
                            : (v) => changed(() => g.selected = v!),
                      ),
                      if (g.selected && !exists(g)) ...[
                        number(
                          g.id,
                          '성적 연도',
                          g.calendarYear,
                          (v) =>
                              changed(() => g.calendarYear = int.tryParse(v)),
                        ),
                        number(
                          g.id,
                          '성적 학년',
                          g.grade.schoolYear,
                          (v) => changed(
                            () => g.grade.schoolYear = int.tryParse(v),
                          ),
                        ),
                        number(
                          g.id,
                          '학기',
                          g.grade.semester,
                          (v) =>
                              changed(() => g.grade.semester = int.tryParse(v)),
                        ),
                        field(
                          '과목명',
                          g.grade.subjectName ?? '',
                          (v) => changed(() => g.grade.subjectName = v),
                        ),
                        number(
                          g.id,
                          '학점',
                          g.grade.credit,
                          (v) => changed(
                            () => g.grade.credit = double.tryParse(v),
                          ),
                        ),
                        number(
                          g.id,
                          '원점수',
                          g.grade.rawScore,
                          (v) => changed(
                            () => g.grade.rawScore = double.tryParse(v),
                          ),
                          required: false,
                        ),
                        number(
                          g.id,
                          '과목평균',
                          g.grade.subjectAverage,
                          (v) => changed(
                            () => g.grade.subjectAverage = double.tryParse(v),
                          ),
                          required: false,
                        ),
                        field(
                          '성취도',
                          g.grade.achievement ?? '',
                          (v) => changed(
                            () => g.grade.achievement = v.trim().isEmpty
                                ? null
                                : v.trim(),
                          ),
                          required: false,
                        ),
                        number(
                          g.id,
                          '석차등급 (공란은 유지)',
                          g.grade.gradeRank,
                          (v) => changed(
                            () => g.grade.gradeRank = int.tryParse(v),
                          ),
                          required: false,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Text('상담 근거 ${r.evidence.length}개'),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => changed(
                      () => r.evidence.add(
                        SchoolEvidenceCandidate(
                          category: '활동 근거',
                          text: '',
                          source: '원본 쪽·항목을 입력하세요.',
                        ),
                      ),
                    ),
              child: const Text('누락 근거 추가'),
            ),
            for (final e in r.evidence)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        title: Text(e.category),
                        subtitle: Text(e.source),
                        value: e.selected,
                        onChanged: _busy
                            ? null
                            : (v) => changed(() => e.selected = v!),
                      ),
                      if (e.selected) ...[
                        number(
                          e.id,
                          '근거 연도',
                          e.calendarYear,
                          (v) =>
                              changed(() => e.calendarYear = int.tryParse(v)),
                        ),
                        number(
                          e.id,
                          '근거 학년',
                          e.schoolYear,
                          (v) => changed(() => e.schoolYear = int.tryParse(v)),
                        ),
                        field(
                          '활동·교과 항목',
                          e.category,
                          (v) => changed(() => e.category = v),
                        ),
                        ExpansionTile(
                          title: const Text('추출 문장 대조'),
                          children: [
                            SelectableText(
                              _original[e.id] ?? '직접 추가한 항목입니다. 원본과 대조하세요.',
                            ),
                          ],
                        ),
                        field(
                          '원문 근거 (개인정보 제거)',
                          e.text,
                          (v) => changed(() => e.text = v),
                          lines: 3,
                        ),
                        field(
                          '출처 위치',
                          e.source,
                          (v) => changed(() => e.source = v),
                        ),
                        field(
                          '관심 진로 메모',
                          e.careerInterest ?? '',
                          (v) => changed(() => e.careerInterest = v),
                          required: false,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            CheckboxListTile(
              title: const Text('선택한 모든 항목을 원본과 대조했고 개인정보를 제거했습니다.'),
              value: _confirmed,
              onChanged: _busy ? null : (v) => setState(() => _confirmed = v!),
            ),
            if (!widget.saveAllowed) const Text('로그인한 일반 모드에서만 저장할 수 있습니다.'),
            if (_busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed:
                  !_busy &&
                      _confirmed &&
                      _loaded &&
                      widget.saveAllowed &&
                      selected > 0
                  ? _save
                  : null,
              child: Text('선택한 $selected개 저장'),
            ),
          ],
        ),
      ),
    );
  }
}
