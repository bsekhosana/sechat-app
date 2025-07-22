import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';
import 'dart:async';

class ChatProvider extends ChangeNotifier {
  List<Chat> _chats = [];
  final Map<String, List<Message>> _messages = {};
  final Map<String, User> _chatUsers = {};
  final Map<String, int> _unreadCounts = {}; // Track unread message counts
  final Map<String, Timer> _messageStatusTimers =
      {}; // Track message status update timers
  final Map<String, String> _activeChatScreens =
      {}; // Track which users are on which chat screens
  bool _isLoading = false;
  String? _error;
  bool _isSyncingPendingMessages =
      false; // Flag to prevent multiple simultaneous syncs

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Message> getMessagesForChat(String chatId) {
    return _messages[chatId] ?? [];
  }

  User? getChatUser(String userId) {
    return _chatUsers[userId];
  }

  int getUnreadCount(String chatId) {
    return _unreadCounts[chatId] ?? 0;
  }

  int get totalUnreadCount {
    return _unreadCounts.values.fold(0, (sum, count) => sum + count);
  }

  bool get hasUnreadMessages => totalUnreadCount > 0;

  ChatProvider() {
    _setupSession();
    _setupNetworkListener();
    _loadChatsFromLocal();
    _startOnlineStatusRefreshTimer();
    _setupLocalStorageListener();
  }

  void _setupSession() {
    SessionService.instance.onMessageReceived = _handleSessionMessage;
    SessionService.instance.onTypingReceived = _handleTypingReceived;
    SessionService.instance.onTypingStopped = _handleTypingStopped;
    SessionService.instance.onConnected = _handleSessionConnected;
    SessionService.instance.onDisconnected = _handleSessionDisconnected;
    SessionService.instance.onError = _handleSessionError;
    SessionService.instance.onContactAdded = _handleContactAdded;
    SessionService.instance.onContactUpdated = _handleContactUpdated;
    SessionService.instance.onContactRemoved = _handleContactRemoved;
    SessionService.instance.onMessageStatusUpdated =
        _handleMessageStatusUpdated;
  }

  void _setupNetworkListener() {
    // Listen to network connectivity changes
    NetworkService.instance.addListener(_handleNetworkChange);
  }

  void _setupLocalStorageListener() {
    // Listen to local storage changes
    LocalStorageService.instance.addListener(_handleLocalStorageChange);
  }

  void _handleLocalStorageChange() {
    // Refresh data when local storage changes
    _loadChatsFromLocal();
    notifyListeners();
  }

