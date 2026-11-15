import 'package:univ_pathfinder/models/document_file_limits.dart';
import 'package:univ_pathfinder/screens/mock_exam_review_screen.dart';
import 'package:univ_pathfinder/models/mock_exam_draft.dart';
import 'package:univ_pathfinder/screens/school_record_review_screen.dart';
import 'package:univ_pathfinder/models/school_record_import.dart';
import 'package:univ_pathfinder/screens/school_record_screen.dart';
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/mock_exam_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/services/grade_file_import_service.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_extraction_review_screen_v2.dart';

class GradeUploadFileScreenV2 extends StatefulWidget {
  const GradeUploadFileScreenV2({
    super.key,
    this.initialKind = StudentDocumentKind.midterm,
    this.importService,
  });
  final StudentDocumentKind initialKind;
  final GradeFileImportService? importService;
  @override
  State<GradeUploadFileScreenV2> createState() =>
      _GradeUploadFileScreenV2State();
}

class _GradeUploadFileScreenV2State extends State<GradeUploadFileScreenV2> {
  PlatformFile? _file;
  Uint8List? _previewBytes;
  int _size = 0;
  String? _error;
  bool _loading = false;
  bool _recognizing = false;
  String _progress = '';
  Uint8List? _sampleBytes;
  late final GradeFileImportService _importer;
  late StudentDocumentKind _kind;
  int _schoolYear = 1, _semester = 1, _month = 3;
  int _calendarYear = DateTime.now().year;
  static const _allowedExt = ['jpg', 'jpeg', 'png', 'pdf'];

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _importer = widget.importService ?? GradeFileImportService();
  }

  @override
  void dispose() {
    if (_recognizing) _importer.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExt,
      );
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      final ext = file.extension?.toLowerCase() ?? '';
      if (!_allowedExt.contains(ext)) {
        throw const FormatException('JPG·JPEG·PNG·PDF만 선택할 수 있습니다.');
      }
      final size = await file.length();
      if (size == null || size <= 0) {
        throw const FormatException('파일 크기를 확인할 수 없거나 빈 파일입니다.');
      }
      final sizeError = DocumentFileLimits.validate(
        size,
        ext == 'pdf' ? 'application/pdf' : 'image/jpeg',
      );
      if (sizeError != null) throw FormatException(sizeError);
      final preview = ext == 'pdf' ? null : await file.xFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _file = file;
        _sampleBytes = null;
        _previewBytes = preview;
        _size = size;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '파일을 읽지 못했습니다. 다시 선택해 주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSample() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await rootBundle.load('assets/samples/sample_grades.pdf');
      if (!mounted) return;
      setState(() {
        _sampleBytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        _file = null;
        _previewBytes = null;
        _size = data.lengthInBytes;
        _kind = StudentDocumentKind.midterm;
        _schoolYear = 2;
        _semester = 1;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '가상 예시 파일을 읽지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _extract({bool forceOcr = false}) async {
    if (_loading) return;
    if (!_importer.available) {
      setState(
        () => _error = '파일 자동 인식은 Chrome 등 웹 버전에서 지원합니다. 새로고침 후 다시 시도해 주세요.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _recognizing = true;
      _error = null;
      _progress = '파일 읽는 중';
    });
    var selectAgain = false;
    try {
      final bytes = _sampleBytes ?? await _file!.xFile.readAsBytes();
      final extension = _sampleBytes != null
          ? 'pdf'
          : _file!.extension!.toLowerCase();
      final mime = extension == 'pdf'
          ? 'application/pdf'
          : extension == 'png'
          ? 'image/png'
          : 'image/jpeg';
      if (_importer.usesNvidia && mime.startsWith('image/')) {
        if (!mounted) return;
        final agreed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('NVIDIA로 이미지 인식'),
            content: const Text(
              '선택한 이미지를 서버를 통해 NVIDIA OCR로 전송합니다. 이름·학교·학번 등 식별정보를 가린 파일인지 확인해 주세요. 앱은 원본을 DB에 저장하지 않습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('인식하기'),
              ),
            ],
          ),
        );
        if (agreed != true || !mounted) return;
      }
      final preview = await _importer.extract(
        bytes,
        mime,
        kind: _kind,
        schoolYear: _schoolYear,
        semester: _semester,
        forceOcr: forceOcr,
        enhancedRecognition: _kind.isSchoolGrade,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      );
      if (!mounted) return;
      if (_kind == StudentDocumentKind.mockExam) {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => MockExamReviewScreen(
              importResult:
                  preview.mockExamImport ?? const MockExamImportResult(),
              calendarYear: _calendarYear,
              schoolYear: _schoolYear,
              examMonth: _month,
              sourceText: preview.rawText,
              warnings: preview.warnings,
              sourceImage: mime.startsWith('image/') ? bytes : null,
              saveAllowed:
                  GradeService.instance.isAuthenticated && _sampleBytes == null,
            ),
          ),
        );
        if (saved == true && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MockExamScreen()),
          );
        }
        return;
      }
      if (_kind == StudentDocumentKind.schoolRecord) {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => SchoolRecordReviewScreen(
              result: preview.schoolRecordImport ?? SchoolRecordImport(),
              saveAllowed:
                  GradeService.instance.isAuthenticated && _sampleBytes == null,
            ),
          ),
        );
        if (saved == true && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SchoolRecordScreen()),
          );
        }
        return;
      }
      final isInnate = _kind.isSchoolGrade;
      final blocked = !preview.canStoreGrades;
      final authenticated = GradeService.instance.isAuthenticated;
      final canSave =
          isInnate && !blocked && authenticated && _sampleBytes == null;
      final period = _kind == StudentDocumentKind.mockExam
          ? '$_month월'
          : _kind == StudentDocumentKind.schoolRecord
          ? ''
          : '$_semester학기';
      selectAgain =
          (await Navigator.push<bool>(
            context,
            MaterialPageRoute<bool>(
              builder: (_) => GradeExtractionReviewScreenV2(
                result: preview.result,
                sourceText: preview.rawText,
                sourceImage: mime.startsWith('image/') ? bytes : null,
                warnings: preview.warnings,
                sourceLabel:
                    '${_kind.label} · $_calendarYear년 $_schoolYear학년 $period · ${preview.pageCount}쪽 · ${preview.engine}',
                saveAllowed: canSave,
                saveDisabledReason: _sampleBytes != null
                    ? '가상 예시 파일입니다. DB 저장은 차단됩니다.'
                    : !isInnate || blocked
                    ? '현재 내신 DB로 저장할 수 없는 자료입니다. 글자 추출 결과만 확인하세요.'
                    : '로그인한 일반 모드에서 실제 파일을 선택하면 DB에 저장할 수 있습니다.',
                requireSourceConfirmation: true,
                initialSchoolYear: _schoolYear,
                initialSemester: _semester,
                calendarYear: _calendarYear,
                examKind: isInnate ? _kind.name : null,
                onSelectAnotherFile: () => Navigator.pop(context, true),
                onSaved: () => CounselingSession.instance.addDocument(
                  StudentDocument(
                    kind: _kind,
                    schoolYear: _schoolYear,
                    calendarYear: _calendarYear,
                    semester: isInnate ? _semester : null,
                    examMonth: _kind == StudentDocumentKind.mockExam
                        ? _month
                        : null,
                    fileName: _file?.name ?? '가상 예시 성적표.pdf',
                  ),
                ),
              ),
            ),
          )) ==
          true;
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '성적 추출 중 오류가 발생했습니다. 파일 형식과 인식 파일 설치 상태를 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _recognizing = false;
        });
      }
    }
    if (selectAgain && mounted) await _pickFile();
  }

  void _register() {
    final document = StudentDocument(
      kind: _kind,
      schoolYear: _schoolYear,
      calendarYear: _calendarYear,
      semester: _kind.isSchoolGrade ? _semester : null,
      examMonth: _kind == StudentDocumentKind.mockExam ? _month : null,
      fileName: _sampleBytes != null ? '가상 예시 성적표.pdf' : _file!.name,
    );
    if (!CounselingSession.instance.addDocument(document)) {
      setState(() => _error = '같은 자료가 이미 목록에 있습니다.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('자료 정보만 목록에 기록했습니다. 성적 추출은 별도로 실행하세요.')),
    );
    Navigator.pop(context);
  }

  Widget _numberChoice(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
          .toList(),
      onChanged: _loading ? null : (v) => setState(() => onChanged(v!)),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('상담 자료 등록')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '이름·학교·학번을 가린 자료를 선택해 주세요. 로그인한 상태에서 이미지를 인식하면 서버를 통해 NVIDIA OCR로 전송합니다.',
          ),
          const Text(
            '사진·이미지는 NVIDIA OCR v2로 읽습니다. PDF는 기존 브라우저 인식을 사용합니다. 체험 모드에서는 로컬 인식만 사용합니다. 확인한 내신 값만 저장합니다.',
          ),
          const SizedBox(height: 16),
          if (_kind.isSchoolGrade)
            const Text(
              '예: 공통국어2(4) → 과목명 공통국어2, 학점 4. 중간고사의 석차를 석차등급으로 계산하지 않으며 원본에 없는 등급은 비워둡니다.',
            ),
          DropdownButtonFormField<int>(
            key: ValueKey('category-${_kind.isSchoolGrade}'),
            initialValue: _kind.isSchoolGrade
                ? 0
                : _kind == StudentDocumentKind.mockExam
                ? 1
                : 2,
            decoration: const InputDecoration(
              labelText: '자료 구분',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('내신 성적표')),
              DropdownMenuItem(value: 1, child: Text('모의고사')),
              DropdownMenuItem(value: 2, child: Text('생활기록부')),
            ],
            onChanged: _loading
                ? null
                : (v) => setState(
                    () => _kind = v == 0
                        ? StudentDocumentKind.midterm
                        : v == 1
                        ? StudentDocumentKind.mockExam
                        : StudentDocumentKind.schoolRecord,
                  ),
          ),
          const SizedBox(height: 12),
          _numberChoice('고등학교 학년', _schoolYear, [
            1,
            2,
            3,
          ], (v) => _schoolYear = v),
          if (_kind.isSchoolGrade)
            _numberChoice('학기', _semester, [1, 2], (v) => _semester = v),
          if (_kind.isSchoolGrade) ...[
            DropdownButtonFormField<StudentDocumentKind>(
              key: ValueKey('exam-$_kind'),
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: '시험 구분',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: StudentDocumentKind.midterm,
                  child: Text('중간고사'),
                ),
                DropdownMenuItem(
                  value: StudentDocumentKind.finalExam,
                  child: Text('기말고사'),
                ),
                DropdownMenuItem(
                  value: StudentDocumentKind.semesterSummary,
                  child: Text('중간·기말·수행 합산 (학기 종합)'),
                ),
              ],
              onChanged: _loading ? null : (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 12),
            const Text(
              '중간·기말 점수와 학기 합산 성적이 함께 있는 자료는 학기 종합을 선택하세요. 학기 종합표는 현재 글자 확인만 지원하며 성적은 직접 입력해야 합니다.',
            ),
          ],
          if (_kind == StudentDocumentKind.mockExam)
            _numberChoice(
              '모의고사 시행 월',
              _month,
              List.generate(12, (i) => i + 1),
              (v) => _month = v,
            ),
          _numberChoice(
            '성적·기록 연도',
            _calendarYear,
            List.generate(10, (i) => DateTime.now().year - i),
            (v) => _calendarYear = v,
          ),
          FilledButton.icon(
            onPressed: _loading ? null : _pickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(_loading ? '읽는 중...' : '파일 선택'),
          ),
          const Text('PDF 최대 20MB·20쪽 / 이미지 최대 5MB'),
          OutlinedButton(
            onPressed: _loading ? null : _loadSample,
            child: const Text('가상 PDF로 인식 시험 · 저장 안 됨'),
          ),
          if (_recognizing) ...[
            const LinearProgressIndicator(),
            Text(_progress),
            TextButton(
              onPressed: () => _importer.cancel(),
              child: const Text('인식 취소'),
            ),
          ],
          if (_file != null || _sampleBytes != null) ...[
            const SizedBox(height: 16),
            Text(
              '선택 파일: ${_sampleBytes != null ? "가상 예시 성적표.pdf" : _file!.name}',
            ),
            Text('${(_size / 1024).toStringAsFixed(1)} KB'),
            if (_previewBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Image.memory(
                  _previewBytes!,
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Text('이미지 미리보기를 표시할 수 없습니다.'),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('PDF는 파일명으로 확인합니다.'),
              ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _file = null;
                      _sampleBytes = null;
                      _previewBytes = null;
                      _error = null;
                    }),
              child: const Text('선택 해제'),
            ),
            const Text(
              '추출값은 확인·수정 후 저장하세요. 원본 파일은 DB로 보내지 않습니다. 표를 구분하지 못하면 과목을 직접 추가할 수 있습니다.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _extract,
              child: const Text('성적 추출 → 확인·수정'),
            ),
            if (_sampleBytes != null ||
                _file?.extension?.toLowerCase() == 'pdf')
              TextButton(
                onPressed: _loading ? null : () => _extract(forceOcr: true),
                child: const Text('PDF를 이미지로 다시 인식'),
              ),
            OutlinedButton(
              onPressed: _loading ? null : _register,
              child: const Text('파일명만 자료 목록에 기록'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
  );
}
