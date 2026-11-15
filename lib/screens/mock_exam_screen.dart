import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';
import 'package:univ_pathfinder/screens/mock_exam_edit_screen.dart';

class MockExamScreen extends StatefulWidget {
  const MockExamScreen({
    super.key,
    this.loadRecords,
    this.saveRecord,
    this.deleteRecord,
  });
  final Future<List<MockExamRecord>> Function()? loadRecords;
  final Future<void> Function(MockExamRecord, bool)? saveRecord;
  final Future<void> Function(String)? deleteRecord;
  @override
  State<MockExamScreen> createState() => _MockExamState();
}

class _MockExamState extends State<MockExamScreen> {
  List<MockExamRecord> _records = [];
  bool _busy = false;
  String? _error;
  int? _year, _month, _calendarYear;
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
          await (widget.loadRecords ?? MockExamService.instance.fetch)();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) setState(() => _error = '모의고사를 불러오지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([MockExamRecord? record]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MockExamEditScreen(record: record, saveRecord: widget.saveRecord),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(MockExamRecord record) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모의고사 삭제'),
        content: Text(
          '${record.calendarYear}년 ${record.examMonth}월 ${record.subject} 기록을 삭제합니다. 복구할 수 없습니다.',
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
      await (widget.deleteRecord ?? MockExamService.instance.delete)(record.id);
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

  @override
  Widget build(BuildContext context) {
    final visible = _records.where(
      (r) =>
          (_calendarYear == null || r.calendarYear == _calendarYear) &&
          (_year == null || r.schoolYear == _year) &&
          (_month == null || r.examMonth == _month),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('저장된 모의고사'),
        actions: [
          IconButton(
            tooltip: '모의고사 새로고침',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('영역 입력'),
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
                Text('DB에 저장된 모의고사 ${_records.length}개 영역'),
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
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('전체 월'),
                      selected: _month == null,
                      onSelected: (_) => setState(() => _month = null),
                    ),
                    for (final month
                        in (_records.map((r) => r.examMonth).toSet().toList()
                          ..sort()))
                      ChoiceChip(
                        label: Text('$month월'),
                        selected: _month == month,
                        onSelected: (_) => setState(() => _month = month),
                      ),
                  ],
                ),
                if (visible.isEmpty) const Text('선택한 조건에 저장된 모의고사가 없습니다.'),
                for (final record in visible)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record.calendarYear}년 ${record.schoolYear}학년 ${record.examMonth}월 · ${record.subject}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '기관 ${record.institution?.isNotEmpty == true ? record.institution : "미상"} · 선택 과목 ${record.elective?.isNotEmpty == true ? record.elective : "없음"}',
                          ),
                          Text(
                            '원점수 ${record.rawScore ?? "-"} · 표준점수 ${record.standardScore ?? "-"}',
                          ),
                          Text(
                            '백분위 ${record.percentile ?? "-"} · 등급 ${record.gradeRank ?? "-"}',
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
                const Text('내신·모의고사 지표를 혼합해 평균하지 않습니다.'),
              ],
            ),
    );
  }
}
