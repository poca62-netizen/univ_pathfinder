import 'package:univ_pathfinder/screens/counseling_summary_screen.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/screens/school_record_screen.dart';
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/grade_upload_file_screen_v2.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';
import 'package:univ_pathfinder/screens/mock_exam_screen.dart';

class CounselingDocumentsScreen extends StatefulWidget {
  const CounselingDocumentsScreen({
    super.key,
    this.loadGrades,
    this.loadMockExams,
  });
  final Future<List<GradeRecord>> Function()? loadGrades;
  final Future<List<MockExamRecord>> Function()? loadMockExams;

  @override
  State<CounselingDocumentsScreen> createState() => _CounselingDocumentsState();
}

class _CounselingDocumentsState extends State<CounselingDocumentsScreen> {
  List<GradeRecord> _saved = [];
  bool _loading = false;
  String? _error;
  List<MockExamRecord> _mockRecords = [];
  String? _mockError;
  bool _mockLoading = false;
  bool get _canLoadMocks =>
      widget.loadMockExams != null || GradeService.instance.isAuthenticated;
  bool get _canLoad =>
      widget.loadGrades != null || GradeService.instance.isAuthenticated;

  @override
  void initState() {
    super.initState();
    _reload();
    _reloadMocks();
  }

  Future<void> _reloadMocks() async {
    if (!_canLoadMocks || _mockLoading) return;
    setState(() {
      _mockLoading = true;
      _mockError = null;
    });
    try {
      final records =
          await (widget.loadMockExams ?? MockExamService.instance.fetch)();
      if (mounted) setState(() => _mockRecords = records);
    } catch (_) {
      if (mounted) setState(() => _mockError = '저장된 모의고사를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _mockLoading = false);
    }
  }

  Future<void> _reload() async {
    if (!_canLoad || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records =
          await (widget.loadGrades ?? GradeService.instance.fetchMyGrades)();
      if (mounted) {
        setState(
          () => _saved = records.where((r) => r.isInGradeScope).toList(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '저장된 성적을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = CounselingSession.instance;
    // A group represents a period of saved grades, not an original file.
    final groups = <(int?, int, int, String?), List<GradeRecord>>{};
    for (final record in _saved) {
      groups
          .putIfAbsent((
            record.calendarYear,
            record.schoolYear,
            record.semester,
            record.examKind,
          ), () => [])
          .add(record);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 자료 모아보기'),
        actions: [
          if (_canLoad)
            IconButton(
              tooltip: '저장 자료 새로고침',
              onPressed: _loading || _mockLoading
                  ? null
                  : () async {
                      await Future.wait([_reload(), _reloadMocks()]);
                    },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '내신부터 생활기록부까지',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '중간·기말 성적은 학년·학기별로, 모의고사는 시행 월별로 구분합니다. 생활기록부의 진로·활동 근거와 출처 위치도 검토해 저장합니다.',
            ),
            const SizedBox(height: 12),
            const Text(
              '내신은 학년 → 학기 → 시험 구분 순서로 선택합니다. 로그인한 이미지 인식은 NVIDIA를 사용하며, PDF는 브라우저에서 읽습니다. 원본 대조 후 확인한 내신만 저장합니다.',
            ),
            const SizedBox(height: 16),
            for (final kind in [
              StudentDocumentKind.midterm,
              StudentDocumentKind.mockExam,
              StudentDocumentKind.schoolRecord,
            ])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(kind.isSchoolGrade ? '내신 성적표' : kind.label),
                  subtitle: Text(
                    '${session.documents.where((d) => kind.isSchoolGrade ? d.kind.isSchoolGrade : d.kind == kind).length}개 · 분석 대기',
                  ),
                  trailing: const Icon(Icons.add),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GradeUploadFileScreenV2(initialKind: kind),
                      ),
                    );
                    if (mounted) await Future.wait([_reload(), _reloadMocks()]);
                  },
                ),
              ),
            const SizedBox(height: 20),
            if (GradeService.instance.isAuthenticated)
              FilledButton.icon(
                icon: const Icon(Icons.school_outlined),
                label: const Text('등록한 성적·생기부로 대학 후보 보기'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UniversityRecommendationScreen(),
                  ),
                ),
              ),
            Card(
              child: ListTile(
                title: const Text('상담 요약 보기'),
                subtitle: const Text('저장된 성적·활동 근거와 관심 진로 모아보기'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CounselingSummaryScreen(),
                  ),
                ),
              ),
            ),
            Text('DB에 저장된 내신', style: Theme.of(context).textTheme.titleMedium),
            if (_loading) const LinearProgressIndicator(),
            if (!_canLoad) const Text('로그인하면 저장된 성적을 불러옵니다.'),
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _reload, child: const Text('다시 불러오기')),
            ],
            if (_canLoad && !_loading && _error == null && groups.isEmpty)
              const Text('DB에 저장된 내신이 없습니다.'),
            for (final entry in groups.entries)
              Card(
                child: ListTile(
                  title: Text(
                    '${entry.key.$1 == null ? "연도 미상" : "${entry.key.$1}년"} · ${entry.key.$2}학년 ${entry.key.$3}학기 · ${entry.value.first.examLabel}',
                  ),
                  subtitle: Text(
                    '${entry.value.length}개 과목 · ${entry.value.map((r) => r.subjectName).join(", ")}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GradeAnalysisScreen(
                          initialCalendarFilter:
                              entry.key.$1?.toString() ?? 'unknown',
                          initialSchoolYear: entry.key.$2,
                          initialSemester: entry.key.$3,
                          initialExamFilter: entry.key.$4 ?? 'unknown',
                          loadGrades: widget.loadGrades,
                        ),
                      ),
                    );
                    if (mounted) await _reload();
                  },
                ),
              ),
            const Text('저장된 성적을 시험 시기별로 묶어 표시합니다. 파일 원본은 보관하지 않습니다.'),
            const SizedBox(height: 20),
            Text(
              'DB에 저장된 모의고사',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_mockLoading) const LinearProgressIndicator(),
            if (_mockError != null) ...[
              Text(_mockError!),
              TextButton(
                onPressed: _reloadMocks,
                child: const Text('모의고사 다시 불러오기'),
              ),
            ],
            if (_canLoadMocks)
              Card(
                child: ListTile(
                  title: const Text('모의고사 저장·조회'),
                  subtitle: Text(
                    '${_mockRecords.length}개 영역 · 원점수·표준점수·백분위·등급',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MockExamScreen(loadRecords: widget.loadMockExams),
                      ),
                    );
                    if (mounted) await _reloadMocks();
                  },
                ),
              )
            else
              const Text('로그인하면 모의고사를 저장하고 다시 조회할 수 있습니다.'),
            for (final period
                in _mockRecords
                    .map(
                      (r) =>
                          '${r.calendarYear}년 ${r.schoolYear}학년 ${r.examMonth}월',
                    )
                    .toSet())
              Text(period),
            const SizedBox(height: 20),
            if (GradeService.instance.isAuthenticated)
              Card(
                child: ListTile(
                  title: const Text('생활기록부 근거 저장·조회'),
                  subtitle: const Text('활동·진로 근거와 원문 출처 위치'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SchoolRecordScreen(),
                    ),
                  ),
                ),
              ),
            Text('등록한 자료', style: Theme.of(context).textTheme.titleMedium),
            const Text('아래 파일 정보 목록은 이번 실행 중에만 유지됩니다.'),
            if (session.documents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('등록한 자료가 없습니다. 위에서 자료 종류를 선택하세요.'),
              ),
            for (final document in session.documents)
              ListTile(
                title: Text('${document.kind.label} · ${document.period}'),
                subtitle: Text(
                  '${document.fileName}\n자료 정보 목록 · 원본은 보관하지 않았습니다.',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: '목록에서 제외',
                  icon: const Icon(Icons.close),
                  onPressed: () => session.removeDocument(document),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
