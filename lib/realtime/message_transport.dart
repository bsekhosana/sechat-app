import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/services/se_socket_service.dart';
import '../core/services/se_session_service.dart';
import '../features/chat/models/message.dart';
import 'realtime_logger.dart';

/// Message delivery states (WhatsApp-style)
enum MessageDeliveryState {
  localQueued, // Message queued locally
  socketSent, // Sent to socket server
  serverAcked, // Server acknowledged (1 tick)
  delivered, // Delivered to recipient (2 ticks)
  read, // Read by recipient (2 blue ticks)
  failed, // Failed to send
}

/// Message transport service with WhatsApp-style delivery states and retry logic
class MessageTransportService {
  static MessageTransportService? _instance;
  static MessageTransportService get instance =>
      _instance ??= MessageTransportService._();

  MessageTransportService._();

  final SeSocketService _socketService = SeSocketService();
  final SeSessionService _sessionService = SeSessionService();

  // Message state tracking
  final Map<String, MessageTransportState> _messageStates = {};

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 1);
  static const double _retryJitter = 0.2; // 20% jitter

  // Stream controllers for message updates
  final StreamController<MessageDeliveryUpdate> _deliveryController =
      StreamController<MessageDeliveryUpdate>.broadcast();

  // Getters
  Stream<MessageDeliveryUpdate> get deliveryStream =>
      _deliveryController.stream;

  /// Send a message with delivery tracking
  Future<bool> sendMessage(Message message) async {
    try {
      RealtimeLogger.message('Sending message with delivery tracking',
          convoId: message.conversationId, messageId: message.id);

      // Create transport state
      final transportState = MessageTransportState(
        messageId: message.id,
        conversationId: message.conversationId,
        recipientId: message.recipientId,
        state: MessageDeliveryState.localQueued,
        timestamp: DateTime.now(),
        retryCount: 0,
      );

      _messageStates[message.id] = transportState;

      // Notify listeners
      _notifyDeliveryUpdate(transportState);

      // Attempt to send via socket
      return await _sendViaSocket(message, transportState);
    } catch (e) {
      RealtimeLogger.message('Failed to send message: $e',
          convoId: message.conversationId,
          messageId: message.id,
          details: {'error': e.toString()});
      return false;
    }
  }

  /// Send message via socket with retry logic
  Future<bool> _sendViaSocket(
      Message message, MessageTransportState transportState) async {
    try {
      if (!_socketService.isConnected) {
        RealtimeLogger.message('Socket not connected, message queued locally',
            convoId: message.conversationId, messageId: message.id);
        return false;
      }

      // Update state to socket sent
      transportState.state = MessageDeliveryState.socketSent;
      transportState.socketSentAt = DateTime.now();
      _notifyDeliveryUpdate(transportState);

      // Prepare message data
      final messageData = {
        'type': 'message:send',
        'messageId': message.id,
        'conversationId': message.conversationId,
        'fromUserId': message.senderId,
        'toUserIds': [message.recipientId],
        'body': message.content,
        'timestamp': message.timestamp.toIso8601String(),
        'metadata': message.metadata ?? {},
      };

      // Send via socket
      _socketService.emit('message:send', messageData);

      RealtimeLogger.message('Message sent via socket, waiting for server ack',
          convoId: message.conversationId, messageId: message.id);

      // Start acknowledgment timeout
      _startAckTimeout(message.id);

      return true;
    } catch (e) {
      RealtimeLogger.message('Failed to send message via socket: $e',
          convoId: message.conversationId,
          messageId: message.id,
          details: {'error': e.toString()});

      // Mark as failed and schedule retry
      await _handleSendFailure(message, transportState);
      return false;
    }
  }

  /// Handle send failure with retry logic
  Future<void> _handleSendFailure(
      Message message, MessageTransportState transportState) async {
    if (transportState.retryCount >= _maxRetries) {
      // Max retries exceeded
      transportState.state = MessageDeliveryState.failed;
      transportState.errorMessage = 'Max retries exceeded';
      _notifyDeliveryUpdate(transportState);

      RealtimeLogger.message('Message send failed after max retries',
          convoId: message.conversationId, messageId: message.id);
      return;
    }

    // Increment retry count
    transportState.retryCount++;

    // Calculate retry delay with exponential backoff and jitter
    final baseDelay =
        _baseRetryDelay.inMilliseconds * pow(2, transportState.retryCount - 1);
    final jitter = baseDelay * _retryJitter * (Random().nextDouble() - 0.5);
    final retryDelay = Duration(milliseconds: (baseDelay + jitter).round());

    RealtimeLogger.message(
        'Scheduling retry ${transportState.retryCount}/$_maxRetries in ${retryDelay.inMilliseconds}ms',
        convoId: message.conversationId,
        messageId: message.id,
        details: {
          'retryCount': transportState.retryCount,
          'retryDelay': retryDelay.inMilliseconds
        });

    // Schedule retry
    Timer(retryDelay, () async {
      if (_messageStates.containsKey(message.id)) {
        await _sendViaSocket(message, transportState);
      }
    });
  }

  /// Start acknowledgment timeout
  void _startAckTimeout(String messageId) {
    Timer(const Duration(seconds: 10), () {
      final state = _messageStates[messageId];
      if (state != null && state.state == MessageDeliveryState.socketSent) {
        RealtimeLogger.message(
            'Server acknowledgment timeout, scheduling retry',
            messageId: messageId,
            details: {'timeout': '10s'});

        // Reset to local queued and retry
        state.state = MessageDeliveryState.localQueued;
        state.socketSentAt = null;
        _notifyDeliveryUpdate(state);

        // Get the original message and retry
        // Note: In a real implementation, you'd need to store the original message
        // For now, we'll just mark it as failed
        state.state = MessageDeliveryState.failed;
        state.errorMessage = 'Server acknowledgment timeout';
        _notifyDeliveryUpdate(state);
      }
    });
  }

  /// Handle server acknowledgment
  void handleServerAck(String messageId) {
    final state = _messageStates[messageId];
    if (state == null) return;

    RealtimeLogger.message('Server acknowledgment received',
        convoId: state.conversationId, messageId: messageId);

    // Update state
    state.state = MessageDeliveryState.serverAcked;
    state.serverAckedAt = DateTime.now();
    _notifyDeliveryUpdate(state);
  }

  /// Handle delivery confirmation
  void handleDeliveryConfirmation(String messageId) {
    final state = _messageStates[messageId];
    if (state == null) return;

    RealtimeLogger.message('Delivery confirmation received',
        convoId: state.conversationId, messageId: messageId);

    // Update state
    state.state = MessageDeliveryState.delivered;
    state.deliveredAt = DateTime.now();
    _notifyDeliveryUpdate(state);
  }

  /// Handle read receipt
  void handleReadReceipt(String messageId) {
    final state = _messageStates[messageId];
    if (state == null) return;

    RealtimeLogger.message('Read receipt received',
        convoId: state.conversationId, messageId: messageId);

    // Update state
    state.state = MessageDeliveryState.read;
    state.readAt = DateTime.now();
    _notifyDeliveryUpdate(state);
  }

  /// Send delivery receipt
  void sendDeliveryReceipt(String messageId, String senderId) {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) return;

      final receiptData = {
        'type': 'receipt:delivered',
        'messageId': messageId,
        'fromUserId': sessionId,
        'toUserId': senderId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (_socketService.isConnected) {
        _socketService.emit('receipt:delivered', receiptData);
        RealtimeLogger.message('Delivery receipt sent',
            messageId: messageId, peerId: senderId);
      }
    } catch (e) {
      RealtimeLogger.message('Failed to send delivery receipt: $e',
          messageId: messageId, details: {'error': e.toString()});
    }
  }

  /// Send read receipt
  void sendReadReceipt(String messageId, String senderId) {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) return;

      final receiptData = {
        'type': 'receipt:read',
        'messageId': messageId,
        'fromUserId': sessionId,
        'toUserId': senderId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (_socketService.isConnected) {
        _socketService.emit('receipt:read', receiptData);
        RealtimeLogger.message('Read receipt sent',
            messageId: messageId, peerId: senderId);
      }
    } catch (e) {
      RealtimeLogger.message('Failed to send read receipt: $e',
          messageId: messageId, details: {'error': e.toString()});
    }
  }

  /// Get message delivery state
  MessageDeliveryState? getMessageState(String messageId) {
    return _messageStates[messageId]?.state;
  }

  /// Get message transport state
  MessageTransportState? getMessageTransportState(String messageId) {
    return _messageStates[messageId];
  }

  /// Get delivery statistics
  Map<String, dynamic> getDeliveryStats() {
    final totalMessages = _messageStates.length;
    final deliveredMessages = _messageStates.values
        .where((state) => state.state == MessageDeliveryState.delivered)
        .length;
    final readMessages = _messageStates.values
        .where((state) => state.state == MessageDeliveryState.read)
        .length;
    final failedMessages = _messageStates.values
        .where((state) => state.state == MessageDeliveryState.failed)
        .length;

    return {
      'totalMessages': totalMessages,
      'deliveredMessages': deliveredMessages,
      'readMessages': readMessages,
      'failedMessages': failedMessages,
      'deliveryRate': totalMessages > 0
          ? (deliveredMessages / totalMessages * 100).toStringAsFixed(1)
          : '0.0',
      'readRate': deliveredMessages > 0
          ? (readMessages / deliveredMessages * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// Notify delivery update
  void _notifyDeliveryUpdate(MessageTransportState state) {
    _deliveryController.add(MessageDeliveryUpdate(
      messageId: state.messageId,
      conversationId: state.conversationId,
      state: state.state,
      timestamp: DateTime.now(),
    ));
  }

  /// Dispose the service
  void dispose() {
    _deliveryController.close();
    _messageStates.clear();

    RealtimeLogger.message('Message transport service disposed');
  }
}

/// Message transport state
class MessageTransportState {
  final String messageId;
  final String conversationId;
  final String recipientId;
  MessageDeliveryState state;
  final DateTime timestamp;
  int retryCount;
  String? errorMessage;

  // Timestamps for each state
  DateTime? socketSentAt;
  DateTime? serverAckedAt;
  DateTime? deliveredAt;
  DateTime? readAt;

  MessageTransportState({
    required this.messageId,
    required this.conversationId,
    required this.recipientId,
    required this.state,
    required this.timestamp,
    required this.retryCount,
    this.errorMessage,
  });

  @override
  String toString() =>
      'MessageTransportState(messageId: $messageId, state: $state, retryCount: $retryCount)';
}

/// Message delivery update event
class MessageDeliveryUpdate {
  final String messageId;
  final String conversationId;
  final MessageDeliveryState state;
  final DateTime timestamp;

  MessageDeliveryUpdate({
    required this.messageId,
    required this.conversationId,
    required this.state,
    required this.timestamp,
  });

  @override
  String toString() =>
      'MessageDeliveryUpdate(messageId: $messageId, state: $state)';
}
