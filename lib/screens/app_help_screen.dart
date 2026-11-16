import 'package:flutter/material.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';
import 'package:univ_pathfinder/widgets/chat_widgets.dart';

/// 앱 사용법을 묻는 도움말 채팅.
/// 답변은 서버 함수가 앱 설계·개발 문서에서 찾은 부분에만 근거한다.
/// 대화는 이 화면을 닫으면 사라지며 어디에도 저장하지 않는다.
class AppHelpScreen extends StatefulWidget {
  const AppHelpScreen({super.key, this.demoMode = false, this.service});

  final bool demoMode;
  final AppHelpService? service;

  static const suggestions = [
    '이 앱에서 뭐부터 시작하나요?',
    '성적표는 어떻게 올리나요?',
    '판단 보류는 왜 나오나요?',
    '학원에서 여러 학생을 관리할 수 있나요?',
  ];

  @override
  State<AppHelpScreen> createState() => _AppHelpScreenState();
}

class _AppHelpScreenState extends State<AppHelpScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <AppHelpMessage>[];
  late final AppHelpService _service = widget.service ?? AppHelpService();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _sending) return;
    final history = List<AppHelpMessage>.of(_messages);
    setState(() {
      _messages.add(AppHelpMessage(role: 'user', text: question));
      _sending = true;
      _error = null;
      _input.clear();
    });
    _scrollToEnd();
    try {
      final answer = await _service.ask(question, history);
      if (!mounted) return;
      setState(() => _messages.add(answer));
    } on AppHelpException catch (e) {
      if (!mounted) return;
      setState(() {
        // 답을 받지 못한 질문은 대화 기록에서 빼고 입력창에 되돌린다.
        _messages.removeLast();
        _input.text = question;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('앱 도움말')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                widget.demoMode
                    ? '체험 모드에서는 AI 도움말을 쓸 수 없습니다. 로그인하면 앱 사용법을 물어볼 수 있습니다.'
                    : '앱 사용법을 물어보세요. 질문은 외부 AI 서비스(Groq)로 보내지고, 답은 앱 설계·개발 문서를 바탕으로 하며 틀릴 수 있습니다. '
                          '학생 이름·학교·성적 같은 개인정보는 적지 마세요. 대화는 저장하지 않습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? _Suggestions(
                      enabled: !widget.demoMode && !_sending,
                      onTap: _ask,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) => i == _messages.length
                          ? const ChatTyping()
                          : ChatBubble(message: _messages[i]),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !widget.demoMode,
                      maxLength: AppHelpService.maxQuestionLength,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: '예: 진학 컨설팅 리포트는 어떻게 만드나요?',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '보내기',
                    onPressed: widget.demoMode || _sending
                        ? null
                        : () => _ask(_input.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.enabled, required this.onTap});

  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('이런 질문을 해 보세요', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in AppHelpScreen.suggestions)
              ActionChip(
                label: Text(q),
                onPressed: enabled ? () => onTap(q) : null,
              ),
          ],
        ),
      ],
    );
  }
}
