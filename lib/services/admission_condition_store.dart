import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';

/// Convenience check marks, local to this browser/device and partitioned by account.
/// No grades or school-record content are saved here.
class AdmissionConditionStore {
  AdmissionConditionStore(
    this.userId, {
    this.preferences,
    this.read,
    this.write,
  });
  final String userId;
  final SharedPreferencesAsync? preferences;
  final Future<String?> Function(String)? read;
  final Future<void> Function(String, String)? write;
  SharedPreferencesAsync get _prefs => preferences ?? SharedPreferencesAsync();
  String get _key => 'admission_conditions_v1/$userId';
  static String checkKey(AdmissionTrack t, String condition) => jsonEncode([
    2028,
    t.university,
    t.type,
    t.name,
    t.department,
    t.eligibility,
    t.recommendation,
    t.recommender,
    t.minimum,
    condition,
  ]);
  Future<Map<String, bool>> load() async {
    if (userId.isEmpty) return {};
    final raw = await (read?.call(_key) ?? _prefs.getString(_key));
    if (raw == null) return {};
    final data = jsonDecode(raw);
    if (data is! Map || data.values.any((v) => v is! bool)) {
      throw const FormatException('Invalid check marks');
    }
    return Map<String, bool>.from(data);
  }

  Future<void> save(Map<String, bool> checks) async {
    if (userId.isEmpty) throw StateError('로그인이 필요합니다.');
    if (write != null) {
      await write!(_key, jsonEncode(checks));
    } else {
      await _prefs.setString(_key, jsonEncode(checks));
    }
  }
}
