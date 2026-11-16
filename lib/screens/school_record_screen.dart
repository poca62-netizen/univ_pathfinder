import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';
import 'package:univ_pathfinder/screens/school_record_edit_screen.dart';

class SchoolRecordScreen extends StatefulWidget {
  const SchoolRecordScreen({
    super.key,
    this.loadRecords,
    this.saveRecord,
    this.deleteRecord,
  });
  final Future<List<SchoolRecordEvidence>> Function()? loadRecords;
  final Future<void> Function(SchoolRecordEvidence, bool)? saveRecord;
  final Future<void> Function(String)? deleteRecord;
  @override
  State<SchoolRecordScreen> createState() => _SchoolRecordState();
}

class _SchoolRecordState extends State<SchoolRecordScreen> {
  List<SchoolRecordEvidence> _records = [];
  bool _busy = false;
  String? _error;
  int? _year, _calendarYear;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records =
          await (widget.loadRecords ?? SchoolRecordService.instance.fetch)();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) setState(() => _error = '생활기록부 근거를 불러오지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([SchoolRecordEvidence? record]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SchoolRecordEditScreen(
          record: record,
          saveRecord: widget.saveRecord,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(SchoolRecordEvidence record) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('생활기록부 근거 삭제'),
        content: Text(
          '${record.calendarYear}년 ${record.category} 기록을 삭제합니다. 복구할 수 없습니다.',
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
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await (widget.deleteRecord ?? SchoolRecordService.instance.delete)(
        record.id,
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '삭제하지 못했습니다. 다시 조회해 주세요.';
        });
      }
    }
  }

  Future<void> _setCareer(SchoolRecordEvidence record, bool enabled) async {
    setState(() => _busy = true);
    try {
      await SchoolRecordService.instance.setCareerEnabled(record.id, enabled);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '상담 활용 설정을 저장하지 못했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _records.where(
      (r) =>
          (_calendarYear == null || r.calendarYear == _calendarYear) &&
          (_year == null || r.schoolYear == _year),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('저장된 생활기록부 근거'),
        actions: [
          IconButton(
            tooltip: '생활기록부 근거 새로고침',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('근거 입력'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('재시도')),
                ],
                Text('DB에 저장된 생활기록부 근거 ${_records.length}개 근거'),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('전체 연도'),
                      selected: _calendarYear == null,
                      onSelected: (_) => setState(() => _calendarYear = null),
                    ),
                    for (final year
                        in (_records.map((r) => r.calendarYear).toSet().toList()
                          ..sort()))
                      ChoiceChip(
                        label: Text('$year년'),
                        selected: _calendarYear == year,
                        onSelected: (_) => setState(() => _calendarYear = year),
                      ),
                  ],
                ),
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
                if (visible.isEmpty) const Text('선택한 조건에 저장된 생활기록부 근거가 없습니다.'),
                for (final record in visible)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record.calendarYear}년 ${record.schoolYear}학년 · ${record.category}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SelectableText(record.evidence),
                          Text('출처: ${record.sourceLocation}'),
                          if (record.careerInterest?.isNotEmpty == true)
                            Text('관심 진로 메모: ${record.careerInterest}'),
                          Text('원본 대조: ${record.confirmedAt.toLocal()}'),
                          SwitchListTile(
                            title: const Text('진로 상담 근거로 사용'),
                            subtitle: const Text('성적 평균 계산에는 포함하지 않습니다.'),
                            value: record.careerEvidenceEnabled,
                            onChanged: _busy
                                ? null
                                : (v) => _setCareer(record, v),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _edit(record),
                                child: const Text('수정'),
                              ),
                              TextButton(
                                onPressed: () => _delete(record),
                                child: const Text('삭제'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text('저장한 근거는 사용자 확인 내용입니다. 홈 → 생기부 컨설팅에서 근거를 골라 AI 상담을 할 수 있습니다(상담 활용이 켜진 근거만).'),
              ],
            ),
    );
  }
}
