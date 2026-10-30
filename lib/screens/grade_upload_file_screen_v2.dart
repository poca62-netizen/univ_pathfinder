import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
class GradeUploadFileScreenV2 extends StatefulWidget { const GradeUploadFileScreenV2({super.key}); @override State<GradeUploadFileScreenV2> createState() => _GradeUploadFileScreenV2State(); }
class _GradeUploadFileScreenV2State extends State<GradeUploadFileScreenV2> {
  PlatformFile? _file;
  Uint8List? _previewBytes;
  String? _error;
  bool _loading = false;
  static const int _maxBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExt = ['jpg','jpeg','png','pdf'];
  Future<void> _pickFile() async {
    setState(()=> _error = null);
    setState(()=> _loading = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _allowedExt);
      if (!mounted) return;
      if (files.isEmpty) { setState(()=> _loading = false); return; }
      final file = files.first;
      final ext = file.extension?.toLowerCase() ?? '';
      if (!_allowedExt.contains(ext)) { setState(()=> _error = '지원하지 않는 파일 형식입니다. JPG·JPEG·PNG·PDF만 선택할 수 있습니다.'); setState(()=> _loading = false); return; }
      final size = await file.length() ?? file.lengthSync() ?? 0;
      if (size > _maxBytes) { setState(()=> _error = '파일 크기가 5MB를 초과했습니다.'); setState(()=> _loading = false); return; }
      Uint8List? preview;
      if (ext != 'pdf') { try { preview = await file.xFile.readAsBytes(); } catch (_) { preview = null; } }
      setState(()=> _file = file); setState(()=> _previewBytes = preview); setState(()=> _error = null); setState(()=> _loading = false);
    } catch (_) { if (mounted) { setState(()=> _error = '파일을 읽는 중 오류가 발생했습니다.'); setState(()=> _loading = false); } }
  }
  void _clearSelection() { setState(()=> _file = null); setState(()=> _previewBytes = null); setState(()=> _error = null); }
  @override Widget build(BuildContext context) {
    final fileSelected = _file != null;
    final isPdf = _file?.extension?.toLowerCase() == 'pdf';
    return Scaffold(appBar: AppBar(title: const Text('성적표 파일 선택')), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('성적표 업로드 전 안내', style: TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
      const SizedBox(height:8),
      const Text('이름·학교명·학번 등 식별정보는 파일에서 제거한 뒤 업로드해 주세요. 현재는 파일을 서버로 전송하지 않습니다.', style: TextStyle(fontSize:13)),
      const SizedBox(height:16),
      FilledButton.icon(onPressed: _loading ? null : _pickFile, icon: const Icon(Icons.attach_file), label: Text(_loading ? '처리 중...' : '파일 선택')),
      const SizedBox(height:12),
      if (fileSelected) ...[
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('선택된 파일: ${_file!.name}'),
          const SizedBox(height:4),
          Text('크기: ${_formatBytes(_file!.lengthSync() ?? 0)}'),
          Text('형식: ${_file!.extension?.toUpperCase() ?? '-'}'),
          const SizedBox(height:12),
          if (_file!.extension!.toLowerCase() != 'pdf' && _previewBytes != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_previewBytes!, errorBuilder: (_, __, ___) => const Text('이미지 미리보기 실패'), fit: BoxFit.contain)),
          if (isPdf) const Text('PDF 미리보기는 제공되지 않습니다. 파일명과 크기로 확인해 주세요.'),
          const SizedBox(height:12),
          Row(children: [ TextButton(onPressed: _pickFile, child: const Text('파일 변경')), const SizedBox(width:8), TextButton(onPressed: _clearSelection, child: const Text('선택 해제')) ]),
        ]))),
        const SizedBox(height:16),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: const Text('파일 선택 완료, 자동 추출은 아직 연결되지 않았습니다. 다음 단계에서 추출 결과를 확인·수정 후 저장할 수 있습니다.', style: TextStyle(fontSize:13))),
      ],
      if (_error != null) ...[ const SizedBox(height:12), Text(_error!, style: const TextStyle(color: Colors.red)) ],
    ]))));
  }
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
