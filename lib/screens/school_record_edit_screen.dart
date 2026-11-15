import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';

class SchoolRecordEditScreen extends StatefulWidget {
  const SchoolRecordEditScreen({
    super.key,
    this.record,
    this.calendarYear,
    this.schoolYear = 1,
    this.sourceText,
    this.saveAllowed = true,
    this.saveRecord,
  });
  final SchoolRecordEvidence? record;
  final int? calendarYear;
  final int schoolYear;
  final String? sourceText;
  final bool saveAllowed;
  final Future<void> Function(SchoolRecordEvidence, bool)? saveRecord;
  @override
  State<SchoolRecordEditScreen> createState() => _SchoolRecordEditState();
}

class _SchoolRecordEditState extends State<SchoolRecordEditScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late final String _id;
  bool _busy = false, _confirmed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _id = r?.id ?? SchoolRecordService.newId();
    final initial = <String, Object?>{
      '연도': r?.calendarYear ?? widget.calendarYear ?? DateTime.now().year,
      '학년': r?.schoolYear ?? widget.schoolYear,
      '활동 항목': r?.category,
      '원문 근거': r?.evidence,
      '출처 위치': r?.sourceLocation,
      '관심 진로': r?.careerInterest,
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
  String? _validate(String key, String? input) {
    final v = input?.trim() ?? '';
    if (key == '관심 진로') return v.length > 300 ? '300자 이내로 입력하세요.' : null;
    if (['활동 항목', '원문 근거', '출처 위치'].contains(key)) {
      final max = key == '원문 근거'
          ? 10000
          : key == '출처 위치'
          ? 300
          : 100;
      return v.isEmpty || v.length > max ? '1~$max자로 입력하세요.' : null;
    }
    if (v.isEmpty) return '필수 항목입니다.';
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return '숫자를 입력하세요.';
    if (const ['연도', '학년'].contains(key) && int.tryParse(v) == null) {
      return '정수를 입력하세요.';
    }
    final (min, max) = switch (key) {
      '연도' => (2000, 2100),
      '학년' => (1, 3),
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
    final record = SchoolRecordEvidence(
      careerEvidenceEnabled: widget.record?.careerEvidenceEnabled ?? true,
      id: _id,
      calendarYear: int.parse(text('연도')),
      schoolYear: int.parse(text('학년')),
      category: text('활동 항목'),
      evidence: text('원문 근거'),
      sourceLocation: text('출처 위치'),
      careerInterest: text('관심 진로'),
      confirmedAt: DateTime.now().toUtc(),
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
        await SchoolRecordService.instance.save(
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
      title: Text(widget.record == null ? '생활기록부 근거 입력' : '생활기록부 근거 수정'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '원본에 있는 활동을 그대로 입력하세요. 출처는 페이지·항목 위치를 적으세요. 관심 진로는 사용자가 작성한 메모입니다.',
          ),
          if (!widget.saveAllowed) const Text('체험·가상 예시는 DB에 저장하지 않습니다.'),
          if (widget.sourceText != null)
            ExpansionTile(
              title: const Text('추출 원문 대조'),
              children: [
                const Text(
                  '추출 원문에서 근거를 골라 원본과 대조하세요. 원본 파일과 추출 원문 전체는 저장하지 않습니다.',
                ),
                SelectableText(widget.sourceText!),
              ],
            ),
          for (final entry in _fields.entries)
            TextFormField(
              controller: entry.value,
              enabled: !_busy,
              maxLines: entry.key == '원문 근거' ? 5 : 1,
              decoration: InputDecoration(labelText: entry.key),
              validator: (v) => _validate(entry.key, v),
              onChanged: (_) => setState(() {
                _confirmed = false;
                _error = null;
              }),
            ),
          CheckboxListTile(
            value: _confirmed,
            title: const Text('활동 근거와 출처 위치를 원본과 대조했습니다.'),
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
            child: Text(_busy ? '저장 중...' : '생활기록부 근거 저장'),
          ),
        ],
      ),
    ),
  );
}
