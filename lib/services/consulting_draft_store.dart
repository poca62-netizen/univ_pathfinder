import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConsultingDraft {
  ConsultingDraft(this.goal, Set<String> selected)
    : selected = Set.unmodifiable(selected);
  final String goal;
  final Set<String> selected;
}

/// Account-scoped local draft. Stores no school-record text or grades.
class ConsultingDraftStore {
  ConsultingDraftStore(this.userId, {this.read, this.write});
  final String userId;
  final Future<String?> Function(String)? read;
  final Future<void> Function(String, String)? write;
  String get _key => 'consulting_draft_v1/$userId';

  Future<ConsultingDraft> load() async {
    if (userId.isEmpty) return ConsultingDraft('', {});
    final raw =
        await (read?.call(_key) ?? SharedPreferencesAsync().getString(_key));
    if (raw == null) return ConsultingDraft('', {});
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['goal'] is! String ||
        (data['goal'] as String).length > 300 ||
        data['selected'] is! List ||
        (data['selected'] as List).any((v) => v is! String)) {
      throw const FormatException('Invalid consulting draft');
    }
    return ConsultingDraft(
      data['goal'] as String,
      Set<String>.from(data['selected']),
    );
  }

  Future<void> save(ConsultingDraft draft) async {
    if (userId.isEmpty) throw StateError('로그인이 필요합니다.');
    if (draft.goal.length > 300) throw ArgumentError('목표는 300자 이내로 입력하세요.');
    final raw = jsonEncode({
      'version': 1,
      'goal': draft.goal,
      'selected': draft.selected.toList(),
    });
    if (write != null) {
      await write!(_key, raw);
    } else {
      await SharedPreferencesAsync().setString(_key, raw);
    }
  }
}
