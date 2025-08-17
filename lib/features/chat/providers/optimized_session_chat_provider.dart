import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/airnotifier_service.dart';
import 'package:sechat_app/features/chat/services/optimized_chat_database_service.dart';
import 'package:sechat_app/features/chat/services/enhanced_chat_encryption_service.dart';
import 'package:sechat_app/features/chat/models/optimized_conversation.dart';
import 'package:sechat_app/features/chat/models/optimized_message.dart';

/// Optimized Session Chat Provider
/// Manages individual chat session with real-time message updates
class OptimizedSessionChatProvider extends ChangeNotifier {
  // Services
  final _databaseService = OptimizedChatDatabaseService();
  final _sessionService = SeSessionService();
  final _airNotifier = AirNotifierService.instance;
  final _encryptionService = EnhancedChatEncryptionService();

  // Current conversation state
  String? _currentConversationId;
  String? _currentRecipientId;
  String? _currentRecipientName;
  OptimizedConversation? _currentConversation;

  // Messages state
  List<OptimizedMessage> _messages = [];
  bool _isLoadingMessages = false;
  String? _messagesError;

  // Typing and online status
  bool _isRecipientTyping = false;
  bool _isRecipientOnline = false;
  DateTime? _recipientLastSeen;

  // UI state
  bool _isLoading = false;
  String? _error;

