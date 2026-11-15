import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/widgets/university_selection_controls.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/university_compare_screen.dart';

class FavoritesSettingsScreen extends StatefulWidget {
  const FavoritesSettingsScreen({super.key, this.nickname});
  final String? nickname;

  @override
  State<FavoritesSettingsScreen> createState() =>
      _FavoritesSettingsScreenState();
}

class _FavoritesSettingsScreenState extends State<FavoritesSettingsScreen> {
  bool _deleting = false;
  bool _deleted = false;
  String? _deleteMessage;

  Future<void> _clearAcademicRecords() async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      // The offline preview has no authenticated client.
    }
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      setState(() => _deleteMessage = '학업 자료를 삭제하려면 로그인하세요.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('등록한 학업 자료를 모두 삭제할까요?'),
        content: const Text(
          '내신 성적, 모의고사 성적, 생활기록부 근거를 영구 삭제합니다. 이후 새 자료를 다시 등록할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('모두 삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || client.auth.currentUser?.id != userId) {
      return;
    }
    setState(() {
      _deleting = true;
      _deleted = false;
      _deleteMessage = null;
    });
    try {
      await client.rpc('clear_academic_records');
      if (client.auth.currentUser?.id == userId) {
        CounselingSession.instance.clearAcademicDocuments();
      }
      if (!mounted) return;
      setState(() {
        _deleted = true;
        _deleteMessage = '등록한 학업 자료를 삭제했습니다. 새 자료를 등록할 수 있습니다.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _deleteMessage = '삭제 결과를 확인하지 못했습니다. 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 및 설정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const Text('대학 탐색에서 선택한 목록입니다.'),
              const UniversitySelectionControls(),
              const SizedBox(height: 16),
              const Text(
                '관심 대학 목록',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: CounselingSession.instance,
                builder: (context, _) => Column(
                  children: [
                    if (CounselingSession.instance.catalogSelection.isEmpty)
                      const Text('대학 탐색에서 관심 대학을 선택하세요.'),
                    for (final name
                        in CounselingSession.instance.catalogSelection)
                      Card(
                        child: ListTile(
                          title: Text(name),
                          trailing: IconButton(
                            tooltip: '선택 해제',
                            icon: const Icon(Icons.close),
                            onPressed:
                                CounselingSession.instance.selectionBusy ||
                                    CounselingSession.instance.selectionError !=
                                        null
                                ? null
                                : () => CounselingSession.instance
                                      .toggleCatalogUniversity(name),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UniversityCompareScreen(),
                  ),
                ),
                child: const Text('관심 대학 비교'),
              ),
              const SizedBox(height: 24),
              const Text(
                '로그인 계정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(widget.nickname ?? '로그인한 사용자'),
              const Text(
                '닉네임은 중복 등록할 수 없는 로그인 ID입니다. 다른 계정으로 들어가려면 홈에서 로그아웃하세요.',
              ),
              const SizedBox(height: 24),
              const Text(
                '학업 자료 관리',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '계정에 등록한 내신·모의고사·생활기록부 자료를 한 번에 삭제합니다. 삭제 후 새 자료를 등록할 수 있습니다.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _clearAcademicRecords,
                icon: const Icon(Icons.delete_outline),
                label: Text(_deleting ? '삭제 중…' : '등록한 학업 자료 모두 삭제'),
              ),
              if (_deleteMessage != null) Text(_deleteMessage!),
              if (_deleted)
                FilledButton.icon(
                  icon: const Icon(Icons.upload_file),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CounselingDocumentsScreen(),
                    ),
                  ),
                  label: const Text('새 학업 자료 등록'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
