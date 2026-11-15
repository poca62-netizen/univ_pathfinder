import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UniversitySelectionStore {
  UniversitySelectionStore(this.userId, {this.read, this.write});
  final String userId;
  final Future<String?> Function(String)? read;
  final Future<void> Function(String, String)? write;
  String get _key => 'university_selection_v1/$userId';

  Future<Set<String>> load() async {
    if (userId.isEmpty) throw StateError('로그인이 필요합니다.');
    final raw =
        await (read?.call(_key) ?? SharedPreferencesAsync().getString(_key));
    if (raw == null) return {};
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        value['year'] != 2028 ||
        value['names'] is! List) {
      throw const FormatException('Invalid university selection');
    }
    final names = value['names'] as List;
    if (names.length > 10 ||
        names.any((v) => v is! String || v.trim().isEmpty) ||
        names.toSet().length != names.length) {
      throw const FormatException('Invalid university names');
    }
    return Set<String>.from(names);
  }

  Future<void> save(Set<String> names) async {
    if (userId.isEmpty) throw StateError('로그인이 필요합니다.');
    if (names.length > 10 || names.any((v) => v.trim().isEmpty)) {
      throw ArgumentError('대학 선택을 확인하세요.');
    }
    final raw = jsonEncode({
      'version': 1,
      'year': 2028,
      'names': names.toList(),
    });
    if (write != null) {
      await write!(_key, raw);
    } else {
      await SharedPreferencesAsync().setString(_key, raw);
    }
  }
}
