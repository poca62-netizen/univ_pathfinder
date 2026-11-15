import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/services/nickname_auth_service.dart';

/// Deletes the signed-in account on the server (PIN re-entry required),
/// then removes this account's data from the current browser/device.
class AccountDeletionService {
  AccountDeletionService({
    SupabaseClient? client,
    Future<void> Function(String key)? remove,
  }) : _override = client,
       _removeKey = remove;

  final SupabaseClient? _override;
  final Future<void> Function(String key)? _removeKey;
  SupabaseClient get _client => _override ?? Supabase.instance.client;

  /// Every per-account key kept in browser/device storage.
  /// Keep in sync with university_selection_store, consulting_draft_store,
  /// admission_condition_store and the comparison history in university_search_screen.
  static List<String> localKeysFor(String userId) => [
    'university_selection_v1/$userId',
    'consulting_draft_v1/$userId',
    'admission_conditions_v1/$userId',
    'comparison_history_v1/$userId',
  ];

  static String messageFor(String? code) => switch (code) {
    'INVALID_CREDENTIALS' => '비밀번호가 올바르지 않습니다.',
    'LOCKED' => '비밀번호를 5회 잘못 입력했습니다. 15분 후 다시 시도하세요.',
    'RATE_LIMIT' => '요청이 많습니다. 15분 후 다시 시도하세요.',
    'INPUT' => '숫자 4자리 비밀번호를 입력하세요.',
    'AUTH' => '로그인이 만료되었습니다. 다시 로그인한 뒤 시도하세요.',
    'NO_NICKNAME_ACCOUNT' => '닉네임 계정이 아니어서 이 화면에서 삭제할 수 없습니다. 관리자에게 문의하세요.',
    _ => '계정을 삭제하지 못했습니다. 잠시 후 다시 시도하세요. 자료는 그대로 남아 있습니다.',
  };

  /// Returns normally only when the server confirmed deletion.
  /// Local cleanup and sign-out are best effort after that point:
  /// the account no longer exists, so failing here must not report failure.
  Future<void> deleteAccount(String pin) async {
    final error = NicknameAuthService.validatePin(pin);
    if (error != null) throw NicknameAuthException(error);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw NicknameAuthException(messageFor('AUTH'));
    try {
      final response = await _client.functions.invoke(
        'delete-account',
        body: {'pin': pin},
      );
      final data = response.data;
      if (response.status != 200 || data is! Map || data['deleted'] != true) {
        throw NicknameAuthException(messageFor(null));
      }
    } on NicknameAuthException {
      rethrow;
    } on FunctionException catch (e) {
      final details = e.details;
      throw NicknameAuthException(
        messageFor(details is Map ? details['error'] as String? : null),
      );
    } catch (_) {
      throw NicknameAuthException(messageFor(null));
    }

    final remove = _removeKey ?? SharedPreferencesAsync().remove;
    for (final key in localKeysFor(userId)) {
      try {
        await remove(key);
      } catch (_) {
        // Keys are scoped to a user ID that no longer exists.
      }
    }
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The server session died with the user; local sign-out is cleanup only.
    }
  }
}
