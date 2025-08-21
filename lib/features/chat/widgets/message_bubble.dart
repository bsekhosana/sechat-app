import 'package:flutter/material.dart';

import '../models/message.dart';
import 'text_message_bubble.dart';
import 'reply_message_bubble.dart';
import 'system_message_bubble.dart';

/// Main message bubble widget that handles text-based message types only
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isLast;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: isFromCurrentUser ? 56 : 20,
        right: isFromCurrentUser ? 20 : 56,
        bottom: isLast ? 20 : 12,
        top: 12,
      ),
      child: Column(
        crossAxisAlignment: isFromCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Message content
          _buildMessageContent(context),

          const SizedBox(height: 6),

          // Message metadata (time, status, etc.)
          _buildMessageMetadata(context),
        ],
      ),
    );
  }

  /// Build the main message content based on type
  Widget _buildMessageContent(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return TextMessageBubble(
          message: message,
          isFromCurrentUser: isFromCurrentUser,
          onTap: onTap,
          onLongPress: onLongPress,
        );

      case MessageType.reply:
        return ReplyMessageBubble(
          message: message,
          isFromCurrentUser: isFromCurrentUser,
          onTap: onTap,
          onLongPress: onLongPress,
        );

      case MessageType.system:
        return SystemMessageBubble(
          message: message,
          onTap: onTap,
          onLongPress: onLongPress,
        );
    }
  }

  /// Build message metadata (time, status, etc.)
  Widget _buildMessageMetadata(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          isFromCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        // Time
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[100], // Light grey background for timestamp
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatTimestamp(message.timestamp),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600], // Light grey text for timestamp
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),

        // Status indicators (only for current user's messages)
        if (isFromCurrentUser) ...[
          const SizedBox(width: 8),
          _buildStatusIndicator(context),
        ],
      ],
    );
  }

  /// Build status indicator (ticks) with modern styling
  Widget _buildStatusIndicator(BuildContext context) {
    IconData icon;
    Color color;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.schedule;
        color = Colors.grey[500]!; // Grey for sending
        break;
      case MessageStatus.sent:
        icon = Icons.check; // Single tick
        color = Colors.grey[500]!; // Grey for sent
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all; // Double ticks
        color = Colors.grey[500]!; // Grey for delivered
        break;
      case MessageStatus.read:
        icon = Icons.done_all; // Double blue ticks
        color =
            Theme.of(context).colorScheme.primary; // Use theme primary color
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Theme.of(context).colorScheme.error;
        break;
      case MessageStatus.deleted:
        icon = Icons.delete_outline;
        color = Colors.grey[400]!; // Grey for deleted
        break;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[50], // Very light grey background
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: 14,
        color: color,
      ),
    );
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      // Today: show time only
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(timestamp).inDays < 7) {
      // Within a week: show day name
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      // Older: show date
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
