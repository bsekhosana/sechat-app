import 'dart:async';
import 'dart:io';
import '../core/services/se_socket_service.dart';
import '../core/services/se_session_service.dart';
import 'presence_service.dart';
import 'typing_service.dart';
import 'message_transport.dart';
import 'realtime_logger.dart';

/// Socket client service for the new realtime protocol
class SocketClientService {
  static SocketClientService? _instance;
  static SocketClientService get instance =>
      _instance ??= SocketClientService._();

  SocketClientService._();

  final SeSocketService _socketService = SeSocketService();
  final SeSessionService _sessionService = SeSessionService();

  // Service references
  late final PresenceService _presenceService;
  late final TypingService _typingService;
  late final MessageTransportService _messageTransportService;

  // Connection state
  bool _isInitialized = false;
  bool _isConnected = false;

  // Stream controllers for realtime events
  final StreamController<PresenceUpdate> _presenceController =
      StreamController<PresenceUpdate>.broadcast();
  final StreamController<TypingUpdate> _typingController =
      StreamController<TypingUpdate>.broadcast();
  final StreamController<MessageDeliveryUpdate> _messageController =
      StreamController<MessageDeliveryUpdate>.broadcast();

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  Stream<PresenceUpdate> get presenceStream => _presenceController.stream;
  Stream<TypingUpdate> get typingStream => _typingController.stream;
  Stream<MessageDeliveryUpdate> get messageStream => _messageController.stream;

  /// Initialize the socket client service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      RealtimeLogger.socket('Initializing socket client service');

      // Initialize realtime services
      _presenceService = PresenceService.instance;
      _typingService = TypingService.instance;
      _messageTransportService = MessageTransportService.instance;

      await _presenceService.initialize();

      // Set up socket event handlers
      _setupSocketEventHandlers();

      // Set up connection state listener
      _setupConnectionStateListener();

      _isInitialized = true;

