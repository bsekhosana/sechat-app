import 'package:flutter/foundation.dart';
import '../../../core/services/airnotifier_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import 'dart:async';

class SessionChatProvider extends ChangeNotifier {
  final AirNotifierService _airNotifier = AirNotifierService.instance;
  final NotificationService _notificationService = NotificationService.instance;

  List<Chat> _chats = [];
  final Map<String, User> _chatUsers = {};
  final Map<String, bool> _typingUsers = {};
  final Map<String, int> _unreadCounts = {};
  bool _isLoading = false;
  String? _error;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  User? getChatUser(String userId) {
    return _chatUsers[userId];
  }

  SessionChatProvider() {
    // No real-time callbacks needed - everything goes through silent notifications
  }

  // Send message using AirNotifier silent notifications
  Future<void> sendMessage({
    required String recipientId,
    required String content,
    String messageType = 'text',
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Generate unique message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_$recipientId';

      // Send message via AirNotifier
      final success = await _airNotifier.sendMessageNotification(
        recipientId: recipientId,
        senderName: _airNotifier.currentUserId ?? 'Anonymous User',
        message: content,
        conversationId: recipientId,
      );

      if (success) {
        // Create message object
        final message = Message(
          id: messageId,
          chatId: recipientId,
          senderId: _airNotifier.currentUserId ?? '',
          content: content,
          type: MessageType.text,
          status: 'sent',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Add message to chat
        _addMessageToChat(recipientId, message);

        // Update chat
        _updateOrCreateChat(recipientId, message);

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
      final success = await _airNotifier.sendTypingIndicator(
        recipientId: recipientId,
        senderName: _airNotifier.currentUserId ?? 'Anonymous User',
        isTyping: isTyping,
      );

      if (success) {
        print(
            '📱 SessionChatProvider: Typing indicator sent via silent notification: $recipientId - $isTyping');
      } else {
        print('📱 SessionChatProvider: Failed to send typing indicator');
      }
    } catch (e) {
      print('📱 SessionChatProvider: Error sending typing indicator: $e');
    }
  }

  // Handle message received via silent notification
  void handleMessageReceived(Map<String, dynamic> data) {
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
        chatId: senderId,
        senderId: senderId,
        content: content,
        type: MessageType.text,
        status: 'received',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Add message to chat
      _addMessageToChat(senderId, message);

      // Update chat
      _updateOrCreateChat(senderId, message);

      // Show notification
      _notificationService.showMessageNotification(
        senderName: senderName,
        message: content,
        conversationId: conversationId,
      );

      // Send delivery status
      _airNotifier.sendMessageDeliveryStatus(
        recipientId: senderId,
        messageId: messageId,
        status: 'delivered',
        conversationId: conversationId,
      );

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
      final isTyping = data['isTyping'] as bool;

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
      final isOnline = data['isOnline'] as bool;
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
    // This would typically add the message to a local storage or in-memory list
    // For now, we'll just update the chat's last message
    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      _chats[chatIndex] = chat.copyWith(
        lastMessageAt: message.createdAt,
        lastMessage: _convertToMessageMap(message),
        updatedAt: message.createdAt,
      );
    }
  }

  // Update or create chat
  void _updateOrCreateChat(String userId, Message message) {
    final existingChatIndex = _chats.indexWhere((chat) => chat.id == userId);

    if (existingChatIndex != -1) {
      // Update existing chat
      final chat = _chats[existingChatIndex];
      _chats[existingChatIndex] = chat.copyWith(
        lastMessageAt: message.createdAt,
        lastMessage: _convertToMessageMap(message),
        updatedAt: message.createdAt,
      );
    } else {
      // Create new chat
      final user = _chatUsers[userId] ??
          User(
            id: userId,
            username: 'Anonymous User',
            profilePicture: null,
            isOnline: false,
            lastSeen: DateTime.now(),
            alreadyInvited: true,
            invitationStatus: 'accepted',
          );

      _chatUsers[userId] = user;

      final chat = Chat(
        id: userId,
        user1Id: _airNotifier.currentUserId ?? '',
        user2Id: userId,
        lastMessageAt: message.createdAt,
        createdAt: message.createdAt,
        updatedAt: message.createdAt,
        otherUser: {
          'id': userId,
          'username': user.username,
          'is_online': user.isOnline,
          'last_seen': user.lastSeen?.toIso8601String() ??
              DateTime.now().toIso8601String(),
        },
        lastMessage: _convertToMessageMap(message),
      );

      _chats.add(chat);
    }
  }

  // Convert Message to Map for Chat
  Map<String, dynamic> _convertToMessageMap(Message message) {
    return {
      'id': message.id,
      'sender_id': message.senderId,
      'content': message.content,
      'type': message.type.toString().split('.').last,
      'timestamp': message.createdAt.toIso8601String(),
      'status': message.status,
    };
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId, String senderId) async {
    try {
      // Send read receipt via AirNotifier
      await _airNotifier.sendMessageDeliveryStatus(
        recipientId: senderId,
        messageId: messageId,
        status: 'read',
        conversationId: senderId,
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

  @override
  void dispose() {
    super.dispose();
  }
}
