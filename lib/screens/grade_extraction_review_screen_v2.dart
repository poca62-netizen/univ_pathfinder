import 'package:univ_pathfinder/models/grade_scope.dart';
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';

import 'dart:math';
import 'dart:typed_data';

class GradeExtractionReviewScreenV2 extends StatefulWidget {
  final ExtractionResult result;
  final bool isTest;
  final bool saveAllowed;
  final String? saveDisabledReason;
  final String? sourceText;
  final String? sourceLabel;
  final List<String> warnings;
  final Uint8List? sourceImage;
  final bool requireSourceConfirmation;
  final int initialSchoolYear;
  final int initialSemester;
  final int? calendarYear;
  final String? examKind;
  final bool isEditing;
  final VoidCallback? onSaved;
  final VoidCallback? onSelectAnotherFile;
  final Future<void> Function(List<Map<String, dynamic>>)? saveGrades;
  const GradeExtractionReviewScreenV2({
    super.key,
    required this.result,
    this.isTest = false,
    this.saveAllowed = true,
    this.saveDisabledReason,
    this.sourceText,
    this.sourceLabel,
    this.warnings = const [],
    this.sourceImage,
    this.requireSourceConfirmation = false,
    this.initialSchoolYear = 1,
    this.initialSemester = 1,
    this.calendarYear,
    this.examKind,
    this.isEditing = false,
    this.onSaved,
    this.onSelectAnotherFile,
    this.saveGrades,
  });
  @override
  State<GradeExtractionReviewScreenV2> createState() =>
      _GradeExtractionReviewStateV2();
}

