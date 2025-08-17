import 'package:flutter/material.dart';
import 'package:sechat_app/features/chat/models/optimized_message.dart';

/// Optimized Message Bubble Widget
/// Clean, focused message bubble with proper alignment and status indicators
class OptimizedMessageBubble extends StatelessWidget {
  final OptimizedMessage message;
  final bool isFromCurrentUser;

  const OptimizedMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            isFromCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isFromCurrentUser) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: _buildMessageBubble(context),
          ),
          if (isFromCurrentUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(),
          ],
        ],
      ),
    );
  }

  /// Build message bubble
  Widget _buildMessageBubble(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: isFromCurrentUser
            ? Theme.of(context).primaryColor
            : Colors.grey[200],
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isFromCurrentUser ? 16 : 4),
          bottomRight: Radius.circular(isFromCurrentUser ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageContent(),
          _buildMessageFooter(),
        ],
      ),
    );
  }

  /// Build message content
  Widget _buildMessageContent() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        message.content,
        style: TextStyle(
          color: isFromCurrentUser ? Colors.white : Colors.black87,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Build message footer with timestamp and status
  Widget _buildMessageFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimestamp(),
          if (isFromCurrentUser) ...[
            const SizedBox(width: 8),
            _buildStatusIndicator(),
          ],
        ],
      ),
    );
  }

  /// Build timestamp
  Widget _buildTimestamp() {
    final time = message.timestamp;
    final now = DateTime.now();
    final difference = now.difference(time);

    String timeText;
    if (difference.inDays > 0) {
      timeText =
          '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      timeText = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inMinutes > 0) {
      timeText =
          '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    } else {
      timeText = 'now';
    }

    return Text(
      timeText,
      style: TextStyle(
        color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
        fontSize: 11,
      ),
    );
  }

  /// Build status indicator
  Widget _buildStatusIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _getStatusIcon(),
          size: 14,
          color: _getStatusColor(),
        ),
        if (message.status == MessageStatus.read) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.done_all,
            size: 14,
            color: _getStatusColor(),
          ),
        ],
      ],
    );
  }

  /// Get status icon
  IconData _getStatusIcon() {
    switch (message.status) {
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.done;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error;
    }
  }

  /// Get status color
  Color _getStatusColor() {
    switch (message.status) {
      case MessageStatus.sending:
        return Colors.orange;
      case MessageStatus.sent:
        return Colors.grey;
      case MessageStatus.delivered:
        return Colors.grey;
      case MessageStatus.read:
        return Colors.blue;
      case MessageStatus.failed:
        return Colors.red;
    }
  }

  /// Build avatar
  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _getAvatarColor(),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getAvatarInitials(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Get avatar color based on sender
  Color _getAvatarColor() {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];

    final index = message.senderId.hashCode % colors.length;
    return colors[index.abs() % colors.length];
  }

  /// Get avatar initials from sender ID
  String _getAvatarInitials() {
    final senderId = message.senderId.trim();
    if (senderId.isEmpty) return '?';

    final parts = senderId.split('_');
    if (parts.length == 1) {
      return senderId.substring(0, 1).toUpperCase();
    }

    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