  void _updateMessageInList(
      String chatId, String messageId, Message updatedMessage) {
    final messages = _messages[chatId];
    if (messages != null) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
        try {
          notifyListeners();
        } catch (e) {
          print('📱 ChatProvider: Error notifying listeners: $e');
        }
      }
    }
  }

  void addMessageToChat(String chatId, Message message) {
    _messages[chatId] = [...(_messages[chatId] ?? []), message];
    try {
      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error notifying listeners: $e');
    }
  }

  void updateMessageInChat(
      String chatId, String messageId, Message updatedMessage) {
    final messages = _messages[chatId];
    if (messages != null) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
        try {
          notifyListeners();
        } catch (e) {
          print('📱 ChatProvider: Error notifying listeners: $e');
        }
      }
    }
  }

  bool _isHandlingNetworkChange = false;

  void _handleNetworkChange() {
    // Prevent multiple simultaneous network change handlers
    if (_isHandlingNetworkChange) {
      print(
          '📱 ChatProvider: Network change handler already in progress, skipping...');
      return;
    }

    _isHandlingNetworkChange = true;
    final networkService = NetworkService.instance;

    if (networkService.isConnected && !networkService.isReconnecting) {
      // Network is connected, attempt to reconnect session and refresh statuses
      print('📱 ChatProvider: Network reconnected, refreshing services');

      // Let Session handle reconnection automatically
      if (!SessionService.instance.isConnected) {
        print('📱 ChatProvider: Session not connected - attempting to connect');
        SessionService.instance.connect();
      } else {
        // If session is already connected, just clear reconnecting status
        NetworkService.instance.handleSuccessfulReconnection();
      }

      // Refresh online statuses (debounced to prevent excessive calls)
      _debouncedRefreshStatuses();

      // Sync pending messages
      _syncPendingMessages();
    } else if (!networkService.isConnected) {
      print('📱 ChatProvider: Network disconnected');
    }

    // Reset the flag after a delay to allow future network changes
    Timer(const Duration(seconds: 2), () {
      _isHandlingNetworkChange = false;
    });
  }

  Timer? _refreshStatusesTimer;

  void _debouncedRefreshStatuses() {
    _refreshStatusesTimer?.cancel();
    _refreshStatusesTimer = Timer(const Duration(seconds: 5), () {
      _refreshAllStatuses();
    });
  }

  void _refreshAllStatuses() async {
    try {
      // Refresh online statuses for all users
      await refreshOnlineStatus();

      // Restart message status tracking for all tracked messages
      _restartMessageStatusTracking();

      print(
          '📱 ChatProvider: All statuses refreshed after network reconnection');
    } catch (e) {
      print(
          '📱 ChatProvider: Error refreshing statuses after network reconnection: $e');
    }
  }

  void _restartMessageStatusTracking() {
    // Restart tracking for all messages that need status updates
    for (final chatId in _messages.keys) {
      final messages = _messages[chatId];
      if (messages != null) {
        for (final message in messages) {
          final isOutgoing =
              message.senderId == SessionService.instance.currentSessionId;
          if ((message.status == 'sent' || message.status == 'delivered') &&
              isOutgoing) {
            _startMessageStatusTracking(chatId, message.id);
          }
        }
      }
    }
  }

  void _syncPendingMessages() {
    if (_isSyncingPendingMessages) {
      print('📱 ChatProvider: Already syncing pending messages, skipping...');
      return;
    }

    _isSyncingPendingMessages = true;
    print('📱 ChatProvider: Syncing pending messages...');

    // Sync pending messages with Session
    // Implementation depends on how you want to handle pending messages
    _isSyncingPendingMessages = false;
  }

  // Load chats from local storage
  Future<void> _loadChatsFromLocal() async {
    try {
      final chats = await LocalStorageService.instance.getChats();
      _chats = chats;
      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error loading chats from local storage: $e');
    }
  }

  // Load messages for a specific chat
  Future<void> _loadMessagesForChat(String chatId) async {
    try {
      final messages = await LocalStorageService.instance.getMessages(chatId);
      _messages[chatId] = messages;
      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error loading messages for chat $chatId: $e');
    }
  }

  // Send message via Session Protocol
  Future<void> sendMessage(String chatId, String content,
      {String messageType = 'text'}) async {
    try {
      final receiverId =
          chatId; // In Session, chatId is the receiver's session ID

      // Create message ID
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create message object
      final message = Message(
        id: messageId,
        chatId: chatId,
        senderId: SessionService.instance.currentSessionId ?? '',
        content: content,
        type: messageType == 'image'
            ? MessageType.image
            : messageType == 'voice'
                ? MessageType.voice
                : messageType == 'file'
                    ? MessageType.file
                    : MessageType.text,
        status: 'sending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Add message to local chat immediately
      addMessageToChat(chatId, message);

      // Send via Session Protocol
      await SessionService.instance.sendMessage(
        receiverId: receiverId,
        content: content,
        messageType: messageType,
      );

      // Update message status to sent
      final sentMessage = message.copyWith(status: 'sent');
      updateMessageInChat(chatId, messageId, sentMessage);

      // Start tracking message status
      _startMessageStatusTracking(chatId, messageId);

      print('📱 ChatProvider: Message sent via Session: $messageId');
    } catch (e) {
      print('📱 ChatProvider: Error sending message: $e');
      _error = 'Failed to send message: $e';
      notifyListeners();
    }
  }

  // Start tracking message status updates
  void _startMessageStatusTracking(String chatId, String messageId) {
    // Cancel existing timer if any
    _messageStatusTimers[messageId]?.cancel();

    // Create new timer to track message status
    _messageStatusTimers[messageId] = Timer(const Duration(seconds: 30), () {
      // If message is still in 'sent' status after 30 seconds, mark as delivered
      final messages = _messages[chatId];
      if (messages != null) {
        final index = messages.indexWhere((m) => m.id == messageId);
        if (index != -1 && messages[index].status == 'sent') {
          final updatedMessage = messages[index].copyWith(status: 'delivered');
          messages[index] = updatedMessage;
          notifyListeners();
        }
      }

      // Remove timer
      _messageStatusTimers.remove(messageId);
    });
  }

  // Refresh online status for all users
  Future<void> refreshOnlineStatus() async {
    try {
      // In Session Protocol, online status is handled differently
      // This would need to be implemented based on Session's approach
      print('📱 ChatProvider: Refreshing online statuses...');
    } catch (e) {
      print('📱 ChatProvider: Error refreshing online status: $e');
    }
  }

  // Mark message as read
  void markMessageAsRead(String chatId, String messageId) {
    try {
      // Update message status locally
      final messages = _messages[chatId];
      if (messages != null) {
        final index = messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final message = messages[index];
          final updatedMessage = message.copyWith(status: 'read');
          messages[index] = updatedMessage;

          // Save to local storage
          LocalStorageService.instance
              .updateMessageStatus(chatId, messageId, 'read');

          // Update last message status if this is the last message
          if (index == messages.length - 1) {
            updateLastMessageStatus(chatId, messageId, 'read');
          }

          // Send read status via Session
          if (SessionService.instance.isConnected) {
            SessionService.instance.updateMessageStatus(messageId, 'read');
          }

          print(
              '📱 ChatProvider: Marked message $messageId as read in chat $chatId');
          notifyListeners();
        }
      }
    } catch (e) {
      print('📱 ChatProvider: Error marking message as read: $e');
    }
  }

  // Update last message status
  void updateLastMessageStatus(String chatId, String messageId, String status) {
    try {
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        final chat = _chats[chatIndex];
        // Update the lastMessage with status information
        final updatedLastMessage = {
          'status': status,
          'id': messageId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        final updatedChat = chat.copyWith(lastMessage: updatedLastMessage);
        _chats[chatIndex] = updatedChat;
        notifyListeners();
      }
    } catch (e) {
      print('📱 ChatProvider: Error updating last message status: $e');
    }
  }

  // Add contact
  Future<void> addContact(String sessionId,
      {String? name, String? profilePicture}) async {
    try {
      await SessionService.instance.addContact(
        sessionId: sessionId,
        name: name,
        profilePicture: profilePicture,
      );

      print('📱 ChatProvider: Contact added: $sessionId');
    } catch (e) {
      print('📱 ChatProvider: Error adding contact: $e');
      _error = 'Failed to add contact: $e';
      notifyListeners();
    }
  }

  // Remove contact
  Future<void> removeContact(String sessionId) async {
    try {
      await SessionService.instance.removeContact(sessionId);

      // Remove from local data
      _chatUsers.remove(sessionId);
      _messages.remove(sessionId);
      _chats.removeWhere((c) => c.id == sessionId);

      print('📱 ChatProvider: Contact removed: $sessionId');
      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error removing contact: $e');
      _error = 'Failed to remove contact: $e';
      notifyListeners();
    }
  }

  // Send typing indicator
  void sendTypingIndicator(String chatId, bool isTyping) {
    try {
      if (SessionService.instance.isConnected) {
        SessionService.instance.sendTypingIndicator(chatId, isTyping);
      }
    } catch (e) {
      print('📱 ChatProvider: Error sending typing indicator: $e');
    }
  }

  // Start online status refresh timer
  void _startOnlineStatusRefreshTimer() {
    _refreshOnlineStatusTimer = Timer.periodic(
      const Duration(minutes: 2), // Refresh every 2 minutes
      (timer) async {
        // Only refresh if there are users to refresh and we're connected
        if (_chatUsers.isNotEmpty && SessionService.instance.isConnected) {
          await refreshOnlineStatus();
        }
      },
    );
  }

  void _disposeOnlineStatusTimer() {
    _refreshOnlineStatusTimer?.cancel();
  }

  // Reset provider state (for logout)
  void reset() {
    try {
      _chats.clear();
      _messages.clear();
      _chatUsers.clear();
      _unreadCounts.clear();
      _activeChatScreens.clear();
      _isLoading = false;
      _error = null;

      // Cancel all timers
      for (final timer in _messageStatusTimers.values) {
        timer.cancel();
      }
      _messageStatusTimers.clear();

      notifyListeners();
      print('📱 ChatProvider: Reset completed');
    } catch (e) {
      print('📱 ChatProvider: Error during reset: $e');
    }
  }

  // Public methods for UI compatibility

  // Load chats from Session contacts
  Future<void> loadChats() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('📱 ChatProvider: Loading chats from Session contacts...');

      // Get contacts from Session Service
      final contacts = SessionService.instance.contacts;

      // Convert contacts to chats
      _chats = contacts.values.map((contact) {
        // Create a chat for each contact
        final currentUserId =
            SessionService.instance.currentIdentity?.sessionId ?? '';
        final chat = Chat(
          id: contact.sessionId,
          user1Id: currentUserId,
          user2Id: contact.sessionId,
          lastMessageAt: contact.lastSeen,
          createdAt: contact.lastSeen,
          updatedAt: contact.lastSeen,
          otherUser: {
            'id': contact.sessionId,
            'username': contact.name ?? 'Anonymous User',
            'profile_picture': contact.profilePicture,
            'is_online': contact.isOnline,
            'last_seen': contact.lastSeen.toIso8601String(),
          },
        );

        // Create user object for the contact
        _chatUsers[contact.sessionId] = User(
          id: contact.sessionId,
          username: contact.name ?? 'Anonymous User',
          profilePicture: contact.profilePicture,
          isOnline: contact.isOnline,
          lastSeen: contact.lastSeen,
        );

        return chat;
      }).toList();

      // Load messages for each chat
      for (final chat in _chats) {
        await _loadMessagesForChat(chat.id);
      }

      print('📱 ChatProvider: Loaded ${_chats.length} chats');
    } catch (e) {
      print('📱 ChatProvider: Error loading chats: $e');
      _error = 'Failed to load chats: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load messages for a specific chat
  Future<void> loadMessages(String chatId) async {
    await _loadMessagesForChat(chatId);
  }

  // Mark all messages as read in a chat
  Future<void> markAllMessagesAsRead(String chatId) async {
    try {
      final messages = _messages[chatId];
      if (messages != null) {
        for (final message in messages) {
          final isOutgoing = message.senderId ==
              SessionService.instance.currentIdentity?.sessionId;
          if (!isOutgoing && message.status != 'read') {
            final updatedMessage = message.copyWith(status: 'read');
            _updateMessageInList(chatId, message.id, updatedMessage);
          }
        }
        _unreadCounts[chatId] = 0;
        notifyListeners();
      }
    } catch (e) {
      print('📱 ChatProvider: Error marking messages as read: $e');
    }
  }

  // Set user as active in a chat (for typing indicators)
  void setUserActiveInChat(String chatId) {
    _activeChatScreens[chatId] = DateTime.now().toIso8601String();
    notifyListeners();
  }

  // Set user as inactive in a chat
  void setUserInactiveInChat(String chatId) {
    _activeChatScreens.remove(chatId);
    notifyListeners();
  }

  // Refresh user online status
  Future<void> refreshUserOnlineStatus() async {
    try {
      // Get updated contacts from Session Service
      final contacts = SessionService.instance.contacts;

      for (final contact in contacts.values) {
        final user = _chatUsers[contact.sessionId];
        if (user != null) {
          final updatedUser = user.copyWith(
            isOnline: contact.isOnline,
            lastSeen: contact.lastSeen,
          );
          _chatUsers[contact.sessionId] = updatedUser;
        }
      }

      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error refreshing online status: $e');
    }
  }

  // Get the other user ID in a chat
  String getOtherUserId(String chatId) {
    final chat = _chats.firstWhere((c) => c.id == chatId);
    final currentUserId = SessionService.instance.currentIdentity?.sessionId;

    // Use the Chat model's getOtherUserId method
    return chat.getOtherUserId(currentUserId ?? '');
  }

  // Delete a message
  Future<void> deleteMessage(String chatId, String messageId,
      {String deleteType = 'for_me'}) async {
    try {
      final messages = _messages[chatId];
      if (messages != null) {
        if (deleteType == 'for_everyone') {
          // Remove message from the list
          _messages[chatId] = messages.where((m) => m.id != messageId).toList();
        } else {
          // Mark as deleted for me
          final messageIndex = messages.indexWhere((m) => m.id == messageId);
          if (messageIndex != -1) {
            final updatedMessage = messages[messageIndex].copyWith(
              content: 'This message was deleted',
              isDeleted: true,
            );
            messages[messageIndex] = updatedMessage;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      print('📱 ChatProvider: Error deleting message: $e');
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Manual refresh online status
  Future<void> manualRefreshOnlineStatus() async {
    await refreshUserOnlineStatus();
  }

  // Get effective online status for a user
  bool getEffectiveOnlineStatus(String userId) {
    final user = _chatUsers[userId];
    return user?.isOnline ?? false;
  }

  // Check if user is typing
  bool isUserTyping(String userId) {
    // This would need to be implemented with typing indicators
    // For now, return false
    return false;
  }

  // Manual sync pending messages
  Future<void> manualSyncPendingMessages() async {
    _syncPendingMessages();
  }

  // Update chat's last message
  void _updateChatLastMessage(
      String chatId, String content, DateTime timestamp) {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final updatedLastMessage = {
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
      final updatedChat = _chats[chatIndex].copyWith(
        lastMessage: updatedLastMessage,
        lastMessageAt: timestamp,
        updatedAt: timestamp,
      );
      _chats[chatIndex] = updatedChat;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposeOnlineStatusTimer();
    _refreshStatusesTimer?.cancel();

    // Cancel all message status tracking timers
    for (final timer in _messageStatusTimers.values) {
      timer.cancel();
    }
    _messageStatusTimers.clear();

    // Remove network listener
    NetworkService.instance.removeListener(_handleNetworkChange);

    super.dispose();
  }

  // Session Protocol Event Handlers
  void _handleSessionMessage(LocalSessionMessage message) {
    try {
      final chatId =
          _isMessageOutgoing(message) ? message.receiverId : message.senderId;

      // Convert LocalSessionMessage to Message
      final convertedMessage = Message(
        id: message.id,
        chatId: chatId,
        senderId: message.senderId,
        content: message.content,
        type: message.messageType == 'image'
            ? MessageType.image
            : message.messageType == 'voice'
                ? MessageType.voice
                : message.messageType == 'file'
                    ? MessageType.file
                    : MessageType.text,
        status: message.status,
        createdAt: message.timestamp,
        updatedAt: message.timestamp,
      );

      addMessageToChat(chatId, convertedMessage);

      // Update unread count if message is incoming
      if (!_isMessageOutgoing(message)) {
        _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
      }

      print('📱 ChatProvider: Session message received: ${message.id}');
    } catch (e) {
      print('📱 ChatProvider: Error handling session message: $e');
    }
  }

  // Helper method to determine if message is outgoing
  bool _isMessageOutgoing(LocalSessionMessage message) {
    return message.senderId == SessionService.instance.currentSessionId;
  }

  void _handleTypingReceived(String sessionId) {
    // Handle typing indicator from Session
    print('📱 ChatProvider: Typing received from: $sessionId');
  }

  void _handleTypingStopped(String sessionId) {
    // Handle typing stopped from Session
    print('📱 ChatProvider: Typing stopped from: $sessionId');
  }

  void _handleSessionConnected() {
    print('📱 ChatProvider: Session connected');
    // Refresh online statuses when Session connects
    _refreshAllStatuses();
  }

  void _handleSessionDisconnected() {
    print('📱 ChatProvider: Session disconnected');
  }

  void _handleSessionError(String error) {
    print('📱 ChatProvider: Session error: $error');
    _error = error;
    notifyListeners();
  }

  void _handleContactAdded(LocalSessionContact contact) {
    // Convert LocalSessionContact to User and add to chat users
    final user = User(
      id: contact.sessionId,
      username: contact.name ?? 'Unknown',
      profilePicture: contact.profilePicture,
      isOnline: contact.isOnline,
      lastSeen: contact.lastSeen,
    );

    _chatUsers[contact.sessionId] = user;
    print('📱 ChatProvider: Contact added: ${contact.sessionId}');
    notifyListeners();
  }

  void _handleContactUpdated(LocalSessionContact contact) {
    // Update existing contact
    final user = User(
      id: contact.sessionId,
      username: contact.name ?? 'Unknown',
      profilePicture: contact.profilePicture,
      isOnline: contact.isOnline,
      lastSeen: contact.lastSeen,
    );

    _chatUsers[contact.sessionId] = user;
    print('📱 ChatProvider: Contact updated: ${contact.sessionId}');
    notifyListeners();
  }

  void _handleContactRemoved(String sessionId) {
    // Remove contact from chat users
    _chatUsers.remove(sessionId);
    print('📱 ChatProvider: Contact removed: $sessionId');
    notifyListeners();
  }

  void _handleMessageStatusUpdated(String messageId) {
    // Handle message status updates from Session
    print('📱 ChatProvider: Message status updated: $messageId');
    // Find and update message status in conversations
    for (final entry in _messages.entries) {
      final messages = entry.value;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        // Update message status (implementation depends on what status is being updated)
        notifyListeners();
        break;
      }
    }
  }

  Timer? _refreshOnlineStatusTimer;
}
