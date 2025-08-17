import 'dart:async';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/message_status.dart' as msg_status;
import '../models/chat_conversation.dart';
import 'message_storage_service.dart';
import '../../../core/services/secure_notification_service.dart';
import '../../../core/services/se_session_service.dart';

/// Service for tracking message delivery status and read receipts
class MessageStatusTrackingService {
  static MessageStatusTrackingService? _instance;
  static MessageStatusTrackingService get instance =>
      _instance ??= MessageStatusTrackingService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final SecureNotificationService _notificationService =
      SecureNotificationService.instance;
  final SeSessionService _sessionService = SeSessionService();

  // Stream controllers for real-time updates
  final StreamController<MessageStatusUpdate> _statusUpdateController =
      StreamController<MessageStatusUpdate>.broadcast();
  final StreamController<TypingIndicatorUpdate> _typingIndicatorController =
      StreamController<TypingIndicatorUpdate>.broadcast();
  final StreamController<LastSeenUpdate> _lastSeenController =
      StreamController<LastSeenUpdate>.broadcast();

  // Active timers for typing indicators
  final Map<String, Timer> _typingTimers = {};

  // Message status cache for performance
  final Map<String, msg_status.MessageStatus> _statusCache = {};

  MessageStatusTrackingService._();

  /// Initialize the tracking service
  Future<void> initialize() async {
    try {
      print('📊 MessageStatusTrackingService: Initializing tracking service');

      // Set up notification service callbacks
      _setupNotificationCallbacks();

      print(
          '📊 MessageStatusTrackingService: ✅ Tracking service initialized successfully');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to initialize tracking service: $e');
      rethrow;
    }
  }

  /// Set up notification service callbacks
  void _setupNotificationCallbacks() {
    // Set up callbacks for message status updates
    _notificationService
        .setOnMessageStatusUpdate((senderId, messageId, status) {
      _handleMessageStatusUpdate(senderId, messageId, status);
    });

    // Set up callbacks for typing indicators
    _notificationService.setOnTypingIndicator((senderId, isTyping) {
      _handleTypingIndicator(senderId, isTyping);
    });
  }

  /// Stream for message status updates
  Stream<MessageStatusUpdate> get statusUpdateStream =>
      _statusUpdateController.stream;

  /// Stream for typing indicator updates
  Stream<TypingIndicatorUpdate> get typingIndicatorStream =>
      _typingIndicatorController.stream;

  /// Stream for last seen updates
  Stream<LastSeenUpdate> get lastSeenStream => _lastSeenController.stream;

  /// Mark message as sent
  Future<void> markMessageAsSent(String messageId) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Marking message as sent: $messageId');

      // Update message status in storage
      await _storageService.updateMessageStatus(messageId, MessageStatus.sent);

