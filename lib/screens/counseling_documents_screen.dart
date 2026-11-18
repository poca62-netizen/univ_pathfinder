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
import 'package:univ_pathfinder/widgets/ui_kit.dart';

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
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          final signedIn = GradeService.instance.isAuthenticated;
          int uploaded(StudentDocumentKind kind) => session.documents
              .where(
                (d) =>
                    kind.isSchoolGrade ? d.kind.isSchoolGrade : d.kind == kind,
              )
              .length;
          const uploads = [
            (
              StudentDocumentKind.midterm,
              Icons.grading_outlined,
              '학년·학기·시험별 성적표 (PDF·사진)',
            ),
            (
              StudentDocumentKind.mockExam,
              Icons.edit_note_outlined,
              '시행 월별 성적표 · 원점수·표준점수·백분위·등급',
            ),
            (
              StudentDocumentKind.schoolRecord,
              Icons.history_edu_outlined,
              '세특·활동 기록에서 진로 근거 고르기',
            ),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('내신부터 생활기록부까지', style: text.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        '성적표와 생활기록부를 올리면 내용을 읽어 표로 보여 드려요. 원본과 맞는지 확인한 것만 저장합니다.',
                        style: text.bodyLarge?.copyWith(
                          color: const Color(0xFF647571),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const StepStrip([
                        '자료 올리기',
                        '원본과 대조·수정',
                        '저장 후 대학 후보·리포트',
                      ]),
                      const SizedBox(height: 28),
                      const SectionHeader(
                        '자료 올리기',
                        caption: '종류를 고르면 학년·학기 같은 시기를 차례로 선택합니다.',
                      ),
                      for (final (kind, icon, description) in uploads) ...[
                        ActionCard(
                          title: kind.isSchoolGrade ? '내신 성적표' : kind.label,
                          subtitle: uploaded(kind) == 0
                              ? description
                              : '$description\n이번에 올린 파일 ${uploaded(kind)}개',
                          icon: icon,
                          trailing: Icons.add_circle_outline,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    GradeUploadFileScreenV2(initialKind: kind),
                              ),
                            );
                            if (mounted) {
                              await Future.wait([_reload(), _reloadMocks()]);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 2),
                      const InfoNote(
                        '파일 원본은 보관하지 않아요. PDF는 이 브라우저 안에서 읽고, 사진은 로그인한 경우 서버의 문자 인식으로 읽습니다.',
                        icon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 32),
                      const SectionHeader('저장한 자료'),
                      if (!_canLoad && !_canLoadMocks)
                        const InfoNote(
                          '로그인하면 저장한 내신·모의고사·생활기록부 근거를 여기서 다시 볼 수 있어요.',
                          icon: Icons.login,
                        )
                      else ...[
                        _label(context, '내신'),
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null) _retry(_error!, '다시 불러오기', _reload),
                        if (_canLoad &&
                            !_loading &&
                            _error == null &&
                            groups.isEmpty)
                          _empty('아직 저장한 내신이 없어요. 위에서 내신 성적표를 올려 보세요.'),
                        for (final entry in groups.entries) ...[
                          ActionCard(
                            title:
                                '${entry.key.$1 == null ? "연도 미상" : "${entry.key.$1}년"} · ${entry.key.$2}학년 ${entry.key.$3}학기 · ${entry.value.first.examLabel}',
                            subtitle:
                                '${entry.value.length}개 과목 · ${entry.value.map((r) => r.subjectName).join(", ")}',
                            minHeight: 64,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GradeAnalysisScreen(
                                    initialCalendarFilter:
                                        entry.key.$1?.toString() ?? 'unknown',
                                    initialSchoolYear: entry.key.$2,
                                    initialSemester: entry.key.$3,
                                    initialExamFilter:
                                        entry.key.$4 ?? 'unknown',
                                    loadGrades: widget.loadGrades,
                                  ),
                                ),
                              );
                              if (mounted) await _reload();
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 16),
                        _label(context, '모의고사 성적'),
                        if (_mockLoading) const LinearProgressIndicator(),
                        if (_mockError != null)
                          _retry(_mockError!, '모의고사 다시 불러오기', _reloadMocks),
                        if (_canLoadMocks)
                          ActionCard(
                            title: '모의고사 저장·조회',
                            subtitle:
                                '${_mockRecords.length}개 영역 · 원점수·표준점수·백분위·등급',
                            minHeight: 64,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MockExamScreen(
                                    loadRecords: widget.loadMockExams,
                                  ),
                                ),
                              );
                              if (mounted) await _reloadMocks();
                            },
                          ),
                        if (_mockRecords.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final period
                                  in _mockRecords
                                      .map(
                                        (r) =>
                                            '${r.calendarYear}년 ${r.schoolYear}학년 ${r.examMonth}월',
                                      )
                                      .toSet())
                                Chip(label: Text(period)),
                            ],
                          ),
                        ],
                        if (signedIn) ...[
                          const SizedBox(height: 16),
                          _label(context, '생활기록부'),
                          ActionCard(
                            title: '생활기록부 근거 저장·조회',
                            subtitle: '활동·진로 근거와 원문 출처 위치',
                            minHeight: 64,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SchoolRecordScreen(),
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 32),
                      const SectionHeader('다음 단계'),
                      if (signedIn) ...[
                        FilledButton.icon(
                          icon: const Icon(Icons.school_outlined),
                          label: const Text('등록한 성적·생기부로 대학 후보 보기'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const UniversityRecommendationScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      ActionCard(
                        title: '상담 요약 보기',
                        subtitle: '저장한 성적·활동 근거와 관심 진로를 한눈에',
                        icon: Icons.summarize_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CounselingSummaryScreen(),
                          ),
                        ),
                      ),
                      if (session.documents.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const SectionHeader(
                          '이번에 올린 파일',
                          caption: '파일 이름 목록만 있으며 앱을 닫으면 사라져요.',
                        ),
                        for (final document in session.documents)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(
                              '${document.kind.label} · ${document.period}',
                            ),
                            subtitle: Text(document.fileName),
                            trailing: IconButton(
                              tooltip: '목록에서 제외',
                              icon: const Icon(Icons.close),
                              onPressed: () => session.removeDocument(document),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF647571),
        letterSpacing: .2,
      ),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13.5, color: Color(0xFF647571)),
    ),
  );

  Widget _retry(String message, String label, VoidCallback onPressed) => Row(
    children: [
      Expanded(child: Text(message)),
      TextButton(onPressed: onPressed, child: Text(label)),
    ],
  );
}
