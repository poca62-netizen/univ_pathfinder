import 'package:supabase_flutter/supabase_flutter.dart';

class NicknameAuthException implements Exception {
  const NicknameAuthException(this.message);
  final String message;
}

class NicknameAuthService {
  NicknameAuthService({SupabaseClient? client}) : _override = client;
  final SupabaseClient? _override;
  static final instance = NicknameAuthService();
  SupabaseClient get _client => _override ?? Supabase.instance.client;
  static String? validateNickname(String value) =>
      RegExp(r'^[a-zA-Z0-9가-힣_]{2,20}$').hasMatch(value.trim())
      ? null
      : '닉네임은 한글·영문·숫자·밑줄 2~20자로 입력하세요.';
  static String? validatePin(String value) =>
      RegExp(r'^[0-9]{4}$').hasMatch(value) ? null : '비밀번호는 숫자 4자리로 입력하세요.';
  static String messageFor(String? code) => switch (code) {
    'NICKNAME_TAKEN' => '이미 사용 중인 닉네임입니다. 다른 닉네임을 입력하세요.',
    'INVALID_CREDENTIALS' => '닉네임 또는 비밀번호가 올바르지 않습니다.',
    'LOCKED' => '비밀번호를 5회 잘못 입력했습니다. 15분 후 다시 시도하세요.',
    'RATE_LIMIT' => '로그인 요청이 많습니다. 15분 후 다시 시도하세요.',
    'INPUT' => '닉네임과 숫자 4자리 비밀번호를 확인하세요.',
    _ => '인증 서버에 연결하지 못했습니다. 잠시 후 다시 시도하세요.',
  };
  Future<String> authenticate(
    String nickname,
    String pin,
    bool register,
  ) async {
    final error = validateNickname(nickname) ?? validatePin(pin);
    if (error != null) throw NicknameAuthException(error);
    try {
      final response = await _client.functions.invoke(
        'nickname-auth',
        body: {
          'action': register ? 'register' : 'login',
          'nickname': nickname.trim().toLowerCase(),
          'pin': pin,
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw const NicknameAuthException('인증하지 못했습니다. 다시 시도하세요.');
      }
      final data = response.data as Map;
      if (data['refresh_token'] is! String || data['nickname'] is! String) {
        throw const FormatException();
      }
      await _client.auth.setSession(data['refresh_token'] as String);
      return data['nickname'] as String;
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
  }
}
