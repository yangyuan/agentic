import 'package:flutter/material.dart';
import 'package:litertlm/litertlm.dart';

import '../rendering/markdown.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: isUser
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                color: isUser
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
              child: _MessageContents(message: message),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageContents extends StatelessWidget {
  const _MessageContents({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final content in message.contents.values)
          switch (content) {
            TextContent(:final text) => AgenticMarkdown(content: text),
            ImageBytesContent(:final bytes) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, width: 180, fit: BoxFit.cover),
              ),
            ),
            AudioBytesContent() => const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq, size: 18),
                SizedBox(width: 8),
                Text('Voice message'),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
      ],
    );
  }
}
