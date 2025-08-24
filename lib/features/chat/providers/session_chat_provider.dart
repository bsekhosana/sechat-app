import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import '../../../core/services/se_session_service.dart';
import '../services/message_storage_service.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../models/message.dart';
import '../../../realtime/realtime_service_manager.dart';
import '../../../realtime/typing_service.dart';
import '../../../core/services/unified_message_service.dart' as unified_msg;
import '../services/message_status_tracking_service.dart';
import '../models/message_status.dart' as msg_status;
import 'chat_list_provider.dart';
import 'dart:async';
import 'dart:convert';

class SessionChatProvider extends ChangeNotifier {
  final SeSocketService _socketService = SeSocketService.instance;
  final unified_msg.UnifiedMessageService _messageService =
      unified_msg.UnifiedMessageService.instance;
  final MessageStorageService _messageStorage = MessageStorageService.instance;

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

  // No need for stream subscription - using ChangeNotifier pattern

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Chat conversation getters
  List<Message> get messages => _messages;
  bool get isRecipientTyping => _isRecipientTyping;
  DateTime? get recipientLastSeen => _recipientLastSeen;
  bool get isRecipientOnline {
    print(
        '🔍 SessionChatProvider: isRecipientOnline getter called: $_isRecipientOnline (recipient: $_currentRecipientId)');
    return _isRecipientOnline;
  }

  String? get currentRecipientName => _currentRecipientName;
  String? get currentRecipientId => _currentRecipientId;

  /// Get the current conversation ID
  String? get currentConversationId {
    // Conversation ID is simply the recipient's session ID
    return _currentRecipientId;
  }

