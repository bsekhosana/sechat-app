import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/se_socket_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/encryption_service.dart';
import '../services/message_storage_service.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../models/chat_conversation.dart';
import '../providers/chat_list_provider.dart';
import '../models/message.dart';
import '../../../realtime/realtime_service_manager.dart';
import '../../../realtime/typing_service.dart';
import 'dart:async';
import 'dart:convert';

class SessionChatProvider extends ChangeNotifier {
  final SeSocketService _socketService = SeSocketService();

  // Realtime services
  TypingService? _typingService;

  // State
  final List<Chat> _chats = [];
  final Map<String, User> _chatUsers = {};
  final Map<String, bool> _typingUsers = {};
  final Map<String, int> _unreadCounts = {};
  bool _isLoading = false;
  String? _error;

  // Chat conversation state
  String? _currentConversationId;
  String? _currentRecipientId;
  String? _currentRecipientName;
  final List<Message> _messages = [];
  bool _isRecipientTyping = false;
  DateTime? _recipientLastSeen;
  bool _isRecipientOnline = false;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Chat conversation getters
  List<Message> get messages => _messages;
  bool get isRecipientTyping => _isRecipientTyping;
  DateTime? get recipientLastSeen => _recipientLastSeen;
  bool get isRecipientOnline => _isRecipientOnline;
  String? get currentRecipientName => _currentRecipientName;
  String? get currentRecipientId => _currentRecipientId;

  /// Get the current conversation ID, generating one if not set
  String get currentConversationId {
    if (_currentConversationId == null || _currentConversationId!.isEmpty) {
      // Generate a consistent conversation ID if none set
      final currentUserId = SeSessionService().currentSessionId ?? '';
      final recipientId = _currentRecipientId ?? '';
      if (currentUserId.isNotEmpty && recipientId.isNotEmpty) {
        _currentConversationId = 'chat_${currentUserId}_$recipientId';
        print(
            '📱 SessionChatProvider: 🔧 Auto-generated conversation ID: $_currentConversationId');
      }
    }
    return _currentConversationId ?? 'unknown';
  }

  /// Ensure conversation ID is consistent and set
  void _ensureConversationId() {
    if (_currentConversationId == null || _currentConversationId!.isEmpty) {
      final currentUserId = SeSessionService().currentSessionId ?? '';
      final recipientId = _currentRecipientId ?? '';
      if (currentUserId.isNotEmpty && recipientId.isNotEmpty) {
        _currentConversationId = 'chat_${currentUserId}_$recipientId';
        print(
            '📱 SessionChatProvider: 🔧 Ensured conversation ID: $_currentConversationId');
      }
    }
  }

  /// Check if a message is from the current user
  bool isMessageFromCurrentUser(Message message) {
    final currentUserId = SeSessionService().currentSessionId;
    // Use both metadata and senderId for reliable ownership detection
    if (currentUserId != null) {
      // First check metadata if available
      if (message.metadata != null &&
          message.metadata!.containsKey('messageDirection')) {
        return message.metadata!['messageDirection'] == 'outgoing';
      }
      // Fallback to senderId comparison
      return message.senderId == currentUserId;
    }
    return false;
  }

  /// Get current user ID
  String? get currentUserId => SeSessionService().currentSessionId;

  /// Check if a specific user is typing
  bool isUserTyping(String userId) {
    return _typingUsers[userId] ?? false;
  }

  User? getChatUser(String userId) {
    return _chatUsers[userId];
  }