class _GradeExtractionReviewStateV2
    extends State<GradeExtractionReviewScreenV2> {
  final _form = GlobalKey<FormState>();
  late List<GradeDraft> drafts;
  bool _busy = false, _confirming = false;
  bool _sourceConfirmed = false;
  final _ids = <GradeDraft, String>{};
  final _subjectKeys = <GradeDraft, GlobalKey>{};
  final _inputErrors = <GradeDraft, Map<String, String>>{};

  List<String> _errorsFor(GradeDraft draft) => [
    ...draft.validationErrors(),
    ...?_inputErrors[draft]?.values,
  ];
  String? _error;
  late bool _hadSubjects;
  @override
  void initState() {
    super.initState();
    drafts = widget.result.subjects
        .where((d) => !GradeScope.isExcludedSubject(d.subjectName ?? ''))
        .map((d) => d.copy())
        .toList();
    _hadSubjects = drafts.isNotEmpty;
  }

  Future<void> _saveAll() async {
    if (_busy ||
        _confirming ||
        widget.isTest ||
        !widget.saveAllowed ||
        drafts.isEmpty ||
        (widget.requireSourceConfirmation && !_sourceConfirmed)) {
      return;
    }
    if (!_form.currentState!.validate()) {
      for (final draft in drafts) {
        if (_errorsFor(draft).isNotEmpty) {
          _showSubject(draft);
          break;
        }
      }
      setState(() => _error = '수정이 필요한 과목의 입력값을 확인해 주세요.');
      return;
    }
    for (final d in drafts) {
      final errors = d.validationErrors();
      if (errors.isNotEmpty) {
        setState(
          () => _error = '${d.subjectName ?? "과목"}: ${errors.join(", ")}',
        );
        return;
      }
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('성적 저장 확인'),
        content: Text('${drafts.length}개 과목을 저장하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final confirmedAt = DateTime.now().toUtc().toIso8601String();
      final payloads = drafts
          .map(
            (d) => <String, dynamic>{
              if (widget.calendarYear != null)
                'calendar_year': widget.calendarYear,
              if (widget.examKind != null) 'exam_kind': widget.examKind,
              if (widget.requireSourceConfirmation)
                'source_confirmed_at': confirmedAt,
              if (widget.requireSourceConfirmation)
                'id': _ids.putIfAbsent(d, _newId),
              'school_year': d.schoolYear!,
              'semester': d.semester!,
              'subject_name': d.subjectName!.trim(),
              'credit': d.credit!,
              if (d.rawScore != null) 'raw_score': d.rawScore,
              if (d.subjectAverage != null) 'subject_average': d.subjectAverage,
              if (d.achievement?.trim().isNotEmpty ?? false)
                'achievement': d.achievement!.trim(),
              if (d.gradeRank != null) 'grade_rank': d.gradeRank,
              if (d.achievementDistribution?.isNotEmpty ?? false)
                'achievement_distribution': d.achievementDistribution,
            },
          )
          .toList();
      await (widget.saveGrades ??
          (widget.requireSourceConfirmation
              ? GradeService.instance.upsertImportedGrades
              : GradeService.instance.insertGradesBatch))(payloads);
      if (!mounted) return;
      widget.onSaved?.call();
      if (widget.isEditing) {
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('성적이 저장되었습니다.')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GradeAnalysisScreen()),
      );
    } on GradeServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '저장하지 못했습니다. 입력은 유지됩니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSubject(GradeDraft draft) {
    final target = _subjectKeys[draft]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      alignment: 0,
    );
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  String? _validateNumber(
    String? input, {
    bool required = false,
    bool integer = false,
    double min = 0,
    double max = 100,
    bool positive = false,
  }) {
    final text = input?.trim() ?? '';
    if (text.isEmpty) return required ? '필수 항목입니다.' : null;
    final value = double.tryParse(text);
    if (value == null ||
        !value.isFinite ||
        (integer && int.tryParse(text) == null)) {
      return '올바른 ${integer ? "정수" : "숫자"}를 입력하세요.';
    }
    if ((positive && value <= 0) || value < min || value > max) {
      return positive ? '0보다 큰 유한 숫자를 입력하세요.' : '$min~$max 범위로 입력하세요.';
    }
    return null;
  }

  Widget _number(
    GradeDraft draft,
    String label,
    num? value,
    ValueChanged<String> update, {
    bool required = false,
    bool integer = false,
    double min = 0,
    double max = 100,
    bool positive = false,
  }) => TextFormField(
    initialValue: value?.toString() ?? '',
    enabled: !_busy && !_confirming,
    decoration: InputDecoration(labelText: label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (v) => _validateNumber(
      v,
      required: required,
      integer: integer,
      min: min,
      max: max,
      positive: positive,
    ),
    onChanged: (v) => setState(() {
      update(v.trim());
      final error = _validateNumber(
        v,
        required: required,
        integer: integer,
        min: min,
        max: max,
        positive: positive,
      );
      final errors = _inputErrors.putIfAbsent(draft, () => {});
      if (error == null) {
        errors.remove(label);
      } else {
        errors[label] = '$label: $error';
      }
      _sourceConfirmed = false;
      _error = null;
    }),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isEditing ? '저장된 성적 수정' : '추출 결과 확인·수정'),
      actions: [
        if (widget.sourceImage != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(context).appBarTheme.foregroundColor ??
                  Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.zoom_in),
            label: const Text('원본 보기'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('원본 이미지 대조'),
                    leading: IconButton(
                      tooltip: '원본 닫기',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '확대하거나 드래그해 과목명·괄호 속 학점·원점수·평균을 대조하세요. 원본에 없는 값은 입력하지 마세요.',
                        ),
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 8,
                          child: Center(
                            child: Image.memory(
                              widget.sourceImage!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text(
                                '원본 이미지를 표시하지 못했습니다. 파일을 다시 선택해 주세요.',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.isTest)
            Container(
              color: Colors.red.shade50,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: const Text(
                '테스트 데이터입니다. 저장 버튼은 비활성화되어 있습니다.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (!widget.saveAllowed && !widget.isTest)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.saveDisabledReason ?? '로그인한 일반 모드에서만 DB에 저장할 수 있습니다.',
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          Expanded(
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (widget.isEditing)
                      const Text(
                        '수정한 값은 저장 후 다시 조회합니다. 이전 원본 대조 확인 표시는 초기화됩니다.',
                      ),
                    if (widget.sourceLabel != null)
                      Text(
                        widget.sourceLabel!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (drafts.isNotEmpty && widget.requireSourceConfirmation)
                      Text(
                        '${drafts.where((d) => _errorsFor(d).isNotEmpty).length}개 과목의 누락·범위 확인이 필요합니다. 값이 채워져 있어도 원본과 대조하세요.',
                      ),
                    if (drafts.any((d) => _errorsFor(d).isNotEmpty))
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final d in drafts.where(
                            (d) => _errorsFor(d).isNotEmpty,
                          ))
                            ActionChip(
                              avatar: const Icon(Icons.error_outline, size: 18),
                              label: Text(
                                '${d.subjectName?.trim().isNotEmpty == true ? d.subjectName!.trim() : "이름 없는 과목"} · 수정 필요',
                              ),
                              onPressed: () => _showSubject(d),
                            ),
                        ],
                      ),
                    if (widget.sourceText != null) ...[
                      const Text(
                        '보통교과 및 전문교과만 저장·분석합니다. 체육·예술·과학탐구실험·교양교과는 제외합니다. 인식값을 원본과 대조하세요. 현재 DB는 5등급 내신 항목만 저장합니다.',
                      ),
                      for (final warning in widget.warnings)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            warning,
                            style: const TextStyle(color: Colors.deepOrange),
                          ),
                        ),
                      ExpansionTile(
                        title: const Text('추출 원문 확인 (이 화면에서만 보관)'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(widget.sourceText!),
                          ),
                        ],
                      ),
                    ],
                    if (drafts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              _hadSubjects
                                  ? '모든 과목을 제외했습니다. 저장할 내용이 없습니다.'
                                  : '자동으로 추출된 과목이 없습니다. 아직 저장된 성적은 없습니다.',
                            ),
                            if (!_hadSubjects)
                              const Text(
                                '사진의 방향·작은 글씨·흐림 또는 표 서식 때문에 인식하지 못했을 수 있습니다. 성적 표가 크게 보이는 선명한 사진을 다시 선택하거나 과목을 직접 추가해 주세요.',
                              ),
                            if (!_hadSubjects &&
                                widget.onSelectAnotherFile != null)
                              OutlinedButton.icon(
                                onPressed: widget.onSelectAnotherFile,
                                icon: const Icon(Icons.image_search),
                                label: const Text('파일 다시 선택'),
                              ),
                          ],
                        ),
                      ),
                    for (final d in drafts)
                      Card(
                        key: _subjectKeys.putIfAbsent(d, () => GlobalKey()),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final error in _errorsFor(d))
                                Text(
                                  error,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: d.subjectName ?? '',
                                      enabled: !_busy && !_confirming,
                                      decoration: const InputDecoration(
                                        labelText: '과목명',
                                      ),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? '과목명을 입력하세요.'
                                          : null,
                                      onChanged: (v) => setState(() {
                                        d.subjectName = v;
                                        _sourceConfirmed = false;
                                        _error = null;
                                      }),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _busy || _confirming || widget.isEditing
                                        ? null
                                        : () => setState(() {
                                            drafts.remove(d);
                                            _subjectKeys.remove(d);
                                            _inputErrors.remove(d);
                                            _ids.remove(d);
                                            _sourceConfirmed = false;
                                          }),
                                    child: const Text('제외'),
                                  ),
                                ],
                              ),
                              _number(
                                d,
                                '학년 1~3',
                                d.schoolYear,
                                (v) => d.schoolYear = int.tryParse(v),
                                required: true,
                                integer: true,
                                min: 1,
                                max: 3,
                              ),
                              _number(
                                d,
                                '학기 1~2',
                                d.semester,
                                (v) => d.semester = int.tryParse(v),
                                required: true,
                                integer: true,
                                min: 1,
                                max: 2,
                              ),
                              _number(
                                d,
                                '학점',
                                d.credit,
                                (v) => d.credit = double.tryParse(v),
                                required: true,
                                max: double.maxFinite,
                                positive: true,
                              ),
                              _number(
                                d,
                                '원점수 0~100',
                                d.rawScore,
                                (v) => d.rawScore = double.tryParse(v),
                              ),
                              _number(
                                d,
                                '과목평균 0~100',
                                d.subjectAverage,
                                (v) => d.subjectAverage = double.tryParse(v),
                              ),
                              TextFormField(
                                initialValue: d.achievement ?? '',
                                enabled: !_busy && !_confirming,
                                decoration: const InputDecoration(
                                  labelText: '성취도',
                                ),
                                onChanged: (v) => setState(() {
                                  d.achievement = v;
                                  _sourceConfirmed = false;
                                }),
                              ),
                              _number(
                                d,
                                '석차등급 1~5',
                                d.gradeRank,
                                (v) => d.gradeRank = int.tryParse(v),
                                integer: true,
                                min: 1,
                                max: 5,
                              ),
                              const SizedBox(height: 12),
                              const Text('성취도 분포 (%) · 원본에 없으면 비워두세요.'),
                              for (final key in ['A', 'B', 'C', 'D', 'E'])
                                _number(
                                  d,
                                  '$key 분포',
                                  d.achievementDistribution?[key],
                                  (v) {
                                    d.achievementDistribution ??= {};
                                    if (v.isEmpty) {
                                      d.achievementDistribution!.remove(key);
                                    } else {
                                      final number = double.tryParse(v);
                                      if (number != null) {
                                        d.achievementDistribution![key] =
                                            number;
                                      } else {
                                        d.achievementDistribution!.remove(key);
                                      }
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.saveAllowed &&
                        !widget.isTest &&
                        !widget.isEditing)
                      OutlinedButton.icon(
                        onPressed: _busy || _confirming
                            ? null
                            : () => setState(() {
                                _hadSubjects = true;
                                drafts.add(
                                  GradeDraft(
                                    schoolYear: widget.initialSchoolYear,
                                    semester: widget.initialSemester,
                                  ),
                                );
                                _sourceConfirmed = false;
                              }),
                        icon: const Icon(Icons.add),
                        label: const Text('과목 직접 추가'),
                      ),
                    if (drafts.isNotEmpty &&
                        widget.requireSourceConfirmation &&
                        widget.saveAllowed &&
                        !widget.isTest)
                      CheckboxListTile(
                        value: _sourceConfirmed,
                        title: const Text('추출값과 누락·경고 항목을 원본과 대조해 확인했습니다.'),
                        onChanged: _busy || _confirming
                            ? null
                            : (v) =>
                                  setState(() => _sourceConfirmed = v ?? false),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed:
                  widget.isTest ||
                      !widget.saveAllowed ||
                      _busy ||
                      _confirming ||
                      drafts.isEmpty ||
                      (widget.requireSourceConfirmation && !_sourceConfirmed)
                  ? null
                  : _saveAll,
              child: Text(_busy ? '처리 중...' : '확인 후 저장'),
            ),
          ),
        ],
      ),
    ),
  );
}
