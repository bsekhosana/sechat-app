import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying text message bubbles with modern Material 3 design
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
              ? Theme.of(context)
                  .colorScheme
                  .primary // Keep orange for current user
              : Colors.grey[100], // Light grey for received messages
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isFromCurrentUser ? 20 : 8),
            bottomRight: Radius.circular(isFromCurrentUser ? 8 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply preview (if this is a reply)
            if (message.replyToMessageId != null) ...[
              _buildReplyPreview(context),
              const SizedBox(height: 10),
            ],

            // Main text content
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isFromCurrentUser
                        ? Colors.white // White text on orange background
                        : Colors
                            .grey[800], // Dark grey text on light background
                    height: 1.5,
                    fontSize: 15,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build reply preview with modern design
  Widget _buildReplyPreview(BuildContext context) {
    final replyText =
        message.content['replyText'] as String? ?? 'Reply to message';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isFromCurrentUser
            ? Colors.white.withOpacity(0.15)
            : Colors.grey[200], // Light grey for reply background
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFromCurrentUser
              ? Colors.white.withOpacity(0.25)
              : Colors.grey[300]!, // Grey border for reply
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Reply indicator
          Icon(
            Icons.reply,
            size: 16,
            color: isFromCurrentUser
                ? Colors.white.withOpacity(0.8)
                : Colors.grey[600], // Grey for reply icon
          ),
          const SizedBox(width: 6),
          // Reply text
          Expanded(
            child: Text(
              replyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isFromCurrentUser
                        ? Colors.white.withOpacity(0.8)
                        : Colors.grey[600], // Grey for reply text
                    fontSize: 13,
                    height: 1.3,
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
