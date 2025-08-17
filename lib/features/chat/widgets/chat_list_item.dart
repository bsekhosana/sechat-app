import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_conversation.dart';
import '../models/message.dart';
import '../providers/chat_list_provider.dart';
import '../../../core/services/se_session_service.dart';

/// Widget for displaying a single chat conversation item in the list
class ChatListItem extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final bool isLast;

  const ChatListItem({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatListProvider>(
      builder: (context, provider, child) {
        final currentUserId = _getCurrentUserId();
        final displayName = conversation.getDisplayName(currentUserId);
        final isTyping = conversation.isTyping;
        final hasUnread = conversation.hasUnreadMessages;
        final isMuted = conversation.isMuted;
        final isPinned = conversation.isPinned;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    // Icon container with conversation type and online status
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hasUnread
                                ? const Color(0xFFFF6B35).withValues(alpha: 0.2)
                                : const Color(0xFFFF6B35)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: const Color(0xFFFF6B35),
                            size: 20,
                          ),
                        ),
                        // Online status indicator
                        if (_isUserOnline(conversation.lastSeen))
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        // Offline indicator (show when user was last seen)
                        if (!_isUserOnline(conversation.lastSeen) &&
                            conversation.lastSeen != null)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.access_time,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Conversation details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display name
                          Text(
                            displayName,
                            style: TextStyle(
                              color:
                                  hasUnread ? Colors.black : Colors.grey[800],
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // Online status and last seen
                          if (conversation.lastSeen != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  _isUserOnline(conversation.lastSeen)
                                      ? Icons.circle
                                      : Icons.access_time,
                                  size: 10,
                                  color: _isUserOnline(conversation.lastSeen)
                                      ? Colors.green
                                      : Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isUserOnline(conversation.lastSeen)
                                      ? 'Online'
                                      : 'Last seen ${_formatLastSeen(conversation.lastSeen!)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Message preview and time
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Unread badge (left side)
                              if (hasUnread)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B35),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${conversation.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Row(
                                  children: [
                                    // Message preview or placeholder
                                    Expanded(
                                      child: Text(
                                        isTyping
                                            ? 'Typing...'
                                            : conversation.lastMessagePreview !=
                                                    null
                                                ? conversation
                                                    .lastMessagePreview!
                                                : 'No messages yet',
                                        style: TextStyle(
                                          color: isTyping
                                              ? Colors.grey[700]
                                              : conversation
                                                          .lastMessagePreview !=
                                                      null
                                                  ? (hasUnread
                                                      ? Colors.grey[700]
                                                      : Colors.grey[600])
                                                  : Colors.grey[400],
                                          fontSize: 14,
                                          fontStyle:
                                              conversation.lastMessagePreview !=
                                                      null
                                                  ? null
                                                  : FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Tick status for last message (show for all messages, not just from others)
                                    if (!isTyping &&
                                        conversation.lastMessageId != null)
                                      _buildTickStatus(
                                          conversation.lastMessageId!),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                conversation.lastMessageAt != null
                                    ? _formatTime(conversation.lastMessageAt)
                                    : '',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),

                          // Status indicators
                          if (isMuted || isPinned) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (isMuted)
                                  Icon(
                                    Icons.volume_off,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                if (isPinned) ...[
                                  if (isMuted) const SizedBox(width: 6),
                                  Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Arrow indicator
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey[400],
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Format time for display
  String _formatTime(DateTime? time) {
    if (time == null) return '';

    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    try {
      // Import and use the session service
      final sessionService = SeSessionService();
      return sessionService.currentSessionId ?? 'unknown_user';
    } catch (e) {
      print('ChatListItem: ❌ Error getting current user ID: $e');
      return 'unknown_user';
    }
  }

  /// Check if user is online based on last seen time
  bool _isUserOnline(DateTime? lastSeen) {
    if (lastSeen == null) return false;

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    // Consider user online if last seen within last 5 minutes
    return difference.inMinutes < 5;
  }

  /// Format last seen time for display
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  /// Build tick status indicator for message
  Widget _buildTickStatus(String messageId) {
    return Consumer<ChatListProvider>(
      builder: (context, provider, child) {
        // Get the latest message for this conversation to show status
        return FutureBuilder<Message?>(
          future: provider.getLatestMessage(conversation.id),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              final message = snapshot.data!;
              final currentUserId = _getCurrentUserId();

              // Show tick status for messages sent by current user
              if (message.senderId == currentUserId) {
                return Container(
                  margin: const EdgeInsets.only(left: 4),
                  child: _buildStatusIcon(message.status),
                );
              }
            }

            // Return empty container if no message or not sent by current user
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  /// Build status icon based on message status
  Widget _buildStatusIcon(MessageStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.sending:
        icon = Icons.schedule;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      case MessageStatus.deleted:
        icon = Icons.delete_outline;
        color = Colors.red;
        break;
    }

    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }
}
