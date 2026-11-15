import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';

class MockExamEditScreen extends StatefulWidget {
  const MockExamEditScreen({
    super.key,
    this.record,
    this.calendarYear,
    this.schoolYear = 1,
    this.examMonth = 3,
    this.sourceText,
    this.recognizedGrades = const {},
    this.recognitionWarnings = const [],
    this.saveAllowed = true,
    this.saveRecord,
  });
  final MockExamRecord? record;
  final int? calendarYear;
  final int schoolYear, examMonth;
  final String? sourceText;
  final Map<String, int> recognizedGrades;
  final List<String> recognitionWarnings;
  final bool saveAllowed;
  final Future<void> Function(MockExamRecord, bool)? saveRecord;
  @override
  State<MockExamEditScreen> createState() => _MockExamEditState();
}

class _MockExamEditState extends State<MockExamEditScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late final String _id;
  bool _busy = false, _confirmed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _id = r?.id ?? MockExamService.newId();
    final initial = <String, Object?>{
      '연도': r?.calendarYear ?? widget.calendarYear ?? DateTime.now().year,
      '학년': r?.schoolYear ?? widget.schoolYear,
      '시행 월': r?.examMonth ?? widget.examMonth,
      '시행 기관': r?.institution,
      '영역': r?.subject,
      '선택 과목': r?.elective,
      '원점수': r?.rawScore,
      '표준점수': r?.standardScore,
      '백분위': r?.percentile,
      '등급': r?.gradeRank,
    };
    for (final entry in initial.entries) {
      _fields[entry.key] = TextEditingController(
        text: entry.value?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String text(String key) => _fields[key]!.text.trim();
  double? number(String key) => double.tryParse(text(key));
  String? _validate(String key, String? input) {
    final v = input?.trim() ?? '';
    if (key == '영역') return v.isEmpty ? '영역을 입력하세요.' : null;
    if (key == '시행 기관' || key == '선택 과목') return null;
    final required = const ['연도', '학년', '시행 월'].contains(key);
    if (v.isEmpty) return required ? '필수 항목입니다.' : null;
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return '숫자를 입력하세요.';
    if (const ['연도', '학년', '시행 월', '등급'].contains(key) &&
        int.tryParse(v) == null) {
      return '정수를 입력하세요.';
    }
    final (min, max) = switch (key) {
      '연도' => (2000, 2100),
      '학년' => (1, 3),
      '시행 월' => (1, 12),
      '등급' => (1, 9),
      '표준점수' => (0, double.maxFinite),
      _ => (0, 100),
    };
    return n < min || n > max ? '$min~$max 범위를 확인하세요.' : null;
  }

  Future<void> _save() async {
    if (_busy ||
        !widget.saveAllowed ||
        !_confirmed ||
        !_form.currentState!.validate()) {
      return;
    }
    final record = MockExamRecord(
      id: _id,
      calendarYear: int.parse(text('연도')),
      schoolYear: int.parse(text('학년')),
      examMonth: int.parse(text('시행 월')),
      subject: text('영역'),
      institution: text('시행 기관'),
      elective: text('선택 과목'),
      rawScore: number('원점수'),
      standardScore: number('표준점수'),
      percentile: number('백분위'),
      gradeRank: int.tryParse(text('등급')),
    );
    final errors = record.validationErrors();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join(' '));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.saveRecord != null) {
        await widget.saveRecord!(record, widget.record != null);
      } else {
        await MockExamService.instance.save(
          record,
          editing: widget.record != null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '저장하지 못했습니다. 입력은 유지됩니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record == null ? '모의고사 성적 입력' : '모의고사 성적 수정'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('영역별로 저장합니다. 원본에 없는 지표는 비워두세요. 내신 성적과 합산하지 않습니다.'),
          if (!widget.saveAllowed) const Text('체험·가상 예시는 DB에 저장하지 않습니다.'),
          if (widget.sourceText != null)
            ExpansionTile(
              title: const Text('추출 원문 대조'),
              children: [
                const Text('자동 열 매핑은 지원하지 않습니다. 원문과 원본 파일을 대조해 영역별 값을 입력하세요.'),
                SelectableText(widget.sourceText!),
              ],
            ),
          for (final warning in widget.recognitionWarnings) Text(warning),
          if (widget.record == null && widget.recognizedGrades.isNotEmpty) ...[
            const Text(
              '부분 재인식한 등급입니다. 영역을 누르면 등급을 입력하며, 이전 영역의 성적 지표는 비웁니다. 원본과 대조하세요.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in widget.recognizedGrades.entries)
                  if (entry.value >= 1 && entry.value <= 9)
                    ActionChip(
                      label: Text('${entry.key} · ${entry.value}등급 반영'),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _fields['영역']!.text = entry.key;
                              for (final key in [
                                '선택 과목',
                                '원점수',
                                '표준점수',
                                '백분위',
                                '등급',
                              ]) {
                                _fields[key]!.clear();
                              }
                              _fields['등급']!.text = entry.value.toString();
                              _confirmed = false;
                              _error = null;
                            }),
                    ),
              ],
            ),
          ],
          for (final entry in _fields.entries)
            TextFormField(
              controller: entry.value,
              enabled: !_busy,
              decoration: InputDecoration(labelText: entry.key),
              validator: (v) => _validate(entry.key, v),
              onChanged: (_) => setState(() {
                _confirmed = false;
                _error = null;
              }),
            ),
          CheckboxListTile(
            value: _confirmed,
            title: const Text('시험 시기와 성적 지표를 원본과 대조했습니다.'),
            onChanged: _busy
                ? null
                : (v) => setState(() => _confirmed = v ?? false),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _busy || !_confirmed || !widget.saveAllowed
                ? null
                : _save,
            child: Text(_busy ? '저장 중...' : '모의고사 저장'),
          ),
        ],
      ),
    ),
  );
}
