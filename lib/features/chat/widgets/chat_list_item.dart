import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_conversation.dart';
import '../models/message.dart';
import '../providers/chat_list_provider.dart';
import '../providers/session_chat_provider.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/contact_service.dart';

/// Widget for displaying a single chat conversation item in the list
class ChatListItem extends StatefulWidget {
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
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  Message? _latestMessage;
  bool _isLoadingMessage = false;

  @override
  void initState() {
    super.initState();
    _loadLatestMessage();
  }

  @override
  void didUpdateWidget(ChatListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload latest message if conversation ID changed or last message changed
    if (oldWidget.conversation.id != widget.conversation.id ||
        oldWidget.conversation.lastMessageId !=
            widget.conversation.lastMessageId) {
      _loadLatestMessage();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload latest message when widget becomes visible (e.g., returning from chat screen)
    _loadLatestMessage();
  }

  Future<void> _loadLatestMessage() async {
    if (_isLoadingMessage) return;

    setState(() {
      _isLoadingMessage = true;
    });

    try {
      final provider = Provider.of<ChatListProvider>(context, listen: false);
      final latestMessage =
          await provider.getLatestMessage(widget.conversation.id);

      if (mounted) {
        setState(() {
          _latestMessage = latestMessage;
          _isLoadingMessage = false;
        });
      }
    } catch (e) {
      print('📱 ChatListItem: ❌ Error loading latest message: $e');
      if (mounted) {
        setState(() {
          _isLoadingMessage = false;
        });
      }
    }
  }

  String _getMessagePreview(Message? message) {
    if (message == null) return '';

    switch (message.type) {
      case MessageType.text:
        return message.content['text'] as String? ?? '';
      case MessageType.reply:
        return '↩️ Reply';
      case MessageType.system:
        return 'System message';
      default:
        return 'Message';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChatListProvider, ContactService>(
      builder: (context, provider, contactService, child) {
        final currentUserId = _getCurrentUserId();
        String displayName = widget.conversation.getDisplayName(currentUserId);

        // Check if display name is a session ID and pull from contacts if needed
        if (displayName.startsWith('session_')) {
          final otherParticipantId =
              widget.conversation.getOtherParticipantId(currentUserId);
          if (otherParticipantId != null) {
            final contact = contactService.getContact(otherParticipantId);
            if (contact != null &&
                contact.displayName != null &&
                contact.displayName!.isNotEmpty) {
              displayName = contact.displayName!;
            }
          }
        }

        final isTyping = widget.conversation.isTyping;
        final hasUnread = widget.conversation.hasUnreadMessages;

        // Get real-time presence information from ContactService
        final otherParticipantId =
            widget.conversation.getOtherParticipantId(currentUserId);
        print(
            '🔍 ChatListItem: Other participant ID: $otherParticipantId for conversation: ${widget.conversation.id}');

        final contact = otherParticipantId != null
            ? contactService.getContact(otherParticipantId)
            : null;
        print(
            '🔍 ChatListItem: Contact found: ${contact != null ? '${contact!.sessionId}:${contact.isOnline}' : 'null'}');

        // 🆕 FIXED: Use real-time online status from ChatListProvider instead of static data
        final isOnline =
            provider.getRecipientOnlineStatus(otherParticipantId ?? '');
        final lastSeen = contact?.lastSeen ?? widget.conversation.lastSeen;
        print(
            '🔍 ChatListItem: Final presence: isOnline=$isOnline (real-time from provider, contact: ${contact?.isOnline}, conversation: ${widget.conversation.isOnline})');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
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
                        if (isOnline)
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
                        if (!isOnline && lastSeen != null)
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
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Conversation details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display name (from ContactService or conversation)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  contact?.displayName ?? displayName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: hasUnread
                                        ? Colors.black
                                        : Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Last message or typing indicator
                          if (isTyping)
                            Row(
                              children: [
                                Icon(
                                  Icons.keyboard,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Typing...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            )
                          else if (_latestMessage != null)
                            Row(
                              children: [
                                Text(
                                  _getMessagePreview(_latestMessage).length > 30
                                      ? '${_getMessagePreview(_latestMessage).substring(0, 30)}...'
                                      : _getMessagePreview(_latestMessage),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),

                                const SizedBox(width: 8),
                                // Show message status for outgoing messages
                                if (widget.conversation.lastMessageId != null)
                                  _buildMessageStatus(
                                      widget.conversation.lastMessageId!,
                                      currentUserId),
                              ],
                            )
                          else
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 4),
                          // Last seen (only show when user is offline)
                          if (lastSeen != null && !isOnline) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Last seen ${_formatLastSeen(lastSeen)}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Right side: conversation ID, unread badge and time
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(height: 4),
                        // Unread badge
                        if (hasUnread)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${widget.conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        // Time
                        Text(
                          widget.conversation.lastMessageAt != null
                              ? _formatTime(widget.conversation.lastMessageAt)
                              : '',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
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

  /// Build message status for chat list preview
  Widget _buildMessageStatus(String messageId, String currentUserId) {
    return Consumer2<ChatListProvider, SessionChatProvider>(
      builder: (context, chatListProvider, sessionChatProvider, child) {
        // 🆕 FIXED: Get message status from SessionChatProvider if available (real-time)
        // This ensures the status icon updates in real-time when message status changes
        Message? latestMessage;
        MessageStatus? messageStatus;

        // First, try to get the message from SessionChatProvider (real-time status)
        // BUT ONLY if we're currently in this conversation
        if (sessionChatProvider.currentConversationId ==
            widget.conversation.id) {
          // Get the latest message from SessionChatProvider's memory
          final messages = sessionChatProvider.messages;
          if (messages.isNotEmpty) {
            // Find the specific message by ID (the last message in the conversation)
            final targetMessage = messages.firstWhere(
              (msg) => msg.id == messageId,
              orElse: () => Message(
                id: '',
                conversationId: '',
                senderId: '',
                recipientId: '',
                type: MessageType.text,
                content: {},
                status: MessageStatus.pending,
              ),
            );

            if (targetMessage.id.isNotEmpty &&
                targetMessage.senderId == currentUserId) {
              latestMessage = targetMessage;
              messageStatus = targetMessage.status;
              print(
                  '🔍 ChatListItem: Found target message from current user in SessionChatProvider: ${targetMessage.id}, status: ${targetMessage.status}');
            } else {
              print(
                  '🔍 ChatListItem: Target message not found or not from current user: $messageId');
            }
          }
        } else {
          // If we're not in this conversation, don't use SessionChatProvider data
          // This prevents showing status for messages from other conversations
          print(
              '🔍 ChatListItem: Not in this conversation (${widget.conversation.id}), using database fallback');
        }

        // Fallback to database if not found in SessionChatProvider
        if (latestMessage == null) {
          return FutureBuilder<Message?>(
            future: chatListProvider.getLatestMessage(widget.conversation.id),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                final message = snapshot.data!;

                // Only show status for messages sent by current user
                if (message.senderId == currentUserId) {
                  print(
                      '🔍 ChatListItem: Showing status for message from current user: ${message.id}, status: ${message.status}');
                  return Container(
                    margin: const EdgeInsets.only(left: 4),
                    child: _buildStatusIcon(message.status),
                  );
                } else {
                  print(
                      '🔍 ChatListItem: Not showing status - message not from current user: ${message.senderId} != $currentUserId');
                }
              }

              // Return empty container if no message or not sent by current user
              return const SizedBox.shrink();
            },
          );
        }

        // If we found a message from current user in SessionChatProvider, show its status
        if (messageStatus != null) {
          print(
              '🔍 ChatListItem: Showing status for message from current user: ${latestMessage!.id}, status: $messageStatus');
          return Container(
            margin: const EdgeInsets.only(left: 4),
            child: _buildStatusIcon(messageStatus),
          );
        }

        // Return empty container if no status found
        return const SizedBox.shrink();
      },
    );
  }

  /// Build tick status indicator for message
  Widget _buildTickStatus(String messageId) {
    return Consumer2<ChatListProvider, SessionChatProvider>(
      builder: (context, chatListProvider, sessionChatProvider, child) {
        // 🆕 FIXED: Get message status from SessionChatProvider if available (real-time)
        // This ensures the status icon updates in real-time when message status changes
        Message? latestMessage;
        MessageStatus? messageStatus;
        final currentUserId = _getCurrentUserId();

        // First, try to get the message from SessionChatProvider (real-time status)
        // BUT ONLY if we're currently in this conversation
        if (sessionChatProvider.currentConversationId ==
            widget.conversation.id) {
          // Get the latest message from SessionChatProvider's memory
          final messages = sessionChatProvider.messages;
          if (messages.isNotEmpty) {
            // Find the specific message by ID (the last message in the conversation)
            final targetMessage = messages.firstWhere(
              (msg) => msg.id == messageId,
              orElse: () => Message(
                id: '',
                conversationId: '',
                senderId: '',
                recipientId: '',
                type: MessageType.text,
                content: {},
                status: MessageStatus.pending,
              ),
            );

            if (targetMessage.id.isNotEmpty &&
                targetMessage.senderId == currentUserId) {
              latestMessage = targetMessage;
              messageStatus = targetMessage.status;
              print(
                  '🔍 ChatListItem: Found target message from current user in SessionChatProvider: ${targetMessage.id}, status: ${targetMessage.status}');
            } else {
              print(
                  '🔍 ChatListItem: Target message not found or not from current user: $messageId');
            }
          }
        } else {
          // If we're not in this conversation, don't use SessionChatProvider data
          // This prevents showing status for messages from other conversations
          print(
              '🔍 ChatListItem: Not in this conversation (${widget.conversation.id}), using database fallback');
        }

        // Fallback to database if not found in SessionChatProvider
        if (latestMessage == null) {
          return FutureBuilder<Message?>(
            future: chatListProvider.getLatestMessage(widget.conversation.id),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                final message = snapshot.data!;

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
        }

        // Show status from SessionChatProvider (real-time)
        if (messageStatus != null) {
          return Container(
            margin: const EdgeInsets.only(left: 4),
            child: _buildStatusIcon(messageStatus),
          );
        }

        // Return empty container if no status found
        return const SizedBox.shrink();
      },
    );
  }

  /// Build status icon based on message status
  Widget _buildStatusIcon(MessageStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.pending:
        icon = Icons.schedule;
        color = Colors.orange;
        break;
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
        color = Colors.orange;
        break;
      case MessageStatus.queued:
        icon = Icons.schedule_send;
        color = Colors.orange;
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