  SessionChatProvider() {
    // Set up socket callbacks for real-time communication

    // Set up typing indicator callback from socket service
    _socketService.setOnTypingIndicator((senderId, isTyping) {
      _handleTypingIndicatorFromSocket(senderId, isTyping);
    });

    // Set up online status callback from socket service
    _socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
      _handleOnlineStatusUpdateFromSocket(senderId, isOnline, lastSeen);
    });

    // Set up chat message received callback from socket service
    _socketService.setOnMessageReceived(
        (senderId, senderName, message, conversationId, messageId) {
      _handleChatMessageReceivedFromSocket(
          senderId, senderName, message, conversationId, messageId);
    });
  }

  /// Update recipient online status from external source (e.g., ChatListProvider)
  void updateRecipientStatus({
    required String recipientId,
    required bool isOnline,
    DateTime? lastSeen,
  }) {
    if (_currentRecipientId == recipientId) {
      _isRecipientOnline = isOnline;
      _recipientLastSeen = lastSeen;
      notifyListeners();
      print('🔌 SessionChatProvider: ✅ Recipient status updated: $isOnline');
    }
  }

  /// Update recipient typing state from external source (e.g., main.dart callback)
  void updateRecipientTypingState(bool isTyping) {
    if (_currentRecipientId != null) {
      _isRecipientTyping = isTyping;
      notifyListeners();
      print(
          '🔌 SessionChatProvider: ✅ Recipient typing state updated: $isTyping');
    }
  }

  /// Handle typing indicator from socket callback
  void _handleTypingIndicatorFromSocket(String senderId, bool isTyping) {
    try {
      print(
          '🔌 SessionChatProvider: Typing indicator callback received: $senderId -> $isTyping');

      // CRITICAL: Prevent sender from processing their own typing indicator
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null && senderId == currentUserId) {
        print(
            '📱 SessionChatProvider: ⚠️ Ignoring own typing indicator from: $senderId');
        return; // Don't process own typing indicator
      }

      // Update typing state for the sender (only for other users)
      if (isTyping) {
        _typingUsers[senderId] = true;
      } else {
        _typingUsers.remove(senderId);
      }

      // If this is the current recipient, update the recipient typing state
      if (_currentRecipientId == senderId) {
        _isRecipientTyping = isTyping;
        print(
            '📱 SessionChatProvider: ✅ Updated current recipient typing state: $isTyping');
      }

      // Notify listeners to update UI
      notifyListeners();
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error handling typing indicator callback: $e');
    }
  }

  /// Handle online status update from socket callback
  void _handleOnlineStatusUpdateFromSocket(
      String senderId, bool isOnline, String? lastSeen) {
    try {
      print(
          '📱 SessionChatProvider: 🔔 Online status callback received: $senderId -> $isOnline (lastSeen: $lastSeen)');

      // CRITICAL: Prevent sender from processing their own online status update
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null && senderId == currentUserId) {
        print(
            '📱 SessionChatProvider: ⚠️ Ignoring own online status update from: $senderId');
        return; // Don't process own online status update
      }

      // Update user data
      if (_chatUsers.containsKey(senderId)) {
        final user = _chatUsers[senderId]!;
        _chatUsers[senderId] = user.copyWith(
          isOnline: isOnline,
          lastSeen:
              lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now(),
        );

        // Update chat
        final chatIndex = _chats.indexWhere((chat) => chat.id == senderId);
        if (chatIndex != -1) {
          final chat = _chats[chatIndex];
          _chats[chatIndex] = chat.copyWith(
            otherUser: {
              ...?chat.otherUser,
              'is_online': isOnline,
              'last_seen': lastSeen ?? DateTime.now().toIso8601String(),
            },
          );
        }

        // If this is the current recipient, update the recipient online state
        if (_currentRecipientId == senderId) {
          _isRecipientOnline = isOnline;
          _recipientLastSeen =
              lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now();
          print(
              '📱 SessionChatProvider: ✅ Updated current recipient online state: $isOnline');
        }

        // Notify listeners to update UI
        notifyListeners();
      }
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error handling online status callback: $e');
    }
  }

  /// Handle chat message received from socket callback
  void _handleChatMessageReceivedFromSocket(String senderId, String senderName,
      String message, String conversationId, String messageId) {
    try {
      print(
          '📱 SessionChatProvider: 🔔 Chat message callback received: $senderName -> $message (ID: $messageId)');

      // Check if this message belongs to the current conversation
      // Use more flexible matching to handle different conversation ID formats
      bool isForCurrentConversation = false;

      if (_currentConversationId != null &&
          _currentConversationId!.isNotEmpty) {
        // Direct match
        if (_currentConversationId == conversationId) {
          isForCurrentConversation = true;
        } else {
          // Check if the conversation ID contains the current user and the other participant
          final currentUserId = SeSessionService().currentSessionId;
          if (currentUserId != null) {
            // Check if this is a conversation between current user and sender
            if (conversationId.contains(currentUserId) &&
                conversationId.contains(senderId)) {
              isForCurrentConversation = true;
            }
            // Also check if current conversation ID contains the sender
            if (_currentConversationId!.contains(senderId)) {
              isForCurrentConversation = true;
            }
          }
        }
      }

      if (isForCurrentConversation) {
        // Create a new message object
        final newMessage = Message(
          id: messageId,
          conversationId: conversationId,
          senderId: senderId,
          recipientId: SeSessionService().currentSessionId ?? '',
          type: MessageType.text,
          content: {'text': message},
          status: MessageStatus.delivered,
          timestamp: DateTime.now(),
        );

        // Add message to the messages list
        _messages.add(newMessage);

        // Sort messages by timestamp
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Update the chat's last message
        _updateOrCreateChat(conversationId, newMessage);

        print(
            '📱 SessionChatProvider: ✅ Message added to current conversation: $messageId');

        // Notify listeners to update UI
        notifyListeners();
      } else {
        print(
            '📱 SessionChatProvider: ℹ️ Message not for current conversation: $conversationId (current: $_currentConversationId)');
      }
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error handling chat message callback: $e');
    }
  }

  // Send message using encrypted notifications
  Future<void> sendMessage({
    required String recipientId,
    required String content,
    String messageType = 'text',
  }) async {
    try {
      // Ensure conversation ID is available
      _ensureConversationId();

      _isLoading = true;
      _error = null;
      notifyListeners();

      // Generate unique message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_$recipientId';

      // Use the consistent conversation ID from the getter
      final consistentConversationId = currentConversationId;

      // Create message data for encryption
      final messageData = {
        'type': 'message',
        'message_id': messageId,
        'sender_id': SeSessionService().currentSessionId ?? '',
        'sender_name': 'User',
        'message': content,
        'conversation_id': consistentConversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Create properly encrypted payload using EncryptionService
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          messageData, recipientId);

      // Send message via socket service
      final success = await _socketService.sendMessage(
        recipientId: recipientId,
        message: content,
        conversationId: consistentConversationId,
        messageId: messageId,
      );

      if (success) {
        // Use the consistent conversation ID
        final properConversationId = consistentConversationId;

        print(
            '📱 SessionChatProvider: 🔍 Sending message with conversation ID: $properConversationId');
        print(
            '📱 SessionChatProvider: 🔍 Current conversation ID: $_currentConversationId');
        print('📱 SessionChatProvider: 🔍 Recipient ID: $recipientId');

        final message = Message(
          id: messageId,
          conversationId: properConversationId,
          senderId: SeSessionService().currentSessionId ?? '',
          recipientId: recipientId,
          type: MessageType.text,
          content: {'text': content},
          status: MessageStatus.sent,
          timestamp: DateTime.now(),
          // Add metadata to distinguish outgoing messages
          metadata: {
            'isFromCurrentUser': true,
            'messageDirection': 'outgoing',
            'sentAt': DateTime.now().toIso8601String(),
            'recipientId': recipientId,
          },
        );

        print(
            '📱 SessionChatProvider: 🔍 Message created: ${message.id} for conversation: ${message.conversationId}');

        // Add message to chat using proper conversation ID
        _addMessageToChat(properConversationId, message);

        // Update chat using proper conversation ID
        _updateOrCreateChat(properConversationId, message);

        // Also update the chat list for the sender (this ensures the sender's chat list updates)
        // This mimics the old implementation's behavior
        try {
          // Update the chat list directly to show the latest message
          // This ensures the sender's chat list updates immediately
          final currentUserId = SeSessionService().currentSessionId;
          if (currentUserId != null) {
            // Find and update the chat in the chat list
            final chatIndex = _chats.indexWhere((chat) =>
                chat.id == properConversationId ||
                chat.otherUser?['id'] == recipientId ||
                chat.user2Id == recipientId);

            if (chatIndex != -1) {
              // Update existing chat
              final existingChat = _chats[chatIndex];
              _chats[chatIndex] = existingChat.copyWith(
                id: properConversationId, // Ensure consistent ID
                lastMessage: {'text': content, 'id': messageId},
                lastMessageAt: DateTime.now(),
              );
              print(
                  '📱 SessionChatProvider: ✅ Updated existing chat in chat list');
            } else {
              // Create new chat entry if it doesn't exist
              final newChat = Chat(
                id: properConversationId,
                user1Id: currentUserId,
                user2Id: recipientId,
                user1DisplayName: currentUserId,
                user2DisplayName: recipientId,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                otherUser: {
                  'id': recipientId,
                  'name':
                      recipientId, // Will be updated when user data is loaded
                  'is_online': false,
                },
                lastMessage: {'text': content, 'id': messageId},
                lastMessageAt: DateTime.now(),
              );
              _chats.add(newChat);
              print('📱 SessionChatProvider: ✅ Added new chat to chat list');
            }

            // Notify listeners to update UI
            notifyListeners();
          }
        } catch (e) {
          print('📱 SessionChatProvider: ⚠️ Error updating chat list: $e');
        }

        print(
            '📱 SessionChatProvider: Message sent via silent notification: $recipientId');
      } else {
        throw Exception('Failed to send message notification');
      }
    } catch (e) {
      _error = 'Failed to send message: $e';
      notifyListeners();
      print('📱 SessionChatProvider: Error sending message: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send typing indicator using AirNotifier silent notifications
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      // Ensure conversation ID is available
      _ensureConversationId();

      // Validate recipient ID
      if (recipientId.isEmpty || recipientId == 'unknown') {
        print(
            '📱 SessionChatProvider: ❌ Invalid recipient ID for typing indicator: $recipientId');
        return;
      }

      print(
          '📱 SessionChatProvider: 🔍 Sending typing indicator to: $recipientId (isTyping: $isTyping)');

      // Use the consistent conversation ID from the getter
      final consistentConversationId = currentConversationId;

      // Use realtime typing service instead of old socket method
      bool success = false;
      try {
        if (_typingService != null) {
          if (isTyping) {
            _typingService!
                .startTyping(consistentConversationId, [recipientId]);
          } else {
            _typingService!.stopTyping(consistentConversationId);
          }
          success = true;
        } else {
          print('📱 SessionChatProvider: ⚠️ Typing service not available');
          success = false;
        }
      } catch (e) {
        print('📱 SessionChatProvider: ❌ Error using typing service: $e');
        success = false;
      }

      if (success) {
        print(
            '📱 SessionChatProvider: ✅ Typing indicator sent via silent notification: $recipientId - $isTyping');
      } else {
        print(
            '📱 SessionChatProvider: ❌ Failed to send typing indicator to: $recipientId');
      }
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error sending typing indicator to $recipientId: $e');
    }
  }

  // Handle message received via silent notification
  Future<void> handleMessageReceived(Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String;
      final senderName = data['senderName'] as String;
      final content = data['message'] as String;
      final conversationId = data['conversationId'] as String;

      // Generate message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_$senderId';

      // Create message object
      final message = Message(
        id: messageId,
        conversationId: conversationId,
        senderId: senderId,
        recipientId: SeSessionService().currentSessionId ?? '',
        type: MessageType.text,
        content: {'text': content},
        status: MessageStatus.sent,
      );

      // Add message to chat
      _addMessageToChat(senderId, message);

      // Update chat
      _updateOrCreateChat(senderId, message);

      // Show notification
      // await _notificationService.showLocalNotification( // This line was removed as per the new_code
      //   title: senderName,
      //   body: content,
      //   type: 'message',
      //   data: {
      //     'senderName': senderName,
      //     'message': content,
      //     'conversationId': conversationId,
      //   },
      // );

      // Send delivery status
      // _airNotifier.sendMessageDeliveryStatus( // This line was removed as per the new_code
      //   recipientId: senderId,
      //   messageId: messageId,
      //   status: 'delivered',
      //   conversationId: conversationId,
      // );

      print(
          '📱 SessionChatProvider: Message received via silent notification: $senderId');
      notifyListeners();
    } catch (e) {
      print('📱 SessionChatProvider: Error handling message received: $e');
    }
  }

  // Handle typing indicator via silent notification
  void handleTypingIndicator(Map<String, dynamic> data) {
    try {
      final senderId = data['senderId'] as String;

      // Handle both boolean and string values for isTyping
      bool isTyping;
      final isTypingValue = data['isTyping'];
      if (isTypingValue is bool) {
        isTyping = isTypingValue;
      } else if (isTypingValue is int) {
        isTyping = isTypingValue == 1;
      } else if (isTypingValue is String) {
        isTyping = isTypingValue == '1' || isTypingValue == 'true';
      } else {
        print(
            '📱 SessionChatProvider: Invalid isTyping value type: ${isTypingValue.runtimeType}');
        return;
      }

      if (isTyping) {
        _typingUsers[senderId] = true;
      } else {
        _typingUsers.remove(senderId);
      }

      print(
          '📱 SessionChatProvider: Typing indicator received via silent notification: $senderId - $isTyping');
      notifyListeners();
    } catch (e) {
      print('📱 SessionChatProvider: Error handling typing indicator: $e');
    }
  }

  // Handle online status update via silent notification
  void handleOnlineStatusUpdate(Map<String, dynamic> data) {
    try {
      final senderId = data['senderId'] as String;

      // Handle both boolean and string values for isOnline
      bool isOnline;
      final isOnlineValue = data['isOnline'];
      if (isOnlineValue is bool) {
        isOnline = isOnlineValue;
      } else if (isOnlineValue is int) {
        isOnline = isOnlineValue == 1;
      } else if (isOnlineValue is String) {
        isOnline = isOnlineValue == '1' || isOnlineValue == 'true';
      } else {
        print(
            '📱 SessionChatProvider: Invalid isOnline value type: ${isOnlineValue.runtimeType}');
        return;
      }

      final lastSeen = data['lastSeen'] as String;

      final user = _chatUsers[senderId];
      if (user != null) {
        _chatUsers[senderId] = user.copyWith(
          isOnline: isOnline,
          lastSeen: DateTime.parse(lastSeen),
        );

        // Update chat
        final chatIndex = _chats.indexWhere((chat) => chat.id == senderId);
        if (chatIndex != -1) {
          final chat = _chats[chatIndex];
          _chats[chatIndex] = chat.copyWith(
            otherUser: {
              ...?chat.otherUser,
              'is_online': isOnline,
              'last_seen': lastSeen,
            },
          );
        }

        print(
            '📱 SessionChatProvider: Online status update received via silent notification: $senderId - $isOnline');
        notifyListeners();
      }
    } catch (e) {
      print('📱 SessionChatProvider: Error handling online status update: $e');
    }
  }

  // Add message to chat
  void _addMessageToChat(String chatId, Message message) {
    // Add message to the messages list for the current conversation
    // Also add if this is a message we're sending (sender is current user)
    final currentUserId = SeSessionService().currentSessionId;
    final isOwnMessage =
        currentUserId != null && message.senderId == currentUserId;

    if (_currentConversationId == chatId || isOwnMessage) {
      _messages.add(message);
      // Sort messages by timestamp
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      print(
          '📱 SessionChatProvider: ✅ Message added to messages list: ${message.id}');
    } else {
      print(
          '📱 SessionChatProvider: ℹ️ Message not added to messages list - not current conversation and not own message');
      print(
          '📱 SessionChatProvider: ℹ️ Current conversation: $_currentConversationId, Message chat: $chatId, Is own message: $isOwnMessage');
    }

    // Update the chat's last message
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      _chats[chatIndex] = chat.copyWith(
        lastMessageAt: message.timestamp,
        lastMessage: _convertToMessageMap(message),
        updatedAt: message.timestamp,
      );
      print('📱 SessionChatProvider: ✅ Updated existing chat: $chatId');
    } else {
      print('📱 SessionChatProvider: ℹ️ Chat not found for message: $chatId');
    }

    // Notify listeners to update UI
    notifyListeners();
  }

  // Update or create chat
  void _updateOrCreateChat(String conversationId, Message message) {
    print(
        '📱 SessionChatProvider: 🔍 Updating/creating chat for conversation: $conversationId');

    // First try to find by conversation ID
    int existingChatIndex =
        _chats.indexWhere((chat) => chat.id == conversationId);

    // If not found by ID, try to find by recipient ID to prevent duplicates
    if (existingChatIndex == -1) {
      final recipientId = _extractRecipientIdFromConversationId(conversationId);
      existingChatIndex = _chats.indexWhere((chat) =>
          chat.user2Id == recipientId || chat.otherUser?['id'] == recipientId);

      if (existingChatIndex != -1) {
        print(
            '📱 SessionChatProvider: 🔍 Found existing chat by recipient ID: $recipientId');
        // Update the existing chat's ID to match the new conversation ID
        final existingChat = _chats[existingChatIndex];
        _chats[existingChatIndex] = existingChat.copyWith(id: conversationId);
      }
    }

    if (existingChatIndex != -1) {
      // Update existing chat
      final chat = _chats[existingChatIndex];
      _chats[existingChatIndex] = chat.copyWith(
        lastMessageAt: message.timestamp,
        lastMessage: _convertToMessageMap(message),
        updatedAt: message.timestamp,
      );
      print('📱 SessionChatProvider: ✅ Updated existing chat: $conversationId');
    } else {
      // Create new chat - extract recipient ID from conversation ID
      final recipientId = _extractRecipientIdFromConversationId(conversationId);
      print(
          '📱 SessionChatProvider: 🔍 Creating new chat for recipient: $recipientId');

      final user = _chatUsers[recipientId] ??
          User(
            id: recipientId,
            username: 'Anonymous User',
            profilePicture: null,
            isOnline: false,
            lastSeen: DateTime.now(),
            alreadyInvited: true,
            invitationStatus: 'accepted',
          );

      _chatUsers[recipientId] = user;

      final chat = Chat(
        id: conversationId,
        user1Id: SeSessionService().currentSessionId ?? '',
        user2Id: recipientId,
        user1DisplayName: 'Me',
        user2DisplayName: user.username,
        status: 'active',
        lastMessageAt: message.timestamp,
        createdAt: message.timestamp,
        updatedAt: message.timestamp,
      );

      _chats.add(chat);
      print('📱 SessionChatProvider: ✅ Created new chat: $conversationId');
    }

    // Notify listeners to update UI
    notifyListeners();
  }

  // Helper method to extract recipient ID from conversation ID
  String _extractRecipientIdFromConversationId(String conversationId) {
    // Handle different conversation ID formats
    if (conversationId.startsWith('chat_')) {
      // Format: chat_${currentUserId}_${recipientId}
      final parts = conversationId.split('_');
      if (parts.length >= 3) {
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && parts[1] == currentUserId) {
          // Return the recipient ID (parts[2])
          return parts[2];
        }
      }
    }

    // Fallback: return the conversation ID as is
    return conversationId;
  }

  // Convert Message to Map for Chat
  Map<String, dynamic> _convertToMessageMap(Message message) {
    return {
      'id': message.id,
      'sender_id': message.senderId,
      'content': message.content['text'] ?? jsonEncode(message.content),
      'type': message.type.toString().split('.').last,
      'timestamp': message.timestamp.toIso8601String(),
      'status': message.status.name,
    };
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId, String senderId) async {
    try {
      // Send read receipt via socket service
      await _socketService.sendMessageStatusUpdate(
        recipientId: senderId,
        messageId: messageId,
        status: 'read',
      );

      print('📱 SessionChatProvider: Message marked as read: $messageId');
    } catch (e) {
      print('📱 SessionChatProvider: Error marking message as read: $e');
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Initialize the chat provider for a specific conversation
  Future<void> initialize({
    required String conversationId,
    required String recipientId,
    required String recipientName,
  }) async {
    try {
      _isLoading = true;
      _error = null;

      // Set the conversation ID and recipient info
      _currentConversationId = conversationId;
      _currentRecipientId = recipientId;
      _currentRecipientName = recipientName;

      // Ensure conversation ID is always set and consistent
      _ensureConversationId();

      // Load existing messages for this conversation
      await _loadMessagesForConversation(_currentConversationId!);

      // Load recipient user data
      await _loadRecipientUserData(recipientId);

      // Initialize realtime typing service
      _setupTypingService();

      _isLoading = false;
      notifyListeners();

      print(
          '📱 SessionChatProvider: ✅ Initialized for conversation: $_currentConversationId');
    } catch (e) {
      _error = 'Failed to initialize chat: $e';
      _isLoading = false;
      notifyListeners();
      print('📱 SessionChatProvider: ❌ Failed to initialize: $e');
    }
  }

  /// Load messages for a specific conversation
  Future<void> _loadMessagesForConversation(String conversationId) async {
    try {
      // Load messages from MessageStorageService
      final messageStorageService = MessageStorageService.instance;
      final loadedMessages =
          await messageStorageService.getMessages(conversationId, limit: 100);

      // Merge with existing messages to avoid duplicates
      final existingMessageIds = _messages.map((m) => m.id).toSet();
      final newMessages = loadedMessages
          .where((m) => !existingMessageIds.contains(m.id))
          .toList();

      // Add new messages to existing list
      _messages.addAll(newMessages);

      // Sort messages by timestamp
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      print(
          '📱 SessionChatProvider: Loaded ${loadedMessages.length} messages for conversation: $conversationId');
      print(
          '📱 SessionChatProvider: Total messages in memory: ${_messages.length}');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error loading messages: $e');
      // Don't clear existing messages on error
    }
  }

  /// Load recipient user data
  Future<void> _loadRecipientUserData(String recipientId) async {
    try {
      // Check if we already have user data
      if (_chatUsers.containsKey(recipientId)) {
        final user = _chatUsers[recipientId]!;
        _isRecipientOnline = user.isOnline;
        _recipientLastSeen = user.lastSeen;
      } else {
        // Create default user data
        _isRecipientOnline = false;
        _recipientLastSeen = DateTime.now();
      }

      // Try to get the latest status from ChatListProvider if available
      try {
        // Note: We'll rely on the main.dart callback to update recipient status
        // when the ChatListProvider receives online status updates
        print(
            '📱 SessionChatProvider: ℹ️ Recipient status will be updated via socket callbacks');
      } catch (e) {
        print('📱 SessionChatProvider: ⚠️ ChatListProvider not available: $e');
      }

      print('📱 SessionChatProvider: Loaded recipient data for: $recipientId');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error loading recipient data: $e');
    }
  }

  /// Mark conversation as read
  Future<void> markAsRead() async {
    try {
      if (_currentRecipientId != null) {
        // Mark all messages as read
        for (final message in _messages) {
          if (message.senderId != _currentRecipientId) {
            await markMessageAsRead(message.id, message.senderId);
          }
        }

        // Update unread count
        _unreadCounts[_currentConversationId ?? ''] = 0;

        print('📱 SessionChatProvider: ✅ Conversation marked as read');
        notifyListeners();
      }
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error marking conversation as read: $e');
    }
  }

  /// Refresh messages for the current conversation
  Future<void> refreshMessages() async {
    try {
      if (_currentConversationId != null) {
        await _loadMessagesForConversation(_currentConversationId!);
        notifyListeners();
        print('📱 SessionChatProvider: ✅ Messages refreshed');
      }
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error refreshing messages: $e');
    }
  }

  /// Update typing indicator for the current recipient
  void updateTypingIndicator(bool isTyping) async {
    try {
      // Ensure conversation ID is available
      _ensureConversationId();

      // CRITICAL: Only update local typing state, don't send to self
      final currentUserId = SeSessionService().currentSessionId;
      if (_currentRecipientId != null && _currentRecipientId != currentUserId) {
        // Send typing indicator to other user via silent notification
        await sendTypingIndicator(_currentRecipientId!, isTyping);
        print(
            '📱 SessionChatProvider: ✅ Typing indicator sent to recipient: $_currentRecipientId');
      } else {
        print(
            '📱 SessionChatProvider: ⚠️ No valid recipient for typing indicator');
      }

      // Update local typing state for UI
      _isRecipientTyping = isTyping;
      notifyListeners();
      print('📱 SessionChatProvider: Typing indicator updated: $isTyping');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error updating typing indicator: $e');
    }
  }

  /// Send text message (alias for sendMessage)
  Future<void> sendTextMessage(String text) async {
    if (_currentRecipientId != null) {
      await sendMessage(
        recipientId: _currentRecipientId!,
        content: text,
        messageType: 'text',
      );
    } else {
      throw Exception('No recipient set. Call initialize() first.');
    }
  }

  /// Check if conversation is muted
  bool get isMuted {
    // For now, return false. In a real implementation, this would check conversation settings
    return false;
  }

  /// Toggle mute notifications for the current conversation
  Future<void> toggleMuteNotifications() async {
    try {
      // For now, just log the action. In a real implementation, this would update conversation settings
      print('📱 SessionChatProvider: Toggle mute notifications called');
      // TODO: Implement actual mute functionality
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error toggling mute notifications: $e');
    }
  }

  /// Setup realtime typing service
  void _setupTypingService() {
    try {
      // Check if already initialized
      if (_typingService != null) {
        print('📱 SessionChatProvider: ℹ️ Typing service already initialized');
        return;
      }

      // Initialize typing service
      _typingService = RealtimeServiceManager.instance.typing;

      // Listen for typing updates from peers
      _typingService!.typingStream.listen((update) {
        if (update.source == 'peer' &&
            update.conversationId == _currentConversationId) {
          _isRecipientTyping = update.isTyping;
          notifyListeners();

          print(
              '📱 SessionChatProvider: ✅ Typing indicator updated via realtime service: ${update.isTyping}');
        }
      });

      print('📱 SessionChatProvider: ✅ Typing service set up successfully');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Failed to set up typing service: $e');
    }
  }

  /// Handle text input for typing indicators
  void onTextInput(String text) {
    if (_currentConversationId != null &&
        _currentRecipientId != null &&
        _typingService != null) {
      _typingService!.onTextInput(
        _currentConversationId!,
        [_currentRecipientId!],
      );
    }
  }

  /// Stop typing when message sent or focus lost
  void stopTyping() {
    if (_currentConversationId != null && _typingService != null) {
      _typingService!.stopTyping(_currentConversationId!);
    }
  }

  /// Check if typing service is available
  bool get isTypingServiceAvailable => _typingService != null;
}
