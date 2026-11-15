import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';

class MockExamService {
  MockExamService({SupabaseClient? client}) : _override = client;
  final SupabaseClient? _override;
  static final instance = MockExamService();
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

  Future<List<MockExamRecord>> fetch() async {
    final rows = await _client
        .from('mock_exam_records')
        .select()
        .eq('user_id', _userId)
        .order('calendar_year', ascending: false)
        .order('exam_month', ascending: false)
        .order('subject');
    return rows.map(MockExamRecord.fromJson).toList();
  }

  Future<void> save(MockExamRecord record, {bool editing = false}) async {
    final userId = _userId;
    final errors = record.validationErrors();
    if (errors.isNotEmpty) throw ArgumentError(errors.join(' '));
    final row = record.toMap();
    if (editing) {
      row.remove('id');
      final changed = await _client
          .from('mock_exam_records')
          .update(row)
          .eq('id', record.id)
          .eq('user_id', userId)
          .select('id');
      if (changed.isEmpty) throw StateError('수정할 기록이 없습니다.');
    } else {
      await _client.from('mock_exam_records').upsert({
        ...row,
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> saveBatch(List<MockExamRecord> records) async {
    final userId = _userId;
    if (records.isEmpty) throw ArgumentError('저장할 영역을 선택하세요.');
    if (records.map((r) => r.id).toSet().length != records.length) {
      throw ArgumentError('영역의 저장 ID가 중복됩니다.');
    }
    for (final record in records) {
      final errors = record.validationErrors();
      if (errors.isNotEmpty) throw ArgumentError(errors.join(' '));
      if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(record.id)) {
        throw ArgumentError('저장 ID가 올바르지 않습니다.');
      }
    }
    // One PostgREST request is atomic. The review retains IDs for safe retries.
    final changed = await _client
        .from('mock_exam_records')
        .upsert([
          for (final r in records) {...r.toMap(), 'user_id': userId},
        ], onConflict: 'id')
        .select('id');
    final ids = changed.map((r) => r['id']).toSet();
    if (ids.length != records.length ||
        records.any((r) => !ids.contains(r.id))) {
      throw StateError('저장 결과를 확인하지 못했습니다. 같은 화면에서 다시 시도하세요.');
    }
  }

  Future<void> delete(String id) async {
    final deleted = await _client
        .from('mock_exam_records')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id');
    if (deleted.isEmpty) throw StateError('삭제할 기록이 없습니다.');
  }
}
