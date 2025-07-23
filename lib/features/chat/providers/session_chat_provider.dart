import 'package:flutter/foundation.dart';
import '../../../core/services/session_messenger_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import 'dart:async';

class SessionChatProvider extends ChangeNotifier {
  final SessionMessengerService _messenger = SessionMessengerService.instance;
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
    _setupMessengerCallbacks();
    loadChatsFromMessenger();
  }

  void _setupMessengerCallbacks() {
    _messenger.onMessageReceived = _handleMessageReceived;
    _messenger.onContactOnline = _handleContactOnline;
    _messenger.onContactOffline = _handleContactOffline;
    _messenger.onContactTyping = _handleContactTyping;
    _messenger.onContactTypingStopped = _handleContactTypingStopped;
    _messenger.onMessageStatusUpdated = _handleMessageStatusUpdated;
    _messenger.onError = _handleMessengerError;
  }

  // Load chats from Session Messenger
  Future<void> loadChatsFromMessenger() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final contacts = _messenger.contacts;
      final conversations = _messenger.conversations;

      _chats.clear();
      _chatUsers.clear();

      for (final contact in contacts.values) {
        // Create user object
        final user = User(
          id: contact.sessionId,
          username: contact.name ?? 'Anonymous User',
          profilePicture: contact.profilePicture,
          isOnline: contact.isOnline,
          lastSeen: contact.lastSeen,
          alreadyInvited: true,
          invitationStatus: 'accepted',
        );

        _chatUsers[contact.sessionId] = user;

        // Get messages for this contact
        final messages = conversations[contact.sessionId] ?? [];

        // Create chat object
        final chat = Chat(
          id: contact.sessionId,
          user1Id: _messenger.currentSessionId ?? '',
          user2Id: contact.sessionId,
          lastMessageAt: contact.lastMessageAt ?? contact.lastSeen,
          createdAt: contact.lastSeen,
          updatedAt: contact.lastMessageAt ?? contact.lastSeen,
          otherUser: {
            'id': contact.sessionId,
            'username': contact.name ?? 'Anonymous User',
            'is_online': contact.isOnline,
            'last_seen': contact.lastSeen.toIso8601String(),
          },
          lastMessage:
              messages.isNotEmpty ? _convertToMessageMap(messages.last) : null,
        );

        _chats.add(chat);

        // Calculate unread count
        _unreadCounts[contact.sessionId] = messages
            .where((msg) => !msg.isOutgoing && msg.status != 'read')
            .length;
      }

      // Sort chats by last message time
      _chats.sort((a, b) => (b.lastMessageAt ?? DateTime.now())
          .compareTo(a.lastMessageAt ?? DateTime.now()));

      print('📱 SessionChatProvider: Loaded ${_chats.length} chats');
    } catch (e) {
      _error = 'Failed to load chats: $e';
      print('📱 SessionChatProvider: Error loading chats: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send message
  Future<String> sendMessage({
    required String recipientId,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
    String? replyToId,
    List<String>? mentions,
  }) async {
    try {
      // Send via Session Messenger
      final messageId = await _messenger.sendMessage(
        recipientId: recipientId,
        content: content,
        messageType: messageType,
        metadata: metadata,
        replyToId: replyToId,
        mentions: mentions,
      );

      // Update chat
      _updateChatWithMessage(recipientId, content, true);

      print('📱 SessionChatProvider: Message sent: $messageId');
      return messageId;
    } catch (e) {
      _error = 'Failed to send message: $e';
      notifyListeners();
      print('📱 SessionChatProvider: Error sending message: $e');
      rethrow;
    }
  }

  // Send typing indicator
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      await _messenger.sendTypingIndicator(recipientId, isTyping);
    } catch (e) {
      print('📱 SessionChatProvider: Error sending typing indicator: $e');
    }
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      await _messenger.markMessageAsRead(messageId);
    } catch (e) {
      print('📱 SessionChatProvider: Error marking message as read: $e');
    }
  }

  // Mark all messages as read for a chat
  Future<void> markChatAsRead(String chatId) async {
    try {
      final messages = _messenger.getMessagesForContact(chatId);
      for (final message in messages) {
        if (!message.isOutgoing && message.status != 'read') {
          await _messenger.markMessageAsRead(message.id);
        }
      }
      _unreadCounts[chatId] = 0;
      notifyListeners();
    } catch (e) {
      print('📱 SessionChatProvider: Error marking chat as read: $e');
    }
  }

  // Get messages for a chat
  List<Message> getMessagesForChat(String chatId) {
    final sessionMessages = _messenger.getMessagesForContact(chatId);
    return sessionMessages
        .map((sessionMsg) => Message(
              id: sessionMsg.id,
              chatId: chatId,
              senderId: sessionMsg.senderId,
              content: sessionMsg.content,
              type: _convertMessageType(sessionMsg.messageType),
              status: sessionMsg.status,
              createdAt: sessionMsg.timestamp,
              updatedAt: sessionMsg.timestamp,
            ))
        .toList();
  }

  MessageType _convertMessageType(String messageType) {
    switch (messageType) {
      case 'image':
        return MessageType.image;
      case 'voice':
        return MessageType.voice;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  // Get unread count for a chat
  int getUnreadCount(String chatId) {
    return _unreadCounts[chatId] ?? 0;
  }

  // Check if user is typing
  bool isUserTyping(String userId) {
    return _typingUsers[userId] ?? false;
  }

  // Get effective online status (considers typing state)
  bool getEffectiveOnlineStatus(String userId) {
    final user = _chatUsers[userId];
    if (user == null) return false;

    // If user is typing, they're considered online
    if (_typingUsers[userId] == true) return true;

    return user.isOnline;
  }

  // Refresh online status
  Future<void> refreshOnlineStatus() async {
    try {
      // The Session Messenger automatically updates online status
      // Just trigger a UI refresh
      notifyListeners();
    } catch (e) {
      print('📱 SessionChatProvider: Error refreshing online status: $e');
    }
  }

  // Manual refresh for online status
  Future<void> manualRefreshOnlineStatus() async {
    await refreshOnlineStatus();
  }

  // Event handlers
  void _handleMessageReceived(SessionMessage sessionMessage) {
    try {
      print('📱 SessionChatProvider: Message received: ${sessionMessage.id}');

      // Update chat with new message
      _updateChatWithMessage(
        sessionMessage.senderId,
        sessionMessage.content,
        false,
      );

      // Increment unread count if message is not from current user
      if (!sessionMessage.isOutgoing) {
        _unreadCounts[sessionMessage.senderId] =
            (_unreadCounts[sessionMessage.senderId] ?? 0) + 1;
      }

      // Show notification for incoming messages
      if (!sessionMessage.isOutgoing) {
        final sender = _chatUsers[sessionMessage.senderId];
        _notificationService.showInvitationReceivedNotification(
          senderUsername: sender?.username ?? 'Anonymous User',
          message: sessionMessage.content,
          invitationId: sessionMessage.id,
        );
      }

      notifyListeners();
    } catch (e) {
      print('📱 SessionChatProvider: Error handling message received: $e');
    }
  }

  void _handleContactOnline(String sessionId) {
    final user = _chatUsers[sessionId];
    if (user != null) {
      _chatUsers[sessionId] = user.copyWith(isOnline: true);
      notifyListeners();
    }
  }

  void _handleContactOffline(String sessionId) {
    final user = _chatUsers[sessionId];
    if (user != null) {
      _chatUsers[sessionId] = user.copyWith(
        isOnline: false,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void _handleContactTyping(String sessionId) {
    _typingUsers[sessionId] = true;
    notifyListeners();
  }

  void _handleContactTypingStopped(String sessionId) {
    _typingUsers[sessionId] = false;
    notifyListeners();
  }

  void _handleMessageStatusUpdated(String messageId) {
    // Update message status in conversations
    final conversations = _messenger.conversations;
    for (final entry in conversations.entries) {
      final messageIndex = entry.value.indexWhere((msg) => msg.id == messageId);
      if (messageIndex != -1) {
        final message = entry.value[messageIndex];
        if (message.status == 'read' && !message.isOutgoing) {
          // Decrement unread count when message is read
          _unreadCounts[entry.key] = (_unreadCounts[entry.key] ?? 1) - 1;
          if (_unreadCounts[entry.key]! < 0) _unreadCounts[entry.key] = 0;
        }
        break;
      }
    }
    notifyListeners();
  }

  void _handleMessengerError(String error) {
    _error = error;
    notifyListeners();
    print('📱 SessionChatProvider: Messenger error: $error');
  }

  // Helper methods
  void _updateChatWithMessage(
      String contactId, String content, bool isOutgoing) {
    final chatIndex = _chats.indexWhere((chat) => chat.id == contactId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      _chats[chatIndex] = chat.copyWith(
        lastMessage: {
          'content': content,
          'sender_id': isOutgoing ? _messenger.currentSessionId : contactId,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'sent',
        },
        lastMessageAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Move chat to top
      final updatedChat = _chats.removeAt(chatIndex);
      _chats.insert(0, updatedChat);
    }
  }

  Map<String, dynamic> _convertToMessageMap(SessionMessage sessionMessage) {
    return {
      'content': sessionMessage.content,
      'sender_id': sessionMessage.senderId,
      'timestamp': sessionMessage.timestamp.toIso8601String(),
      'status': sessionMessage.status,
    };
  }

  // Public methods for UI compatibility
  Future<void> loadChats() async {
    await loadChatsFromMessenger();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _chats.clear();
    _chatUsers.clear();
    _typingUsers.clear();
    _unreadCounts.clear();
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
