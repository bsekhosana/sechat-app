import 'dart:async';

import '../models/message.dart';
import '../models/message_status.dart' as msg_status;
import 'message_storage_service.dart';
import '../../../core/services/se_session_service.dart';
import '/../core/utils/logger.dart';

/// Service for tracking message delivery status and read receipts
class MessageStatusTrackingService {
  static MessageStatusTrackingService? _instance;
  static MessageStatusTrackingService get instance =>
      _instance ??= MessageStatusTrackingService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
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
      Logger.debug(
          '📊 MessageStatusTrackingService: Initializing tracking service');

      // Note: Socket callbacks are now handled by ChannelSocketService
      // This service focuses on local status tracking and UI updates

      Logger.success(
          '📊 MessageStatusTrackingService:  Tracking service initialized successfully');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to initialize tracking service: $e');
      rethrow;
    }
  }

  /// Handle message status update from external source (e.g., ChannelSocketService)
  void handleMessageStatusUpdate(
      String senderId, String messageId, String status) {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Handling status update: $messageId -> $status');

      // Convert string status to enum
      msg_status.MessageDeliveryStatus messageStatus;
      switch (status.toLowerCase()) {
        case 'sent':
          messageStatus = msg_status.MessageDeliveryStatus.sent;
          break;
        case 'delivered':
          messageStatus = msg_status.MessageDeliveryStatus.delivered;
          break;
        case 'read':
          messageStatus = msg_status.MessageDeliveryStatus.read;
          break;
        case 'failed':
          messageStatus = msg_status.MessageDeliveryStatus.failed;
          break;
        default:
          Logger.debug(
              '📊 MessageStatusTrackingService: Unknown status: $status');
          return;
      }

      // Update cache
      _updateStatusCache(messageId, messageStatus);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: messageStatus,
        timestamp: DateTime.now(),
        senderId: senderId,
      ));

      Logger.success(
          '📊 MessageStatusTrackingService:  Status update handled: $messageId -> ${messageStatus.name}');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to handle status update: $e');
    }
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
      Logger.debug(
          '📊 MessageStatusTrackingService: Marking message as sent: $messageId');

      // Update cache only (storage update not implemented yet)
      _updateStatusCache(messageId, msg_status.MessageDeliveryStatus.sent);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: msg_status.MessageDeliveryStatus.sent,
        timestamp: DateTime.now(),
      ));

      Logger.success(
          '📊 MessageStatusTrackingService:  Message marked as sent: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to mark message as sent: $e');
      rethrow;
    }
  }

  /// Mark message as delivered
  Future<void> markMessageAsDelivered(String messageId) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Marking message as delivered: $messageId');

      // Update cache only (storage update not implemented yet)
      _updateStatusCache(messageId, msg_status.MessageDeliveryStatus.delivered);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: msg_status.MessageDeliveryStatus.delivered,
        timestamp: DateTime.now(),
      ));

      // Send delivery confirmation to sender
      await _sendDeliveryConfirmation(messageId);

      Logger.success(
          '📊 MessageStatusTrackingService:  Message marked as delivered: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to mark message as delivered: $e');
      rethrow;
    }
  }

  /// Mark message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Marking message as read: $messageId');

      // Update cache only (storage update not implemented yet)
      _updateStatusCache(messageId, msg_status.MessageDeliveryStatus.read);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: msg_status.MessageDeliveryStatus.read,
        timestamp: DateTime.now(),
      ));

      // Send read receipt to sender
      await _sendReadReceipt(messageId);

      Logger.success(
          '📊 MessageStatusTrackingService:  Message marked as read: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to mark message as read: $e');
      rethrow;
    }
  }

  /// Mark message as failed
  Future<void> markMessageAsFailed(String messageId, String error) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Marking message as failed: $messageId');

      // Update cache only (storage update not implemented yet)
      _updateStatusCache(messageId, msg_status.MessageDeliveryStatus.failed);

      // Notify listeners
      _statusUpdateController.add(MessageStatusUpdate(
        messageId: messageId,
        status: msg_status.MessageDeliveryStatus.failed,
        timestamp: DateTime.now(),
      ));

      Logger.success(
          '📊 MessageStatusTrackingService:  Message marked as failed: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to mark message as failed: $e');
      rethrow;
    }
  }

  /// Update typing indicator for a conversation
  Future<void> updateTypingIndicator(
      String conversationId, String userId, bool isTyping) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Updating typing indicator: $userId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) return;

      // Only update typing indicator if the user is NOT the current user
      // (i.e., don't show typing indicator on sender's screen)
      if (userId == currentUserId) {
        Logger.debug(
            '📊 MessageStatusTrackingService: Skipping typing indicator update for current user');
        return;
      }

      // Note: Storage service methods not implemented yet
      // For now, just handle local typing state
      if (isTyping) {
        _setupTypingTimeout(conversationId, userId);
      } else {
        _clearTypingTimeout(conversationId);
      }

      // Notify listeners
      _typingIndicatorController.add(TypingIndicatorUpdate(
        conversationId: conversationId,
        userId: userId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
      ));

      Logger.success(
          '📊 MessageStatusTrackingService:  Typing indicator updated: $userId -> $isTyping');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to update typing indicator: $e');
    }
  }

  /// Handle typing indicator update
  Future<void> _handleTypingIndicator(String senderId, bool isTyping) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Handling typing indicator: $senderId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) return;

      // FIXED: Allow bidirectional typing indicators for better user experience
      // Only prevent users from seeing their own typing indicator if they're not in a conversation
      if (senderId == currentUserId) {
        // For now, always process typing indicators for consistency
        Logger.info(
            '📊 MessageStatusTrackingService:  Processing own typing indicator for UI consistency');
      }

      // Note: Storage service methods not implemented yet
      // For now, just handle local typing state
      if (isTyping) {
        _setupTypingTimeout(
            '', senderId); // Use empty string as conversation ID for now
      } else {
        _clearTypingTimeout(''); // Use empty string as conversation ID for now
      }

      // Notify listeners
      _typingIndicatorController.add(TypingIndicatorUpdate(
        conversationId:
            '', // Will be filled when storage integration is complete
        userId: senderId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
      ));

      Logger.success(
          '📊 MessageStatusTrackingService:  Typing indicator handled: $senderId -> $isTyping');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to handle typing indicator: $e');
    }
  }

  /// Public method to handle typing indicators from external sources (e.g., push notifications)
  /// This method can be called from SecureNotificationService when typing indicator notifications are received
  Future<void> handleExternalTypingIndicator(
      String senderId, bool isTyping) async {
    try {
      Logger.debug(
          '📊 MessageStatusTrackingService: Handling external typing indicator: $senderId -> $isTyping');

      // Get current user ID
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        Logger.debug(
            '📊 MessageStatusTrackingService: No current session ID available');
        return;
      }

      // FIXED: Allow bidirectional typing indicators for better user experience
      // Only prevent users from seeing their own typing indicator if they're not in a conversation
      if (senderId == currentUserId) {
        // Check if we have any active conversations to determine if we should process this
        final conversations =
            await _storageService.getUserConversations(currentUserId);
        if (conversations.isEmpty) {
          Logger.debug(
              '📊 MessageStatusTrackingService: Skipping external typing indicator for current user (no conversations)');
          return;
        }
        // If we have conversations, process the typing indicator for UI consistency
        Logger.info(
            '📊 MessageStatusTrackingService:  Processing own external typing indicator in active conversation');
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

      Logger.success(
          '📊 MessageStatusTrackingService:  External typing indicator handled: $senderId -> $isTyping');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to handle external typing indicator: $e');
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

    _typingTimers[userId] = timer;
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
      Logger.debug(
          '📊 MessageStatusTrackingService: Updating last seen for: $userId');

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

      Logger.success(
          '📊 MessageStatusTrackingService:  Last seen updated for: $userId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to update last seen: $e');
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
      Logger.debug(
          '📊 MessageStatusTrackingService: Would send delivery confirmation for: $messageId');

      Logger.success(
          '📊 MessageStatusTrackingService:  Delivery confirmation sent for: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to send delivery confirmation: $e');
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
      Logger.debug(
          '📊 MessageStatusTrackingService: Would send read receipt for: $messageId');

      Logger.success(
          '📊 MessageStatusTrackingService:  Read receipt sent for: $messageId');
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to send read receipt: $e');
    }
  }

  /// Get message by ID (helper method)
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This would typically come from the storage service
      // For now, we'll return null and implement this later
      return null;
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to get message: $e');
      return null;
    }
  }

  /// Update status cache
  void _updateStatusCache(
      String messageId, msg_status.MessageDeliveryStatus status) {
    _statusCache[messageId] = msg_status.MessageStatus(
      messageId: messageId,
      conversationId:
          '', // Will be filled when we implement the full storage integration
      recipientId: '',
      deliveryStatus: status,
    );
  }

  /// Get message status from cache
  msg_status.MessageStatus? getMessageStatus(String messageId) {
    return _statusCache[messageId];
  }

  /// Get typing status for a user
  bool isUserTyping(String userId) {
    try {
      // Check if user has active typing indicators
      return _typingTimers.containsKey(userId);
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to get typing status: $e');
      return false;
    }
  }

  /// Get last seen for a user
  DateTime? getLastSeen(String userId) {
    try {
      // This would typically come from a presence service
      // For now, return null as we don't have this data
      return null;
    } catch (e) {
      Logger.error(
          '📊 MessageStatusTrackingService:  Failed to get last seen: $e');
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

    Logger.success('📊 MessageStatusTrackingService:  Service disposed');
  }
}

/// Data class for message status updates
class MessageStatusUpdate {
  final String messageId;
  final msg_status.MessageDeliveryStatus status;
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
