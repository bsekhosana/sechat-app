import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying text message bubbles
class TextMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TextMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final text =
        message.content['text'] as String? ?? 'Message content unavailable';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isFromCurrentUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isFromCurrentUser ? 20 : 4),
            bottomRight: Radius.circular(isFromCurrentUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply preview (if this is a reply)
            if (message.replyToMessageId != null) ...[
              _buildReplyPreview(context),
              const SizedBox(height: 8),
            ],

            // Main text content
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isFromCurrentUser
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build reply preview
  Widget _buildReplyPreview(BuildContext context) {
    final replyText =
        message.content['replyText'] as String? ?? 'Reply to message';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isFromCurrentUser
            ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.2)
            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFromCurrentUser
              ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.3)
              : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Reply indicator
          Icon(
            Icons.reply,
            size: 16,
            color: isFromCurrentUser
                ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                : Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withOpacity(0.7),
          ),

          const SizedBox(width: 8),

          // Reply text preview
          Expanded(
            child: Text(
              replyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isFromCurrentUser
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.8)
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.8),
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
