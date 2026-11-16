import 'package:flutter/material.dart';
import 'package:univ_pathfinder/services/app_help_service.dart';

/// 앱 도움말·생기부 상담 채팅이 함께 쓰는 말풍선.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.sourcesLabel = '근거 문서',
  });

  final AppHelpMessage message;
  final String sourcesLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: user ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message.text),
              if (message.sources.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '$sourcesLabel: ${message.sources.join(' · ')}',
                  style: small?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (message.note != null) ...[
                const SizedBox(height: 6),
                Text(
                  message.note!,
                  style: small?.copyWith(color: scheme.tertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ChatTyping extends StatelessWidget {
  const ChatTyping({super.key, this.label = '답변을 찾는 중…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
