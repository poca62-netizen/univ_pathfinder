import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/mock_exam_draft.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';

class MockExamReviewScreen extends StatefulWidget {
  const MockExamReviewScreen({
    super.key,
    required this.importResult,
    required this.calendarYear,
    required this.schoolYear,
    required this.examMonth,
    this.sourceText = '',
    this.sourceImage,
    this.warnings = const [],
    this.saveAllowed = true,
    this.saveRecords,
  });
  final MockExamImportResult importResult;
  final int calendarYear, schoolYear, examMonth;
  final String sourceText;
  final Uint8List? sourceImage;
  final List<String> warnings;
  final bool saveAllowed;
  final Future<void> Function(List<MockExamRecord>)? saveRecords;
  @override
  State<MockExamReviewScreen> createState() => _MockExamReviewState();
}

class _ReviewRow {
  _ReviewRow(MockExamDraft draft)
    : id = MockExamService.newId(),
      recovered = draft.recoveredGrade,
      fields = {
        'subject': TextEditingController(text: draft.subject),
        'elective': TextEditingController(),
        'raw': TextEditingController(text: draft.rawScore?.toString() ?? ''),
        'standard': TextEditingController(
          text: draft.standardScore?.toString() ?? '',
        ),
        'percentile': TextEditingController(
          text: draft.percentile?.toString() ?? '',
        ),
        'grade': TextEditingController(text: draft.gradeRank?.toString() ?? ''),
      };
  final String id;
  final bool recovered;
  final Map<String, TextEditingController> fields;
  bool selected = true;
  String text(String field) => fields[field]!.text.trim();
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
  }
}

