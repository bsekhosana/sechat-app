import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_conversation.dart';
import '../models/message.dart';
import '../providers/chat_list_provider.dart';

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
                    // Icon container with conversation type
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasUnread
                            ? const Color(0xFFFF6B35).withValues(alpha: 0.2)
                            : const Color(0xFFFF6B35).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        color: const Color(0xFFFF6B35),
                        size: 20,
                      ),
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

                          // Message preview and time
                          if (conversation.lastMessagePreview != null ||
                              isTyping) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isTyping
                                        ? 'Typing...'
                                        : conversation.lastMessagePreview ?? '',
                                    style: TextStyle(
                                      color: hasUnread
                                          ? Colors.grey[700]
                                          : Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(conversation.lastMessageAt),
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Status indicators
                          if (hasUnread || isMuted || isPinned) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (hasUnread)
                                  Container(
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
                                if (isMuted) ...[
                                  if (hasUnread) const SizedBox(width: 6),
                                  Icon(
                                    Icons.volume_off,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                ],
                                if (isPinned) ...[
                                  if (hasUnread || isMuted)
                                    const SizedBox(width: 6),
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
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
  }
}
