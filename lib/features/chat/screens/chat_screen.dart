import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/utils/guid_generator.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  String? _currentUserId;
  String? _otherUserDisplayName;

  @override
  void initState() {
    super.initState();
    _currentUserId = SeSessionService().currentSessionId;
    _otherUserDisplayName =
        widget.chat.getOtherUserDisplayName(_currentUserId ?? '');
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);

      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final chatMessages = <Message>[];

      for (final messageJson in messagesJson) {
        try {
          final message = Message.fromJson(messageJson);
          if (message.chatId == widget.chat.id && !message.isDeleted) {
            chatMessages.add(message);
          }
        } catch (e) {
          print('📱 ChatScreen: Error parsing message: $e');
        }
      }

      // Sort messages by creation time
      chatMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      setState(() {
        _messages = chatMessages;
        _isLoading = false;
      });

      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      print('📱 ChatScreen: Error loading messages: $e');
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // With reverse: true, scrolling to 0 means the bottom (newest messages)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUserId == null) return;

    try {
      // Create new message
      final newMessage = Message(
        id: GuidGenerator.generateShortId(),
        chatId: widget.chat.id,
        senderId: _currentUserId!,
        content: messageText,
        type: MessageType.text,
        status: 'sent',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Add to local list (newest messages will appear at bottom with reverse: true)
      setState(() {
        _messages.add(newMessage);
        // Sort to ensure proper order
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

      // Clear input
      _messageController.clear();

      // Scroll to bottom (newest message)
      _scrollToBottom();

      // Save message to SharedPreferences
      await _saveMessage(newMessage);

      // Update chat's last message
      await _updateChatLastMessage(newMessage);

      // Send push notification to other user
      await _sendPushNotification(newMessage);
    } catch (e) {
      print('📱 ChatScreen: Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveMessage(Message message) async {
    try {
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      messagesJson.add(message.toJson());
      await _prefsService.setJsonList('messages', messagesJson);
    } catch (e) {
      print('📱 ChatScreen: Error saving message: $e');
    }
  }

  Future<void> _updateChatLastMessage(Message message) async {
    try {
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final chatIndex = chatsJson.indexWhere((c) => c['id'] == widget.chat.id);

      if (chatIndex != -1) {
        final updatedChat = widget.chat.copyWith(
          lastMessageAt: message.createdAt,
          updatedAt: DateTime.now(),
        );
        chatsJson[chatIndex] = updatedChat.toJson();
        await _prefsService.setJsonList('chats', chatsJson);
      }
    } catch (e) {
      print('📱 ChatScreen: Error updating chat: $e');
    }
  }

  Future<void> _sendPushNotification(Message message) async {
    try {
      final otherUserId = widget.chat.getOtherUserId(_currentUserId!);
      final currentUserDisplayName =
          widget.chat.getOtherUserDisplayName(otherUserId);

      // Send regular message notification
      final success = await SimpleNotificationService.instance.sendMessage(
        recipientId: otherUserId,
        senderName: currentUserDisplayName,
        message: message.content,
        conversationId: widget.chat.id,
      );

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Failed to send message notification. Please check your internet connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Also send encrypted version for enhanced security
      try {
        await SimpleNotificationService.instance.sendEncryptedMessage(
          recipientId: otherUserId,
          senderName: currentUserDisplayName,
          message: message.content,
          conversationId: widget.chat.id,
        );
      } catch (e) {
        print('📱 ChatScreen: ⚠️ Failed to send encrypted message: $e');
        // Don't fail the whole operation if encrypted message fails
      }
    } catch (e) {
      print('📱 ChatScreen: Error sending push notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      // Mark message as deleted
      final updatedMessage = message.copyWith(
        isDeleted: true,
        deleteType: 'for_me',
        updatedAt: DateTime.now(),
      );

      // Update in SharedPreferences
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final messageIndex =
          messagesJson.indexWhere((m) => m['id'] == message.id);

      if (messageIndex != -1) {
        messagesJson[messageIndex] = updatedMessage.toJson();
        await _prefsService.setJsonList('messages', messagesJson);
      }

      // Reload messages
      await _loadMessages();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print('📱 ChatScreen: Error deleting message: $e');
    }
  }

  void _showMessageOptions(Message message) {
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
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Message',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFFF6B35),
              child: Text(
                _otherUserDisplayName?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherUserDisplayName ?? 'Unknown User',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.chat.getBlockedStatus() ? 'Blocked' : 'Online',
                    style: TextStyle(
                      color: widget.chat.getBlockedStatus()
                          ? Colors.red
                          : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {
              // TODO: Show chat options (block, clear chat, etc.)
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF6B35),
                    ),
                  )
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(),
          ),

          // Message Input
          if (!widget.chat.getBlockedStatus())
            _buildMessageInput()
          else
            _buildBlockedMessage(),
        ],
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
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true, // Messages start from bottom
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        // Reverse the index to show newest messages at the bottom
        final reversedIndex = _messages.length - 1 - index;
        final message = _messages[reversedIndex];
        final isMyMessage = message.senderId == _currentUserId;

        return _buildMessageBubble(message, isMyMessage);
      },
    );
  }

  Widget _buildMessageBubble(Message message, bool isMyMessage) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMyMessage) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFF6B35),
              child: Text(
                _otherUserDisplayName?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showMessageOptions(message),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMyMessage ? const Color(0xFFFF6B35) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMyMessage ? Colors.white : Colors.black,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatMessageTime(message.createdAt),
                          style: TextStyle(
                            color: isMyMessage
                                ? Colors.white.withValues(alpha: 0.7)
                                : Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        if (isMyMessage) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.statusIcon,
                            size: 14,
                            color: message.getStatusColor(Colors.white),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMyMessage) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFF6B35),
              child: Text(
                'Me',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) {
                  setState(() {
                    _isTyping = value.isNotEmpty;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isTyping ? _sendMessage : null,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isTyping ? const Color(0xFFFF6B35) : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send,
                color: _isTyping ? Colors.white : Colors.grey[600],
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.block, color: Colors.red[600]),
          const SizedBox(width: 8),
          Text(
            'You have blocked this user',
            style: TextStyle(
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
