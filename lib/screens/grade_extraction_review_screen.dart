import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';

class GradeExtractionReviewScreen extends StatefulWidget {
  final ExtractionResult result;
  const GradeExtractionReviewScreen({super.key, required this.result});

  @override
  State<GradeExtractionReviewScreen> createState() => _GradeExtractionReviewState();
}

class _GradeExtractionReviewState extends State<GradeExtractionReviewScreen> {
  late List<GradeDraft> drafts;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    drafts = List.from(widget.result.subjects);
  }

  bool _hasMissingRequired() {
    return drafts.any((d) => !d.isValid);
  }

  Future<void> _saveAll() async {
    setState(() { _busy = true; _error = null; });
    try {
      for (final d in drafts) {
        final errors = d.validationErrors();
        if (errors.isNotEmpty) {
          setState(() { _error = '${d.subjectName ?? '과목'} 검증 오류: ${errors.join(', ')}'; });
          setState(() { _busy = false; });
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
      for (final d in drafts) {
        await GradeService.instance.insertGrade(
          schoolYear: d.schoolYear!,
          semester: d.semester!,
          subjectName: d.subjectName!.trim(),
          credit: d.credit!,
          rawScore: d.rawScore,
          subjectAverage: d.subjectAverage,
          achievement: d.achievement,
          gradeRank: d.gradeRank,
          achievementDistribution: d.achievementDistribution,
        );
      }
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
                              Expanded(child: Text(d.subjectName ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                              TextButton(onPressed: () => setState(() => drafts.removeAt(index)), child: const Text('제외')),
                            ],
                          ),
                          _field('학년', d.schoolYear?.toString() ?? ''),
                          _field('학기', d.semester?.toString() ?? ''),
                          _field('학점', d.credit?.toString() ?? ''),
                          _field('원점수', d.rawScore?.toString() ?? ''),
                          _field('과목평균', d.subjectAverage?.toString() ?? ''),
                          _field('성취도', d.achievement ?? ''),
                          _field('석차등급', d.gradeRank?.toString() ?? ''),
                          if (d.achievementDistribution != null)
                            Text('A~E 분포: ${d.achievementDistribution}'),
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
                onPressed: _busy || _hasMissingRequired() ? null : _saveAll,
                child: Text(_busy ? '처리 중...' : '확인 후 저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$label: $value'),
      );
}
