import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/network_service.dart';
import 'chat_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/shared/widgets/profile_icon_widget.dart';
import 'package:sechat_app/shared/widgets/invite_user_widget.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/shared/models/user.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'package:sechat_app/shared/widgets/connection_status_widget.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();
  List<Chat> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final chats = <Chat>[];

      for (final chatJson in chatsJson) {
        try {
          chats.add(Chat.fromJson(chatJson));
        } catch (e) {
          print('📱 ChatListScreen: Error parsing chat: $e');
        }
      }

      setState(() {
        _chats = chats;
        _isLoading = false;
      });

      print(
          '📱 ChatListScreen: Loaded ${_chats.length} chats from SharedPreferences');
    } catch (e) {
      print('📱 ChatListScreen: Error loading chats: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openChat(Chat chat) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  void _shareApp() {
    const String shareText = '''
🔒 Join me on SeChat - Private & Secure Messaging! 

✨ Features:
• End-to-end encrypted conversations
• Anonymous messaging
• No personal data required
• Clean, modern interface

Download now and let's chat securely!

#SeChat #PrivateMessaging #Encrypted
    ''';

    Share.share(
      shareText,
      subject: 'Join me on SeChat - Secure Messaging App',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.chat,
                      color: Color(0xFFFF6B35),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Chats',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (_chats.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_chats.length}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.search,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Connection Status
            const ConnectionStatusWidget(),

            // Chats List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                      ),
                    )
                  : _chats.isEmpty
                      ? _buildEmptyState()
                      : _buildChatsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation by accepting an invitation',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _chats.length,
      itemBuilder: (context, index) {
        // Reverse the index to show newest chats at the bottom
        final reversedIndex = _chats.length - 1 - index;
        final chat = _chats[reversedIndex];
        return _buildChatCard(chat);
      },
    );
  }

  Widget _buildChatCard(Chat chat) {
    final currentUserId = SeSessionService().currentSessionId ?? '';
    final otherUserDisplayName = chat.getOtherUserDisplayName(currentUserId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: InkWell(
        onTap: () => _openChat(chat),
        onLongPress: () => _showChatActions(context, chat),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: chat.getBlockedStatus()
                      ? Colors.grey[400]
                      : const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    otherUserDisplayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Chat info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherUserDisplayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: chat.getBlockedStatus()
                                  ? Colors.grey[600]
                                  : Colors.black,
                            ),
                          ),
                        ),
                        if (chat.getBlockedStatus())
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'BLOCKED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<List<Message>>(
                      future: _getLastMessage(chat.id),
                      builder: (context, snapshot) {
                        String lastMessageText = 'No messages yet';
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final lastMessage = snapshot.data!.first;
                          lastMessageText = lastMessage.content;
                        }

                        return Text(
                          lastMessageText,
                          style: TextStyle(
                            fontSize: 14,
                            color: chat.getBlockedStatus()
                                ? Colors.grey[500]
                                : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Menu button
              IconButton(
                onPressed: () => _showChatActions(context, chat),
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m';
      }
      return '${difference.inHours}h';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  Future<List<Message>> _getLastMessage(String chatId) async {
    try {
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final chatMessages = <Message>[];

      for (final messageJson in messagesJson) {
        try {
          final message = Message.fromJson(messageJson);
          if (message.chatId == chatId && !message.isDeleted) {
            chatMessages.add(message);
          }
        } catch (e) {
          print('📱 ChatListScreen: Error parsing message: $e');
        }
      }

      // Sort by creation time and return the last message
      chatMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return chatMessages.isNotEmpty ? [chatMessages.last] : [];
    } catch (e) {
      print('📱 ChatListScreen: Error getting last message: $e');
      return [];
    }
  }

  void _showChatActions(BuildContext context, Chat chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                chat.getBlockedStatus() ? Icons.block : Icons.block_outlined,
                color: chat.getBlockedStatus() ? Colors.red : Colors.grey[600],
              ),
              title: Text(
                chat.getBlockedStatus() ? 'Unblock User' : 'Block User',
                style: TextStyle(
                  color: chat.getBlockedStatus() ? Colors.red : Colors.black,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleBlockChat(chat);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_sweep,
                color: Colors.orange,
              ),
              title: const Text(
                'Clear All Messages',
                style: TextStyle(color: Colors.orange),
              ),
              onTap: () {
                Navigator.pop(context);
                _showClearMessagesConfirmation(context, chat);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: Colors.red,
              ),
              title: const Text(
                'Delete Chat',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteChatConfirmation(context, chat);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _toggleBlockChat(Chat chat) async {
    try {
      final updatedChat = chat.copyWith(
        isBlocked: !chat.getBlockedStatus(),
        blockedAt: !chat.getBlockedStatus() ? DateTime.now() : null,
        updatedAt: DateTime.now(),
      );

      // Update chat in SharedPreferences
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final index = chatsJson.indexWhere((c) => c['id'] == chat.id);

      if (index != -1) {
        chatsJson[index] = updatedChat.toJson();
        await _prefsService.setJsonList('chats', chatsJson);

        // Refresh the chat list
        _loadChats();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updatedChat.getBlockedStatus()
                  ? 'User blocked'
                  : 'User unblocked',
            ),
            backgroundColor:
                updatedChat.getBlockedStatus() ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      print('📱 ChatListScreen: ❌ Error toggling block status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update block status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showClearMessagesConfirmation(BuildContext context, Chat chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Messages'),
        content: const Text(
          'This will permanently delete all messages in this conversation. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllMessages(chat);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showDeleteChatConfirmation(BuildContext context, Chat chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text(
          'This will permanently delete this conversation and all its messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteChat(chat);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _clearAllMessages(Chat chat) async {
    try {
      // Remove all messages for this chat
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final filteredMessages =
          messagesJson.where((m) => m['chat_id'] != chat.id).toList();
      await _prefsService.setJsonList('messages', filteredMessages);

      // Update chat to remove last message info
      final updatedChat = chat.copyWith(
        lastMessageAt: null,
        updatedAt: DateTime.now(),
      );

      // Update chat in SharedPreferences
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final index = chatsJson.indexWhere((c) => c['id'] == chat.id);

      if (index != -1) {
        chatsJson[index] = updatedChat.toJson();
        await _prefsService.setJsonList('chats', chatsJson);

        // Refresh the chat list
        _loadChats();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All messages cleared'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('📱 ChatListScreen: ❌ Error clearing messages: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear messages'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteChat(Chat chat) async {
    try {
      // Remove all messages for this chat
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final filteredMessages =
          messagesJson.where((m) => m['chat_id'] != chat.id).toList();
      await _prefsService.setJsonList('messages', filteredMessages);

      // Remove chat from SharedPreferences
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final filteredChats = chatsJson.where((c) => c['id'] != chat.id).toList();
      await _prefsService.setJsonList('chats', filteredChats);

      // Refresh the chat list
      _loadChats();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat deleted'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      print('📱 ChatListScreen: ❌ Error deleting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete chat'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