class _MockExamReviewState extends State<MockExamReviewScreen> {
  final _form = GlobalKey<FormState>();
  late final List<_ReviewRow> _rows;
  late final Map<String, TextEditingController> _period;
  bool _confirmed = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final initial = widget.importResult.rows.isEmpty
        ? [
            for (final s in [
              '국어',
              '수학',
              '영어',
              '한국사',
              if (widget.calendarYear - widget.schoolYear == 2024) ...[
                '통합사회',
                '통합과학',
              ] else ...[
                '사회탐구',
                '과학탐구',
              ],
            ])
              MockExamDraft(subject: s),
          ]
        : widget.importResult.rows;
    _rows = initial.map(_ReviewRow.new).toList();
    _period = {
      '연도': TextEditingController(text: widget.calendarYear.toString()),
      '학년': TextEditingController(text: widget.schoolYear.toString()),
      '시행 월': TextEditingController(text: widget.examMonth.toString()),
      '시행 기관': TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in _period.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _confirmed = false;
    _error = null;
  });
  String? _number(
    String? text, {
    bool required = false,
    bool integer = false,
    double min = 0,
    double max = double.maxFinite,
  }) {
    final v = text?.trim() ?? '';
    if (v.isEmpty) return required ? '필수 항목입니다.' : null;
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return '숫자를 입력하세요.';
    if (integer && int.tryParse(v) == null) return '정수를 입력하세요.';
    if (n < min || n > max) return '$min~$max 범위를 확인하세요.';
    return null;
  }

  Future<void> _source() async {
    if (widget.sourceImage == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('모의고사 원본 보기')),
          body: Center(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 8,
              child: Image.memory(widget.sourceImage!),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_busy || !widget.saveAllowed || !_confirmed) return;
    if (!_form.currentState!.validate()) {
      setState(() => _error = '표의 입력 오류를 수정하세요.');
      return;
    }
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) {
      setState(() => _error = '저장할 영역을 하나 이상 선택하세요.');
      return;
    }
    final records = [
      for (final r in selected)
        MockExamRecord(
          id: r.id,
          calendarYear: int.parse(_period['연도']!.text.trim()),
          schoolYear: int.parse(_period['학년']!.text.trim()),
          examMonth: int.parse(_period['시행 월']!.text.trim()),
          institution: _period['시행 기관']!.text.trim().isEmpty
              ? null
              : _period['시행 기관']!.text.trim(),
          subject: r.text('subject'),
          elective: r.text('elective').isEmpty ? null : r.text('elective'),
          rawScore: double.tryParse(r.text('raw')),
          standardScore: double.tryParse(r.text('standard')),
          percentile: double.tryParse(r.text('percentile')),
          gradeRank: int.tryParse(r.text('grade')),
        ),
    ];
    final errors = [
      for (final r in records)
        for (final e in r.validationErrors()) '${r.subject}: $e',
    ];
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    if (records.map((r) => (r.subject, r.elective ?? '')).toSet().length !=
        records.length) {
      setState(() => _error = '영역과 선택 과목이 중복됩니다. 같은 영역은 선택 과목으로 구분하세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      final yes = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('모의고사 일괄 저장 확인'),
          content: Text(
            '${records.first.calendarYear}년 ${records.first.schoolYear}학년 ${records.first.examMonth}월 · ${records.length}개 영역을 저장합니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      await (widget.saveRecords ?? MockExamService.instance.saveBatch)(records);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '저장하지 못했습니다. 수정값은 유지됩니다. 같은 화면에서 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printed = widget.importResult;
    final mismatch =
        printed.calendarYear != null &&
            printed.calendarYear != int.tryParse(_period['연도']!.text.trim()) ||
        printed.schoolYear != null &&
            printed.schoolYear != int.tryParse(_period['학년']!.text.trim()) ||
        printed.examMonth != null &&
            printed.examMonth != int.tryParse(_period['시행 월']!.text.trim());
    const columns = {
      'subject': '영역',
      'elective': '선택 과목',
      'raw': '원점수',
      'standard': '표준점수',
      'percentile': '백분위',
      'grade': '등급',
    };
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('모의고사 인식 결과 검토'),
          actions: [
            if (widget.sourceImage != null)
              TextButton(
                onPressed: _busy ? null : _source,
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(context).appBarTheme.foregroundColor ??
                      Theme.of(context).colorScheme.onSurface,
                ),
                child: const Text('원본 보기'),
              ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '영역별 인식값을 원본과 대조하고 수정하세요. 원본에 없는 지표는 비워두며, 선택한 영역을 함께 저장합니다.',
              ),
              if (!widget.saveAllowed) const Text('체험·가상 예시는 DB에 저장하지 않습니다.'),
              if (mismatch)
                Text(
                  '원문에서 읽은 시기: ${printed.calendarYear ?? "미상"}년 ${printed.schoolYear ?? "미상"}학년 ${printed.examMonth ?? "미상"}월. 선택한 시험 시기와 대조하세요.',
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final entry in _period.entries)
                    SizedBox(
                      width: entry.key == '시행 기관' ? 260 : 120,
                      child: TextFormField(
                        key: ValueKey('mock-period-${entry.key}'),
                        controller: entry.value,
                        enabled: !_busy,
                        decoration: InputDecoration(labelText: entry.key),
                        validator: (v) => switch (entry.key) {
                          '연도' => _number(
                            v,
                            required: true,
                            integer: true,
                            min: 2000,
                            max: 2100,
                          ),
                          '학년' => _number(
                            v,
                            required: true,
                            integer: true,
                            min: 1,
                            max: 3,
                          ),
                          '시행 월' => _number(
                            v,
                            required: true,
                            integer: true,
                            min: 1,
                            max: 12,
                          ),
                          _ => null,
                        },
                        onChanged: (_) => _changed(),
                      ),
                    ),
                ],
              ),
              if (widget.sourceText.isNotEmpty)
                ExpansionTile(
                  title: const Text('추출 원문 대조'),
                  children: [SelectableText(widget.sourceText)],
                ),
              for (final warning in {...widget.warnings, ...printed.warnings})
                Text(warning),
              const SizedBox(height: 12),
              Text(
                '검토할 영역 ${_rows.length}개 · 저장 선택 ${_rows.where((r) => r.selected).length}개',
              ),
              const Text('표가 화면보다 넓으면 좌우로 이동하세요. 등급 보완 표시는 부분 재인식한 초기값입니다.'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 12,
                  onSelectAll: _busy
                      ? null
                      : (value) {
                          setState(() {
                            for (final r in _rows) {
                              r.selected = value ?? false;
                            }
                            _confirmed = false;
                          });
                        },
                  columns: [
                    for (final label in columns.values)
                      DataColumn(label: Text(label)),
                  ],
                  rows: [
                    for (var i = 0; i < _rows.length; i++)
                      DataRow(
                        key: ValueKey('mock-row-$i'),
                        selected: _rows[i].selected,
                        onSelectChanged: _busy
                            ? null
                            : (value) {
                                setState(() {
                                  _rows[i].selected = value ?? false;
                                  _confirmed = false;
                                  _error = null;
                                });
                              },
                        cells: [
                          for (final field in columns.keys)
                            DataCell(
                              SizedBox(
                                width: field == 'subject' || field == 'elective'
                                    ? 140
                                    : 120,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextFormField(
                                      key: ValueKey('mock-$i-$field'),
                                      controller: _rows[i].fields[field],
                                      enabled: !_busy && _rows[i].selected,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                      ),
                                      validator: (v) {
                                        if (!_rows[i].selected) return null;
                                        if (field == 'subject') {
                                          return v?.trim().isEmpty ?? true
                                              ? '영역을 입력하세요.'
                                              : null;
                                        }
                                        if (field == 'elective') return null;
                                        return _number(
                                          v,
                                          integer: field == 'grade',
                                          min: field == 'grade' ? 1 : 0,
                                          max: field == 'standard'
                                              ? double.maxFinite
                                              : field == 'grade'
                                              ? 9
                                              : 100,
                                        );
                                      },
                                      onChanged: (_) => _changed(),
                                    ),
                                    if (field == 'grade' && _rows[i].recovered)
                                      const Text(
                                        '등급 보완',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                  dataRowMinHeight: 72,
                  dataRowMaxHeight: 108,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _rows.add(
                              _ReviewRow(const MockExamDraft(subject: '')),
                            );
                            _confirmed = false;
                          });
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('영역 추가'),
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('mock-batch-confirm'),
                value: _confirmed,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _confirmed = v ?? false),
                title: const Text('시험 시기와 선택한 모든 영역의 지표를 원본과 대조했습니다.'),
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
                child: Text(_busy ? '저장 중...' : '선택 영역 일괄 저장'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
