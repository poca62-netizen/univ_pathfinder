import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/services/grade_service.dart';

class GradeAnalysisScreen extends StatefulWidget {
  const GradeAnalysisScreen({super.key});
  @override
  State<GradeAnalysisScreen> createState() => _GradeAnalysisState();
}
class _GradeAnalysisState extends State<GradeAnalysisScreen> {
  List<GradeRecord> _records = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final records = await GradeService.instance.fetchMyGrades();
      if (mounted) setState(() => _records = records);
    } on GradeServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '성적을 불러오지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('성적 분석'), actions: [
      IconButton(tooltip: '새로고침', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
    ]),
    body: SafeArea(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Text(_error!), const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('재시도')),
            ])))
        : RefreshIndicator(onRefresh: _load, child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (_records.isEmpty) const Padding(
                padding: EdgeInsets.all(24), child: Text('저장된 성적이 없습니다. 홈에서 성적을 입력하세요.')),
              for (final record in _records) Card(child: Padding(
                padding: const EdgeInsets.all(16), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${record.schoolYear}학년 ${record.semester}학기 · ${record.subjectName}',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('학점 ${record.credit} · 원점수 ${record.rawScore ?? "-"} · 평균 ${record.subjectAverage ?? "-"}'),
                    Text('성취도 ${record.achievement ?? "-"} · 석차등급 ${record.gradeRank ?? "-"}'),
                    if (record.achievementDistribution != null)
                      Text('성취도 분포: ' + record.achievementDistribution!.entries
                        .map((entry) => '${entry.key} ${entry.value}%').join(', ')),
                  ]))),
              const Text('서로 다른 성적 체계를 임의로 환산하지 않습니다.'),
            ]))),
  );
}