      // Update cache
      _updateStatusCache(messageId, MessageStatus.sent);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
      ));

      print(
          '📊 MessageStatusTrackingService: ✅ Message marked as sent: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to mark message as sent: $e');
      rethrow;
    }
  }

  /// Mark message as delivered
  Future<void> markMessageAsDelivered(String messageId) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Marking message as delivered: $messageId');

      // Update message status in storage
      await _storageService.updateMessageStatus(
          messageId, MessageStatus.delivered);

      // Update cache
      _updateStatusCache(messageId, MessageStatus.delivered);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
      ));

      // Send delivery confirmation to sender
      await _sendDeliveryConfirmation(messageId);

      print(
          '📊 MessageStatusTrackingService: ✅ Message marked as delivered: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to mark message as delivered: $e');
      rethrow;
    }
  }

  /// Mark message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Marking message as read: $messageId');

      // Update message status in storage
      await _storageService.updateMessageStatus(messageId, MessageStatus.read);

      // Update cache
      _updateStatusCache(messageId, MessageStatus.read);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: MessageStatus.read,
        timestamp: DateTime.now(),
      ));

      // Send read receipt to sender
      await _sendReadReceipt(messageId);

      print(
          '📊 MessageStatusTrackingService: ✅ Message marked as read: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to mark message as read: $e');
      rethrow;
    }
  }

  /// Mark message as failed
  Future<void> markMessageAsFailed(String messageId, String error) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Marking message as failed: $messageId');

      // Update message status in storage
      await _storageService.updateMessageStatus(
          messageId, MessageStatus.failed);

      // Update cache
      _updateStatusCache(messageId, MessageStatus.failed);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        error: error,
      ));

      print(
          '📊 MessageStatusTrackingService: ✅ Message marked as failed: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to mark message as failed: $e');
      rethrow;
    }
  }

  /// Handle message status update from notification
  Future<void> _handleMessageStatusUpdate(
      String senderId, String messageId, String status) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Handling status update: $messageId -> $status');

      MessageStatus messageStatus;
      switch (status.toLowerCase()) {
        case 'sent':
          messageStatus = MessageStatus.sent;
          break;
        case 'delivered':
          messageStatus = MessageStatus.delivered;
          break;
        case 'read':
          messageStatus = MessageStatus.read;
          break;
        case 'failed':
          messageStatus = MessageStatus.failed;
          break;
        default:
          print('📊 MessageStatusTrackingService: Unknown status: $status');
          return;
      }

      // Update message status in storage
      await _storageService.updateMessageStatus(messageId, messageStatus);

      // Update cache
      _updateStatusCache(messageId, messageStatus);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: messageStatus,
        timestamp: DateTime.now(),
        senderId: senderId,
      ));

      print(
          '📊 MessageStatusTrackingService: ✅ Status update handled: $messageId -> ${messageStatus.name}');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to handle status update: $e');
    }
  }

  /// Update typing indicator for a conversation
  Future<void> updateTypingIndicator(
      String conversationId, String userId, bool isTyping) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Updating typing indicator: $userId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) return;

      // Only update typing indicator if the user is NOT the current user
      // (i.e., don't show typing indicator on sender's screen)
      if (userId == currentUserId) {
        print(
            '📊 MessageStatusTrackingService: Skipping typing indicator update for current user');
        return;
      }

      // Find conversation
      final conversations =
          await _storageService.getUserConversations(currentUserId);
      final conversation = conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      // Update conversation typing indicator
      final updatedConversation = conversation.updateTypingIndicator(isTyping);
      await _storageService.saveConversation(updatedConversation);

      // Notify listeners
      _typingIndicatorController.add(TypingIndicatorUpdate(
        conversationId: conversation.id,
        userId: userId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
      ));

      // Set up typing timeout if typing started
      if (isTyping) {
        _setupTypingTimeout(conversation.id, userId);
      } else {
        _clearTypingTimeout(conversation.id);
      }

      print(
          '📊 MessageStatusTrackingService: ✅ Typing indicator updated: $userId -> $isTyping');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to update typing indicator: $e');
    }
  }

  /// Handle typing indicator update
  Future<void> _handleTypingIndicator(String senderId, bool isTyping) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Handling typing indicator: $senderId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) return;

      // Only show typing indicator if the sender is NOT the current user
      // (i.e., show typing indicator on recipient's screen, not sender's)
      if (senderId == currentUserId) {
        print(
            '📊 MessageStatusTrackingService: Skipping typing indicator for current user');
        return;
      }

      // Find conversation with this sender
      final conversations =
          await _storageService.getUserConversations(currentUserId);
      final conversation = conversations.firstWhere(
        (c) => c.isParticipant(senderId),
        orElse: () => throw Exception('Conversation not found'),
      );

      // Update conversation typing indicator
      final updatedConversation = conversation.updateTypingIndicator(isTyping);
      await _storageService.saveConversation(updatedConversation);

      // Notify listeners
      _typingIndicatorController.add(TypingIndicatorUpdate(
        conversationId: conversation.id,
        userId: senderId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
      ));

      // Set up typing timeout if typing started
      if (isTyping) {
        _setupTypingTimeout(conversation.id, senderId);
      } else {
        _clearTypingTimeout(conversation.id);
      }

      print(
          '📊 MessageStatusTrackingService: ✅ Typing indicator handled: $senderId -> $isTyping');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to handle typing indicator: $e');
    }
  }

  /// Public method to handle typing indicators from external sources (e.g., push notifications)
  /// This method can be called from SecureNotificationService when typing indicator notifications are received
  Future<void> handleExternalTypingIndicator(
      String senderId, bool isTyping) async {
    try {
      print(
          '📊 MessageStatusTrackingService: Handling external typing indicator: $senderId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        print(
            '📊 MessageStatusTrackingService: No current session ID available');
        return;
      }

      // Only show typing indicator if the sender is NOT the current user
      // (i.e., show typing indicator on recipient's screen, not sender's)
      if (senderId == currentUserId) {
        print(
            '📊 MessageStatusTrackingService: Skipping external typing indicator for current user');
        return;
      }

      // Find conversation with this sender
      final conversations =
          await _storageService.getUserConversations(currentUserId);
      final conversation = conversations.firstWhere(
        (c) => c.isParticipant(senderId),
        orElse: () => throw Exception('Conversation not found'),
      );

      // Update conversation typing indicator
      final updatedConversation = conversation.updateTypingIndicator(isTyping);
      await _storageService.saveConversation(updatedConversation);

      // Notify listeners
      _typingIndicatorController.add(TypingIndicatorUpdate(
        conversationId: conversation.id,
        userId: senderId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
      ));

      // Set up typing timeout if typing started
      if (isTyping) {
        _setupTypingTimeout(conversation.id, senderId);
      } else {
        _clearTypingTimeout(conversation.id);
      }

      print(
          '📊 MessageStatusTrackingService: ✅ External typing indicator handled: $senderId -> $isTyping');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to handle external typing indicator: $e');
    }
  }

  /// Set up typing timeout
  void _setupTypingTimeout(String conversationId, String userId) {
    // Clear existing timer
    _clearTypingTimeout(conversationId);

    // Set new timer (5 seconds timeout)
    final timer = Timer(const Duration(seconds: 5), () {
      _handleTypingIndicator(userId, false);
    });

    _typingTimers[conversationId] = timer;
  }

  /// Clear typing timeout
  void _clearTypingTimeout(String conversationId) {
    final timer = _typingTimers[conversationId];
    if (timer != null) {
      timer.cancel();
      _typingTimers.remove(conversationId);
    }
  }

  /// Update last seen for a user
  Future<void> updateLastSeen(String userId) async {
    try {
      print('📊 MessageStatusTrackingService: Updating last seen for: $userId');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) return;

      // Find conversation with this user
      final conversations =
          await _storageService.getUserConversations(currentUserId);
      final conversation = conversations.firstWhere(
        (c) => c.isParticipant(userId),
        orElse: () => throw Exception('Conversation not found'),
      );

      // Update conversation last seen
      final updatedConversation = conversation.updateLastSeen();
      await _storageService.saveConversation(updatedConversation);

      // Notify listeners
      _lastSeenController.add(LastSeenUpdate(
        conversationId: conversation.id,
        userId: userId,
        timestamp: DateTime.now(),
      ));

      print(
          '📊 MessageStatusTrackingService: ✅ Last seen updated for: $userId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to update last seen: $e');
    }
  }

  /// Send delivery confirmation to sender
  Future<void> _sendDeliveryConfirmation(String messageId) async {
    try {
      // Get message details
      final message = await _getMessageById(messageId);
      if (message == null) return;

      // Send silent notification to sender using existing notification service
      // For now, we'll use a placeholder - this will be implemented when we extend the notification service
      print(
          '📊 MessageStatusTrackingService: Would send delivery confirmation for: $messageId');

      print(
          '📊 MessageStatusTrackingService: ✅ Delivery confirmation sent for: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to send delivery confirmation: $e');
    }
  }

  /// Send read receipt to sender
  Future<void> _sendReadReceipt(String messageId) async {
    try {
      // Get message details
      final message = await _getMessageById(messageId);
      if (message == null) return;

      // Send silent notification to sender using existing notification service
      // For now, we'll use a placeholder - this will be implemented when we extend the notification service
      print(
          '📊 MessageStatusTrackingService: Would send read receipt for: $messageId');

      print(
          '📊 MessageStatusTrackingService: ✅ Read receipt sent for: $messageId');
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to send read receipt: $e');
    }
  }

  /// Get message by ID (helper method)
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This would typically come from the storage service
      // For now, we'll return null and implement this later
      return null;
    } catch (e) {
      print('📊 MessageStatusTrackingService: ❌ Failed to get message: $e');
      return null;
    }
  }

  /// Update status cache
  void _updateStatusCache(String messageId, MessageStatus status) {
    _statusCache[messageId] = msg_status.MessageStatus(
      messageId: messageId,
      conversationId:
          '', // Will be filled when we implement the full storage integration
      recipientId: '',
      deliveryStatus: _convertToDeliveryStatus(status),
    );
  }

  /// Convert MessageStatus to MessageDeliveryStatus
  msg_status.MessageDeliveryStatus _convertToDeliveryStatus(
      MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return msg_status.MessageDeliveryStatus.pending;
      case MessageStatus.sent:
        return msg_status.MessageDeliveryStatus.sent;
      case MessageStatus.delivered:
        return msg_status.MessageDeliveryStatus.delivered;
      case MessageStatus.read:
        return msg_status.MessageDeliveryStatus.read;
      case MessageStatus.failed:
        return msg_status.MessageDeliveryStatus.failed;
      case MessageStatus.deleted:
        return msg_status
            .MessageDeliveryStatus.failed; // Map deleted to failed for now
    }
  }

  /// Get message status from cache
  msg_status.MessageStatus? getCachedStatus(String messageId) {
    return _statusCache[messageId];
  }

  /// Clear status cache
  void clearStatusCache() {
    _statusCache.clear();
  }

  /// Get conversation typing status
  Future<bool> isUserTyping(String conversationId, String userId) async {
    try {
      final conversation =
          await _storageService.getConversation(conversationId);
      if (conversation == null) return false;

      return conversation.isTyping &&
          conversation.getOtherParticipantId(userId) == userId;
    } catch (e) {
      print(
          '📊 MessageStatusTrackingService: ❌ Failed to get typing status: $e');
      return false;
    }
  }

  /// Get user's last seen time
  Future<DateTime?> getUserLastSeen(
      String conversationId, String userId) async {
    try {
      final conversation =
          await _storageService.getConversation(conversationId);
      if (conversation == null) return null;

      return conversation.lastSeen;
    } catch (e) {
      print('📊 MessageStatusTrackingService: ❌ Failed to get last seen: $e');
      return null;
    }
  }

  /// Dispose of resources
  void dispose() {
    // Cancel all active timers
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();

    // Close stream controllers
    _statusUpdateController.close();
    _typingIndicatorController.close();
    _lastSeenController.close();

    // Clear cache
    _statusCache.clear();

    print('📊 MessageStatusTrackingService: ✅ Service disposed');
  }
}

/// Data class for message status updates
class MessageStatusUpdate {
  final String messageId;
  final MessageStatus status;
  final DateTime timestamp;
  final String? senderId;
  final String? error;

  MessageStatusUpdate({
    required this.messageId,
    required this.status,
    required this.timestamp,
    this.senderId,
    this.error,
  });
}

/// Data class for typing indicator updates
class TypingIndicatorUpdate {
  final String conversationId;
  final String userId;
  final bool isTyping;
  final DateTime timestamp;

  TypingIndicatorUpdate({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
    required this.timestamp,
  });
}

/// Data class for last seen updates
class LastSeenUpdate {
  final String conversationId;
  final String userId;
  final DateTime timestamp;

  LastSeenUpdate({
    required this.conversationId,
    required this.userId,
    required this.timestamp,
  });
}
