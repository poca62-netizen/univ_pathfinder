import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';
import 'package:univ_pathfinder/widgets/chat_widgets.dart';

/// 생기부 컨설팅에서 고른 근거로 AI와 상담하는 채팅.
/// 첫 질문 전에 외부 전송 동의를 받는다. 대화는 화면을 닫으면 사라지며 저장하지 않는다.
class RecordChatScreen extends StatefulWidget {
  const RecordChatScreen({
    super.key,
    required this.evidence,
    this.goal = '',
    this.service,
  });

  /// 앱에서 고른 순서. 서버도 이 순서로 [근거 1], [근거 2]… 번호를 붙인다.
  final List<SchoolRecordEvidence> evidence;
  final String goal;
  final RecordChatService? service;

  static const suggestions = [
    '이 활동들에서 드러나는 강점은 무엇일까요?',
    '다음 탐구 주제로 무엇을 이어 가면 좋을까요?',
    '기록에서 더 보완하면 좋을 부분은 무엇일까요?',
    '면접에서 이 활동을 어떻게 설명하면 좋을까요?',
  ];

  @override
  State<RecordChatScreen> createState() => _RecordChatScreenState();
}

class _RecordChatScreenState extends State<RecordChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <AppHelpMessage>[];
  late final RecordChatService _service = widget.service ?? RecordChatService();
  bool _consented = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _label(SchoolRecordEvidence e) =>
      '${e.calendarYear}년 ${e.schoolYear}학년 · ${e.category}';

  Future<bool> _askConsent() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('외부 AI로 생기부 근거를 보냅니다'),
        content: SingleChildScrollView(
          child: Text(
            '상담을 시작하면 아래 내용이 서버를 거쳐 외부 AI 서비스(Groq)로 전송됩니다.\n\n'
            '• 선택한 생기부 근거 ${widget.evidence.length}개의 원문(근거마다 앞부분 최대 700자)과 진로 메모\n'
            '• 상담 목표와 질문, 이 화면의 최근 대화\n\n'
            '근거 원문에 학생 이름·학교명·학번 같은 개인정보가 남아 있으면 먼저 "생활기록부 근거 저장·조회"에서 지운 뒤 상담하세요. '
            '내신·모의고사 성적은 보내지 않습니다. 대화는 앱에 저장하지 않습니다.\n\n'
            'AI의 답은 상담 참고용이며 틀릴 수 있습니다. 합격 가능성이나 점수는 판단하지 않습니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('동의하고 상담 시작'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _ask(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _sending) return;
    if (!_consented) {
      if (!await _askConsent() || !mounted) return;
      setState(() => _consented = true);
    }
    final history = List<AppHelpMessage>.of(_messages);
    setState(() {
      _messages.add(AppHelpMessage(role: 'user', text: question));
      _sending = true;
      _error = null;
      _input.clear();
    });
    _scrollToEnd();
    try {
      final answer = await _service.ask(
        question,
        history,
        evidenceIds: [for (final e in widget.evidence) e.id],
        goal: widget.goal,
      );
      if (!mounted) return;
      setState(() => _messages.add(answer));
    } on AppHelpException catch (e) {
      if (!mounted) return;
      setState(() {
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
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: const Text('생기부 AI 상담')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '상담 근거 ${widget.evidence.length}개',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (var i = 0; i < widget.evidence.length; i++)
                    Text(
                      '근거 ${i + 1} · ${_label(widget.evidence[i])}',
                      style: small,
                    ),
                  if (widget.goal.trim().isNotEmpty)
                    Text('상담 목표: ${widget.goal.trim()}', style: small),
                  const SizedBox(height: 4),
                  Text(
                    'AI(Groq)가 고른 근거만 읽고 답합니다. 답은 참고용이며 틀릴 수 있고, 합격 가능성·점수는 판단하지 않습니다. 대화는 저장하지 않습니다.',
                    style: small,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '이런 질문으로 시작해 보세요',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final q in RecordChatScreen.suggestions)
                              ActionChip(
                                label: Text(q),
                                onPressed: _sending ? null : () => _ask(q),
                              ),
                          ],
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) => i == _messages.length
                          ? const ChatTyping(label: '근거를 읽고 답하는 중…')
                          : ChatBubble(
                              message: _messages[i],
                              sourcesLabel: '인용한 근거',
                            ),
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
                      maxLength: AppHelpService.maxQuestionLength,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: '예: 이 탐구를 3학년 때 어떻게 심화할까요?',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '보내기',
                    onPressed: _sending ? null : () => _ask(_input.text),
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