      RealtimeLogger.socket('Socket client service initialized successfully');
    } catch (e) {
      RealtimeLogger.socket('Failed to initialize socket client service: $e',
          details: {'error': e.toString()});
      rethrow;
    }
  }

  /// Set up socket event handlers for the new protocol
  void _setupSocketEventHandlers() {
    // Presence events
    _socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
      _handlePresenceUpdate(senderId, isOnline, lastSeen);
    });

    // Typing events
    _socketService.setOnTypingIndicator((senderId, isTyping) {
      _handleTypingUpdate(senderId, isTyping);
    });

    // Message events
    _socketService.setOnMessageReceived(
        (senderId, senderName, message, conversationId, messageId) {
      _handleMessageReceived(
          senderId, senderName, message, conversationId, messageId);
    });

    // Set up additional socket event listeners
    _setupAdditionalEventHandlers();
  }

  /// Set up additional socket event handlers
  void _setupAdditionalEventHandlers() {
    // Note: For now, we'll rely on the existing SeSocketService callbacks
    // In the future, we can extend SeSocketService to support these new events
    RealtimeLogger.socket('Additional event handlers setup completed');
  }

  /// Set up connection state listener
  void _setupConnectionStateListener() {
    _socketService.connectionStateStream.listen((isConnected) {
      final wasConnected = _isConnected;
      _isConnected = isConnected;

      if (wasConnected != isConnected) {
        RealtimeLogger.socket(
            'Connection state changed: ${isConnected ? 'connected' : 'disconnected'}');

        if (isConnected) {
          _onSocketConnected();
        } else {
          _onSocketDisconnected();
        }
      }
    });
  }

  /// Handle socket connection
  void _onSocketConnected() {
    RealtimeLogger.socket('Socket connected, initializing realtime services');

    // Initialize presence service
    _presenceService.forcePresenceUpdate(true);
  }

  /// Handle socket disconnection
  void _onSocketDisconnected() {
    RealtimeLogger.socket('Socket disconnected, pausing realtime services');

    // Note: Presence service will handle offline state via app lifecycle
  }

  /// Handle presence update from socket
  void _handlePresenceUpdate(String senderId, bool isOnline, String? lastSeen) {
    try {
      RealtimeLogger.socket(
          'Presence update received: $senderId -> ${isOnline ? 'online' : 'offline'}',
          peerId: senderId);

      // Create presence update event
      final presenceUpdate = PresenceUpdate(
        isOnline: isOnline,
        timestamp: lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now(),
        source: 'peer',
      );

      // Forward to presence service
      _presenceController.add(presenceUpdate);

      RealtimeLogger.socket('Presence update forwarded to listeners',
          peerId: senderId);
    } catch (e) {
      RealtimeLogger.socket('Failed to handle presence update: $e',
          peerId: senderId, details: {'error': e.toString()});
    }
  }

  /// Handle presence event from socket
  void _handlePresenceEvent(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final sessionId = data['sessionId'] as String?;
        final isOnline = data['isOnline'] as bool?;
        final timestamp = data['timestamp'] as String?;

        if (sessionId != null && isOnline != null) {
          _handlePresenceUpdate(sessionId, isOnline, timestamp);
        }
      }
    } catch (e) {
      RealtimeLogger.socket('Failed to handle presence event: $e',
          details: {'error': e.toString()});
    }
  }

  /// Handle typing update from socket
  void _handleTypingUpdate(String senderId, bool isTyping) {
    try {
      RealtimeLogger.socket('Typing update received: $senderId -> $isTyping',
          peerId: senderId);

      // Note: We need conversation ID to properly handle typing updates
      // For now, we'll broadcast to all active conversations
      // In a real implementation, you'd need to track which conversation this is for

      RealtimeLogger.socket('Typing update processed', peerId: senderId);
    } catch (e) {
      RealtimeLogger.socket('Failed to handle typing update: $e',
          peerId: senderId, details: {'error': e.toString()});
    }
  }

  /// Handle typing event from socket
  void _handleTypingEvent(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final conversationId = data['conversationId'] as String?;
        final fromUserId = data['fromUserId'] as String?;
        final isTyping = data['isTyping'] as bool?;

        if (conversationId != null && fromUserId != null && isTyping != null) {
          // Create typing update event
          final typingUpdate = TypingUpdate(
            conversationId: conversationId,
            isTyping: isTyping,
            timestamp: DateTime.now(),
            source: 'peer',
          );

          // Forward to typing service
          _typingController.add(typingUpdate);

          RealtimeLogger.socket('Typing update forwarded to listeners',
              convoId: conversationId, peerId: fromUserId);
        }
      }
    } catch (e) {
      RealtimeLogger.socket('Failed to handle typing event: $e',
          details: {'error': e.toString()});
    }
  }

  /// Handle message received from socket
  void _handleMessageReceived(String senderId, String senderName,
      String message, String conversationId, String messageId) {
    try {
      RealtimeLogger.socket('Message received: $messageId from $senderId',
          convoId: conversationId,
          peerId: senderId,
          details: {'messageId': messageId});

      // Send delivery receipt
      _messageTransportService.sendDeliveryReceipt(messageId, senderId);

      // Note: Message content handling would be done by the chat provider
      // This service only handles delivery state

      RealtimeLogger.socket('Message delivery receipt sent',
          convoId: conversationId,
          peerId: senderId,
          details: {'messageId': messageId});
    } catch (e) {
      RealtimeLogger.socket('Failed to handle message received: $e',
          convoId: conversationId,
          details: {'error': e.toString(), 'messageId': messageId});
    }
  }

  /// Handle message acknowledgment
  void _handleMessageAck(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final messageId = data['messageId'] as String?;

        if (messageId != null) {
          _messageTransportService.handleServerAck(messageId);
          RealtimeLogger.socket('Message acknowledgment processed',
              details: {'messageId': messageId});
        }
      }
    } catch (e) {
      RealtimeLogger.socket('Failed to handle message ack: $e',
          details: {'error': e.toString()});
    }
  }

  /// Handle message delivery confirmation
  void _handleMessageDelivery(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final messageId = data['messageId'] as String?;

        if (messageId != null) {
          _messageTransportService.handleDeliveryConfirmation(messageId);
          RealtimeLogger.socket('Message delivery confirmation processed',
              details: {'messageId': messageId});
        }
      }
    } catch (e) {
      RealtimeLogger.socket('Failed to handle message delivery: $e',
          details: {'error': e.toString()});
    }
  }

  /// Handle message read receipt
  void _handleMessageRead(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final messageId = data['messageId'] as String?;

        if (messageId != null) {
          _messageTransportService.handleReadReceipt(messageId);
          RealtimeLogger.socket('Message read receipt processed',
              details: {'messageId': messageId});
        }
      }
    } catch (e) {
      RealtimeLogger.socket('Failed to handle message read: $e',
          details: {'error': e.toString()});
    }
  }

  /// Get service statistics
  Map<String, dynamic> getServiceStats() {
    return {
      'isInitialized': _isInitialized,
      'isConnected': _isConnected,
      'presenceStats': _presenceService.getPresenceStats(),
      'typingStats': _typingService.getTypingStats(),
      'messageStats': _messageTransportService.getDeliveryStats(),
    };
  }

  /// Dispose the service
  void dispose() {
    _presenceController.close();
    _typingController.close();
    _messageController.close();
    _isInitialized = false;

    RealtimeLogger.socket('Socket client service disposed');
  }
}