  // Getters
  String? get currentConversationId => _currentConversationId;
  String? get currentRecipientId => _currentRecipientId;
  String? get currentRecipientName => _currentRecipientName;
  OptimizedConversation? get currentConversation => _currentConversation;
  List<OptimizedMessage> get messages => _messages;
  bool get isLoadingMessages => _isLoadingMessages;
  String? get messagesError => _messagesError;
  bool get isRecipientTyping => _isRecipientTyping;
  bool get isRecipientOnline => _isRecipientOnline;
  DateTime? get recipientLastSeen => _recipientLastSeen;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Initialize chat session for a specific conversation
  Future<void> initialize(String conversationId) async {
    try {
      _setLoading(true);
      _clearError();

      _currentConversationId = conversationId;

      // Load conversation details
      await _loadConversationDetails(conversationId);

      // Load messages
      await _loadMessagesForConversation(conversationId);

      print(
          '📱 OptimizedSessionChatProvider: ✅ Initialized for conversation: $conversationId');
    } catch (e) {
      _setError('Failed to initialize chat session: $e');
      print('📱 OptimizedSessionChatProvider: ❌ Initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load conversation details
  Future<void> _loadConversationDetails(String conversationId) async {
    try {
      final conversationData =
          await _databaseService.getConversation(conversationId);
      if (conversationData == null) {
        throw Exception('Conversation not found: $conversationId');
      }

      _currentConversation = OptimizedConversation.fromMap(conversationData);

      // Determine recipient ID and name
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId != null) {
        _currentRecipientId =
            _currentConversation!.getOtherParticipantId(currentUserId);
        _currentRecipientName =
            _currentConversation!.getDisplayNameForUser(currentUserId);

        // Update typing and online status
        _isRecipientTyping = _currentConversation!.isTyping;
        _isRecipientOnline = _currentConversation!.isOnline;
        _recipientLastSeen = _currentConversation!.lastSeen;
      }

      print('📱 OptimizedSessionChatProvider: ✅ Loaded conversation details');
    } catch (e) {
      throw Exception('Failed to load conversation details: $e');
    }
  }

  /// Load messages for conversation
  Future<void> _loadMessagesForConversation(String conversationId) async {
    try {
      _setMessagesLoading(true);
      _clearMessagesError();

      final messagesData =
          await _databaseService.getConversationMessages(conversationId);
      _messages =
          messagesData.map((data) => OptimizedMessage.fromMap(data)).toList();

      print(
          '📱 OptimizedSessionChatProvider: ✅ Loaded ${_messages.length} messages');
    } catch (e) {
      _setMessagesError('Failed to load messages: $e');
      print('📱 OptimizedSessionChatProvider: ❌ Failed to load messages: $e');
    } finally {
      _setMessagesLoading(false);
    }
  }

  /// Send text message
  Future<void> sendTextMessage(String content) async {
    try {
      if (_currentRecipientId == null || _currentConversationId == null) {
        throw Exception('No active conversation');
      }

      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        throw Exception('No current user session');
      }

      // Generate message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';

      // Create message object
      final message = OptimizedMessage(
        id: messageId,
        conversationId: _currentConversationId!,
        senderId: currentUserId,
        recipientId: _currentRecipientId!,
        content: content,
        messageType: MessageType.text,
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
        metadata: {
          'messageDirection': 'outgoing',
          'sentAt': DateTime.now().toIso8601String(),
          'recipientId': _currentRecipientId,
        },
      );

      // Save message locally first
      await _databaseService.saveMessage(message.toMap());

      // Add to local messages list
      _addMessageToLocalList(message);

      // Update conversation with last message
      await _updateConversationLastMessage(content, messageId);

      // Encrypt the message using enhanced encryption service
      print(
          '🔐 OptimizedSessionChatProvider: 🔒 Encrypting message before sending');
      final encryptedMessage = await _encryptionService.encryptMessage(message);

      // Send encrypted message via AirNotifier
      final success = await _airNotifier.sendEncryptedMessageNotification(
        recipientId: _currentRecipientId!,
        senderName: currentUserId,
        encryptedData: encryptedMessage['encrypted_data'],
        checksum: encryptedMessage['checksum'],
        conversationId: _currentConversationId!,
      );

      if (success) {
        // Update message status to sent
        await _updateMessageStatus(messageId, MessageStatus.sent);
        print('📱 OptimizedSessionChatProvider: ✅ Message sent successfully');
      } else {
        // Update message status to failed
        await _updateMessageStatus(messageId, MessageStatus.failed);
        throw Exception('Failed to send message via AirNotifier');
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to send message: $e');
      print('📱 OptimizedSessionChatProvider: ❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Add message to local messages list
  void _addMessageToLocalList(OptimizedMessage message) {
    _messages.add(message);
    _sortMessages();
    notifyListeners();
  }

  /// Sort messages by timestamp
  void _sortMessages() {
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Update conversation with last message
  Future<void> _updateConversationLastMessage(
      String content, String messageId) async {
    try {
      await _databaseService.updateConversation(_currentConversationId!, {
        'last_message_at': DateTime.now().toIso8601String(),
        'last_message_preview': content,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ⚠️ Failed to update conversation last message: $e');
    }
  }

  /// Update message status
  Future<void> _updateMessageStatus(
      String messageId, MessageStatus status) async {
    try {
      final messageIndex = _messages.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        final oldMessage = _messages[messageIndex];
        final updatedMessage = oldMessage.copyWith(status: status);

        if (status == MessageStatus.delivered) {
          updatedMessage.copyWith(deliveredAt: DateTime.now());
        } else if (status == MessageStatus.read) {
          updatedMessage.copyWith(readAt: DateTime.now());
        }

        _messages[messageIndex] = updatedMessage;

        // Update database
        await _databaseService.updateMessageStatus(messageId, status.name);

        notifyListeners();
        print(
            '📱 OptimizedSessionChatProvider: ✅ Message status updated: $messageId -> $status');
      }
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error updating message status: $e');
    }
  }

  /// Handle incoming message (called by notification service)
  Future<void> handleIncomingMessage({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
    required String messageId,
  }) async {
    try {
      // Only process if this is for the current conversation
      if (conversationId != _currentConversationId) {
        return;
      }

      print(
          '📱 OptimizedSessionChatProvider: 📨 Handling incoming message: $message');

      // Create message object
      final incomingMessage = OptimizedMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: senderId,
        recipientId: _sessionService.currentSessionId ?? '',
        content: message,
        messageType: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
        deliveredAt: DateTime.now(),
        metadata: {
          'messageDirection': 'incoming',
          'processedAt': DateTime.now().toIso8601String(),
        },
      );

      // Save to database
      await _databaseService.saveMessage(incomingMessage.toMap());

      // Add to local messages list
      _addMessageToLocalList(incomingMessage);

      // Update conversation with last message
      await _updateConversationLastMessage(message, messageId);

      // Mark conversation as read
      await _markConversationAsRead();

      print(
          '📱 OptimizedSessionChatProvider: ✅ Incoming message processed: $messageId');
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error handling incoming message: $e');
    }
  }

  /// Handle typing indicator update
  void handleTypingIndicator(String senderId, bool isTyping) {
    try {
      // Only process if this is from the current recipient
      if (senderId != _currentRecipientId) {
        return;
      }

      print('📱 OptimizedSessionChatProvider: ⌨️ Typing indicator: $isTyping');

      _isRecipientTyping = isTyping;
      notifyListeners();

      print('📱 OptimizedSessionChatProvider: ✅ Typing indicator updated');
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error handling typing indicator: $e');
    }
  }

  /// Handle online status update
  void handleOnlineStatusUpdate(
      String senderId, bool isOnline, String? lastSeen) {
    try {
      // Only process if this is from the current recipient
      if (senderId != _currentRecipientId) {
        return;
      }

      print('📱 OptimizedSessionChatProvider: 🌐 Online status: $isOnline');

      _isRecipientOnline = isOnline;
      if (lastSeen != null) {
        _recipientLastSeen = DateTime.parse(lastSeen);
      }

      notifyListeners();

      print('📱 OptimizedSessionChatProvider: ✅ Online status updated');
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error handling online status: $e');
    }
  }

  /// Handle message status update
  void handleMessageStatusUpdate(
      String senderId, String messageId, String status) {
    try {
      // Only process if this is for a message in the current conversation
      final messageIndex = _messages.indexWhere((m) => m.id == messageId);
      if (messageIndex == -1) {
        return;
      }

      print(
          '📱 OptimizedSessionChatProvider: 📊 Message status update: $messageId -> $status');

      // Update message status
      final oldMessage = _messages[messageIndex];
      MessageStatus newStatus;

      switch (status) {
        case 'delivered':
          newStatus = MessageStatus.delivered;
          break;
        case 'read':
          newStatus = MessageStatus.read;
          break;
        default:
          newStatus = MessageStatus.sent;
      }

      final updatedMessage = oldMessage.copyWith(status: newStatus);
      _messages[messageIndex] = updatedMessage;

      notifyListeners();

      print(
          '📱 OptimizedSessionChatProvider: ✅ Message status updated: $messageId -> $status');
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error handling message status update: $e');
    }
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator(bool isTyping) async {
    try {
      if (_currentRecipientId == null) {
        return;
      }

      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        return;
      }

      // Prevent sending to self
      if (_currentRecipientId == currentUserId) {
        return;
      }

      // Encrypt typing indicator using enhanced encryption service
      print('🔐 OptimizedSessionChatProvider: 🔒 Encrypting typing indicator');
      await _encryptionService.encryptTypingIndicator(
        senderId: currentUserId,
        senderName: currentUserId,
        isTyping: isTyping,
        conversationId: _currentConversationId ?? 'temp_conv',
      );

      // Send encrypted typing indicator via AirNotifier
      final success = await _airNotifier.sendTypingIndicator(
        recipientId: _currentRecipientId!,
        senderName: currentUserId,
        isTyping: isTyping,
      );

      if (success) {
        print(
            '📱 OptimizedSessionChatProvider: ✅ Encrypted typing indicator sent: $isTyping');
      } else {
        print(
            '📱 OptimizedSessionChatProvider: ❌ Failed to send encrypted typing indicator');
      }
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error sending typing indicator: $e');
    }
  }

  /// Mark conversation as read
  Future<void> _markConversationAsRead() async {
    try {
      if (_currentConversationId == null) {
        return;
      }

      await _databaseService.updateConversation(_currentConversationId!, {
        'unread_count': 0,
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('📱 OptimizedSessionChatProvider: ✅ Conversation marked as read');
    } catch (e) {
      print(
          '📱 OptimizedSessionChatProvider: ❌ Error marking conversation as read: $e');
    }
  }

  /// Refresh messages
  Future<void> refreshMessages() async {
    try {
      if (_currentConversationId != null) {
        await _loadMessagesForConversation(_currentConversationId!);
      }
    } catch (e) {
      print('📱 OptimizedSessionChatProvider: ❌ Error refreshing messages: $e');
    }
  }

  /// Check if message is from current user
  bool isMessageFromCurrentUser(OptimizedMessage message) {
    final currentUserId = _sessionService.currentSessionId;
    if (currentUserId == null) return false;

    // Use metadata first, then fallback to senderId
    if (message.metadata != null &&
        message.metadata!.containsKey('messageDirection')) {
      return message.metadata!['messageDirection'] == 'outgoing';
    }

    return message.senderId == currentUserId;
  }

  /// Get current user ID
  String? get currentUserId => _sessionService.currentSessionId;

  // ===== PRIVATE HELPER METHODS =====

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
  }

  /// Set error state
  void _setError(String error) {
    _error = error;
  }

  /// Clear error state
  void _clearError() {
    _error = null;
  }

  /// Set messages loading state
  void _setMessagesLoading(bool loading) {
    _isLoadingMessages = loading;
  }

  /// Set messages error state
  void _setMessagesError(String error) {
    _messagesError = error;
  }

  /// Clear messages error state
  void _clearMessagesError() {
    _messagesError = null;
  }

  @override
  void dispose() {
    print('📱 OptimizedSessionChatProvider: 🗑️ Disposed');
    super.dispose();
  }
}
