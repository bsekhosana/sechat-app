import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../shared/providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../../../core/services/api_service.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();

    // Add scroll listener to track position
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chatProvider = context.read<ChatProvider>();
      final currentUser = context.read<AuthProvider>().currentUser;

      if (currentUser != null) {
        // Set current user as active in this chat
        chatProvider.setUserActiveInChat(currentUser.id, widget.chat.id);

        chatProvider.loadMessages(widget.chat.id, currentUser.id);
        chatProvider.markMessagesAsRead(widget.chat.id, currentUser.id);

        // Refresh online status for the other user
        final otherUserId = widget.chat.getOtherUserId(currentUser.id);
        if (otherUserId.isNotEmpty) {
          print(
              '📱 ChatScreen: Refreshing online status for user $otherUserId');
          // Refresh online status via API
          await chatProvider.refreshUserOnlineStatus(otherUserId);
        }

        // Add listener to scroll to bottom when new messages arrive
        chatProvider.addListener(_onMessagesChanged);

        // No need to scroll to bottom initially since ListView is reversed
        // Messages will appear at the bottom by default
      } else {
        print('📱 ChatScreen: Current user not found');
      }
    });
  }

  void _onScroll() {
    // Trigger rebuild to update floating action button visibility
    setState(() {});
  }

  void _onMessagesChanged() {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.getMessagesForChat(widget.chat.id);

    // Scroll to bottom if there are messages
    if (messages.isNotEmpty && _scrollController.hasClients) {
      try {
        // Check if this is the initial load (no previous scroll position)
        final isInitialLoad = _scrollController.position.pixels == 0;

        if (isInitialLoad) {
          // Always scroll to bottom on initial load
          _scrollToBottom();
        } else {
          // For subsequent updates, only scroll if user is near bottom (top of reversed list)
          final isAtBottom =
              _scrollController.position.pixels <= 100; // 100px threshold

          if (isAtBottom) {
            _scrollToBottom();
          }
        }
      } catch (e) {
        // Handle case where scroll position is not available yet
        print(
            '📱 ChatScreen: Scroll position not available in _onMessagesChanged: $e');
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();

    // Remove listener to prevent memory leaks
    context.read<ChatProvider>().removeListener(_onMessagesChanged);

    // Set current user as inactive when leaving chat
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser != null) {
      context.read<ChatProvider>().setUserInactiveInChat(currentUser.id);
    }

    // Stop typing indicator when leaving chat
    if (_isTyping) {
      context.read<ChatProvider>().sendTypingIndicator(widget.chat.id, false);
    }
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    // Stop typing indicator
    _stopTypingIndicator();

    final chatProvider = context.read<ChatProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;

    if (currentUser != null) {
      chatProvider.sendMessage(
          widget.chat.id, _messageController.text.trim(), currentUser.id);
    } else {
      print('📱 ChatScreen: Current user not found, cannot send message');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    _messageController.clear();

    // Scroll to bottom after sending message
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Since ListView is reversed, scroll to 0 to show newest messages
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    // Only start typing indicator if there's actual content (not just spaces)
    if (text.trim().isNotEmpty) {
      if (!_isTyping) {
        _startTypingIndicator();
      }

      // Reset typing timer
      // _typingTimer?.cancel();
      // _typingTimer = Timer(const Duration(milliseconds: 1000), () {
      //   _stopTypingIndicator();
      // });
    } else {
      // If text is empty or only spaces, stop typing indicator
      if (_isTyping) {
        _stopTypingIndicator();
      }
    }
  }

  void _startTypingIndicator() {
    if (!_isTyping) {
      _isTyping = true;
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser != null) {
        context
            .read<ChatProvider>()
            .sendTypingIndicator(widget.chat.id, true, currentUser.id);
      }
    }
  }

  void _stopTypingIndicator() {
    if (_isTyping) {
      _isTyping = false;
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser != null) {
        context
            .read<ChatProvider>()
            .sendTypingIndicator(widget.chat.id, false, currentUser.id);
      }
    }
  }

  Future<void> _blockUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Block User',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to block this user? This will remove all chats and messages between you and prevent future communication.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await ApiService.blockUser(userId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'User blocked successfully'),
              backgroundColor: Colors.red,
            ),
          );
          // Navigate back to chat list
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to block user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error blocking user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeUserChats(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Remove Chats',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to remove all chats and messages with this user? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await ApiService.removeUserChats(userId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response['message'] ?? 'Chats removed successfully'),
              backgroundColor: Colors.orange,
            ),
          );
          // Navigate back to chat list
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to remove chats'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing chats: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthProvider>().currentUser;
    final otherUserId = widget.chat.getOtherUserId(currentUser?.id ?? '');
    final otherUser = context.read<ChatProvider>().getChatUser(otherUserId);

    // Get username from chat data if user not found
    String displayUsername = 'Unknown User';
    if (otherUser != null) {
      displayUsername = otherUser.username;
      print('📱 ChatScreen: Using username from otherUser: $displayUsername');
    } else if (widget.chat.otherUser != null &&
        widget.chat.otherUser!.containsKey('username')) {
      displayUsername = widget.chat.otherUser!['username'];
      print(
          '📱 ChatScreen: Using username from chat.otherUser: $displayUsername');
    } else {
      print(
          '📱 ChatScreen: No username found, using fallback: $displayUsername');
      print('📱 ChatScreen: otherUser: $otherUser');
      print('📱 ChatScreen: chat.otherUser: ${widget.chat.otherUser}');
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80, // Increased height
        title: Row(
          children: [
            CircleAvatar(
              radius: 24, // Increased avatar size
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                displayUsername.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18, // Increased font size
                ),
              ),
            ),
            const SizedBox(width: 16), // Increased spacing
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayUsername,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18, // Increased font size
                    ),
                  ),
                  const SizedBox(height: 4), // Added spacing
                  Consumer<ChatProvider>(
                    builder: (context, chatProvider, child) {
                      final isTyping = chatProvider.isUserTyping(otherUserId);

                      // Get effective online status that considers typing state
                      final effectiveOnlineStatus =
                          chatProvider.getEffectiveOnlineStatus(otherUserId);

                      if (isTyping) {
                        return Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 14, // Increased font size
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      } else {
                        return Text(
                          effectiveOnlineStatus ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 14, // Increased font size
                            color: effectiveOnlineStatus
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 28),
            onSelected: (value) async {
              switch (value) {
                case 'block':
                  await _blockUser(otherUserId);
                  break;
                case 'remove_chats':
                  await _removeUserChats(otherUserId);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Block User'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove_chats',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Remove Chats'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.call, size: 28), // Increased icon size
            onPressed: () {
              // TODO: Implement voice calling
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice calling coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final messages = chatProvider.getMessagesForChat(
                  widget.chat.id,
                );

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  reverse:
                      true, // Start from bottom, scroll up for older messages
                  itemBuilder: (context, index) {
                    // Use reversed index since we want newest messages at bottom
                    final message = messages[messages.length - 1 - index];
                    final currentUser =
                        context.read<AuthProvider>().currentUser;
                    final isOwnMessage = message.senderId == currentUser?.id;

                    return _MessageBubble(
                      message: message,
                      isOwnMessage: isOwnMessage,
                    );
                  },
                );
              },
            ),
          ),
          // Message Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  mini: true,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final messages = chatProvider.getMessagesForChat(widget.chat.id);

          // Show scroll to bottom button if there are messages and user is not at bottom
          if (messages.isNotEmpty && _scrollController.hasClients) {
            try {
              // Since ListView is reversed, check if user is near the top (which shows newest messages)
              final isAtBottom = _scrollController.position.pixels <= 100;

              if (!isAtBottom) {
                return FloatingActionButton(
                  onPressed: _scrollToBottom,
                  mini: true,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white),
                );
              }
            } catch (e) {
              // Handle case where scroll position is not available yet
              print('📱 ChatScreen: Scroll position not available yet: $e');
            }
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isOwnMessage;

  const _MessageBubble({required this.message, required this.isOwnMessage});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isOwnMessage
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: isOwnMessage
                ? const Radius.circular(16)
                : const Radius.circular(4),
            bottomRight: isOwnMessage
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isOwnMessage
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: isOwnMessage
                    ? Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
            if (isOwnMessage) ...[
              const SizedBox(width: 4),
              Icon(
                message.statusIcon,
                size: 12,
                color: message.getStatusColor(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
