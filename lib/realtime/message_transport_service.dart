import 'dart:async';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import '../features/chat/services/message_storage_service.dart';
import 'realtime_logger.dart';
import '../features/chat/models/message.dart';

/// Service for handling message transport and delivery states
class MessageTransportService {
  static final MessageTransportService _instance =
      MessageTransportService._internal();
  factory MessageTransportService() => _instance;
  MessageTransportService._internal();

  final SeSocketService _socketService = SeSocketService.instance;
  final SeSessionService _sessionService = SeSessionService();
  final MessageStorageService _messageStorage = MessageStorageService.instance;

  // Message delivery state tracking
  final Map<String, MessageDeliveryState> _deliveryStates = {};

  // Server acknowledgment timeout
  static const Duration _serverTimeout = Duration(seconds: 10);

  /// Send a message via the channel-based socket service
  Future<bool> sendMessage(Message message) async {
    try {
      // Get the recipient ID directly from the message
      final recipientId = message.recipientId;
      if (recipientId.isEmpty) {
        RealtimeLogger.message('Message has no recipient ID',
            convoId: message.conversationId, messageId: message.id);
        return false;
      }

      // Initialize socket service if needed
      await _socketService.initialize();

      // Send message via channel socket
      _socketService.sendMessage(
        messageId: message.id,
        recipientId: recipientId,
        body: message.content['text'] ?? '',
        conversationId: message.conversationId,
      );

      RealtimeLogger.message(
          'Message sent via channel socket, waiting for server ack',
          convoId: message.conversationId,
          messageId: message.id);

      // Start acknowledgment timeout
      _startAcknowledgmentTimeout(message.id, message.conversationId);

      return true;
    } catch (e) {
      RealtimeLogger.message('Failed to send message: $e',
          convoId: message.conversationId, messageId: message.id);
      return false;
    }
  }

  /// Start acknowledgment timeout for a message
  void _startAcknowledgmentTimeout(String messageId, String conversationId) {
    Timer(_serverTimeout, () {
      final state = _deliveryStates[messageId];
      if (state != null && state.state == MessageDeliveryStateType.sending) {
        RealtimeLogger.message('Server acknowledgment timeout',
            convoId: conversationId, messageId: messageId);

        // Mark as failed and schedule retry
        state.state = MessageDeliveryStateType.failed;
        _scheduleRetry(messageId, conversationId);
      }
    });
  }

  /// Schedule retry for failed message
  void _scheduleRetry(String messageId, String conversationId) {
    Timer(const Duration(seconds: 5), () {
      final state = _deliveryStates[messageId];
      if (state != null && state.state == MessageDeliveryStateType.failed) {
        RealtimeLogger.message('Retrying failed message',
            convoId: conversationId, messageId: messageId);

        // Reset state and retry
        state.state = MessageDeliveryStateType.sending;
        state.retryCount++;

        // Get message from storage and retry
        _retryMessage(messageId, conversationId);
      }
    });
  }

  /// Retry sending a failed message
  Future<void> _retryMessage(String messageId, String conversationId) async {
    try {
      // For now, we'll just log the retry attempt
      // In the future, this can be enhanced to retrieve and retry specific messages
      RealtimeLogger.message('Retrying failed message (retry logic simplified)',
          convoId: conversationId, messageId: messageId);

      // Mark as failed permanently since we can't easily retrieve the message
      final state = _deliveryStates[messageId];
      if (state != null) {
        state.state = MessageDeliveryStateType.failed;
        state.error = 'Retry failed - message not retrievable';
      }
    } catch (e) {
      RealtimeLogger.message('Failed to retry message: $e',
          convoId: conversationId, messageId: messageId);
    }
  }

  /// Update message delivery state
  void updateDeliveryState(
      String messageId, MessageDeliveryStateType newState) {
    _deliveryStates[messageId] = MessageDeliveryState(state: newState);
  }

  /// Get delivery state for a message
  MessageDeliveryState? getDeliveryState(String messageId) {
    return _deliveryStates[messageId];
  }

  /// Mark message as delivered
  void markAsDelivered(String messageId) {
    final state = _deliveryStates[messageId];
    if (state != null) {
      state.state = MessageDeliveryStateType.delivered;
      state.deliveredAt = DateTime.now();
    }
  }

  /// Mark message as read
  void markAsRead(String messageId) {
    final state = _deliveryStates[messageId];
    if (state != null) {
      state.state = MessageDeliveryStateType.read;
      state.readAt = DateTime.now();
    }
  }

  /// Clear delivery state for a message
  void clearDeliveryState(String messageId) {
    _deliveryStates.remove(messageId);
  }
}

/// Message delivery state tracking
class MessageDeliveryState {
  MessageDeliveryStateType state;
  DateTime? sentAt;
  DateTime? deliveredAt;
  DateTime? readAt;
  int retryCount;
  String? error;

  MessageDeliveryState({
    required this.state,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.retryCount = 0,
    this.error,
  });
}

/// Message delivery state types
enum MessageDeliveryStateType {
  sending,
  sent,
  delivered,
  read,
  failed,
}
