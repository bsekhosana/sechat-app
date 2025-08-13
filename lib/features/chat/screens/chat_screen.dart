import 'dart:async';
import 'package:flutter/material.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/secure_notification_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/utils/guid_generator.dart';
import '../../../core/utils/encryption_error_handler.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;
  String? _currentUserId;
  String? _otherUserDisplayName;

  @override
  void initState() {
    super.initState();
    _currentUserId = SeSessionService().currentSessionId;
    _otherUserDisplayName =
        widget.chat.getOtherUserDisplayName(_currentUserId ?? '');
    _loadMessages().then((_) {
      // When messages are loaded, send read receipts for unread messages
      _sendReadReceipts();
    });
    _setupNotificationListeners();
  }

  /// Set up listeners for incoming notifications
  void _setupNotificationListeners() {
    // Listen for incoming encrypted messages
    SimpleNotificationService.instance
        .setOnEncryptedMessageReceived((recipientId, encryptedData, checksum) {
      _handleEncryptedMessage(encryptedData, checksum);
    });

    // Listen for message status updates (delivery/read receipts)
    SimpleNotificationService.instance
        .setOnMessageStatusUpdate((senderId, messageId, status) {
      _handleMessageStatusUpdate(senderId, messageId, status);
    });

    // Listen for typing indicators
    SimpleNotificationService.instance
        .setOnTypingIndicator((senderId, isTyping) {
      _handleTypingIndicator(senderId, isTyping);
    });
  }

  /// Handle typing indicator from another user
  void _handleTypingIndicator(String senderId, bool isTyping) {
    if (_currentUserId == null) return;

    try {
      // Verify this is for the current chat
      final otherUserId = widget.chat.getOtherUserId(_currentUserId!);
      if (senderId != otherUserId) {
        // Typing indicator is for a different chat
        return;
      }

      // Update the UI to show/hide typing indicator
      setState(() {
        _isOtherUserTyping = isTyping;
      });

      // Set a timer to hide the typing indicator after a delay
      if (isTyping) {
        _resetTypingTimeout();
      }

      print('📱 ChatScreen: Other user typing: $isTyping');
    } catch (e) {
      print('📱 ChatScreen: Error handling typing indicator: $e');
    }
  }

  /// Handle message status updates (delivery/read receipts)
  Future<void> _handleMessageStatusUpdate(
      String senderId, String messageId, String status) async {
    try {
      // Check if this message belongs to this chat
      final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      if (messageIndex == -1) {
        print('📱 ChatScreen: Status update for unknown message: $messageId');
        return;
      }

      final message = _messages[messageIndex];

      // Only process updates for messages we sent
      if (message.senderId != _currentUserId) {
        print(
            '📱 ChatScreen: Ignoring status update for message from another user');
        return;
      }

      // Update the message status
      MessageStatus? newStatus;
      if (status == 'delivered') {
        newStatus = MessageStatus.delivered;
      } else if (status == 'read') {
        newStatus = MessageStatus.read;
      } else {
        print('📱 ChatScreen: Unknown message status: $status');
        return;
      }

      // Create updated message
      final updatedMessage = message.copyWith(
        status: status,
        messageStatus: newStatus,
        deliveredAt:
            status == 'delivered' ? DateTime.now() : message.deliveredAt,
        readAt: status == 'read' ? DateTime.now() : message.readAt,
        updatedAt: DateTime.now(),
      );

      // Update in state
      setState(() {
        _messages[messageIndex] = updatedMessage;
      });

      // Update in storage
      await _updateMessageInStorage(updatedMessage);

      print('📱 ChatScreen: Updated message $messageId to status: $status');
    } catch (e) {
      print('📱 ChatScreen: Error handling message status update: $e');
    }
  }

  /// Update a message in storage
  Future<void> _updateMessageInStorage(Message message) async {
    try {
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final storageIndex =
          messagesJson.indexWhere((msg) => msg['id'] == message.id);

      if (storageIndex != -1) {
        messagesJson[storageIndex] = message.toJson();
        await _prefsService.setJsonList('messages', messagesJson);
      }
    } catch (e) {
      print('📱 ChatScreen: Error updating message in storage: $e');
    }
  }

  /// Send typing indicator to the other user
  Future<void> _sendTypingIndicator(bool isTyping) async {
    if (_currentUserId == null) return;

    try {
      // Get other user ID
      final otherUserId = widget.chat.getOtherUserId(_currentUserId!);

      // Send encrypted typing indicator
      await SecureNotificationService.instance.sendEncryptedTypingIndicator(
        recipientId: otherUserId,
        isTyping: isTyping,
        conversationId: widget.chat.id,
      );

      print('📱 ChatScreen: Sent typing indicator: $isTyping');
    } catch (e) {
      print('📱 ChatScreen: Error sending typing indicator: $e');
      // Don't show an error message for typing indicators
    }
  }

  /// Handle incoming encrypted message (automatically send delivery receipt for step 2)
  Future<void> _handleEncryptedMessage(
      String encryptedData, String checksum) async {
    try {
      // Try to decrypt the message data using the new encryption service
      final messageData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);
      if (messageData == null) {
        final errorType = EncryptionErrorType.decryptionFailed;
        EncryptionErrorHandler.instance.logError(
            'Failed to decrypt message data after retries',
            type: errorType);

        // Show error only if user is actively using the app
        if (mounted) {
          EncryptionErrorHandler.instance.displayError(context,
              EncryptionErrorHandler.instance.getUserFriendlyMessage(errorType),
              isWarning: true);
        }
        return;
      }

      // Verify message integrity
      final isValid = EncryptionService.verifyChecksum(messageData, checksum);
      if (!isValid) {
        final errorType = EncryptionErrorType.checksumVerificationFailed;
        EncryptionErrorHandler.instance
            .logError('Message checksum verification failed', type: errorType);

        if (mounted) {
          EncryptionErrorHandler.instance.displayError(context,
              EncryptionErrorHandler.instance.getUserFriendlyMessage(errorType),
              isWarning: true);
        }
        return;
      }

      // Extract message details
      final messageId = messageData['message_id'] as String?;
      final senderId = messageData['sender_id'] as String?;
      final conversationId = messageData['conversation_id'] as String?;
      final messageContent = messageData['message'] as String?;
      // Sender name is available but not used in this context
      final _ = messageData['sender_name'] as String?; // ignore unused
      final timestamp = messageData['timestamp'] as int?;

      // Verify this message is for this chat
      if (conversationId != widget.chat.id) {
        print('📱 ChatScreen: Message not for this chat');
        return;
      }

      if (messageId == null || senderId == null || messageContent == null) {
        EncryptionErrorHandler.instance.logError(
            'Missing required message data',
            type: EncryptionErrorType.decryptionFailed);
        return;
      }

      // Create a new message object
      final newMessage = Message(
        id: messageId,
        chatId: widget.chat.id,
        senderId: senderId,
        content: messageContent,
        type: MessageType.text,
        status: 'delivered', // Mark as delivered immediately
        messageStatus: MessageStatus.delivered,
        createdAt: timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.now(),
        updatedAt: DateTime.now(),
        isEncrypted: true,
        deliveredAt: DateTime.now(), // Mark delivery time
      );

      // Check if message already exists
      bool messageExists = false;
      for (final msg in _messages) {
        if (msg.id == messageId) {
          messageExists = true;
          break;
        }
      }

      // Only add if message doesn't exist
      if (!messageExists) {
        setState(() {
          _messages.add(newMessage);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });

        // Save message
        await _saveMessage(newMessage);

        // Update chat's last message
        await _updateChatLastMessage(newMessage);

        // Send delivery receipt (handshake step 2)
        await _sendDeliveryReceipt(messageId, senderId, widget.chat.id);
      }
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.unknownError;

      EncryptionErrorHandler.instance
          .logError('Error handling encrypted message: $e', type: errorType);

      // Only show errors to the user if they're actively using the app
      if (mounted) {
        EncryptionErrorHandler.instance.displayError(
            context,
            EncryptionErrorHandler.instance.getUserFriendlyMessage(errorType,
                details: 'Failed to process incoming message'));
      }
    }
  }

  /// Send delivery receipt (handshake step 2)
  Future<void> _sendDeliveryReceipt(
    String messageId,
    String recipientId,
    String conversationId,
  ) async {
    try {
      // Send encrypted delivery receipt
      await SecureNotificationService.instance.sendEncryptedDeliveryReceipt(
        recipientId: recipientId,
        messageId: messageId,
        conversationId: conversationId,
      );

      print('📱 ChatScreen: Delivery receipt sent for message $messageId');
    } catch (e) {
      print('📱 ChatScreen: Error sending delivery receipt: $e');
    }
  }

  /// Send read receipts for all unread messages (handshake step 3)
  Future<void> _sendReadReceipts() async {
    if (_currentUserId == null) return;

    try {
      // Find all received messages that need read receipts
      final unreadMessages = <Message>[];
      final otherUserId = widget.chat.getOtherUserId(_currentUserId!);
      final messageIds = <String>[];

      // Only process messages from the other user that need a read receipt
      for (final message in _messages) {
        if (message.senderId == otherUserId && message.needsReadReceipt) {
          unreadMessages.add(message);
          messageIds.add(message.id);

          // Update local message status to 'read'
          _updateMessageStatusToRead(message.id);
        }
      }

      if (unreadMessages.isEmpty) {
        print('📱 ChatScreen: No unread messages to mark as read');
        return;
      }

      print(
          '📱 ChatScreen: Sending read receipts for ${messageIds.length} messages');

      // Send a single read receipt for all messages (batch)
      await SecureNotificationService.instance.sendEncryptedReadReceipt(
        recipientId: otherUserId,
        messageIds: messageIds,
        conversationId: widget.chat.id,
      );

      print('📱 ChatScreen: Read receipts sent successfully');
    } catch (e) {
      print('📱 ChatScreen: Error sending read receipts: $e');
    }
  }

  /// Update a message's status to 'read'
  Future<void> _updateMessageStatusToRead(String messageId) async {
    try {
      // Find the message in the list
      final index = _messages.indexWhere((msg) => msg.id == messageId);
      if (index == -1) return;

      // Update the message status
      final message = _messages[index];
      final updatedMessage = message.markAsRead();

      // Update in the list
      setState(() {
        _messages[index] = updatedMessage;
      });

      // Save to persistent storage
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final storageIndex =
          messagesJson.indexWhere((msg) => msg['id'] == messageId);

      if (storageIndex != -1) {
        messagesJson[storageIndex] = updatedMessage.toJson();
        await _prefsService.setJsonList('messages', messagesJson);
      }
    } catch (e) {
      print('📱 ChatScreen: Error updating message status: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Reset typing timeout - used to automatically hide typing indicator
  void _resetTypingTimeout() {
    // Cancel existing timer if any
    _typingTimer?.cancel();

    // Start a new timer
    _typingTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isOtherUserTyping = false;
        });
      }
    });
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
      // Generate message ID for tracking
      final messageId = GuidGenerator.generateShortId();

      // Create new message with handshake step 1 status
      final newMessage = Message(
        id: messageId,
        chatId: widget.chat.id,
        senderId: _currentUserId!,
        content: messageText,
        type: MessageType.text,
        status: 'sent', // Step 1: Sent
        messageStatus: MessageStatus.sent,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isEncrypted: true, // All new messages are encrypted
        encryptionVersion: '1.0',
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

      // Send encrypted push notification to other user
      await _sendEncryptedPushNotification(newMessage);
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

  /// Send encrypted push notification for a message (handshake step 1)
  Future<void> _sendEncryptedPushNotification(Message message) async {
    try {
      // First verify encryption setup with recipient
      final otherUserId = widget.chat.getOtherUserId(_currentUserId!);

      // Verify encryption setup before sending
      try {
        // Check if we have the recipient's public key
        final recipientPublicKey =
            await EncryptionService.getRecipientPublicKey(otherUserId);
        if (recipientPublicKey == null) {
          if (mounted) {
            EncryptionErrorHandler.instance.displayError(context,
                'Unable to establish secure connection with recipient. Message will be saved locally but not delivered.',
                isWarning: true);

            // Update message status to error
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              setState(() {
                _messages[index] = message.copyWith(
                  status: 'error',
                  messageStatus: MessageStatus.error,
                  updatedAt: DateTime.now(),
                );
              });
              await _updateMessageInStorage(_messages[index]);
            }
            return;
          }
        }
      } catch (e) {
        print('🔒 ChatScreen: Error verifying encryption setup: $e');
        // Continue with message sending attempt
      }

      // Get current user's display name for the notification
      final currentUserDisplayName =
          widget.chat.getOtherUserDisplayName(otherUserId);

      // Send encrypted message notification with handshake step 1
      final success =
          await SecureNotificationService.instance.sendEncryptedMessage(
        recipientId: otherUserId,
        senderName: currentUserDisplayName,
        message: message.content,
        conversationId: widget.chat.id,
        messageId: message.id,
      );

      if (!success) {
        final errorType = EncryptionErrorType.networkError;
        EncryptionErrorHandler.instance.logError(
            'Failed to send encrypted message notification',
            type: errorType);

        if (mounted) {
          EncryptionErrorHandler.instance.displayError(
              context,
              EncryptionErrorHandler.instance
                  .getUserFriendlyMessage(errorType));

          // Update message status to error
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            setState(() {
              _messages[index] = message.copyWith(
                status: 'error',
                messageStatus: MessageStatus.error,
                updatedAt: DateTime.now(),
              );
            });
            await _updateMessageInStorage(_messages[index]);
          }
        }
      }
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.unknownError;

      EncryptionErrorHandler.instance.logError(
          'Error sending encrypted push notification: $e',
          type: errorType);

      if (mounted) {
        EncryptionErrorHandler.instance.displayError(
            context,
            EncryptionErrorHandler.instance.getUserFriendlyMessage(errorType,
                details: 'Failed to send encrypted message'));

        // Update message status to error
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          setState(() {
            _messages[index] = message.copyWith(
              status: 'error',
              messageStatus: MessageStatus.error,
              updatedAt: DateTime.now(),
            );
          });
          await _updateMessageInStorage(_messages[index]);
        }
      }
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

          // Typing Indicator
          if (_isOtherUserTyping && !widget.chat.getBlockedStatus())
            _buildTypingIndicator(),

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
                        if (isMyMessage && message.isEncrypted) ...[
                          const SizedBox(width: 4),
                          _buildMessageStatusIndicator(message),
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
                  // Update typing state
                  final wasTyping = _isTyping;
                  setState(() {
                    _isTyping = value.isNotEmpty;
                  });

                  // Only send typing indicator when state changes
                  if (wasTyping != _isTyping) {
                    _sendTypingIndicator(_isTyping);
                  }
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

  /// Build typing indicator UI (WhatsApp style)
  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // User avatar
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

          // Animated dots container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                _TypingDot(delay: 0),
                SizedBox(width: 3),
                _TypingDot(delay: 300),
                SizedBox(width: 3),
                _TypingDot(delay: 600),
              ],
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

  /// Build a WhatsApp style message status indicator (1 tick, 2 ticks, 2 blue ticks)
  Widget _buildMessageStatusIndicator(Message message) {
    // Error status
    if (message.isError) {
      return Icon(
        Icons.error_outline,
        size: 14,
        color: Colors.red[400],
      );
    }

    // Pending status (clock)
    if (message.isPendingStatus || message.isSending) {
      return const Icon(
        Icons.access_time,
        size: 14,
        color: Colors.white70,
      );
    }

    // Read status (2 blue ticks)
    if (message.isRead) {
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.lightBlueAccent,
      );
    }

    // Delivered status (2 ticks)
    if (message.isDelivered) {
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.white,
      );
    }

    // Sent status (1 tick)
    return const Icon(
      Icons.done,
      size: 14,
      color: Colors.white70,
    );
  }
}

/// Animated typing indicator dot with bounce effect
class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  _TypingDotState createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    )..addListener(() {
        setState(() {});
      });

    // Start animation after the delay
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -3 * _animation.value),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B35),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
