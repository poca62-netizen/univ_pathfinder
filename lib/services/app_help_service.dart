import 'package:supabase_flutter/supabase_flutter.dart';

/// 채팅 한 줄. role은 'user' 또는 'assistant'.
class AppHelpMessage {
  const AppHelpMessage({
    required this.role,
    required this.text,
    this.sources = const [],
    this.note,
  });

  final String role;
  final String text;

  /// 답변의 근거 (도움말: "문서 > 제목", 생기부 상담: 인용한 근거). 사용자 메시지는 비어 있다.
  final List<String> sources;

  /// 답변에 붙는 주의 문구 (예: 근거를 인용하지 않은 답). 서버로 다시 보내지 않는다.
  final String? note;

  bool get isUser => role == 'user';

  Map<String, String> toJson() => {'role': role, 'content': text};
}

class AppHelpException implements Exception {
  const AppHelpException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef ChatSend = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);

/// 서버 함수 `app-help`로 앱 사용법 질문을 보낸다.
/// 질문과 최근 대화만 보내며, 대화는 이 화면에서만 유지하고 저장하지 않는다.
class AppHelpService {
  AppHelpService({this.send});

  /// 테스트용 전송 함수. 없으면 Supabase 서버 함수를 부른다.
  final ChatSend? send;

  static const maxQuestionLength = 500;
  static const historyLimit = 4;

  /// 서버가 알려 준 오늘 남은 횟수가 이 값 이하이면 답 아래에 알려 준다.
  static const remainingNoticeAt = 5;

  static String messageFor(String? code, {int? limit}) => switch (code) {
    'AUTH' => '로그인이 만료되었습니다. 다시 로그인한 뒤 물어보세요.',
    'NOT_CONFIGURED' => 'AI 상담이 아직 준비되지 않았습니다. 앱 사용 안내 문서를 참고하세요.',
    'RATE_LIMIT' => '지금 질문이 많아 답할 수 없습니다. 1분쯤 뒤에 다시 물어보세요.',
    'DAILY_LIMIT' =>
      '오늘 쓸 수 있는 AI 질문${limit == null ? '' : '($limit회)'}을 모두 썼습니다. '
          '내일 다시 이용해 주세요.',
    'SERVICE_LIMIT' => '오늘 AI 상담 이용이 많아 잠시 멈췄습니다. 내일 다시 이용해 주세요.',
    'INPUT' => '질문을 $maxQuestionLength자 이내로 입력하세요.',
    'EVIDENCE' =>
      '선택한 근거 중 삭제되었거나 상담 활용이 꺼진 것이 있습니다. 생기부 컨설팅 화면을 새로고침한 뒤 다시 고르세요.',
    _ => '답변을 받지 못했습니다. 잠시 후 다시 시도하세요.',
  };

  Future<AppHelpMessage> ask(
    String question,
    List<AppHelpMessage> history,
  ) async {
    final data = await post(send, {
      'question': checkQuestion(question),
      'history': recentHistory(history),
    });
    final sources = <String>[
      for (final s in (data['sources'] as List? ?? const []))
        if (s is Map && s['title'] is String)
          s['source'] is String
              ? '${s['source']} > ${s['title']}'
              : s['title'] as String,
    ];
    return AppHelpMessage(
      role: 'assistant',
      text: answerOf(data),
      sources: sources,
      note: remainingNote(data),
    );
  }

  /// 오늘 남은 AI 질문이 적으면 안내 문구를 만든다.
  static String? remainingNote(Map<String, dynamic> data) {
    final remaining = data['remaining'];
    if (remaining is! int || remaining > remainingNoticeAt) return null;
    return remaining == 0 ? '오늘 남은 AI 질문이 없습니다.' : '오늘 남은 AI 질문 $remaining회.';
  }

  static int? _limitOf(Object? details) =>
      details is Map && details['limit'] is int
      ? details['limit'] as int
      : null;

  static String checkQuestion(String question) {
    final text = question.trim();
    if (text.isEmpty || text.length > maxQuestionLength) {
      throw AppHelpException(messageFor('INPUT'));
    }
    return text;
  }

  static List<Map<String, String>> recentHistory(List<AppHelpMessage> history) {
    final recent = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    return recent.map((m) => m.toJson()).toList();
  }

  static String answerOf(Map<String, dynamic> data) {
    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw AppHelpException(
        messageFor(data['error'] as String?, limit: _limitOf(data)),
      );
    }
    return answer.trim();
  }

  static Future<Map<String, dynamic>> post(
    ChatSend? send,
    Map<String, dynamic> body,
  ) async {
    try {
      return await (send ?? _invoke)(body);
    } on AppHelpException {
      rethrow;
    } catch (_) {
      throw AppHelpException(messageFor(null));
    }
  }

  static Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      throw AppHelpException(messageFor('AUTH'));
    }
    if (client.auth.currentSession == null) {
      throw AppHelpException(messageFor('AUTH'));
    }
    try {
      final response = await client.functions
          .invoke('app-help', body: body)
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      throw AppHelpException(messageFor(null));
    } on FunctionException catch (e) {
      final details = e.details;
      throw AppHelpException(
        messageFor(
          details is Map ? details['error'] as String? : null,
          limit: _limitOf(details),
        ),
      );
    }
  }
}

/// 생기부 상담 채팅. 근거 원문은 보내지 않고 근거 ID만 보낸다.
/// 서버가 로그인한 사용자 권한으로 DB에서 원문을 읽어 AI(Groq)에 전달한다.
class RecordChatService {
  RecordChatService({this.send});

  final ChatSend? send;

  static const maxEvidence = 6;
  static const maxGoalLength = 300;

  static const uncitedNote = '이 답은 선택한 근거를 인용하지 않았습니다. 일반적인 조언으로만 참고하세요.';

  Future<AppHelpMessage> ask(
    String question,
    List<AppHelpMessage> history, {
    required List<String> evidenceIds,
    String goal = '',
  }) async {
    if (evidenceIds.isEmpty || evidenceIds.length > maxEvidence) {
      throw const AppHelpException('상담할 근거를 1~$maxEvidence개 고르세요.');
    }
    final trimmedGoal = goal.trim();
    final data = await AppHelpService.post(send, {
      'mode': 'record',
      'question': AppHelpService.checkQuestion(question),
      'history': AppHelpService.recentHistory(history),
      'evidenceIds': evidenceIds,
      'goal': trimmedGoal.length > maxGoalLength
          ? trimmedGoal.substring(0, maxGoalLength)
          : trimmedGoal,
    });
    final text = AppHelpService.answerOf(data);
    final citations = [
      for (final c in (data['citations'] as List? ?? const []))
        if (c is Map && c['number'] is int && c['label'] is String)
          '근거 ${c['number']} ${c['label']}',
    ];
    final invalid = data['invalidCitations'] is int
        ? data['invalidCitations'] as int
        : 0;
    final notes = [
      if (citations.isEmpty) uncitedNote,
      ?AppHelpService.remainingNote(data),
      if (invalid > 0) '선택하지 않은 근거를 가리킨 인용 $invalid개를 지웠습니다.',
    ];
    return AppHelpMessage(
      role: 'assistant',
      text: text,
      sources: citations,
      note: notes.isEmpty ? null : notes.join(' '),
    );
  }
}
