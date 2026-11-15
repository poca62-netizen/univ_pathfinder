import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/services/counseling_summary_service.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/screens/mock_exam_screen.dart';
import 'package:univ_pathfinder/screens/school_record_screen.dart';

class CounselingSummaryScreen extends StatefulWidget {
  const CounselingSummaryScreen({super.key, this.loadSummary});
  final Future<CounselingSummary> Function()? loadSummary;
  @override
  State<CounselingSummaryScreen> createState() => _CounselingSummaryState();
}

class _CounselingSummaryState extends State<CounselingSummaryScreen> {
  CounselingSummary? _summary;
  bool _busy = false;
  String? _error, _interest;
  bool get _canLoad =>
      widget.loadSummary != null || GradeService.instance.isAuthenticated;
  @override
  void initState() {
    super.initState();
    if (_canLoad) _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _summary = null;
      _error = null;
    });
    try {
      final summary =
          await (widget.loadSummary ?? CounselingSummaryService().fetch)();
      if (mounted) {
        setState(() {
          _summary = summary;
          if (!summary.careerInterests.contains(_interest)) _interest = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '상담 자료를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 요약'),
        actions: [
          if (_canLoad)
            IconButton(
              tooltip: '상담 요약 새로고침',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '저장된 자료를 바탕으로 상담에 사용할 근거를 모았습니다. 자동 적성 판정·합격 예측·대학 추천은 아직 제공하지 않습니다.',
          ),
          if (!_canLoad)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('로그인하면 저장한 자료로 상담 요약을 볼 수 있습니다.'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('다시 불러오기')),
          ],
          if (s != null) ...[
            FilledButton.icon(
              onPressed: () => _open(
                UniversityRecommendationScreen(loadSummary: widget.loadSummary),
              ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('성적·생기부로 대학 후보 보기'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  _open(ConsultingScreen(loadSummary: widget.loadSummary)),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('생기부 컨설팅 시작'),
            ),
            _heading('자료 확인과 보완'),
            if (s.grades.failed ||
                s.mockExams.failed ||
                s.activities.failed) ...[
              const Text('일부 자료 조회에 실패했습니다. 아래 내용은 전체 요약이 아닙니다.'),
              TextButton(onPressed: _load, child: const Text('실패한 자료 다시 조회')),
            ],
            for (final message in s.missingInformation) Text('• $message'),
            if (s.missingInformation.isEmpty &&
                !s.grades.failed &&
                !s.mockExams.failed &&
                !s.activities.failed)
              const Text('세 종류의 자료가 모두 있습니다. 상담 전 기록 시기와 출처를 확인하세요.'),
            _heading('원본 대조 확인된 내신'),
            if (s.grades.failed) const Text('내신을 불러오지 못했습니다.'),
            if (!s.grades.failed)
              Text(
                '${s.confirmedGrades.length}개 과목 · 미확인 ${s.unconfirmedGradeCount}개 제외',
              ),
            const Text('시험별 과목 기록입니다. 서로 다른 시험·등급 체계를 합산하지 않습니다.'),
            for (final r in s.confirmedGrades)
              Card(
                child: ListTile(
                  title: Text(
                    '${r.subjectName} · ${r.calendarYear == null ? "연도 미상" : "${r.calendarYear}년"} ${r.schoolYear}학년 ${r.semester}학기 · ${r.examLabel}',
                  ),
                  subtitle: Text(
                    '원점수 ${r.rawScore ?? "-"} · 평균 ${r.subjectAverage ?? "-"} · 학점 ${r.credit}\n성취도 ${r.achievement ?? "-"} · 석차등급 ${r.gradeRank ?? "-"}\n원본 대조 ${r.sourceConfirmedAt!.toLocal()}${r.sourceLocation == null ? "" : " · ${r.sourceLocation}"}',
                  ),
                  isThreeLine: true,
                ),
              ),
            if (GradeService.instance.isAuthenticated)
              TextButton(
                onPressed: () => _open(const GradeAnalysisScreen()),
                child: const Text('내신 기록 확인·수정'),
              ),
            _heading('저장된 모의고사'),
            if (s.mockExams.failed) const Text('모의고사를 불러오지 못했습니다.'),
            if (!s.mockExams.failed) Text('${s.mockExams.records.length}개 영역'),
            const Text(
              '사용자가 저장한 성적입니다. 모의고사 DB에는 원본 대조 확인 시각이 없어 확인 이력을 검증할 수 없습니다.',
            ),
            for (final r in s.mockExams.records)
              Card(
                child: ListTile(
                  title: Text(
                    '${r.calendarYear}년 ${r.schoolYear}학년 ${r.examMonth}월 · ${r.subject}',
                  ),
                  subtitle: Text(
                    '기관 ${r.institution?.isNotEmpty == true ? r.institution : "미상"} · 선택 ${r.elective?.isNotEmpty == true ? r.elective : "없음"}\n원점수 ${r.rawScore ?? "-"} · 표준점수 ${r.standardScore ?? "-"}\n백분위 ${r.percentile ?? "-"} · 등급 ${r.gradeRank ?? "-"}',
                  ),
                  isThreeLine: true,
                ),
              ),
            if (GradeService.instance.isAuthenticated)
              TextButton(
                onPressed: () => _open(const MockExamScreen()),
                child: const Text('모의고사 기록 확인·수정'),
              ),
            _heading('관심 분야와 생활기록부 근거'),
            const Text(
              '체육·예술·과학탐구실험·교양의 세특도 포함합니다. 생활기록부에서 상담 활용을 끈 근거는 제외합니다.',
            ),
            const Text(
              '관심 분야는 사용자가 작성한 진로 메모입니다. 선택하면 같은 메모가 붙은 활동만 표시합니다. 성적 목록에는 영향을 주지 않습니다.',
            ),
            if (s.activities.failed) const Text('생활기록부를 불러오지 못했습니다.'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('전체 활동'),
                  selected: _interest == null,
                  onSelected: (_) => setState(() => _interest = null),
                ),
                for (final interest in s.careerInterests)
                  ChoiceChip(
                    label: Text(interest),
                    selected: _interest == interest,
                    onSelected: (_) => setState(() => _interest = interest),
                  ),
              ],
            ),
            if (!s.activities.failed)
              Text('표시된 활동 ${s.activitiesFor(_interest).length}개'),
            for (final r in s.activitiesFor(_interest))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.calendarYear}년 ${r.schoolYear}학년 · ${r.category}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SelectableText(r.evidence),
                      Text('출처: ${r.sourceLocation}'),
                      Text(
                        '관심 진로 메모: ${r.careerInterest?.trim().isNotEmpty == true ? r.careerInterest : "미작성"}',
                      ),
                      Text('원본 대조: ${r.confirmedAt.toLocal()}'),
                    ],
                  ),
                ),
              ),
            if (GradeService.instance.isAuthenticated)
              TextButton(
                onPressed: () => _open(const SchoolRecordScreen()),
                child: const Text('생활기록부 근거 확인·수정'),
              ),
            _heading('대학 상담 준비'),
            const Text(
              '관심 학과의 공식 모집요강·평가 항목과 위 근거를 대조할 수 있도록 준비하세요. 공식 대학 자료 연결은 다음 단계입니다. 현재 대학 탐색·비교 목록은 가상 예시입니다.',
            ),
          ],
        ],
      ),
    );
  }
}
