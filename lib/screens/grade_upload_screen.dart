import 'package:flutter/material.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';

class GradeUploadScreen extends StatefulWidget {
  const GradeUploadScreen({super.key});
  @override
  State<GradeUploadScreen> createState() => _GradeUploadState();
}
class _GradeUploadState extends State<GradeUploadScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in ['과목', '학점', '원점수', '과목평균', '성취도', '석차등급', 'A', 'B', 'C', 'D', 'E'])
      key: TextEditingController(),
  };
  int _year = 1, _semester = 1;
  bool _busy = false;
  String? _error;
  String _text(String key) => _fields[key]!.text.trim();
  double? _number(String key) => double.tryParse(_text(key));
  @override
  void dispose() {
    for (final controller in _fields.values) { controller.dispose(); }
    super.dispose();
  }
  String? _validate(String key, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return key == '과목' || key == '학점' ? '$key 항목을 입력하세요.' : null;
    }
    if (key == '과목' || key == '성취도') return null;
    if (key == '석차등급') {
      final rank = int.tryParse(text);
      return rank == null || rank < 1 || rank > 5 ? '1~5 정수를 입력하세요.' : null;
    }
    final number = double.tryParse(text);
    if (number == null || !number.isFinite) return '올바른 숫자를 입력하세요.';
    if (key == '학점') return number <= 0 ? '0보다 크게 입력하세요.' : null;
    return number < 0 || number > 100 ? '0~100으로 입력하세요.' : null;
  }
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final distribution = <String, double>{
      for (final key in ['A', 'B', 'C', 'D', 'E'])
        if (_text(key).isNotEmpty) key: _number(key)!,
    };
    final sum = distribution.values.fold<double>(0, (a, b) => a + b);
    if (distribution.length == 5 && (sum < 99.5 || sum > 100.5)) {
      setState(() => _error = 'A~E 비율의 합은 99.5~100.5%여야 합니다.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('성적 저장 확인'),
          content: SingleChildScrollView(child: Text(
            '$_year학년 $_semester학기\n' +
            _fields.keys.map((key) => '$key: ${_text(key).isEmpty ? "-" : _text(key)}').join('\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('저장')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await GradeService.instance.insertGrade(
        schoolYear: _year, semester: _semester, subjectName: _text('과목'),
        credit: _number('학점')!, rawScore: _number('원점수'), subjectAverage: _number('과목평균'),
        achievement: _text('성취도').isEmpty ? null : _text('성취도'),
        gradeRank: int.tryParse(_text('석차등급')),
        achievementDistribution: distribution.isEmpty ? null : distribution,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('성적이 저장되었습니다.')));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GradeAnalysisScreen()));
    } on GradeServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '저장하지 못했습니다. 연결을 확인하고 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('성적 직접 입력')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('과목·학점은 필수입니다. 성적표에 없는 선택 항목은 비워두세요. 분포는 %로 입력합니다.'),
        AbsorbPointer(absorbing: _busy, child: Column(children: [
          DropdownButtonFormField<int>(initialValue: _year, decoration: const InputDecoration(labelText: '학년'),
            items: [1, 2, 3].map((v) => DropdownMenuItem(value: v, child: Text('$v학년'))).toList(),
            onChanged: (v) => setState(() => _year = v!)),
          DropdownButtonFormField<int>(initialValue: _semester, decoration: const InputDecoration(labelText: '학기'),
            items: [1, 2].map((v) => DropdownMenuItem(value: v, child: Text('$v학기'))).toList(),
            onChanged: (v) => setState(() => _semester = v!)),
          for (final key in _fields.keys) Padding(padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextFormField(controller: _fields[key], enabled: !_busy,
              decoration: InputDecoration(labelText: key),
              validator: (value) => _validate(key, value))),
        ])),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? '처리 중…' : '저장')),
      ])),
    )),
  );
}
