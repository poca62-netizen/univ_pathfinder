import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';

class SchoolRecordService {
  SchoolRecordService({SupabaseClient? client}) : _override = client;
  final SupabaseClient? _override;
  static final instance = SchoolRecordService();
  SupabaseClient get _client => _override ?? Supabase.instance.client;
  String get _userId =>
      _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

  static String newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<List<SchoolRecordEvidence>> fetch() async {
    final rows = await _client
        .from('school_record_evidence')
        .select()
        .eq('user_id', _userId)
        .order('calendar_year', ascending: false)
        .order('school_year', ascending: false)
        .order('category');
    return rows.map(SchoolRecordEvidence.fromJson).toList();
  }

  Future<void> save(SchoolRecordEvidence record, {bool editing = false}) async {
    final userId = _userId;
    final errors = record.validationErrors();
    if (errors.isNotEmpty) throw ArgumentError(errors.join(' '));
    final row = record.toMap();
    if (editing) {
      row.remove('id');
      final changed = await _client
          .from('school_record_evidence')
          .update(row)
          .eq('id', record.id)
          .eq('user_id', userId)
          .select('id');
      if (changed.isEmpty) throw StateError('수정할 기록이 없습니다.');
    } else {
      await _client.from('school_record_evidence').upsert({
        ...row,
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> delete(String id) async {
    final deleted = await _client
        .from('school_record_evidence')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id');
    if (deleted.isEmpty) throw StateError('삭제할 기록이 없습니다.');
  }

  Future<void> setCareerEnabled(String id, bool enabled) async {
    final rows = await _client
        .from('school_record_evidence')
        .update({'career_evidence_enabled': enabled})
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id');
    if (rows.isEmpty) throw StateError('변경할 근거가 없습니다.');
  }

  Future<Map<String, dynamic>> importReviewed({
    required List<Map<String, dynamic>> grades,
    required List<SchoolRecordEvidence> evidence,
  }) async {
    final userId = _userId;
    for (final record in evidence) {
      if (record.validationErrors().isNotEmpty) {
        throw ArgumentError(record.validationErrors().join(' '));
      }
    }
    final result = await _client.rpc(
      'import_school_record',
      params: {
        'p_grades': grades,
        'p_evidence': evidence.map((r) => r.toMap()).toList(),
      },
    );
    if (_userId != userId) throw StateError('로그인 사용자가 바뀌었습니다. 다시 조회하세요.');
    return Map<String, dynamic>.from(result as Map);
  }
}
