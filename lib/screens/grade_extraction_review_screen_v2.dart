import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';

class GradeExtractionReviewScreenV2 extends StatefulWidget {
  final ExtractionResult result;
  final bool isTest;
  const GradeExtractionReviewScreenV2({super.key, required this.result, this.isTest = false});

  @override
  State<GradeExtractionReviewScreenV2> createState() => _GradeExtractionReviewStateV2();
}

class _GradeExtractionReviewStateV2 extends State<GradeExtractionReviewScreenV2> {
  late List<GradeDraft> drafts;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    drafts = List.from(widget.result.subjects);
  }

  bool _hasMissingRequired() {
    return drafts.isEmpty || drafts.any((d) => !d.isValid);
  }

  Future<void> _saveAll() async {
    for (final d in drafts) {
      final errors = d.validationErrors();
      if (errors.isNotEmpty) {
        setState(() => _error = '${d.subjectName ?? '과목'} 검증 오류: ${errors.join(', ')}');
        return;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('성적 저장 확인'),
        content: Text('${drafts.length}개 과목을 저장하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      final payloads = drafts.map((d) => {
        'school_year': d.schoolYear!,
        'semester': d.semester!,
        'subject_name': d.subjectName!.trim(),
        'credit': d.credit!,
        if (d.rawScore != null) 'raw_score': d.rawScore,
        if (d.subjectAverage != null) 'subject_average': d.subjectAverage,
        if (d.achievement != null && d.achievement!.isNotEmpty) 'achievement': d.achievement,
        if (d.gradeRank != null) 'grade_rank': d.gradeRank,
        if (d.achievementDistribution != null && d.achievementDistribution!.isNotEmpty)
          'achievement_distribution': d.achievementDistribution,
      }).toList();
      await GradeService.instance.insertGradesBatch(payloads);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('성적이 저장되었습니다.')));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GradeAnalysisScreen()));
    } on GradeServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '저장하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('추출 결과 확인·수정')),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.isTest) Container(color: Colors.red.shade50, width: double.infinity, padding: const EdgeInsets.all(12), child: const Text('테스트 데이터입니다. 저장 버튼은 비활성화되어 있습니다.', style: TextStyle(color: Colors.red))),
            Expanded(
              child: ListView.builder(
                itemCount: drafts.length,
                itemBuilder: (context, index) {
                  final d = drafts[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(labelText: '과목명'),
                                  onChanged: (v) => d.subjectName = v,
                                ),
                              ),
                              TextButton(onPressed: () => setState(() => drafts.removeAt(index)), child: const Text('제외')),
                            ],
                          ),
                          TextField(decoration: const InputDecoration(labelText: '학년 1~3'), keyboardType: TextInputType.number, onChanged: (v) => d.schoolYear = int.tryParse(v)),
                          TextField(decoration: const InputDecoration(labelText: '학기 1~2'), keyboardType: TextInputType.number, onChanged: (v) => d.semester = int.tryParse(v)),
                          TextField(decoration: const InputDecoration(labelText: '학점'), keyboardType: TextInputType.number, onChanged: (v) => d.credit = double.tryParse(v)),
                          TextField(decoration: const InputDecoration(labelText: '원점수 0~100'), keyboardType: TextInputType.number, onChanged: (v) => d.rawScore = double.tryParse(v)),
                          TextField(decoration: const InputDecoration(labelText: '과목평균 0~100'), keyboardType: TextInputType.number, onChanged: (v) => d.subjectAverage = double.tryParse(v)),
                          TextField(decoration: const InputDecoration(labelText: '성취도'), onChanged: (v) => d.achievement = v),
                          TextField(decoration: const InputDecoration(labelText: '석차등급 1~5'), keyboardType: TextInputType.number, onChanged: (v) => d.gradeRank = int.tryParse(v)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: (widget.isTest || _busy || _hasMissingRequired()) ? null : _saveAll,
                child: Text(_busy ? '처리 중...' : '확인 후 저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