  /// Ensure conversation ID is set
  void _ensureConversationId() {
    if (_currentConversationId == null && _currentRecipientId != null) {
      // Set conversation ID to recipient ID for simplicity
      _currentConversationId = _currentRecipientId;
      print(
          '📱 SessionChatProvider: ✅ Set conversation ID to recipient ID: $_currentConversationId');
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

  /// Setup listener for UnifiedMessageService updates
  void _setupMessageServiceListener() {
    // Listen to UnifiedMessageService for new messages using ChangeNotifier
    print(
        '📱 SessionChatProvider: 🔍 Setting up listener on UnifiedMessageService instance: ${_messageService.hashCode}');
    _messageService.addListener(_onMessageServiceUpdate);
    print('📱 SessionChatProvider: ✅ Message service listener setup');
  }

  /// Stop message service listener
  void _stopMessageServiceListener() {
    _messageService.removeListener(_onMessageServiceUpdate);
    print('📱 SessionChatProvider: ✅ Message service listener stopped');
  }

  /// Handle UnifiedMessageService updates
  void _onMessageServiceUpdate() {
    print('📱 SessionChatProvider: 🔔 UnifiedMessageService update received');
    print(
        '📱 SessionChatProvider: 🔍 Current conversation ID: $_currentConversationId');
    if (_currentConversationId != null) {
      print('📱 SessionChatProvider: 🔄 Triggering database refresh...');
      _refreshMessagesFromDatabase();
    } else {
      print(
          '📱 SessionChatProvider: ⚠️ No current conversation ID, skipping refresh');
    }
  }

  /// Refresh messages from database for real-time updates
  Future<void> _refreshMessagesFromDatabase() async {
    try {
      if (_currentConversationId == null) return;

      print(
          '📱 SessionChatProvider: 🔄 Refreshing messages from database for conversation: $_currentConversationId');

      final loadedMessages = await _messageStorage
          .getMessages(_currentConversationId!, limit: 100);
      print(
          '📱 SessionChatProvider: 🔄 Loaded ${loadedMessages.length} messages from database');

      // Check if we have new messages
      final currentMessageIds = _messages.map((m) => m.id).toSet();
      final newMessages = loadedMessages
          .where((m) => !currentMessageIds.contains(m.id))
          .toList();

      print(
          '📱 SessionChatProvider: 🔄 Current messages in memory: ${_messages.length}');
      print(
          '📱 SessionChatProvider: 🔄 New messages found: ${newMessages.length}');

      if (newMessages.isNotEmpty) {
        print(
            '📱 SessionChatProvider: 🔄 Found ${newMessages.length} new messages from database');

        // Debug: Log the content of new messages
        for (final message in newMessages) {
          print('📱 SessionChatProvider: 🔄 New message: ${message.id}');
          print(
              '📱 SessionChatProvider: 🔄 Message content keys: ${message.content.keys.toList()}');
          print(
              '📱 SessionChatProvider: 🔄 Message text: ${message.content['text']}');
          if (message.content.containsKey('encryptedText')) {
            print(
                '📱 SessionChatProvider: 🔄 Message was encrypted: ${message.content['encryptedText']?.toString().length ?? 0} chars');
          }
        }

        // Add new messages
        _messages.addAll(newMessages);

        // Sort messages by timestamp
        // CRITICAL: Sort messages by timestamp ASCENDING (oldest first) for natural chat flow
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Update chat list with new messages
        for (final message in newMessages) {
          _updateOrCreateChat(message.conversationId, message);
        }

        // Notify listeners for UI update
        notifyListeners();
        print(
            '📱 SessionChatProvider: ✅ Notified listeners after adding ${newMessages.length} new messages');
      } else {
        print('📱 SessionChatProvider: ℹ️ No new messages found in database');
      }
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error refreshing messages from database: $e');
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
        // CRITICAL: Don't create a new message here - let UnifiedMessageService handle it
        // The message should already be saved to the database by the time this callback is called
        // Just refresh from database to get the decrypted content
        print(
            '📱 SessionChatProvider: 🔄 Message belongs to current conversation, refreshing from database');
        _refreshMessagesFromDatabase();

        // CRITICAL: Notify listeners to trigger auto-scroll to bottom
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

  /// CRITICAL: Method to trigger auto-scroll to bottom when new messages arrive
  void _triggerAutoScrollToBottom() {
    // This will be called by the UI to scroll to bottom after messages update
    print('📱 SessionChatProvider: 🔄 Triggering auto-scroll to bottom');
    notifyListeners();
  }

  /// CRITICAL: Public method for UI to trigger auto-scroll to bottom
  void triggerAutoScrollToBottom() {
    print('📱 SessionChatProvider: 🔄 Public auto-scroll trigger called');
    _triggerAutoScrollToBottom();
  }

  // Add missing methods
  User? getChatUser(String userId) {
    return _chatUsers[userId];
  }

  SessionChatProvider() {
    // ChannelSocketService uses an event-driven system instead of callbacks
    // Event listeners are set up when the service initializes
    print(
        '📱 SessionChatProvider: ✅ Provider created - using channel-based socket system');
  }

  /// Update recipient online status from external source (e.g., ChatListProvider)
  void updateRecipientStatus({
    required String recipientId,
    required bool isOnline,
    DateTime? lastSeen,
  }) {
    print(
        '🔌 SessionChatProvider: 🔍 updateRecipientStatus called: $recipientId -> $isOnline');
    print(
        '🔌 SessionChatProvider: 🔍 Current recipient ID: $_currentRecipientId');

    if (_currentRecipientId == recipientId) {
      final oldStatus = _isRecipientOnline;
      _isRecipientOnline = isOnline;
      _recipientLastSeen = lastSeen;
      notifyListeners();
      print(
          '🔌 SessionChatProvider: ✅ Recipient status updated: $oldStatus -> $isOnline');
      print(
          '🔌 SessionChatProvider: 🔔 notifyListeners() called for presence update');
    } else {
      print(
          '🔌 SessionChatProvider: ⚠️ Recipient ID mismatch: expected $_currentRecipientId, got $recipientId');
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

      // FIXED: Allow bidirectional typing indicators for better user experience
      // Only prevent users from seeing their own typing indicator if they're not in a chat
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null && senderId == currentUserId) {
        // If we're in an active chat, we might want to show our own typing state
        // This allows for better UX in group chats or when switching between users
        if (_currentRecipientId == null) {
          print(
              '📱 SessionChatProvider: ⚠️ Ignoring own typing indicator (no active chat)');
          return;
        }
        // If we have an active chat, process the typing indicator for UI consistency
        print(
            '📱 SessionChatProvider: ℹ️ Processing own typing indicator in active chat');
      }

      // Update typing state for the sender
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
          '🔌 SessionChatProvider: 🔔 Online status callback received: $senderId -> $isOnline (lastSeen: $lastSeen)');

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

      // Use the current conversation ID to ensure consistency
      final conversationId = _currentConversationId ?? recipientId;

      print(
          '📱 SessionChatProvider: 🔍 Sending message with conversation ID: $conversationId');
      print(
          '📱 SessionChatProvider: 🔍 Current conversation ID: $_currentConversationId');
      print('📱 SessionChatProvider: 🔍 Recipient ID: $recipientId');

      final message = Message(
        id: messageId,
        conversationId: conversationId,
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

      // Add message to chat using conversation ID
      _addMessageToChat(conversationId, message);

      // Update chat using conversation ID
      _updateOrCreateChat(conversationId, message);

      // Also update the chat list for the sender (this ensures the sender's chat list updates)
      // This mimics the old implementation's behavior
      try {
        // Update the chat list directly to show the latest message
        // This ensures the sender's chat list updates immediately
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          // Find and update the chat in the chat list
          final chatIndex = _chats.indexWhere((chat) =>
              chat.id == conversationId ||
              chat.otherUser?['id'] == recipientId ||
              chat.user2Id == recipientId);

          if (chatIndex != -1) {
            // Update existing chat
            final existingChat = _chats[chatIndex];
            _chats[chatIndex] = existingChat.copyWith(
              id: conversationId, // Ensure consistent ID
              lastMessage: {'text': content, 'id': messageId},
              lastMessageAt: DateTime.now(),
            );
            print(
                '📱 SessionChatProvider: ✅ Updated existing chat in chat list');
          } else {
            // Create new chat entry if it doesn't exist
            final newChat = Chat(
              id: conversationId,
              user1Id: currentUserId,
              user2Id: recipientId,
              user1DisplayName: currentUserId,
              user2DisplayName: recipientId,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              otherUser: {
                'id': recipientId,
                'name': recipientId, // Will be updated when user data is loaded
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

      // Send message via unified message service (API-compliant)
      final sendResult = await _messageService.sendMessage(
        messageId: messageId,
        recipientId: recipientId,
        body: content,
        conversationId:
            conversationId, // Use recipient's session ID as conversation ID
      );

      if (sendResult.success) {
        print(
            '📱 SessionChatProvider: ✅ Message sent successfully with conversation ID: $conversationId');
      } else {
        print(
            '📱 SessionChatProvider: ❌ Message send failed: ${sendResult.error}');
        throw Exception('Message send failed: ${sendResult.error}');
      }

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to send message: $e';
      _isLoading = false;
      notifyListeners();
      print('📱 SessionChatProvider: ❌ Failed to send message: $e');
      rethrow;
    }
  }

  // Send typing indicator using socket service
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      // Ensure conversation ID is available
      _ensureConversationId();

      // SIMPLIFIED: Just use the parameter directly - no complex logic needed!
      final actualRecipientId = recipientId;

      // Validate recipient ID
      if (actualRecipientId.isEmpty || actualRecipientId == 'unknown') {
        print(
            '📱 SessionChatProvider: ❌ Invalid recipient ID for typing indicator: $actualRecipientId');
        return;
      }

      print(
          '📱 SessionChatProvider: 🔍 Sending typing indicator to: $actualRecipientId (isTyping: $isTyping)');

      // Check socket connection first
      if (!_socketService.isConnected) {
        print(
            '📱 SessionChatProvider: ⚠️ Socket not connected, cannot send typing indicator');

        // Try to test the connection
        final testResult = await _socketService.testSocketConnection();
        if (testResult) {
          print(
              '📱 SessionChatProvider: ✅ Socket connection test passed, retrying...');
        } else {
          print('📱 SessionChatProvider: ❌ Socket connection test failed');
          return;
        }
      }

      // SIMPLIFIED: Just use the conversation ID directly
      final conversationId = _currentConversationId ?? 'unknown';

      print(
          '📱 SessionChatProvider: 🔍 Using conversation ID: $conversationId for typing indicator');

      // Send typing indicator via socket service
      _socketService.sendTyping(
        actualRecipientId, // Use the parameter directly
        conversationId, // Use the conversation ID
        isTyping,
      );

      print(
          '📱 SessionChatProvider: ✅ Typing indicator sent via socket: $actualRecipientId - $isTyping');
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
      // CRITICAL: Sort messages by timestamp DESCENDING (newest first) for bottom-up display
      _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      print(
          '📱 SessionChatProvider: ✅ Message added to messages list: ${message.id}');

      // CRITICAL: Trigger auto-scroll to bottom for new messages
      _triggerAutoScrollToBottom();
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
      // Store encrypted content only - no decrypted text
      'content': jsonEncode(message.content),
      'type': message.type.toString().split('.').last,
      'timestamp': message.timestamp.toIso8601String(),
      'status': message.status.name,
    };
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId, String senderId) async {
    try {
      print(
          '📱 SessionChatProvider: 📊 Message marked as read: $messageId from $senderId');

      // Update local message status in storage
      final messageStorageService = MessageStorageService.instance;
      await messageStorageService.updateMessageStatus(
          messageId, MessageStatus.read);

      // Update local message status in memory
      final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      if (messageIndex != -1) {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          status: MessageStatus.read,
          readAt: DateTime.now(),
        );
      }

      // Send read status update back to the sender via socket
      final socketService = SeSocketService.instance;
      await socketService.sendMessageStatusUpdate(
        recipientId: senderId,
        messageId: messageId,
        status: 'read',
      );

      print(
          '📱 SessionChatProvider: ✅ Message marked as read and status sent: $messageId');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error marking message as read: $e');
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

      // SIMPLIFIED: Just use the recipientId parameter directly - no parsing needed!
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

      // Setup message service listener for real-time updates
      _setupMessageServiceListener();

      // Setup socket callbacks for message status updates
      _setupSocketCallbacks();

      // Note: ChatListProvider registration will be handled by the ChatScreen
      // when it has access to the BuildContext
      print(
          '📱 SessionChatProvider: ℹ️ ChatListProvider registration will be handled by ChatScreen');

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

  @override
  void dispose() {
    // Clean up listener
    _stopMessageServiceListener();
    super.dispose();
  }

  /// Load messages for a specific conversation
  Future<void> _loadMessagesForConversation(String conversationId) async {
    try {
      print(
          '📱 SessionChatProvider: 🔄 Loading messages for conversation: $conversationId');

      // Load messages from MessageStorageService
      final messageStorageService = MessageStorageService.instance;
      final loadedMessages =
          await messageStorageService.getMessages(conversationId, limit: 100);

      print(
          '📱 SessionChatProvider: 🔄 Loaded ${loadedMessages.length} messages from database');

      // Debug: Log the content of loaded messages
      for (final message in loadedMessages) {
        print('📱 SessionChatProvider: 🔄 Loaded message: ${message.id}');
        print(
            '📱 SessionChatProvider: 🔄 Message content keys: ${message.content.keys.toList()}');
        print(
            '📱 SessionChatProvider: 🔄 Message text: ${message.content['text']}');
        print(
            '📱 SessionChatProvider: 🔄 Message encryptedText: ${message.content['encryptedText']}');
      }

      // Merge with existing messages to avoid duplicates
      final existingMessageIds = _messages.map((m) => m.id).toSet();
      final newMessages = loadedMessages
          .where((m) => !existingMessageIds.contains(m.id))
          .toList();

      print(
          '📱 SessionChatProvider: 🔄 New messages to add: ${newMessages.length}');

      // Add new messages to existing list
      _messages.addAll(newMessages);

      // CRITICAL: Sort messages by timestamp ASCENDING (oldest first) for natural chat flow
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

  /// Manually trigger message refresh (for testing)
  Future<void> manualRefreshMessages() async {
    print('📱 SessionChatProvider: 🔄 Manual refresh triggered');
    await _refreshMessagesFromDatabase();
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
        print(
            '📱 SessionChatProvider: 🔄 Marking all unread messages as read...');

        // Efficiently mark all unread messages sent TO me in the conversation as read
        final messageStorageService = MessageStorageService.instance;
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null) {
          await messageStorageService.markConversationMessagesAsRead(
            _currentConversationId ?? _currentRecipientId!,
            currentUserId,
          );
        }

        // Also mark messages currently in memory as read (for immediate UI update)
        if (currentUserId != null) {
          for (final message in _messages) {
            if (message.recipientId ==
                    currentUserId && // Only messages sent TO me
                message.status != MessageStatus.read) {
              await markMessageAsRead(message.id, message.senderId);
            }
          }
        }

        // CRITICAL: Send delivery receipts ONLY for messages from ONLINE recipients
        // This prevents false "delivered" status for offline users
        final socketService = SeSocketService.instance;
        for (final message in _messages) {
          if (message.recipientId ==
                  currentUserId && // Only messages sent TO me
              message.status != MessageStatus.delivered &&
              message.status != MessageStatus.read) {
            // Check if the sender is actually online before sending delivery receipt
            final senderId = message.senderId;
            final isSenderOnline = await _checkIfUserIsOnline(senderId);

            if (isSenderOnline) {
              // Only send delivery receipt if sender is online and can receive it
              await socketService.sendDeliveryReceipt(
                recipientId: message.senderId,
                messageId: message.id,
              );

              print(
                  '📬 SessionChatProvider: ✅ Delivery receipt sent for message: ${message.id} (sender online)');
            } else {
              print(
                  '📬 SessionChatProvider: ⚠️ Skipping delivery receipt for message: ${message.id} (sender offline: $senderId)');
            }
          }
        }

        // Also mark messages currently in memory as read
        for (final message in _messages) {
          if (message.senderId != _currentRecipientId &&
              message.status != MessageStatus.read) {
            await markMessageAsRead(message.id, message.senderId);
          }
        }

        // Update unread count
        _unreadCounts[_currentConversationId ?? ''] = 0;

        print('📱 SessionChatProvider: ✅ All unread messages marked as read');
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

      // CRITICAL: Only send typing indicator to recipient, don't update local state
      final currentUserId = SeSessionService().currentSessionId;
      if (_currentRecipientId != null && _currentRecipientId != currentUserId) {
        // Send typing indicator to other user via socket
        await sendTypingIndicator(_currentRecipientId!, isTyping);
        print(
            '📱 SessionChatProvider: ✅ Typing indicator sent to recipient: $_currentRecipientId');
      } else {
        print(
            '📱 SessionChatProvider: ⚠️ No valid recipient for typing indicator');
      }

      // DON'T update _isRecipientTyping here - that should only be updated
      // when we receive typing indicators from the recipient via socket
      // _isRecipientTyping = isTyping; // REMOVED - This was wrong!

      // Only notify listeners for UI updates (like input field state)
      notifyListeners();
      print('📱 SessionChatProvider: Typing indicator sent: $isTyping');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error updating typing indicator: $e');
    }
  }

  /// Check if a user is currently online
  /// For now, we'll be conservative and assume offline to prevent false delivery receipts
  Future<bool> _checkIfUserIsOnline(String userId) async {
    try {
      // CRITICAL: For now, assume all users are offline to prevent false delivery receipts
      // This ensures messages don't get marked as "delivered" when recipients are offline
      // TODO: Implement proper presence checking when presence service is available

      print(
          '📱 SessionChatProvider: 🔍 User $userId online status: assumed offline (conservative approach)');
      return false; // Assume offline for now
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error checking online status for user $userId: $e');
      return false; // Assume offline on error
    }
  }

  /// Validate message status update to prevent false delivery status
  /// This ensures messages are only marked as "delivered" when appropriate
  bool _validateMessageStatusUpdate(String messageId, MessageStatus newStatus) {
    try {
      // Find the message
      final message = _messages.firstWhere((msg) => msg.id == messageId);

      // CRITICAL: Prevent false "delivered" status for offline recipients
      if (newStatus == MessageStatus.delivered) {
        // Check if the recipient (current user) is actually online
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && message.recipientId == currentUserId) {
          // This is a message sent TO us, we can mark it as delivered
          print(
              '📱 SessionChatProvider: ✅ Valid delivery status update for message: $messageId');
          return true;
        } else {
          // This is a message sent BY us, we should NOT mark it as delivered
          // unless we receive a proper receipt from the recipient
          print(
              '📱 SessionChatProvider: ⚠️ Invalid delivery status update for message: $messageId (sent by us)');
          return false;
        }
      }

      // Other status updates are valid
      return true;
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error validating message status update: $e');
      return false;
    }
  }

  /// Send text message
  Future<void> sendTextMessage(String content) async {
    print('📱 SessionChatProvider: 🔧 sendTextMessage called with: "$content"');
    print(
        '📱 SessionChatProvider: 🔍 _currentRecipientId: $_currentRecipientId');
    print(
        '📱 SessionChatProvider: 🔍 _currentConversationId: $_currentConversationId');

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Ensure conversation ID is available
      _ensureConversationId();

      // Validate content
      if (content.trim().isEmpty) {
        print('📱 SessionChatProvider: ❌ Message content is empty');
        throw Exception('Message content cannot be empty');
      }

      final recipientId = _currentRecipientId!;
      print('📱 SessionChatProvider: 🔍 Using recipientId: $recipientId');

      print(
          '📱 SessionChatProvider: 🚀 Sending text message to $recipientId in conversation $_currentConversationId');

      // Generate message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_${SeSessionService().currentSessionId}';

      // Create message object
      final message = Message(
        id: messageId,
        conversationId: recipientId,
        senderId: SeSessionService().currentSessionId ?? '',
        recipientId: recipientId,
        type: MessageType.text,
        content: {'text': content},
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
      );

      // Add message to local list first for immediate UI feedback
      _messages.add(message);
      notifyListeners();

      // Update chat list
      try {
        _updateChatListWithMessage(recipientId, content, messageId);
      } catch (e) {
        print('📱 SessionChatProvider: ⚠️ Error updating chat list: $e');
      }

      // Check socket connection before sending
      if (!_socketService.isConnected) {
        print(
            '📱 SessionChatProvider: ⚠️ Socket not connected, attempting to reconnect...');

        // Try to test the connection first
        final testResult = await _socketService.testSocketConnection();
        if (testResult) {
          print(
              '📱 SessionChatProvider: ✅ Socket connection test passed, retrying...');
        } else {
          print('📱 SessionChatProvider: ❌ Socket connection test failed');
          throw Exception(
              'Socket not connected. Please check your internet connection and try again.');
        }
      }

      print(
          '📱 SessionChatProvider: 🔧 Calling _messageService.sendMessage...');
      print('📱 SessionChatProvider: 🔍 messageId: $messageId');
      print('📱 SessionChatProvider: 🔍 recipientId: $recipientId');
      print('📱 SessionChatProvider: 🔍 body: $content');
      print(
          '📱 SessionChatProvider: 🔍 conversationId: $_currentConversationId');

      // Send message via unified message service (API-compliant)
      final sendResult = await _messageService.sendMessage(
        messageId: messageId,
        recipientId: recipientId,
        body: content,
        conversationId:
            _currentConversationId!, // Use the consistent conversation ID
      );

      print('📱 SessionChatProvider: 🔍 sendResult: $sendResult');

      if (sendResult.success) {
        print(
            '📱 SessionChatProvider: ✅ Message sent successfully with conversation ID: $_currentConversationId');

        // Update message status to 'sent' after successful send
        final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
        if (messageIndex != -1) {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.sent,
          );

          // Update message status in database
          final messageStorageService = MessageStorageService.instance;
          await messageStorageService.updateMessageStatus(
              messageId, MessageStatus.sent);

          print(
              '📱 SessionChatProvider: ✅ Message status updated to sent: $messageId');
          notifyListeners(); // Update UI immediately
        }

        // Note: Chat list update will be handled by the ChatScreen
        // when it has access to the BuildContext
        print(
            '📱 SessionChatProvider: ℹ️ Chat list update will be handled by ChatScreen');
      } else {
        print(
            '📱 SessionChatProvider: ❌ Message send failed: ${sendResult.error}');
        throw Exception('Message send failed: ${sendResult.error}');
      }

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Exception caught in sendTextMessage: $e');
      print('📱 SessionChatProvider: 🔍 Exception type: ${e.runtimeType}');
      print('📱 SessionChatProvider: 🔍 Stack trace: ${StackTrace.current}');

      _error = 'Failed to send message: $e';
      _isLoading = false;
      notifyListeners();
      print('📱 SessionChatProvider: ❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Update chat list with new message
  void _updateChatListWithMessage(
      String recipientId, String content, String messageId) {
    try {
      // Find existing chat
      final existingChatIndex =
          _chats.indexWhere((chat) => chat.id == recipientId);

      if (existingChatIndex != -1) {
        // Update existing chat
        final existingChat = _chats[existingChatIndex];
        _chats[existingChatIndex] = existingChat.copyWith(
          lastMessage: {'text': content, 'id': messageId},
          lastMessageAt: DateTime.now(),
        );
        print(
            '📱 SessionChatProvider: ✅ Updated existing chat with new message');
      } else {
        // Create new chat
        final currentUserId = SeSessionService().currentSessionId ?? 'unknown';
        final newChat = Chat(
          id: recipientId,
          user1Id: currentUserId,
          user2Id: recipientId,
          user1DisplayName: currentUserId,
          user2DisplayName: recipientId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          otherUser: {
            'id': recipientId,
            'name': recipientId, // Will be updated when user data is loaded
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
    } catch (e) {
      print('📱 SessionChatProvider: ⚠️ Error updating chat list: $e');
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

      print('📱 SessionChatProvider: 🔧 Setting up realtime typing service...');

      // Initialize typing service
      _typingService = RealtimeServiceManager().typing;
      print(
          '📱 SessionChatProvider: 🔧 Typing service instance: ${_typingService != null}');

      // Listen for typing updates from peers
      _typingService!.typingStream.listen((update) {
        print(
            '📱 SessionChatProvider: 🔔 Typing update from realtime service: ${update.source} -> ${update.isTyping} in conversation ${update.conversationId}');
        print(
            '📱 SessionChatProvider: 🔍 Current conversation ID: $_currentConversationId');

        // Handle typing updates from peers (server/other users)
        if (update.source == 'peer' || update.source == 'server') {
          if (update.conversationId == _currentConversationId) {
            _isRecipientTyping = update.isTyping;
            print(
                '📱 SessionChatProvider: ✅ Updating recipient typing state: $_isRecipientTyping');
            notifyListeners();
            print(
                '📱 SessionChatProvider: ✅ Typing indicator updated via realtime service: ${update.isTyping}');
          } else {
            print(
                '📱 SessionChatProvider: ℹ️ Typing update for different conversation: ${update.conversationId} vs $_currentConversationId');
          }
        }
        // Handle local typing updates (for UI consistency)
        else if (update.source == 'local') {
          if (update.conversationId == _currentConversationId) {
            // Local typing updates are handled by the socket callback
            // This is just for logging and debugging
            print(
                '📱 SessionChatProvider: ℹ️ Local typing update received: ${update.isTyping}');
          }
        }
      });

      print('📱 SessionChatProvider: ✅ Typing service set up successfully');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Failed to set up typing service: $e');
    }
  }

  /// Setup socket callbacks for message status updates
  void _setupSocketCallbacks() {
    try {
      print('📱 SessionChatProvider: 🔧 Setting up socket callbacks...');

      // Set up message acknowledgment callback
      _socketService.setOnMessageAcked((messageId) {
        print(
            '📱 SessionChatProvider: ✅ Message acknowledged by server: $messageId');

        // Update message status to 'sent' when acknowledged by server
        final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
        if (messageIndex != -1) {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.sent,
          );

          // Update message status in database
          _updateMessageStatusInDatabase(messageId, MessageStatus.sent);

          print(
              '📱 SessionChatProvider: ✅ Message status updated to sent after acknowledgment: $messageId');
          notifyListeners(); // Update UI immediately
        }
      });

      print('📱 SessionChatProvider: ✅ Socket callbacks set up successfully');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Failed to set up socket callbacks: $e');
    }
  }

  /// Update message status in database
  Future<void> _updateMessageStatusInDatabase(
      String messageId, MessageStatus status) async {
    try {
      final messageStorageService = MessageStorageService.instance;
      await messageStorageService.updateMessageStatus(messageId, status);
      print(
          '📱 SessionChatProvider: ✅ Message status updated in database: $messageId -> $status');
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Failed to update message status in database: $e');
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

  /// Test method to manually trigger typing indicator for debugging
  void testTypingIndicator(bool isTyping) {
    try {
      print('📱 SessionChatProvider: 🧪 Testing typing indicator: $isTyping');
      print(
          '📱 SessionChatProvider: 🔍 Current recipient ID: $_currentRecipientId');
      print(
          '📱 SessionChatProvider: 🔍 Current conversation ID: $_currentConversationId');
      print(
          '📱 SessionChatProvider: 🔍 Typing service available: ${_typingService != null}');

      if (_typingService != null &&
          _currentConversationId != null &&
          _currentRecipientId != null) {
        if (isTyping) {
          _typingService!
              .startTyping(_currentConversationId!, [_currentRecipientId!]);
        } else {
          _typingService!.stopTyping(_currentConversationId!);
        }
        print(
            '📱 SessionChatProvider: 🧪 Test typing indicator sent: $isTyping');
      } else {
        print(
            '📱 SessionChatProvider: 🧪 Cannot test typing indicator - missing dependencies');
      }
    } catch (e) {
      print('📱 SessionChatProvider: 🧪 Error testing typing indicator: $e');
    }
  }

  /// Send presence update to specific users
  void sendPresenceUpdate(bool isOnline, List<String> toUserIds) {
    try {
      _socketService.sendPresence(isOnline, toUserIds);
      print(
          '📱 SessionChatProvider: ✅ Presence update sent: ${isOnline ? 'online' : 'offline'} to ${toUserIds.length} users');
    } catch (e) {
      print('📱 SessionChatProvider: ❌ Error sending presence update: $e');
    }
  }

  /// Send presence update to current recipient
  void sendPresenceToCurrentRecipient(bool isOnline) {
    if (_currentRecipientId != null) {
      sendPresenceUpdate(isOnline, [_currentRecipientId!]);
    }
  }

  /// Register this provider with ChatListProvider for real-time updates
  void registerWithChatListProvider(ChatListProvider chatListProvider) {
    chatListProvider.setActiveSessionChatProvider(this);
    print(
        '📱 SessionChatProvider: ✅ Registered with ChatListProvider for real-time updates');
  }

  /// Unregister this provider from ChatListProvider
  void unregisterFromChatListProvider(ChatListProvider chatListProvider) {
    chatListProvider.setActiveSessionChatProvider(null);
    print('📱 SessionChatProvider: ❌ Unregistered from ChatListProvider');
  }

  /// Get current conversation ID for external use
  String? get conversationId => _currentConversationId;

  /// Handle real-time message status updates (called from ChatListProvider)
  Future<void> handleMessageStatusUpdate(MessageStatusUpdate update) async {
    try {
      // Since MessageStatusUpdate doesn't have conversationId, we'll process all updates
      // and let the message lookup filter by conversation
      print(
          '📱 SessionChatProvider: 🔄 Processing message status update: ${update.messageId} -> ${update.status}');

      // Find the message in memory and update its status
      final messageIndex =
          _messages.indexWhere((msg) => msg.id == update.messageId);
      if (messageIndex != -1) {
        // Update the message status in memory
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          status: _convertDeliveryStatusToMessageStatus(update.status),
        );

        // Update the message status in the database
        final messageStorageService = MessageStorageService.instance;
        await messageStorageService.updateMessageStatus(
          update.messageId,
          _convertDeliveryStatusToMessageStatus(update.status),
        );

        print(
            '📱 SessionChatProvider: ✅ Message status updated in memory and database: ${update.messageId} -> ${update.status}');

        // Notify listeners to update the UI immediately
        notifyListeners();
      } else {
        print(
            '📱 SessionChatProvider: ⚠️ Message not found in memory: ${update.messageId}');
      }
    } catch (e) {
      print(
          '📱 SessionChatProvider: ❌ Error handling message status update: $e');
    }
  }

  /// Convert MessageDeliveryStatus to MessageStatus
  MessageStatus _convertDeliveryStatusToMessageStatus(
      msg_status.MessageDeliveryStatus deliveryStatus) {
    switch (deliveryStatus) {
      case msg_status.MessageDeliveryStatus.pending:
        return MessageStatus.pending;
      case msg_status.MessageDeliveryStatus.sent:
        return MessageStatus.sent;
      case msg_status.MessageDeliveryStatus.delivered:
        return MessageStatus.delivered;
      case msg_status.MessageDeliveryStatus.read:
        return MessageStatus.read;
      case msg_status.MessageDeliveryStatus.failed:
        return MessageStatus.failed;
      case msg_status.MessageDeliveryStatus.retrying:
        return MessageStatus.sending;
    }
  }
}
