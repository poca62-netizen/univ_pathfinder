import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';

class UniversitySelectionControls extends StatefulWidget {
  const UniversitySelectionControls({super.key, this.store});
  final UniversitySelectionStore? store;
  @override
  State<UniversitySelectionControls> createState() =>
      _UniversitySelectionControlsState();
}

class _UniversitySelectionControlsState
    extends State<UniversitySelectionControls> {
  UniversitySelectionStore? _store;
  final _session = CounselingSession.instance;
  @override
  void initState() {
    super.initState();
    _store = widget.store;
    if (_store == null) {
      try {
        final id = Supabase.instance.client.auth.currentUser?.id;
        if (id != null) _store = UniversitySelectionStore(id);
      } catch (_) {
        /* Offline preview. */
      }
    }
    // Avoid notifying parent listeners during their build.
    if (_store != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _session.restoreSelection(_store!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _store == null ? '체험 모드의 선택은 앱 실행 중에만 유지됩니다.' : '목록 저장을 누르면 현재 계정의 이 브라우저·기기에 저장합니다. 다른 기기에는 동기화되지 않으며 브라우저 데이터 삭제 시 사라집니다.',
        ),
        if (_store != null) ...[
          if (_session.selectionBusy) const LinearProgressIndicator(),
          if (_session.selectionError != null) ...[
            Text(_session.selectionError!),
            TextButton(
              onPressed: _session.selectionBusy
                  ? null
                  : () => _session.restoreSelection(_store!, retry: true),
              child: const Text('관심 대학 다시 불러오기'),
            ),
          ],
          OutlinedButton.icon(
            onPressed: _session.selectionBusy || _session.selectionError != null
                ? null
                : _session.saveSelection,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _session.selectionDirty ? '관심 대학 목록 저장 · 변경 있음' : '관심 대학 목록 저장',
            ),
          ),
          if (_session.selectionStatus != null) Text(_session.selectionStatus!),
        ],
      ],
    ),
  );
}
