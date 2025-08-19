import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying reply message bubbles
class ReplyMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ReplyMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final replyText = content['replyText'] as String? ?? 'Reply to message';
    final replySenderName = content['replySenderName'] as String? ?? 'Unknown';
    final replyMessageType = content['replyMessageType'] as String? ?? 'text';

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
            // Reply preview
            _buildReplyPreview(
                context, replyText, replySenderName, replyMessageType),

            const SizedBox(height: 8),

            // Main message content
            _buildMainMessageContent(context, content),
          ],
        ),
      ),
    );
  }

  /// Build reply preview section
  Widget _buildReplyPreview(BuildContext context, String replyText,
      String replySenderName, String replyMessageType) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply header
          Row(
            children: [
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

              Text(
                replySenderName,
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
                      fontWeight: FontWeight.w600,
                    ),
              ),

              const SizedBox(width: 8),

              // Message type indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isFromCurrentUser
                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.3)
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _getMessageTypeLabel(replyMessageType),
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
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Reply text preview
          Text(
            replyText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isFromCurrentUser
                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.8),
                  fontStyle: FontStyle.italic,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build main message content
  Widget _buildMainMessageContent(
      BuildContext context, Map<String, dynamic> content) {
    final messageType = content['messageType'] as String? ?? 'text';

    switch (messageType) {
      case 'text':
        final text = content['text'] as String? ?? 'Message content';
        return Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isFromCurrentUser
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        );

      case 'emoticon':
        final emoticon = content['emoticon'] as String? ?? '😊';
        return Text(
          emoticon,
          style: const TextStyle(
            fontSize: 24,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
        );

      default:
        return Text(
          'Reply message',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isFromCurrentUser
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        );
    }
  }

  /// Get message type label
  String _getMessageTypeLabel(String messageType) {
    switch (messageType) {
      case 'text':
        return 'Text';
      case 'voice':
        return 'Voice';
      case 'video':
        return 'Video';
      case 'image':
        return 'Image';
      case 'document':
        return 'Document';
      case 'location':
        return 'Location';
      case 'contact':
        return 'Contact';
      case 'emoticon':
        return 'Emoticon';
      default:
        return 'Message';
    }
  }
}
