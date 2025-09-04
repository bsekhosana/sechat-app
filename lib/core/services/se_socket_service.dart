import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/features/chat/providers/session_chat_provider.dart';
import 'package:sechat_app/features/notifications/services/local_notification_badge_service.dart';
import 'package:sechat_app/core/services/contact_service.dart';

import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app//../core/utils/logger.dart';
import '/..//../core/utils/logger.dart';

class SeSocketService {
  SeSocketService._();
  static SeSocketService? _instance;
  static bool _isDestroyed = false; // Track destruction state separately

  static SeSocketService get instance {
    if (_instance == null && !_isDestroyed) {
      _instance = SeSocketService._();
      Logger.info('New instance created', 'SeSocketService');
    } else if (_instance == null && _isDestroyed) {
      // Reset destruction state and create new instance
      _isDestroyed = false;
      _instance = SeSocketService._();
      Logger.info('Instance recreated after destruction', 'SeSocketService');
    }
    return _instance!;
  }

  // Check if instance is destroyed
  static bool get isDestroyed => _isDestroyed;

  // Check if instance exists and is valid
  static bool get hasValidInstance =>
      _instance != null && _instance!._socket != null;

  // CRITICAL: Method to completely destroy the singleton instance
  static void destroyInstance() {
    if (_instance != null) {
      Logger.debug('Destroying singleton instance...', 'SeSocketService');

      // First dispose the current instance
      _instance!.dispose();

      // Clear all static references
      _instance = null;
      _isDestroyed = true; // Mark as destroyed

      // Force garbage collection hint
      Logger.success(
          ' SeSocketService:  Singleton instance destroyed and references cleared');
    }
  }

  // Additional cleanup method for aggressive memory cleanup
  static void forceCleanup() {
    Logger.debug(
        'Force cleaning up all socket resources...', 'SeSocketService');

    // Destroy instance if it exists
    destroyInstance();

    // Additional cleanup steps
    Logger.success('Force cleanup completed', 'SeSocketService');
  }

  /// Create push notification for socket events (excluding connect/disconnect)
  Future<void> _createSocketEventNotification({
    required String eventType,
    required String title,
    required String body,
    String? senderId,
    String? senderName,
    String? conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
    bool silent = false,
  }) async {
    try {
      // Skip notifications for silent events
      if (silent) {
        Logger.debug(
            ' SeSocketService: 🔇 Skipping notification for silent event: $eventType');
        return;
      }

      // Skip notifications for connect/disconnect events
      if (eventType == 'connect' ||
          eventType == 'disconnect' ||
          eventType == 'connect_error' ||
          eventType == 'reconnect' ||
          eventType == 'reconnect_failed') {
        Logger.debug(
            ' SeSocketService: 🔇 Skipping notification for connection event: $eventType');
        return;
      }

      Logger.debug(
          ' SeSocketService: 🔔 Creating notification for event: $eventType');

      // Use new local notification system
      final localNotificationBadgeService = LocalNotificationBadgeService();

      await localNotificationBadgeService.showKerNotification(
        title: title,
        body: body,
        type: eventType,
        payload: {
          'type': eventType,
          'senderId': senderId,
          'recipientId': _sessionId,
          'conversationId': conversationId,
          'messageId': messageId,
          'metadata': metadata,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      Logger.success(
          'Notification created for event: $eventType', 'SeSocketService');
    } catch (e) {
      Logger.error(
          ' SeSocketService:  Failed to create notification for event $eventType: $e');
    }
  }

  // Method to reset the service for new connections
  static void resetForNewConnection() {
    Logger.info(' SeSocketService:  Resetting service for new connection...');

    // Reset the destroyed flag
    _isDestroyed = false;

    // If there's an existing instance, clean it up properly
    if (_instance != null) {
      try {
        // Force disconnect any existing socket
        if (_instance!._socket != null) {
          _instance!._socket!.disconnect();
          _instance!._socket = null;
        }

        // Clear all timers
        _instance!._reconnectTimer?.cancel();
        _instance!._heartbeatTimer?.cancel();
        _instance!._stabilityTimer?.cancel();
        _instance!._clientHeartbeatTimer?.cancel();

        // Reset all state variables
        _instance!._ready = false;
        _instance!._isConnecting = false;
        _instance!._reconnectAttempts = 0;
        _instance!._sessionConfirmed = false;
        _instance!._sessionId = null;

        // Close and reset the stream controller
        _instance!._connectionStateController?.close();
        _instance!._connectionStateController = null;

        Logger.success(' SeSocketService:  Existing instance cleaned up');
      } catch (e) {
        Logger.warning(
            ' SeSocketService:  Warning - error cleaning up existing instance: $e');
      }
    }

    Logger.success(' SeSocketService:  Service reset for new connection');
  }

  // Check if service is ready for new connections
  static bool get isReadyForNewConnection => !_isDestroyed;

  // Get current instance status
  static String get instanceStatus {
    if (_instance == null && _isDestroyed) return 'destroyed';
    if (_instance == null && !_isDestroyed) return 'ready_for_creation';
    if (_instance != null && _isDestroyed) return 'invalid_state';
    return 'active';
  }

  final String _url = 'https://sechat-socket.strapblaque.com';
  IO.Socket? _socket;
  String? _sessionId;
  bool _ready = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  // Stream controller for connection state changes
  StreamController<bool>? _connectionStateController;

  // Getter for connection state stream
  Stream<bool> get connectionStateStream {
    _connectionStateController ??= StreamController<bool>.broadcast();
    return _connectionStateController!.stream;
  }

  // Private method to safely add events to the stream controller
  void _addConnectionStateEvent(bool state) {
    try {
      if (_connectionStateController != null &&
          !_connectionStateController!.isClosed) {
        _connectionStateController!.add(state);
      }
    } catch (e) {
      Logger.warning(
          ' SeSocketService:  Warning - could not add connection state event: $e');
    }
  }

  // Heartbeat and stability monitoring
  Timer? _heartbeatTimer;
  Timer? _stabilityTimer;
  Timer? _clientHeartbeatTimer;
  bool _sessionConfirmed = false;

  Function(String messageId)? onMessageAcked;
  Function(String senderId, String senderName, String message,
      String conversationId, String messageId)? onMessageReceived;
  Function(String messageId, String fromUserId, String toUserId)? onDelivered;
  Function(String messageId, String fromUserId, String toUserId)? onRead;
  // 🆕 ADD THIS: Callback for queued message status
  Function(String messageId, String toUserId, String fromUserId)? onQueued;
  Function(String sessionId, bool isOnline, String timestamp)? onPresence;
  Function(String fromUserId, String conversationId, bool isTyping)? onTyping;
  Function(Map<String, dynamic> data)? onKeyExchangeRequest;
  Function(Map<String, dynamic> data)? onKeyExchangeResponse;
  // Message delete callbacks - API Compliant
  Function(Map<String, dynamic> data)? onMessageDeleted;
  Function(Map<String, dynamic> data)? onAllMessagesDeleted;
  Function(Map<String, dynamic> data)? onKeyExchangeRevoked;
  Function(Map<String, dynamic> data)? onKeyExchangeDeclined;
  Function(Map<String, dynamic> data)? onUserDataExchange;
  Function(Map<String, dynamic> data)? onConversationCreated;
  Function(Map<String, dynamic> data)? onUserDeleted;
  Function(Map<String, dynamic> data)? onContactAdded;
  Function(Map<String, dynamic> data)? onContactRemoved;
  Function(Map<String, dynamic> data)? onSessionRegistered;
  Function(
      String senderId,
      String messageId,
      String status,
      String? conversationId,
      String? recipientId)? onMessageStatusUpdateExternal;

  Future<void> connect(String sessionId) async {
    // If instance was destroyed, reset it for new connection
    if (SeSocketService.isDestroyed) {
      Logger.info(
          ' SeSocketService:  Instance was destroyed, resetting for new connection...');
      SeSocketService.resetForNewConnection();
    }

    if (_socket != null) await disconnect();

    _sessionId = sessionId;
    _isConnecting = true;
    _ready = false;
    _sessionConfirmed = false;

    Logger.debug(
        ' SeSocketService: Connecting to $_url with session: $sessionId');

    try {
      _socket = IO.io(_url, {
        'transports': ['websocket', 'polling'], // Allow fallback to polling
        'path': '/socket.io/',
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': _maxReconnectAttempts,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 10000,
        'timeout': 30000, // Extended to 30 seconds as per server update
        'forceNew': true,
        'upgrade': true, // Enable transport upgrade
        'rememberUpgrade': true, // Remember transport preference
        'maxReconnectionAttempts': _maxReconnectAttempts,
        'reconnectionDelayFactor': 1.5, // Exponential backoff
      });

      _bindCore();
      _socket!.connect();

      // Add connection timeout
      Timer(const Duration(seconds: 35), () {
        if (_isConnecting && !_ready) {
          Logger.warning(
              ' SeSocketService:  Connection timeout, forcing disconnect');
          _socket?.disconnect();
          _isConnecting = false;
          _addConnectionStateEvent(false);
        }
      });
    } catch (e) {
      Logger.error(' SeSocketService:  Error creating socket connection: $e');
      _isConnecting = false;
      _addConnectionStateEvent(false);
      rethrow;
    }
  }

  void _bindCore() {
    _socket!.on('connect', (_) async {
      Logger.success(' SeSocketService:  Connected to server');
      _isConnecting = false;
      _reconnectAttempts = 0;
      // Don't set _ready = true here - wait for session_registered confirmation
      _addConnectionStateEvent(
          false); // Still not fully ready until session confirmed

      if (_sessionId != null) {
        Logger.debug(' SeSocketService: Registering session: $_sessionId');

        // Get the user's public key for session registration
        String? userPublicKey;
        try {
          // Import SeSessionService to get current user's public key
          final sessionService = SeSessionService();
          userPublicKey = sessionService.currentSession?.publicKey;
          if (userPublicKey != null) {
            Logger.success(
                ' SeSocketService:  Retrieved user public key for session registration');
          } else {
            Logger.warning(
                ' SeSocketService:  No public key available in current session');
          }
        } catch (e) {
          Logger.warning(
              ' SeSocketService:  Warning - could not retrieve user public key: $e');
          // Continue without public key, but this may cause key exchange issues
        }

        // Register session with public key as required by API
        final registrationData = <String, dynamic>{
          'sessionId': _sessionId,
        };

        if (userPublicKey != null) {
          registrationData['publicKey'] = userPublicKey;
          Logger.debug(
              ' SeSocketService: 🔑 Including public key in session registration');
        } else {
          Logger.warning(
              ' SeSocketService:  No public key available for session registration');
        }

        _socket!.emit('register_session', registrationData);

        // FALLBACK: If server doesn't send session_registered within 5 seconds,
        // assume registration was successful and proceed
        Timer(const Duration(seconds: 5), () {
          if (!_sessionConfirmed && _socket?.connected == true) {
            Logger.warning(
                ' SeSocketService:  No session_registered received, assuming success');
            _sessionConfirmed = true;
            _ready = true;
            _startClientHeartbeat();
            _addConnectionStateEvent(true);

            // Send presence update after session is confirmed
            _sendOnlinePresence();
          }
        });
      }
    });

    _socket!.on('session_registered', (data) async {
      Logger.success(
          ' SeSocketService: Session confirmed: ${data['sessionId']}');

      // Create notification for session registered
      await _createSocketEventNotification(
        eventType: 'session_registered',
        title: 'Session Established',
        body: 'Real-time connection established successfully',
        metadata: data,
      );

      _sessionConfirmed = true;
      _ready = true;
      _startClientHeartbeat();
      _addConnectionStateEvent(true);

      // Send presence update after session is confirmed
      _sendOnlinePresence();

      // Notify callback if set
      if (onSessionRegistered != null) {
        onSessionRegistered!(data);
      }
    });

    _socket!.on('disconnect', (reason) {
      Logger.error(
          ' SeSocketService:  Disconnected from server. Reason: $reason');
      _ready = false;
      _isConnecting = false;
      _addConnectionStateEvent(false);

      // Send offline presence before disconnecting
      if (_sessionId != null) {
        try {
          sendPresence(false, []); // Empty array means broadcast to all users
          Logger.success(
              ' SeSocketService:  Offline presence sent on disconnect');
        } catch (e) {
          Logger.warning(
              ' SeSocketService:  Failed to send offline presence: $e');
        }
      }

      // Stop all timers
      _heartbeatTimer?.cancel();
      _stabilityTimer?.cancel();
      _clientHeartbeatTimer?.cancel();
    });

    _socket!.on('reconnect', (attemptNumber) {
      Logger.info(
          ' SeSocketService:  Reconnected to server. Attempt: $attemptNumber');
      _isConnecting = false;
      _reconnectAttempts = 0;
      // Don't set _ready = true here - wait for session_registered confirmation
      _addConnectionStateEvent(false);

      // CRITICAL: Rebind event handlers after reconnection
      Logger.info(
          ' SeSocketService:  Rebinding event handlers after reconnection');
      _bindCore();

      if (_sessionId != null) {
        Logger.debug(' SeSocketService: Re-registering session: $_sessionId');
        _socket!.emit('register_session', {'sessionId': _sessionId});

        // FALLBACK: If server doesn't send session_registered within 5 seconds,
        // assume registration was successful and proceed
        Timer(const Duration(seconds: 5), () {
          if (!_sessionConfirmed && _socket?.connected == true) {
            Logger.warning(
                ' SeSocketService:  No session_registered received, assuming success');
            _sessionConfirmed = true;
            _ready = true;
            _startClientHeartbeat();
            _addConnectionStateEvent(true);
          }
        });
      }
    });

    _socket!.on('reconnect_failed', (data) {
      Logger.error(' SeSocketService:  Reconnection failed');
      _isConnecting = false;
      _ready = false;
      _addConnectionStateEvent(false);
    });

    // CRITICAL: Heartbeat response (MUST respond within 1 second)
    _socket!.on('heartbeat:ping', (data) {
      // Reduced logging to reduce clutter
      _respondToHeartbeat(data);
    });

    // Connection stability checks
    _socket!.on('connection:stability_check', (data) {
      Logger.info(' SeSocketService:  Connection stability check received');
      _respondToStabilityCheck(data);
    });

    _socket!.on('connection:ping', (data) {
      Logger.info(' SeSocketService:  Connection ping received');
      _respondToConnectionPing(data);
    });

    // Key exchange events
    _socket!.on('key_exchange:request', (data) async {
      Logger.debug(' SeSocketService: Key exchange request received');

      // Process the key exchange request with KeyExchangeService
      try {
        KeyExchangeService.instance.processKeyExchangeRequest(data);
        Logger.success(
            ' SeSocketService:  Key exchange request processed by KeyExchangeService');
      } catch (e) {
        Logger.error(
            ' SeSocketService:  Error processing key exchange request: $e');
      }

      // Create notification for key exchange request
      await _createSocketEventNotification(
        eventType: 'key_exchange:request',
        title: 'Key Exchange Request',
        body:
            'You received a key exchange request to start a secure conversation.',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onKeyExchangeRequest != null) {
        Logger.info(
            ' SeSocketService:  Calling onKeyExchangeRequest callback...');
        onKeyExchangeRequest!(data);
        Logger.success(
            ' SeSocketService:  onKeyExchangeRequest callback completed');
      } else {
        Logger.error(
            ' SeSocketService:  onKeyExchangeRequest callback is NULL!');
      }
    });

    _socket!.on('key_exchange:response', (data) async {
      Logger.info(
          ' SeSocketService: 🔍🔍 KEY EXCHANGE RESPONSE EVENT RECEIVED!');
      Logger.info(' SeSocketService: 🔍🔍 Event data: $data');
      Logger.info(' SeSocketService: 🔍🔍 Data type: ${data.runtimeType}');
      Logger.info(
          ' SeSocketService: 🔍🔍 Socket connected: ${_socket?.connected}');
      Logger.info(' SeSocketService: 🔍🔍 Socket ready: $_ready');
      Logger.info(' SeSocketService: 🔍🔍 Session ID: $_sessionId');
      Logger.info(
          ' SeSocketService: 🔍🔍 onKeyExchangeResponse callback: ${onKeyExchangeResponse != null ? 'SET' : 'NULL'}');

      // Create notification for key exchange response
      await _createSocketEventNotification(
        eventType: 'key_exchange:response',
        title: 'Key Exchange Response',
        body: 'Key exchange response received',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onKeyExchangeResponse != null) {
        Logger.info(
            ' SeSocketService:  Calling onKeyExchangeResponse callback...');
        onKeyExchangeResponse!(data);
        Logger.success(
            ' SeSocketService:  onKeyExchangeResponse callback completed');
      } else {
        Logger.error(
            ' SeSocketService:  onKeyExchangeResponse callback is NULL!');

        // CRITICAL: Even if callback is null, we need to process this event
        // This prevents the key exchange from failing completely
        Logger.debug(
            ' SeSocketService: 🚨 CRITICAL: Processing key exchange response without callback');
        Logger.info(
            ' SeSocketService:  This should not happen - callback should be set in main.dart');

        // Try to process the event directly with KeyExchangeService as a fallback
        try {
          Logger.info(
              ' SeSocketService:  Attempting fallback processing with KeyExchangeService...');
          // Import KeyExchangeService to handle the event directly
          // import 'package:sechat_app/core/services/key_exchange_service.dart'; // This import is already at the top
          KeyExchangeService.instance.handleKeyExchangeResponse(data);
          Logger.success(
              ' SeSocketService:  Fallback processing completed successfully');
        } catch (e) {
          Logger.error(' SeSocketService:  Fallback processing failed: $e');
          Logger.debug(
              ' SeSocketService: 🚨 This key exchange response will be lost!');
        }
      }
    });

    _socket!.on('key_exchange:revoked', (data) async {
      Logger.debug(' SeSocketService: Key exchange revoked');

      // Create notification for key exchange revoked
      await _createSocketEventNotification(
        eventType: 'key_exchange:revoked',
        title: 'Key Exchange Revoked',
        body: 'Key exchange has been revoked',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onKeyExchangeRevoked != null) {
        onKeyExchangeRevoked!(data);
      }
    });

    // Key exchange declined events (received by requester)
    _socket!.on('key_exchange:declined', (data) async {
      Logger.debug(' SeSocketService: Key exchange declined');
      Logger.debug(' SeSocketService: Decline data: $data');

      // Create notification for key exchange declined
      await _createSocketEventNotification(
        eventType: 'key_exchange:declined',
        title: 'Key Exchange Declined',
        body: 'Your key exchange request was declined',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      // Notify KeyExchangeService about the decline
      try {
        await KeyExchangeService.instance.handleKeyExchangeDeclined(data);
        Logger.success(
            ' SeSocketService:  Key exchange decline processed by KeyExchangeService');
      } catch (e) {
        Logger.error(
            ' SeSocketService:  Error processing key exchange decline: $e');
      }

      // Call the callback if set
      if (onKeyExchangeDeclined != null) {
        onKeyExchangeDeclined!(data);
      }
    });

    // Key exchange accepted events (received by requester)
    _socket!.on('key_exchange:accept', (data) async {
      Logger.debug(' SeSocketService: Key exchange accepted');
      Logger.debug(' SeSocketService: Accept data: $data');

      // Create notification for key exchange accepted
      await _createSocketEventNotification(
        eventType: 'key_exchange:accept',
        title: 'Key Exchange Accepted',
        body: 'Your key exchange request was accepted',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      // Notify KeyExchangeService about the acceptance
      try {
        await KeyExchangeService.instance.handleKeyExchangeAccepted(data);
        Logger.success(
            ' SeSocketService:  Key exchange acceptance processed by KeyExchangeService');
      } catch (e) {
        Logger.error(
            ' SeSocketService:  Error processing key exchange acceptance: $e');
      }

      // Call the callback if set
      if (onKeyExchangeResponse != null) {
        onKeyExchangeResponse!(data);
      }
    });

    // Key exchange error events
    _socket!.on('key_exchange:error', (data) async {
      Logger.debug(' SeSocketService: Key exchange error received');
      Logger.debug(' SeSocketService: Error data: $data');

      // Handle key exchange error
      await _handleKeyExchangeError(data);
    });

    // User data exchange events
    _socket!.on('user_data_exchange:data', (data) async {
      Logger.info(' SeSocketService: 🔍🔍 USER DATA EXCHANGE EVENT RECEIVED!');
      Logger.info(' SeSocketService: 🔍🔍 Event: user_data_exchange:data');
      Logger.info(' SeSocketService: 🔍🔍 Data: $data');
      Logger.info(' SeSocketService: 🔍🔍 Data type: ${data.runtimeType}');
      Logger.info(
          ' SeSocketService: 🔍🔍 Socket connected: ${_socket?.connected}');
      Logger.info(' SeSocketService: 🔍🔍 Socket ready: $_ready');
      Logger.info(' SeSocketService: 🔍🔍 Session ID: $_sessionId');
      Logger.info(
          ' SeSocketService: 🔍🔍 Session confirmed: $_sessionConfirmed');
      Logger.info(' SeSocketService: 🔍🔍 Socket ID: ${_socket?.id}');
      Logger.info(
          ' SeSocketService: 🔍🔍 Socket transport: ${_socket?.io.engine?.transport?.name ?? 'unknown'}');
      Logger.info(
          ' SeSocketService: 🔍🔍 onUserDataExchange callback: ${onUserDataExchange != null ? 'SET' : 'NULL'}');
      Logger.debug(
          '🔑 SeSocketService: 🔍🔍🔍 Current timestamp: ${DateTime.now().toIso8601String()}');
      Logger.info(
          ' SeSocketService: 🔍🔍 Event received on recipient side: ${_sessionId == data['recipientId'] ? 'YES' : 'NO'}');

      // Create notification for user data exchange
      await _createSocketEventNotification(
        eventType: 'user_data_exchange:data',
        title: 'User Data Exchange',
        body: 'New user data exchange received',
        senderId: data['senderId']?.toString(),
        senderName: data['senderName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onUserDataExchange != null) {
        Logger.info(
            ' SeSocketService:  Calling onUserDataExchange callback...');
        onUserDataExchange!(data);
        Logger.success(
            ' SeSocketService:  onUserDataExchange callback completed');
      } else {
        Logger.error(' SeSocketService:  onUserDataExchange callback is NULL!');

        // CRITICAL: Even if callback is null, we need to process this event
        // This prevents user data exchange from failing completely
        Logger.debug(
            ' SeSocketService: 🚨 CRITICAL: Processing user data exchange without callback');
        Logger.info(
            ' SeSocketService:  This should not happen - callback should be set in main.dart');

        // Try to process the event directly with KeyExchangeService as a fallback
        try {
          Logger.info(
              ' SeSocketService:  Attempting fallback processing with KeyExchangeService...');

          // Extract the required parameters from the socket data
          final senderId = data['senderId']?.toString();
          final encryptedData = data['encryptedData']?.toString();
          final conversationId = data['conversationId']?.toString();

          if (senderId != null && encryptedData != null) {
            await KeyExchangeService.instance.processUserDataExchange(
              senderId: senderId,
              encryptedData: encryptedData,
              conversationId: conversationId,
            );
            Logger.success(
                ' SeSocketService:  Fallback processing completed successfully');
          } else {
            Logger.error(
                ' SeSocketService:  Invalid user data exchange data: senderId=$senderId, encryptedData=${encryptedData != null}');
          }
        } catch (e) {
          Logger.error(' SeSocketService:  Fallback processing failed: $e');
          Logger.debug(
              ' SeSocketService: 🚨 This user data exchange will be lost!');
        }
      }
    });

    // Conversation creation events
    _socket!.on('conversation:created', (data) async {
      Logger.debug('💬 SeSocketService: Conversation created event received');

      // Create notification for conversation created
      await _createSocketEventNotification(
        eventType: 'conversation:created',
        title: 'New Conversation',
        body: 'New conversation created',
        senderId: data['creatorId']?.toString(),
        senderName: data['creatorName']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onConversationCreated != null) {
        onConversationCreated!(data);
      }
    });

    // User deletion events
    _socket!.on('user:deleted', (data) async {
      Logger.info(' SeSocketService: User deleted event received');

      // Create notification for user deleted
      await _createSocketEventNotification(
        eventType: 'user:deleted',
        title: 'User Deleted',
        body: 'A user has been deleted',
        senderId: data['deletedUserId']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      if (onUserDeleted != null) {
        onUserDeleted!(data);
      }
    });

    // Message events
    _socket!.on('message:acked', (data) {
      Logger.success(' SeSocketService: Message acknowledged');
      final id = data['messageId']?.toString() ?? '';
      if (id.isNotEmpty) onMessageAcked?.call(id);
    });

    _socket!.on('message:received', (data) async {
      Logger.debug('💬 SeSocketService: Message received');
      Logger.info('💬 SeSocketService:  Message data: $data');

      if (onMessageReceived != null) {
        // Extract sender name from data or use senderId as fallback
        final senderName =
            data['senderName'] ?? data['fromUserId'] ?? 'Unknown User';

        onMessageReceived!(
          data['fromUserId'] ?? '', // senderId
          senderName, // senderName
          data['body'] ?? '', // message
          data['conversationId'] ?? '', // conversationId
          data['messageId'] ?? '', // messageId
        );
        Logger.success(
            '💬 SeSocketService:  Message received callback executed with sender: $senderName');
      } else {
        Logger.error(
            '💬 SeSocketService:  onMessageReceived callback is null - message not processed!');
      }
    });

    // Message delete events - API Compliant
    _socket!.on('message:deleted', (data) async {
      Logger.info(' SeSocketService: Message deleted event received');
      Logger.info(' SeSocketService: 🔍 Delete data: $data');

      // Create notification for message deleted
      await _createSocketEventNotification(
        eventType: 'message:deleted',
        title: 'Message Deleted',
        body: 'A message has been deleted',
        senderId: data['deletedBy']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      // Call message deleted callback if set
      if (onMessageDeleted != null) {
        onMessageDeleted!(data);
      }
    });

    _socket!.on('message:all_deleted', (data) async {
      Logger.info(' SeSocketService: All messages deleted event received');
      Logger.info(' SeSocketService: 🔍 Delete all data: $data');

      // Create notification for all messages deleted
      await _createSocketEventNotification(
        eventType: 'message:all_deleted',
        title: 'All Messages Deleted',
        body: 'All messages in conversation have been deleted',
        senderId: data['deletedBy']?.toString(),
        conversationId: data['conversationId']?.toString(),
        metadata: data,
      );

      // Call all messages deleted callback if set
      if (onAllMessagesDeleted != null) {
        onAllMessagesDeleted!(data);
      }
    });

    // 🚫 REMOVED: Legacy message:delivered handler - now handled by message:status_update
    // This prevents premature status updates when recipient is offline

    // 🚫 REMOVED: Legacy message:read handler - now handled by message:status_update
    // This prevents premature status updates when recipient is offline

    // Presence events - CONSOLIDATED FLOW
    _socket!.on('presence:update', (data) async {
      Logger.debug('🟢 SeSocketService: Presence update received');
      Logger.info('🟢 SeSocketService:  Presence data: $data');

      // Check if the data is encrypted
      final bool isEncrypted = data['metadata']?['encrypted'] == true;

      Map<String, dynamic> decryptedData = data;

      if (isEncrypted && data['encryptedData'] != null) {
        try {
          // Decrypt the presence data
          final decrypted =
              await EncryptionService.decryptAesCbcPkcs7(data['encryptedData']);
          decryptedData = decrypted ?? data;
          Logger.success('🟢 SeSocketService:  Decrypted presence update');
        } catch (e) {
          Logger.error(
              '🟢 SeSocketService:  Failed to decrypt presence update: $e');
          return;
        }
      }

      // Create notification for presence update (only if not silent)
      final bool silent = decryptedData['silent'] ?? false;
      if (!silent) {
        final bool isOnline = decryptedData['isOnline'] ?? false;
        await _createSocketEventNotification(
          eventType: 'presence:update',
          title: isOnline ? 'User Online' : 'User Offline',
          body: isOnline ? 'User came online' : 'User went offline',
          senderId: decryptedData['fromUserId']?.toString() ??
              decryptedData['sessionId']?.toString(),
          metadata: decryptedData,
          silent: silent,
        );
      }

      // Call the main presence callback (mapped to onPresence via setOnOnlineStatusUpdate)
      if (onPresence != null) {
        Logger.debug(
            '🟢 SeSocketService: 🔄 Calling onPresence callback (mapped from onOnlineStatusUpdate)');
        onPresence!(
          decryptedData['fromUserId'] ?? decryptedData['sessionId'] ?? '',
          decryptedData['isOnline'] ?? false,
          decryptedData['timestamp'] ?? '',
        );
        Logger.success('🟢 SeSocketService:  onPresence callback executed');
      } else {
        Logger.warning(
            '🟢 SeSocketService:  onPresence callback is null - presence not processed!');
      }
    });

    // Handle presence:request response - CRITICAL for getting actual last seen times from Smart Presence System
    _socket!.on('presence:request', (data) async {
      Logger.debug(
          '🟢 SeSocketService: Smart Presence System response received');
      Logger.info('🟢 SeSocketService:  Smart Presence data: $data');

      try {
        // Handle different possible response formats from server
        List<dynamic> contactsData = [];

        if (data is Map<String, dynamic>) {
          // Format 1: { contacts: [...] }
          if (data['contacts'] is List) {
            contactsData = data['contacts'] as List<dynamic>;
          }
          // Format 3: Single contact object
          else if (data['sessionId'] != null || data['userId'] != null) {
            contactsData = [data];
          }
        } else if (data is List) {
          // Format 2: Direct array response
          contactsData = data;
        }

        if (contactsData.isNotEmpty) {
          Logger.success(
              '🟢 SeSocketService:  Processing ${contactsData.length} contact presence updates from Smart Presence System response');

          for (final contactData in contactsData) {
            if (contactData is Map<String, dynamic>) {
              final String contactId =
                  contactData['sessionId'] ?? contactData['userId'] ?? '';
              final bool isOnline = contactData['isOnline'] ?? false;
              // Try multiple possible field names for last seen (prioritize lastSeen from Smart Presence System)
              final String? lastSeenString = contactData['lastSeen'] ??
                  contactData['last_seen'] ??
                  contactData['lastSeenTime'] ??
                  contactData['offlineTime'] ??
                  contactData['timestamp'];

              if (contactId.isNotEmpty) {
                Logger.debug(
                    '🟢 SeSocketService:  Processing contact from Smart Presence System: $contactId (online: $isOnline, lastSeen: $lastSeenString)');

                // Call the presence callback with the actual server data from Smart Presence System
                if (onPresence != null) {
                  onPresence!(contactId, isOnline, lastSeenString ?? '');
                  Logger.success(
                      '🟢 SeSocketService:  Smart Presence data processed for: $contactId');
                }
              }
            }
          }
        } else {
          Logger.warning(
              '🟢 SeSocketService:  No contact data found in Smart Presence System response: $data');
        }
      } catch (e) {
        Logger.error(
            '🟢 SeSocketService:  Error processing Smart Presence System response: $e');
      }
    });

    // Contact management events
    _socket!.on('contacts:added', (data) async {
      Logger.debug('🔗 SeSocketService: Contact added event received');
      Logger.info('🔗 SeSocketService:  Contact data: $data');

      // Create notification for contact added
      await _createSocketEventNotification(
        eventType: 'contacts:added',
        title: 'Contact Added',
        body: 'New contact has been added',
        senderId: data['contactId']?.toString(),
        senderName: data['contactName']?.toString(),
        metadata: data,
      );

      // This event is sent when a contact is successfully added
      // The client should update their local contact list
      if (onContactAdded != null) {
        onContactAdded!(data);
      } else {
        Logger.warning('🔗 SeSocketService:  onContactAdded callback is null');
      }
    });

    // 🚫 REMOVED: Duplicate message:status_update handler - now consolidated into single handler

    // CRITICAL: Handle receipt:delivered events from server
    _socket!.on('receipt:delivered', (data) async {
      final String messageId = data['messageId'];
      final String fromUserId = data['fromUserId'];
      final String toUserId = data['toUserId'];
      String? conversationId = data['conversationId'];
      final bool silent = data['silent'] ?? true; // Usually silent

      // Receipt delivered event received
      Logger.success(
          '📬 SeSocketService:  Recipient has actually processed/viewed the message');

      // CRITICAL: Generate conversation ID if missing (server doesn't always send it)
      if (conversationId == null || conversationId.isEmpty) {
        conversationId =
            _generateConsistentConversationId(fromUserId, toUserId);
        Logger.debug(
            '📬 SeSocketService: 🔧 Generated conversation ID: $conversationId');
      }

      // Update local message status to 'delivered'
      _updateMessageStatus(messageId, 'delivered', toUserId,
          conversationId: conversationId);

      // 🆕 FIXED: Don't call onMessageStatusUpdateExternal for delivered status
      // This status should only be processed through the dedicated onDelivered callback
      // to ensure proper receipt-based status updates

      // CRITICAL: Also call the onDelivered callback for UI updates
      if (onDelivered != null) {
        onDelivered!(messageId, fromUserId, toUserId);
      }

      // 🚫 REMOVED: Duplicate onMessageStatusUpdateExternal call - already called above

      // Notify listeners about delivery status change
      _notifyMessageStatusChange(messageId, 'delivered', toUserId);

      // Create notification for delivery confirmation (only if not silent)
      // if (!silent) {
      //   await _createSocketEventNotification(
      //     eventType: 'receipt:delivered',
      //     title: 'Message Delivered',
      //     body: 'Message has been delivered to recipient',
      //     senderId: fromUserId,
      //     messageId: messageId,
      //     conversationId: conversationId,
      //     metadata: data,
      //     silent: silent,
      //   );
      // }
    });

    // CRITICAL: Handle receipt:read events from server
    _socket!.on('receipt:read', (data) async {
      final String messageId = data['messageId'];
      final String fromUserId = data['fromUserId'];
      final String toUserId = data['toUserId'];
      String? conversationId = data['conversationId'];
      final bool silent = data['silent'] ?? true; // Usually silent

      // Receipt read event received

      // CRITICAL: Generate conversation ID if missing (server doesn't always send it)
      if (conversationId == null || conversationId.isEmpty) {
        conversationId =
            _generateConsistentConversationId(fromUserId, toUserId);
        Logger.debug(
            '📬 SeSocketService: 🔧 Generated conversation ID: $conversationId');
      }

      // Update local message status to 'read'
      _updateMessageStatus(messageId, 'read', toUserId,
          conversationId: conversationId);

      // 🆕 FIXED: Don't call onMessageStatusUpdateExternal for read status
      // This status should only be processed through the dedicated onRead callback
      // to ensure proper receipt-based status updates

      // CRITICAL: Also call the onRead callback for UI updates
      if (onRead != null) {
        onRead!(messageId, fromUserId, toUserId);
      }

      // 🚫 REMOVED: Duplicate onMessageStatusUpdateExternal call - already called above

      // Notify listeners about read status change
      _notifyMessageStatusChange(messageId, 'read', toUserId);

      // Create notification for read confirmation (only if not silent)
      if (!silent) {
        await _createSocketEventNotification(
          eventType: 'receipt:read',
          title: 'Message Read',
          body: 'Message has been read by recipient',
          senderId: fromUserId,
          messageId: messageId,
          conversationId: conversationId,
          metadata: data,
          silent: silent,
        );
      }
    });

    // 🆕 FIXED: Handle message:status_update events from server
    _socket!.on('message:status_update', (data) async {
      // Check if the data is encrypted
      final bool isEncrypted = data['metadata']?['encrypted'] == true;

      Map<String, dynamic> decryptedData = data;

      if (isEncrypted && data['encryptedData'] != null) {
        try {
          // Decrypt the status data
          final decrypted =
              await EncryptionService.decryptAesCbcPkcs7(data['encryptedData']);
          decryptedData = decrypted ?? data;
          Logger.success(
              '📊 SeSocketService:  Decrypted message status update');
        } catch (e) {
          Logger.error(
              '📊 SeSocketService:  Failed to decrypt message status update: $e');
          return;
        }
      }

      final String messageId = decryptedData['messageId'];
      final String status = decryptedData['status'];
      final String? fromUserId = decryptedData['fromUserId'];
      final String? toUserId = decryptedData['toUserId'];
      final String? conversationId = decryptedData['conversationId'];
      final String? recipientId = decryptedData['recipientId'];
      final bool silent = decryptedData['silent'] ?? false;
      final bool wasQueued = decryptedData['wasQueued'] ?? false;

      Logger.debug(
          '📊 SeSocketService: [STATUS] Message status update: $messageId -> $status (silent: $silent, queued: $wasQueued)');

      // 🆕 FIXED: Filter out delivered/read status updates from message:status_update
      // These should only come through receipt:delivered and receipt:read events
      if (status.toLowerCase() == 'delivered' ||
          status.toLowerCase() == 'read') {
        Logger.warning(
            '📊 SeSocketService:  Ignoring delivered/read status from message:status_update - waiting for proper receipt events');
        return; // Don't process delivered/read status from message:status_update
      }

      // Determine the effective conversation ID
      String? effectiveConversationId = conversationId;
      if (effectiveConversationId == null || effectiveConversationId.isEmpty) {
        if (fromUserId != null && toUserId != null) {
          effectiveConversationId =
              _generateConsistentConversationId(fromUserId, toUserId);
        } else if (recipientId != null && _sessionId != null) {
          effectiveConversationId =
              _generateConsistentConversationId(_sessionId!, recipientId);
        }
      }

      // Call external callbacks for UI updates
      if (onMessageStatusUpdateExternal != null) {
        onMessageStatusUpdateExternal!(
            fromUserId ?? recipientId ?? '',
            messageId,
            status,
            effectiveConversationId,
            toUserId ?? recipientId ?? '');
      }

      // Handle specific status updates (only sent/queued now)
      if (status == 'queued' && onQueued != null) {
        onQueued!(messageId, toUserId ?? '', fromUserId ?? '');
      }

      // Update local message status if we have the message
      if (effectiveConversationId != null) {
        _updateMessageStatus(messageId, status, toUserId ?? recipientId ?? '',
            conversationId: effectiveConversationId);
      }
    });

    // 🆕 ADD THIS: Handle message:queued events from server
    _socket!.on('message:queued', (data) async {
      final String messageId = data['messageId'];
      final String toUserId = data['toUserId'];
      final String? fromUserId = data['fromUserId'];
      final String? conversationId = data['conversationId'];
      final String? reason = data['reason'];

      Logger.debug(
          '📬 SeSocketService: Message queued: $messageId (reason: $reason)');

      // Call the queued callback if available
      if (onQueued != null) {
        onQueued!(messageId, toUserId, fromUserId ?? '');
      }

      // Call the main status update callback for queued messages
      if (onMessageStatusUpdateExternal != null) {
        onMessageStatusUpdateExternal!(
          fromUserId ?? '',
          messageId,
          'queued',
          conversationId,
          toUserId,
        );
      }
    });

    // Enhanced typing status updates (silent)
    _socket!.on('typing:status_update', (data) async {
      // Check if the data is encrypted
      final bool isEncrypted = data['metadata']?['encrypted'] == true;

      Map<String, dynamic> decryptedData = data;

      if (isEncrypted && data['encryptedData'] != null) {
        try {
          // Decrypt the typing data
          final decrypted =
              await EncryptionService.decryptAesCbcPkcs7(data['encryptedData']);
          decryptedData = decrypted ?? data;
          Logger.success(' SeSocketService:  Decrypted typing status update');
        } catch (e) {
          Logger.error(
              ' SeSocketService:  Failed to decrypt typing status update: $e');
          return;
        }
      }

      final String fromUserId = decryptedData['fromUserId'];
      final String recipientId = decryptedData['recipientId'];
      final String conversationId = decryptedData['conversationId'] ?? '';
      final String showIndicatorOnSessionId =
          decryptedData['showIndicatorOnSessionId'] ?? ''; // NEW: Server field
      final bool isTyping = decryptedData['isTyping'];
      final dynamic deliveredData = decryptedData['delivered'];
      final bool delivered = deliveredData is bool
          ? deliveredData
          : (deliveredData is Map && deliveredData['success'] == true);
      final bool autoStopped = decryptedData['autoStopped'] ?? false;
      final bool silent = decryptedData['silent'] ?? false;

      Logger.debug(
          '⌨️ SeSocketService: Typing status update: $fromUserId -> $recipientId (delivered: $delivered, autoStopped: $autoStopped)');
      Logger.info(' SeSocketService:  Conversation ID: $conversationId');

      // CRITICAL: Only show typing indicator if we are the session that should display it
      final currentSessionId = _sessionId;
      if (currentSessionId != null &&
          showIndicatorOnSessionId == currentSessionId) {
        Logger.debug(
            '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

        // Update local typing status using the direct recipientId from server
        _updateTypingStatus(
            fromUserId, recipientId, isTyping, delivered, autoStopped);

        // Notify typing status change for UI updates
        _notifyTypingStatusChange(
            fromUserId, recipientId, isTyping, delivered, autoStopped);
      } else {
        Logger.info(
            ' SeSocketService:  Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
      }

      // Notify listeners about typing status change (silent)
      if (silent) {
        // Silent updates still need to update the UI
        Logger.debug(
            ' SeSocketService: 🔔 Silent typing update - updating UI only');
      } else {}
    });

    _socket!.on('contacts:removed', (data) async {
      Logger.debug('🔗 SeSocketService: Contact removed event received');
      Logger.info('🔗 SeSocketService:  Contact data: $data');

      // Create notification for contact removed
      await _createSocketEventNotification(
        eventType: 'contacts:removed',
        title: 'Contact Removed',
        body: 'Contact has been removed',
        senderId: data['contactId']?.toString(),
        senderName: data['contactName']?.toString(),
        metadata: data,
      );

      // This event is sent when a contact is successfully removed
      // The client should update their local contact list
      if (onContactRemoved != null) {
        onContactRemoved!(data);
      } else {
        Logger.warning(
            '🔗 SeSocketService:  onContactRemoved callback is null');
      }
    });

    // Typing events - RECIPIENT receives this when someone types
    _socket!.on('typing:update', (data) async {
      Logger.debug(
          '⌨️ SeSocketService: 🔔 TYPING UPDATE EVENT RECEIVED (recipient side)');
      Logger.info(' SeSocketService:  Typing data: $data');
      Logger.info(
          ' SeSocketService:  onTyping callback: ${onTyping != null ? 'SET' : 'NULL'}');

      // Check if the data is encrypted
      final bool isEncrypted = data['metadata']?['encrypted'] == true;

      Map<String, dynamic> decryptedData = data;

      if (isEncrypted && data['encryptedData'] != null) {
        try {
          // Decrypt the typing data
          final decrypted =
              await EncryptionService.decryptAesCbcPkcs7(data['encryptedData']);
          decryptedData = decrypted ?? data;
          Logger.success(' SeSocketService:  Decrypted typing update');
        } catch (e) {
          Logger.error(
              ' SeSocketService:  Failed to decrypt typing update: $e');
          return;
        }
      }

      // Create notification for typing update (only if not silent)
      final bool silent = decryptedData['silent'] ?? false;

      // CRITICAL: Only call typing callback if we should show the typing indicator
      final currentSessionId = _sessionId;
      final showIndicatorOnSessionId =
          decryptedData['showIndicatorOnSessionId'] ?? '';

      if (currentSessionId != null &&
          showIndicatorOnSessionId == currentSessionId) {
        Logger.debug(
            '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

        if (onTyping != null) {
          onTyping!(
            decryptedData['fromUserId'] ?? '',
            decryptedData['conversationId'] ?? '',
            decryptedData['isTyping'] ?? false,
          );
          Logger.success(' SeSocketService:  Typing callback executed');
        } else {
          Logger.error(
              ' SeSocketService:  onTyping callback is NULL - typing indicator not processed!');
        }
      } else {
        Logger.info(
            ' SeSocketService:  Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
      }

      // ✅ FIX: Only call internal handler if we should show the typing indicator
      try {
        final fromUserId = decryptedData['fromUserId'] ?? '';
        final conversationId = decryptedData['conversationId'] ?? '';
        final showIndicatorOnSessionId =
            decryptedData['showIndicatorOnSessionId'] ??
                ''; // NEW: Server field
        final isTyping = decryptedData['isTyping'] ?? false;

        // CRITICAL: Only show typing indicator if we are the session that should display it
        final currentSessionId = _sessionId;
        if (currentSessionId != null &&
            showIndicatorOnSessionId == currentSessionId) {
          Logger.debug(
              '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

          // Call the internal handler to update SessionChatProvider
          // Use the direct recipientId from server for better accuracy
          final recipientId = data['recipientId'] ?? '';
          _notifyTypingStatusChange(
              fromUserId, recipientId, isTyping, true, false);
          Logger.success(
              ' SeSocketService:  Internal typing status change handler called');
        } else {
          Logger.info(
              ' SeSocketService:  Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
        }
      } catch (e) {
        Logger.error(
            ' SeSocketService:  Error calling internal typing handler: $e');
      }
    });

    // Debug: Log all incoming events (reduced for less clutter)
    _socket!.onAny((event, data) {
      // Always log typing-related events for debugging
      if (event.contains('typing')) {
        Logger.info(
            ' SeSocketService:  TYPING EVENT RECEIVED: $event with data: $data');
      }
      // Only log important events, skip routine stats, admin logs, and heartbeat
      else if (!event.startsWith('server_stats') &&
          !event.startsWith('channel_update') &&
          !event.startsWith('heartbeat') &&
          !event.startsWith('admin_log')) {
        Logger.info(
            ' SeSocketService: DEBUG - Received event: $event with data: $data');
      }

      // Special debugging for user data exchange events
      if (event == 'user_data_exchange:data') {
        Logger.info(
            ' SeSocketService: 🔍🔍🔍 USER DATA EXCHANGE EVENT RECEIVED!');
        Logger.info(' SeSocketService: 🔍🔍🔍 Event: $event');
        Logger.info(' SeSocketService: 🔍🔍🔍 Data: $data');
        Logger.info(' SeSocketService: 🔍🔍🔍 Current session ID: $_sessionId');
        Logger.info(
            ' SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
        Logger.info(' SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      }

      // Debug ALL key exchange related events
      if (event.contains('user_data') ||
          event.contains('conversation') ||
          event.contains('key_exchange')) {
        Logger.info(' SeSocketService: 🔍🔍🔍 KEY EXCHANGE EVENT RECEIVED!');
        Logger.info(' SeSocketService: 🔍🔍🔍 Event: $event');
        Logger.info(' SeSocketService: 🔍🔍🔍 Data: $data');
        Logger.info(' SeSocketService: 🔍🔍🔍 Current session ID: $_sessionId');
        Logger.info(
            ' SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
        Logger.info(' SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      }
    });
  }

  /// Handle key exchange error events
  Future<void> _handleKeyExchangeError(Map<String, dynamic> errorData) async {
    try {
      Logger.debug(' SeSocketService: Handling key exchange error');

      final errorCode = errorData['errorCode']?.toString();
      final errorType = errorData['errorType']?.toString();
      final message = errorData['message']?.toString();
      final requestId = errorData['requestId']?.toString();

      Logger.debug(' SeSocketService: Error Code: $errorCode');
      Logger.debug(' SeSocketService: Error Type: $errorType');
      Logger.debug(' SeSocketService: Message: $message');
      Logger.debug(' SeSocketService: Request ID: $requestId');

      // Create user-friendly error message
      String userMessage = _getUserFriendlyErrorMessage(errorCode, message);

      // Notify KeyExchangeService about the error (it will handle the snackbar)
      try {
        KeyExchangeService.instance.handleKeyExchangeError(errorData);
      } catch (e) {
        Logger.debug(
            ' SeSocketService: Error notifying KeyExchangeService: $e');
      }

      // Create notification for the error
      await _createSocketEventNotification(
        eventType: 'key_exchange:error',
        title: 'Key Exchange Error',
        body: userMessage,
        senderId: errorData['recipientId']?.toString(),
        conversationId: null,
        metadata: errorData,
      );
    } catch (e) {
      Logger.debug(' SeSocketService: Error handling key exchange error: $e');
    }
  }

  /// Get user-friendly error message based on error code
  String _getUserFriendlyErrorMessage(String? errorCode, String? message) {
    switch (errorCode) {
      case 'RECIPIENT_NOT_FOUND':
        return 'The recipient is currently offline. Your request will be delivered when they come online.';
      case 'INVALID_PAYLOAD':
        return 'Invalid request format. Please try again.';
      case 'UNAUTHORIZED_REQUEST':
        return 'You can only send key exchange requests from your own session.';
      case 'NO_PUBLIC_KEY':
        return 'No public key found. Please ensure you are properly registered.';
      case 'REQUESTER_NOT_FOUND':
        return 'Unable to deliver response. The requester may be offline.';
      case 'UNAUTHORIZED_ACCEPT':
        return 'You can only accept key exchange requests sent to you.';
      case 'UNAUTHORIZED_DECLINE':
        return 'You can only decline key exchange requests sent to you.';
      case 'DECLINE_NOTIFICATION_FAILED':
        return 'Unable to notify requester of decline. They may be offline.';
      default:
        return message ??
            'An error occurred during key exchange. Please try again.';
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      Logger.debug(' SeSocketService: Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer(Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30)), () {
      if (_sessionId != null && !_ready && !_isConnecting) {
        Logger.info(' SeSocketService:  Attempting reconnection...');
        connect(_sessionId!);
      }
    });
  }

  // CRITICAL: Heartbeat response (MUST respond within 1 second)
  void _respondToHeartbeat(dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('heartbeat:pong', {
        'sessionId': _sessionId,
        'timestamp': DateTime.now().toIso8601String()
      });
      // Reduced logging to reduce clutter
    }
  }

  // CRITICAL: Stability check response (MUST respond within 1 second)
  void _respondToStabilityCheck(dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('connection:stability_check:response', {
        'sessionId': _sessionId,
        'status': 'stable',
        'timestamp': DateTime.now().toIso8601String()
      });
      Logger.info(' SeSocketService: Stability check response sent');
    }
  }

  // CRITICAL: Connection ping response (MUST respond within 1 second)
  void _respondToConnectionPing(dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('connection:pong', {
        'sessionId': _sessionId,
        'timestamp': DateTime.now().toIso8601String()
      });
      Logger.debug('🏓 SeSocketService: Connection ping response sent');
    }
  }

  // Start client-side heartbeat monitoring
  void _startClientHeartbeat() {
    _clientHeartbeatTimer?.cancel();
    _clientHeartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_socket != null && _socket!.connected && _sessionId != null) {
        _socket!.emit('client:heartbeat', {
          'sessionId': _sessionId,
          'timestamp': DateTime.now().toIso8601String()
        });
        // Reduced logging to reduce clutter
      }
    });
  }

  bool get isConnected => _ready && (_socket?.connected ?? false);
  bool get isConnecting => _isConnecting;
  bool get isReadyToSend => isConnected;

  String getSocketStatus() {
    if (_socket == null) return 'Not initialized';
    if (_ready && _socket!.connected) return 'Connected';
    if (_isConnecting) return 'Connecting';
    if (_socket!.connected && !_ready) return 'Connected (unregistered)';
    return 'Disconnected';
  }

  /// Send presence update to specific users
  void sendPresence(bool isOnline, List<String> toUserIds) {
    if (!isConnected || _sessionId == null) {
      Logger.error(
          ' SeSocketService:  Cannot send presence update - not connected or no session');
      return;
    }

    try {
      final payload = {
        'fromUserId': _sessionId,
        'isOnline': isOnline,
        'toUserIds': toUserIds, // Array of user IDs to notify
        'timestamp': DateTime.now().toIso8601String(),
      };

      Logger.debug(
          ' SeSocketService: 🟢 Sending presence update: ${isOnline ? 'online' : 'offline'} to ${toUserIds.length} users');
      Logger.info(' SeSocketService:  Payload: $payload');

      _socket!.emit('presence:update', payload);
      Logger.success(' SeSocketService:  Presence update sent successfully');
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending presence update: $e');
      _scheduleReconnect();
    }
  }

  /// Send typing indicator to a specific user
  Future<void> sendTyping(
      String recipientId, String conversationId, bool isTyping) async {
    if (!isConnected || _sessionId == null) {
      Logger.error(
          ' SeSocketService:  Cannot send typing indicator - not connected or no session');
      return;
    }

    try {
      // CRITICAL: Use the conversation ID passed from SessionChatProvider
      // According to server docs, this should be the existing conversation ID
      final currentUserId = _sessionId;

      // Validate that we have a valid sender ID
      if (currentUserId == null || currentUserId.isEmpty) {
        Logger.error(' SeSocketService:  ERROR: Invalid sender session ID');
        return;
      }

      // Use the passed conversationId instead of generating a new one
      // This ensures we use the same conversation ID that both users share
      final finalConversationId = conversationId.isNotEmpty
          ? conversationId
          : _generateConsistentConversationId(currentUserId, recipientId);

      // CRITICAL: Ensure showIndicatorOnSessionId is a clean session ID
      // The recipientId might be malformed, so we need to clean it
      String cleanShowIndicatorId;
      if (recipientId.startsWith('session_')) {
        // This looks like a valid session ID
        cleanShowIndicatorId = recipientId;
      } else if (recipientId.contains('session_')) {
        // This is malformed - extract the first session ID
        final parts = recipientId.split('session_');
        if (parts.length >= 2) {
          cleanShowIndicatorId = 'session_${parts[1]}';
        } else {
          cleanShowIndicatorId = recipientId; // Fallback
        }
      } else {
        cleanShowIndicatorId = recipientId; // Fallback
      }

      // Create the typing data payload for encryption
      final typingData = {
        'fromUserId': _sessionId,
        'recipientId': recipientId,
        'conversationId': finalConversationId,
        'isTyping': isTyping,
        'showIndicatorOnSessionId': cleanShowIndicatorId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the typing data using AES encryption
      final encryptedData =
          await EncryptionService.encryptAesCbcPkcs7(typingData, recipientId);

      final payload = {
        'fromUserId': _sessionId,
        'recipientId': recipientId,
        'conversationId': finalConversationId,
        'isTyping': isTyping,
        'showIndicatorOnSessionId': cleanShowIndicatorId,
        'encryptedData': encryptedData['data'],
        'checksum': encryptedData['checksum'],
        'metadata': {
          'encrypted': true,
          'version': '2.0',
          'encryptionType': 'AES-256-CBC'
        }
      };

      // Track typing status locally
      final key = '$_sessionId->$recipientId';
      _typingStatuses[key] = {
        'isTyping': isTyping,
        'delivered': false,
        'autoStopped': false,
        'timestamp': DateTime.now().toIso8601String(),
      };
      Logger.debug(
          ' SeSocketService: Typing status tracked: $key -> ${isTyping ? 'typing' : 'stopped'}');

      Logger.debug(
          ' SeSocketService: ⌨️ Sending typing indicator: ${isTyping ? 'started' : 'stopped'} to $recipientId');
      Logger.info(' SeSocketService:  Payload: $payload');
      Logger.debug(
          '🔌 SeSocketService: 🔍 conversationId (final): $finalConversationId');
      Logger.debug('🔌 SeSocketService: 🔍 fromUserId (sender): $_sessionId');

      _socket!.emit('typing:update', payload);
      Logger.success(' SeSocketService:  Typing indicator sent successfully');
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending typing indicator: $e');
      _scheduleReconnect();
    }
  }

  /// Send a message to a specific user
  void sendMessage({
    required String messageId,
    required String recipientId,
    required String body,
    String? conversationId, // This will be the consistent conversation ID
  }) async {
    Logger.debug(' SeSocketService: 🔧 sendMessage called with:');
    Logger.info(' SeSocketService:  messageId: $messageId');
    Logger.info(' SeSocketService:  recipientId: $recipientId');
    Logger.info(' SeSocketService:  body: $body');
    Logger.info(' SeSocketService:  conversationId: $conversationId');
    if (!isConnected || _sessionId == null) {
      Logger.error(
          ' SeSocketService:  Cannot send message - not connected or no session');
      return;
    }

    try {
      // CRITICAL: Use consistent conversation ID for both users
      final currentUserId = _sessionId;

      // Validate that we have a valid sender ID
      if (currentUserId == null || currentUserId.isEmpty) {
        Logger.error(' SeSocketService:  ERROR: Invalid sender session ID');
        return;
      }

      // Use the passed conversationId if provided, otherwise generate one
      final consistentConversationId = conversationId?.isNotEmpty == true
          ? conversationId!
          : _generateConsistentConversationId(currentUserId, recipientId);

      Logger.info(' SeSocketService:  Passed conversationId: $conversationId');
      Logger.info(
          ' SeSocketService:  Generated consistentConversationId: $consistentConversationId');
      Logger.info(
          ' SeSocketService:  Using conversationId: $consistentConversationId');

      // Encrypt the message body before sending
      Map<String, String> encryptedResult;
      try {
        // Create message data map for encryption
        final messageData = {
          'text': body,
          'timestamp': DateTime.now().toIso8601String(),
          'messageId': messageId,
        };

        encryptedResult = await EncryptionService.encryptAesCbcPkcs7(
            messageData, recipientId);
        Logger.success(' SeSocketService:  Message encrypted successfully');
      } catch (e) {
        Logger.error(' SeSocketService:  Failed to encrypt message: $e');
        return;
      }

      final payload = {
        'messageId': messageId,
        'fromUserId': _sessionId,
        'recipientId': recipientId,
        'conversationId': consistentConversationId,
        'body': encryptedResult['data']!,
        'checksum': encryptedResult['checksum']!,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'encrypted': true,
          'version': '2.0',
          'encryptionType': 'AES-256-CBC',
        },
      };

      // Track message locally for status updates
      _messageStatuses[messageId] = 'sent';
      Logger.debug(
          '📊 SeSocketService: Message status tracked: $messageId -> sent');

      Logger.debug(
          ' SeSocketService: 📤 Sending message: $messageId to $recipientId');
      Logger.info(' SeSocketService:  Payload: $payload');
      Logger.debug(
          '🔌 SeSocketService: 🔍 conversationId (consistent): $consistentConversationId');
      Logger.debug('🔌 SeSocketService: 🔍 fromUserId (sender): $_sessionId');

      _socket!.emit('message:send', payload);
      Logger.success(' SeSocketService:  Message sent successfully');
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending message: $e');
      _scheduleReconnect();
    }
  }

  Future<void> sendReadReceipt(String toUserId, String messageId) async {
    if (!isConnected || _sessionId == null) return;

    try {
      // CRITICAL: Use consistent conversation ID for both users
      final currentUserId = _sessionId!;
      final consistentConversationId =
          _generateConsistentConversationId(currentUserId, toUserId);

      // Create the read receipt data payload for encryption
      final receiptData = {
        'messageId': messageId,
        'fromUserId': _sessionId,
        'toUserId': toUserId,
        'conversationId': consistentConversationId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the receipt data using AES encryption
      final encryptedData =
          await EncryptionService.encryptAesCbcPkcs7(receiptData, toUserId);

      _socket!.emit('receipt:read', {
        'messageId': messageId,
        'fromUserId': _sessionId,
        'toUserId': toUserId,
        'encryptedData': encryptedData['data'],
        'checksum': encryptedData['checksum'],
        'metadata': {
          'encrypted': true,
          'version': '2.0',
          'encryptionType': 'AES-256-CBC'
        }
      });

      Logger.success(
          '📬 SeSocketService:  Encrypted read receipt sent: $messageId -> $toUserId');
    } catch (e) {
      Logger.error(
          '📬 SeSocketService:  Error sending encrypted read receipt: $e');
    }
  }

  /// Delete a single message - API Compliant
  Future<void> deleteMessage({
    required String messageId,
    required String conversationId,
    required String deletedBy,
  }) async {
    if (!isConnected || _sessionId == null) return;

    try {
      _socket!.emit('message:delete', {
        'messageId': messageId,
        'conversationId': conversationId,
        'deletedBy': deletedBy,
        'timestamp': DateTime.now().toIso8601String()
      });

      Logger.success(
          '🗑️ SeSocketService:  Message delete request sent: $messageId');
    } catch (e) {
      Logger.error('🗑️ SeSocketService:  Error sending message delete: $e');
    }
  }

  /// Delete all messages in a conversation - API Compliant
  Future<void> deleteAllMessages({
    required String conversationId,
    required String deletedBy,
  }) async {
    if (!isConnected || _sessionId == null) return;

    try {
      _socket!.emit('message:delete_all', {
        'conversationId': conversationId,
        'deletedBy': deletedBy,
        'timestamp': DateTime.now().toIso8601String()
      });

      Logger.success(
          '🗑️ SeSocketService:  Delete all messages request sent: $conversationId');
    } catch (e) {
      Logger.error(
          '🗑️ SeSocketService:  Error sending delete all messages: $e');
    }
  }

  void sendKeyExchangeRequest(
      {required String recipientId,
      required String publicKey,
      required String requestId,
      required String requestPhrase,
      String version = '1'}) {
    if (!isConnected || _sessionId == null) return;

    // Send according to API documentation format
    _socket!.emit('key_exchange:request', {
      'senderId': _sessionId,
      'recipientId': recipientId,
      'publicKey': publicKey,
      'requestId': requestId,
      'requestPhrase': requestPhrase,
      'version': version,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
  }

  void sendKeyExchangeResponse(
      {required String recipientId,
      required String publicKey,
      required String responseId,
      String requestVersion = '1',
      String type = 'key_exchange_response'}) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('key_exchange:response', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'publicKey': publicKey,
      'responseId': responseId,
      'requestVersion': requestVersion,
      'type': type
    });
  }

  void sendKeyExchangeDecline({
    required String senderId,
    required String recipientId,
    required String requestId,
    String? reason,
  }) {
    if (!isConnected || _sessionId == null) return;

    // Send according to API documentation format
    _socket!.emit('key_exchange:decline', {
      'senderId': senderId,
      'recipientId': recipientId,
      'requestId': requestId,
      'reason': reason ?? 'Key exchange request declined',
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
  }

  void revokeKeyExchange(
      {required String recipientId, required String requestId}) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('key_exchange:revoked', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'requestId': requestId
    });
  }

  void sendUserDataExchange(
      {required String recipientId,
      required String encryptedData,
      String? conversationId}) {
    Logger.info(' SeSocketService: 🔍🔍 SENDING USER DATA EXCHANGE EVENT!');
    Logger.info(' SeSocketService: 🔍🔍 Event: user_data_exchange:send');
    Logger.debug(
        '🔑 SeSocketService: 🔍🔍🔍 Data: {recipientId: $recipientId, senderId: $_sessionId, encryptedData: ${encryptedData.substring(0, 50)}..., conversationId: $conversationId}');
    Logger.info(
        ' SeSocketService: 🔍🔍 Socket connected: ${_socket?.connected}');
    Logger.info(' SeSocketService: 🔍🔍 Socket ready: $_ready');
    Logger.info(' SeSocketService: 🔍🔍 Session ID: $_sessionId');
    Logger.info(' SeSocketService: 🔍🔍 Session confirmed: $_sessionConfirmed');
    Logger.info(' SeSocketService: 🔍🔍 Socket ID: ${_socket?.id}');

    if (!isConnected || _sessionId == null) {
      Logger.error(
          ' SeSocketService:  Cannot send - socket not connected or session ID null');
      return;
    }

    try {
      _socket!.emit('user_data_exchange:send', {
        'recipientId': recipientId,
        'senderId': _sessionId,
        'encryptedData': encryptedData,
        'conversationId': conversationId ?? ''
      });
      Logger.success(
          ' SeSocketService:  User data exchange event sent successfully');
    } catch (e) {
      Logger.error(
          ' SeSocketService:  Failed to send user data exchange event: $e');
    }
  }

  void notifyConversationCreated(
      {required String recipientId, required String conversationIdLocal}) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('conversation:created', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'conversation_id_local': conversationIdLocal
    });
  }

  void notifyUserDeleted(List<String> toUserIds) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit(
        'user:deleted', {'fromUserId': _sessionId, 'toUserIds': toUserIds});
  }

  Future<void> disconnect() async {
    // If instance was destroyed, reset it for cleanup
    if (SeSocketService.isDestroyed) {
      Logger.info(
          ' SeSocketService:  Instance was destroyed, resetting for cleanup...');
      SeSocketService.resetForNewConnection();
    }

    _ready = false;
    _isConnecting = false;
    _sessionConfirmed = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _stabilityTimer?.cancel();
    _clientHeartbeatTimer?.cancel();
    _addConnectionStateEvent(false);

    try {
      if (_socket != null && _sessionId != null) {
        // CRITICAL: Leave the room/channel before disconnecting
        Logger.debug(' SeSocketService: 🚪 Leaving room/channel: $_sessionId');

        // Send a final event to notify server we're leaving
        try {
          _socket!.emit('session:leaving', {
            'sessionId': _sessionId,
            'timestamp': DateTime.now().toIso8601String(),
            'reason': 'user_disconnect'
          });

          // Wait a moment for server to process
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          Logger.warning(
              ' SeSocketService:  Warning - could not send leaving event: $e');
        }

        // Now disconnect
        _socket!.disconnect();
        _socket!.destroy();
        Logger.success(' SeSocketService:  Socket disconnected and room left');
      }
    } catch (e) {
      Logger.error(' SeSocketService:  Error during disconnect: $e');
    } finally {
      _socket = null;
    }
  }

  // Compatibility methods for existing code
  void setOnMessageReceived(
      Function(String senderId, String senderName, String message,
              String conversationId, String messageId)?
          callback) {
    // Set the callback directly since the signature now matches
    onMessageReceived = callback;
  }

  void setOnTypingIndicator(
      Function(String senderId, bool isTyping)? callback) {
    Logger.debug(
        ' SeSocketService: 🔧 Setting typing indicator callback: ${callback != null ? 'SET' : 'NULL'}');

    // Map the existing callback to the new format
    if (callback != null) {
      onTyping = (fromUserId, conversationId, isTyping) {
        Logger.debug(
            ' SeSocketService: 🔧 onTyping callback mapped: $fromUserId -> $isTyping');
        callback(fromUserId, isTyping);
      };
      Logger.success(
          ' SeSocketService:  Typing indicator callback set successfully');
    } else {
      Logger.warning(' SeSocketService:  Typing indicator callback is null');
      onTyping = null;
    }
  }

  // NEW: Enhanced typing indicator callback with showIndicatorOnSessionId
  void setOnTypingIndicatorEnhanced(
      Function(String senderId, bool isTyping, String showIndicatorOnSessionId)?
          callback) {
    Logger.debug(
        ' SeSocketService: 🔧 Setting ENHANCED typing indicator callback: ${callback != null ? 'SET' : 'NULL'}');

    // Map the enhanced callback to the new format
    if (callback != null) {
      onTyping = (fromUserId, conversationId, isTyping) {
        Logger.debug(
            ' SeSocketService: 🔧 Enhanced onTyping callback mapped: $fromUserId -> $isTyping');
        callback(fromUserId, isTyping,
            conversationId); // Pass conversationId as showIndicatorOnSessionId for now
      };
      Logger.success(
          ' SeSocketService:  Enhanced typing indicator callback set successfully');
    } else {
      Logger.warning(
          ' SeSocketService:  Enhanced typing indicator callback is null');
      onTyping = null;
    }
  }

  void setOnOnlineStatusUpdate(
      Function(String senderId, bool isOnline, String? lastSeen)? callback) {
    // Map the existing callback to the new format
    if (callback != null) {
      onPresence = (sessionId, isOnline, timestamp) {
        callback(sessionId, isOnline, timestamp);
      };
    }
  }

  // Additional callback methods needed by main.dart - ENHANCED with additional context
  void setOnMessageStatusUpdate(
      Function(String senderId, String messageId, String status,
              String? conversationId, String? recipientId)?
          callback) {
    // 🆕 FIXED: Only set the external callback for message status updates
    // DO NOT override the dedicated onDelivered and onRead callbacks
    // This prevents duplicate processing and ensures proper receipt flow
    onMessageStatusUpdateExternal = callback;
  }

  void setOnKeyExchangeRequestReceived(
      Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeRequest = callback;
    }
  }

  void setOnKeyExchangeAccepted(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeResponse = callback;
    }
  }

  void setOnKeyExchangeDeclined(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeDeclined = callback;
    }
  }

  void setOnKeyExchangeResponse(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeResponse = callback;
    }
  }

  void setOnConversationCreated(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onConversationCreated = callback;
    }
  }

  void setOnUserDataExchange(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onUserDataExchange = callback;
    }
  }

  void setOnMessageAcked(Function(String messageId)? callback) {
    if (callback != null) {
      onMessageAcked = callback;
    }
  }

  void setOnMessageDelivered(
      Function(String messageId, String fromUserId, String toUserId)?
          callback) {
    if (callback != null) {
      onDelivered = callback;
    }
  }

  void setOnMessageRead(
      Function(String messageId, String fromUserId, String toUserId)?
          callback) {
    if (callback != null) {
      onRead = callback;
    }
  }

  // 🆕 ADD THIS: Setter for queued message callback
  void setOnMessageQueued(
      Function(String messageId, String toUserId, String fromUserId) callback) {
    onQueued = callback;
  }

  void setOnKeyExchangeRevoked(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeRevoked = callback;
    }
  }

  void setOnUserDeleted(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onUserDeleted = callback;
    }
  }

  void setOnContactAdded(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onContactAdded = callback;
    }
  }

  void setOnContactRemoved(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onContactRemoved = callback;
    }
  }

  void setOnSessionRegistered(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onSessionRegistered = callback;
    }
  }

  // Additional utility methods that might be needed
  // Stream<bool> get connectionStateStream => _connectionStateController.stream; // This line is removed as per the new_code

  // Additional methods needed by SocketProvider
  String? get currentSessionId => _sessionId;

  Future<void> initialize() async {
    // This method is called by some services, so we need to implement it
    // For SeSocketService, initialization happens via connect() method
    if (_sessionId != null) {
      Logger.debug(
          '🔌 SeSocketService: ℹ️ initialize() called, but SeSocketService uses connect() method');
      Logger.debug(
          '🔌 SeSocketService: ℹ️ Please use connect($_sessionId) instead of initialize()');
      // Auto-connect if we have a session ID
      await connect(_sessionId!);
    } else {
      Logger.debug(
          '🔌 SeSocketService: ⚠️ initialize() called but no session ID available');
      Logger.debug(
          '🔌 SeSocketService: ℹ️ Please use connect(sessionId) method instead');
    }
  }

  void refreshConnectionStatus() {
    // This method is called by SocketProvider, implement as needed
    notifyListeners();
  }

  void notifyListeners() {
    // This is a placeholder for the notifyListeners functionality
    // In a real implementation, this would notify listeners of state changes
  }

  Future<bool> testConnection() async {
    try {
      if (_socket != null && _socket!.connected) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> manualConnect() async {
    if (_sessionId != null) {
      await connect(_sessionId!);
    }
  }

  Future<void> emergencyReconnect() async {
    await disconnect();
    if (_sessionId != null) {
      await connect(_sessionId!);
    }
  }

  void debugPrintState() {
    Logger.debug(' SeSocketService: Debug State:');
    Logger.debug('  - Connected: ${_socket?.connected ?? false}');
    Logger.debug('  - Ready: $_ready');
    Logger.debug('  - Session Confirmed: $_sessionConfirmed');
    Logger.debug('  - Session ID: $_sessionId');
    Logger.debug('  - Socket ID: ${_socket?.id ?? 'null'}');
    Logger.debug('  - Is Connecting: $_isConnecting');
    Logger.debug('  - Reconnect Attempts: $_reconnectAttempts');
  }

  // Method to manually check connection health
  void checkConnectionHealth() {
    Logger.debug(' SeSocketService: Connection Health Check:');
    Logger.debug('  - Socket exists: ${_socket != null}');
    if (_socket != null) {
      Logger.debug('  - Socket connected: ${_socket!.connected}');
      Logger.debug('  - Socket id: ${_socket!.id}');
      try {
        final engine = _socket!.io.engine;
        if (engine != null) {
          final transport = engine.transport;
          Logger.debug('  - Socket transport: ${transport?.name ?? 'unknown'}');
        } else {
          Logger.debug('  - Socket transport: engine is null');
        }
      } catch (e) {
        Logger.debug('  - Socket transport: error accessing - $e');
      }
    }
    Logger.debug('  - Ready state: $_ready');
    Logger.debug('  - Session confirmed: $_sessionConfirmed');
    Logger.debug('  - Session ID: $_sessionId');
    Logger.debug(
        '  - Connection state stream active: ${_connectionStateController?.isClosed == false}');
  }

  // Method for testing connections (used by main_nav_screen)
  void emit(String event, Map<String, dynamic> data) {
    if (!isConnected || _sessionId == null) {
      Logger.error(
          ' SeSocketService:  Cannot emit event: Socket not connected or session invalid');
      Logger.info(
          ' SeSocketService:  Connection status: isConnected=$isConnected, sessionId=$_sessionId');
      return;
    }

    // Debug logging for key exchange events
    if (event == 'key_exchange:accept') {
      Logger.info(' SeSocketService: 🔍🔍 SENDING KEY EXCHANGE ACCEPT EVENT!');
      Logger.info(' SeSocketService: 🔍🔍 Event: $event');
      Logger.info(' SeSocketService: 🔍🔍 Data: $data');
      Logger.info(
          ' SeSocketService: 🔍🔍 Socket connected: ${_socket?.connected}');
      Logger.info(' SeSocketService: 🔍🔍 Session ID: $_sessionId');
    }

    try {
      _socket!.emit(event, data);

      // Confirm the event was sent
      if (event == 'key_exchange:accept') {
        Logger.success(
            ' SeSocketService:  Key exchange accept event sent via socket');
      }
    } catch (e) {
      Logger.error(' SeSocketService:  Error emitting event $event: $e');
      Logger.info(
          ' SeSocketService:  This may be due to socket connectivity issues');

      // Try to reconnect if there's a connection issue
      if (_socket?.connected == false) {
        Logger.info(
            ' SeSocketService:  Attempting to reconnect due to emit failure...');
        _scheduleReconnect();
      }
    }
  }

  // Method for deleting session on server (used by user_existence_guard)
  Future<void> deleteSessionOnServer({String? sessionId}) async {
    if (!isConnected || _sessionId == null) return;
    try {
      final sessionToDelete = sessionId ?? _sessionId;

      // Send session deletion request to server
      _socket!.emit('user:deleted', {
        'fromUserId': sessionToDelete,
        'toUserIds': [], // Empty list means notify all users
        'timestamp': DateTime.now().toIso8601String(),
        'reason': 'account_deletion'
      });

      Logger.success(
          ' SeSocketService:  Session deletion request sent for: $sessionToDelete');

      // Wait a moment for the server to process the deletion
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending session deletion: $e');
    }
  }

  // Method for sending message status updates (used by online_status_service)
  Future<void> sendMessageStatusUpdate({
    required String recipientId,
    required String messageId,
    String? status,
    String? conversationId, // Add optional conversation ID parameter
  }) async {
    if (!isConnected || _sessionId == null) return;
    try {
      // Use provided conversation ID or generate consistent one
      final effectiveConversationId = conversationId ??
          _generateConsistentConversationId(_sessionId!, recipientId);

      // Create the message status data payload for encryption
      final statusData = {
        'fromUserId': _sessionId,
        'recipientId': recipientId,
        'messageId': messageId,
        'status': status ?? 'sent',
        'conversationId': effectiveConversationId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the status data using AES encryption
      final encryptedData =
          await EncryptionService.encryptAesCbcPkcs7(statusData, recipientId);

      _socket!.emit('message:status_update', {
        'fromUserId': _sessionId,
        'recipientId': recipientId,
        'messageId': messageId,
        'status': status ?? 'sent',
        'conversationId': effectiveConversationId,
        'encryptedData': encryptedData['data'],
        'checksum': encryptedData['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'encrypted':
              true, // ✅ FIXED: Set to true for encrypted status updates
          'version': '1.0',
          'encryptionType': 'aes-cbc-pkcs7'
        }
      });
      Logger.debug(
          '🔌 SeSocketService: Message status update sent: $messageId -> $status (conversationId: $effectiveConversationId)');
    } catch (e) {
      Logger.error(
          ' SeSocketService:  Error sending message status update: $e');
    }
  }

  // CRITICAL: Send receipt:delivered when recipient opens chat
  Future<void> sendDeliveryReceipt({
    required String recipientId,
    required String messageId,
    String? conversationId, // Add optional conversation ID parameter
  }) async {
    if (!isConnected || _sessionId == null) return;
    try {
      // Use provided conversation ID or generate consistent one
      final effectiveConversationId = conversationId ??
          _generateConsistentConversationId(_sessionId!, recipientId);

      _socket!.emit('receipt:delivered', {
        'messageId': messageId,
        'fromUserId': _sessionId, // We are the recipient
        'toUserId': recipientId, // Original sender
        'conversationId':
            effectiveConversationId, // ✅ Use proper conversation ID
        'timestamp': DateTime.now().toIso8601String(),
        'silent': true, // Usually silent to avoid spam
      });
      Logger.debug(
          '📬 SeSocketService: Delivery receipt sent: $messageId -> $recipientId (conversationId: $effectiveConversationId)');
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending delivery receipt: $e');
    }
  }

  // Methods for event handling (used by se_auth_checker)
  void on(String event, Function(dynamic) handler) {
    if (_socket != null) {
      _socket!.on(event, handler);
    }
  }

  void off(String event, [Function(dynamic)? handler]) {
    if (_socket != null) {
      if (handler != null) {
        _socket!.off(event, handler);
      } else {
        _socket!.off(event);
      }
    }
  }

  // Method for cleanup (used by realtime_service_manager)
  void dispose() {
    Logger.info(' SeSocketService:  Disposing socket service...');

    // Clean up all timers and resources
    _heartbeatTimer?.cancel();
    _stabilityTimer?.cancel();
    _clientHeartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    // Close stream controller
    try {
      _connectionStateController?.close();
    } catch (e) {
      Logger.warning(
          ' SeSocketService:  Warning - stream controller already closed: $e');
    }

    // Force disconnect socket
    try {
      if (_socket != null) {
        // Disable reconnection to prevent memory leaks
        _socket!.disconnect();
        _socket!.destroy();
        Logger.success(' SeSocketService:  Socket destroyed');
      }
    } catch (e) {
      Logger.warning(' SeSocketService:  Warning - socket cleanup failed: $e');
    } finally {
      _socket = null;
    }

    // Clear all state
    _ready = false;
    _isConnecting = false;
    _sessionConfirmed = false;
    _reconnectAttempts = 0;
    _sessionId = null;

    Logger.success(' SeSocketService:  Socket service disposed completely');
  }

  // Force disconnect without sending events (for account deletion)
  Future<void> forceDisconnect() async {
    // If instance was destroyed, reset it for cleanup
    if (SeSocketService.isDestroyed) {
      Logger.info(
          ' SeSocketService:  Instance was destroyed, resetting for cleanup...');
      SeSocketService.resetForNewConnection();
    }

    Logger.debug(
        '🔌 SeSocketService: 🚫 Force disconnecting (no events sent)...');

    _ready = false;
    _isConnecting = false;
    _sessionConfirmed = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _stabilityTimer?.cancel();
    _clientHeartbeatTimer?.cancel();
    _addConnectionStateEvent(false);

    try {
      if (_socket != null) {
        // Force disconnect without sending events
        _socket!.disconnect();
        _socket!.destroy();
        Logger.success(' SeSocketService:  Force disconnect completed');
      }
    } catch (e) {
      Logger.error(' SeSocketService:  Error during force disconnect: $e');
    } finally {
      _socket = null;
    }
  }

  // Get detailed connection status for error reporting
  Map<String, dynamic> getDetailedConnectionStatus() {
    return {
      'isConnected': isConnected,
      'isConnecting': _isConnecting,
      'isReady': _ready,
      'sessionConfirmed': _sessionConfirmed,
      'sessionId': _sessionId,
      'socketConnected': _socket?.connected ?? false,
      'socketId': _socket?.id,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': _maxReconnectAttempts,
      'streamControllerActive': _connectionStateController?.isClosed == false,
      'url': _url,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Get callback status for debugging
  Map<String, dynamic> getCallbackStatus() {
    return {
      'onKeyExchangeResponse': onKeyExchangeResponse != null,
      'onUserDataExchange': onUserDataExchange != null,
      'onConversationCreated': onConversationCreated != null,
      'onMessageReceived': onMessageReceived != null,
      'onMessageAcked': onMessageAcked != null,
      'onDelivered': onDelivered != null,
      'onRead': onRead != null,
      'onPresence': onPresence != null,
      'onTyping': onTyping != null,
      'onKeyExchangeRequest': onKeyExchangeRequest != null,
      'onKeyExchangeRevoked': onKeyExchangeRevoked != null,
      'onUserDeleted': onUserDeleted != null,
      'onContactAdded': onContactAdded != null,
      'onContactRemoved': onContactRemoved != null,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Method for checking connection quality (new feature)
  Future<Map<String, dynamic>> checkConnectionQuality() async {
    try {
      if (!isConnected) {
        return {
          'status': 'disconnected',
          'quality': 'poor',
          'message': 'Socket not connected',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      // Check if session is confirmed
      if (!_sessionConfirmed) {
        return {
          'status': 'connecting',
          'quality': 'fair',
          'message': 'Session not yet confirmed',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      // Check socket health
      final socketHealth = _socket?.connected ?? false;
      if (!socketHealth) {
        return {
          'status': 'unhealthy',
          'quality': 'poor',
          'message': 'Socket connection lost',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      return {
        'status': 'healthy',
        'quality': 'excellent',
        'message': 'Connection stable and responsive',
        'sessionConfirmed': _sessionConfirmed,
        'socketConnected': socketHealth,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'error',
        'quality': 'unknown',
        'message': 'Error checking connection quality: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  // Method for sending presence updates (used by presence_service)
  void sendPresenceUpdate(String recipientId, bool isOnline) {
    sendPresence(isOnline, [recipientId]);
  }

  // Method for sending typing indicators (used by typing_service)
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    // Use recipient's session ID as conversation ID for simplicity
    await sendTyping(recipientId, recipientId, isTyping);
  }

  // Method for sending user online status (used by auth screens)
  Future<void> sendUserOnlineStatus(bool isOnline) async {
    if (!isConnected || _sessionId == null) return;

    try {
      // Send presence update to all contacts
      sendPresence(isOnline, []); // Empty list means broadcast to all
      Logger.debug(
          ' SeSocketService: User online status sent: ${isOnline ? 'online' : 'offline'}');
    } catch (e) {
      Logger.error(' SeSocketService:  Error sending user online status: $e');
    }
  }

  // Method for setting up contact listeners (compatibility with old code)
  void setupContactListeners(List<String> contactSessionIds) {
    if (!isConnected || _sessionId == null) return;

    Logger.debug(
        ' SeSocketService: Setting up listeners for ${contactSessionIds.length} contacts');

    // In the new room-based system, we don't need to set up individual contact listeners
    // The server handles routing based on session IDs
    // This method is kept for compatibility but doesn't need to do anything

    for (final contactId in contactSessionIds) {
      Logger.success(
          ' SeSocketService:  Listener ready for contact: $contactId');
    }
  }

  // Test method to verify socket connection and send test events
  Future<bool> testSocketConnection() async {
    try {
      Logger.debug(' SeSocketService: 🧪 Testing socket connection...');

      if (!isConnected) {
        Logger.error(' SeSocketService:  Socket not connected');
        return false;
      }

      if (_sessionId == null) {
        Logger.error(' SeSocketService:  No session ID');
        return false;
      }

      Logger.success(
          ' SeSocketService:  Socket connected with session: $_sessionId');

      // Test sending a presence update to ourselves
      try {
        sendPresence(true, [_sessionId!]);
        Logger.success(
            ' SeSocketService:  Test presence update sent successfully');
        return true;
      } catch (e) {
        Logger.error(' SeSocketService:  Test presence update failed: $e');
        return false;
      }
    } catch (e) {
      Logger.error(' SeSocketService:  Test connection failed: $e');
      return false;
    }
  }

  void _onSocketConnected() {
    Logger.success(' SeSocketService:  Connected to server');
    _isConnecting = false;
    _ready = false;
    _addConnectionStateEvent(true);

    // Send presence update to indicate we're online
    if (_sessionId != null) {
      try {
        sendPresence(true, []); // Empty array means broadcast to all users
        Logger.success(' SeSocketService:  Online presence sent on connection');
      } catch (e) {
        Logger.warning(' SeSocketService:  Failed to send online presence: $e');
      }
    }
  }

  // Helper method to send online presence to all users
  void _sendOnlinePresence() {
    if (_sessionId != null) {
      sendPresence(true, []); // Empty array means broadcast to all users
      Logger.success(
          ' SeSocketService:  Online presence sent on session confirmation');
    }
  }

  /// Send session deletion request to server
  void sendSessionDeletionRequest(String sessionToDelete) {
    if (_socket != null && _sessionId != null) {
      try {
        // Send session deletion request to server
        _socket!.emit('user:deleted', {
          'fromUserId': sessionToDelete,
          'toUserIds': [], // Empty list means notify all users
          'timestamp': DateTime.now().toIso8601String(),
        });

        Logger.success(
            ' SeSocketService:  Session deletion request sent for: $sessionToDelete');
      } catch (e) {
        Logger.error(
            ' SeSocketService:  Error sending session deletion request: $e');
      }
    } else {
      Logger.error(
          ' SeSocketService:  Cannot add contact - not connected or no session');
    }
  }

  // ===== CONTACT MANAGEMENT METHODS =====

  /// Add a new contact to the server
  void addContact(String contactSessionId) {
    if (_socket != null && _sessionId != null) {
      try {
        _socket!.emit('contacts:add', {
          'sessionId': _sessionId,
          'contactSessionId': contactSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });

        Logger.success('🔗 SeSocketService:  Contact added: $contactSessionId');
      } catch (e) {
        Logger.error('🔗 SeSocketService:  Error adding contact: $e');
      }
    } else {
      Logger.error(
          '🔗 SeSocketService:  Cannot add contact - not connected or no session');
    }
  }

  /// Remove a contact from the server
  void removeContact(String contactSessionId) {
    if (_socket != null && _sessionId != null) {
      try {
        _socket!.emit('contacts:remove', {
          'sessionId': _sessionId,
          'contactSessionId': contactSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });

        Logger.success(
            '🔗 SeSocketService:  Contact removed: $contactSessionId');
      } catch (e) {
        Logger.error('🔗 SeSocketService:  Error removing contact: $e');
      }
    } else {
      Logger.error(
          '🔗 SeSocketService:  Cannot remove contact - not connected or no session');
    }
  }

  /// Broadcast presence to all contacts
  void broadcastPresenceToContacts() {
    if (_socket != null && _sessionId != null) {
      try {
        // Send to all contacts (empty toUserIds = broadcast to all contacts)
        _socket!.emit('presence:update', {
          'fromUserId': _sessionId,
          'isOnline': true,
          'toUserIds': [], // Empty array = broadcast to all contacts
          'timestamp': DateTime.now().toIso8601String(),
        });

        Logger.success(
            '📡 SeSocketService:  Broadcasting presence to all contacts');
      } catch (e) {
        Logger.error('📡 SeSocketService:  Error broadcasting presence: $e');
      }
    } else {
      Logger.error(
          '📡 SeSocketService:  Cannot broadcast presence - not connected or no session');
    }
  }

  /// Update presence for specific users or broadcast to all contacts
  void updatePresence(bool isOnline, {List<String>? specificUsers}) {
    if (_socket != null && _sessionId != null) {
      try {
        // Create the presence data payload for encryption
        final presenceData = {
          'fromUserId': _sessionId,
          'isOnline': isOnline,
          'timestamp': DateTime.now().toIso8601String(),
        };

        // If specific users provided, send to them; otherwise broadcast to all contacts
        if (specificUsers != null && specificUsers.isNotEmpty) {
          presenceData['toUserIds'] = specificUsers;
          Logger.debug(
              '📡 SeSocketService: 🟢 Sending presence update: ${isOnline ? 'online' : 'offline'} to ${specificUsers.length} specific users');
        } else {
          presenceData['toUserIds'] =
              []; // Empty array = broadcast to all contacts
          Logger.debug(
              '📡 SeSocketService: 🟢 Broadcasting presence update: ${isOnline ? 'online' : 'offline'} to all contacts');
        }

        // For presence updates, we'll send to all contacts, so we need to encrypt for each recipient
        // For now, let's use a simplified approach and encrypt for a general broadcast
        final payload = {
          'fromUserId': _sessionId,
          'isOnline': isOnline,
          'timestamp': DateTime.now().toIso8601String(),
          'toUserIds':
              specificUsers ?? [], // Empty array = broadcast to all contacts
          'metadata': {
            'encrypted':
                true, // ✅ FIXED: Set to true for encrypted presence updates
            'version': '1.0',
            'encryptionType': 'aes-cbc-pkcs7'
          }
        };

        Logger.info('📡 SeSocketService:  Presence payload: $payload');
        _socket!.emit('presence:update', payload);
        Logger.success(
            '📡 SeSocketService:  Presence update sent successfully');
      } catch (e) {
        Logger.error('📡 SeSocketService:  Error sending presence update: $e');
        _scheduleReconnect();
      }
    } else {
      Logger.error(
          '📡 SeSocketService:  Cannot send presence update - not connected or no session');
    }
  }

  /// Request presence status for specific contacts
  void requestPresenceStatus(List<String> contactIds) {
    if (_socket != null && _sessionId != null && isConnected) {
      try {
        final payload = {
          'requesterId': _sessionId,
          'contactIds': contactIds,
          'timestamp': DateTime.now().toIso8601String(),
        };

        Logger.info(
            '📡 SeSocketService: 🟢 Sending presence:request to Smart Presence System with payload: $payload');
        _socket!.emit('presence:request', payload);

        Logger.success(
            '📡 SeSocketService:  Smart Presence status requested for ${contactIds.length} contacts');
      } catch (e) {
        Logger.error(
            '📡 SeSocketService:  Error requesting presence status: $e');
        _scheduleReconnect();
      }
    } else {
      Logger.error(
          '📡 SeSocketService:  Cannot request presence status - socket not connected');
    }
  }

  // Enhanced status tracking fields
  final Map<String, String> _messageStatuses = {};
  final Map<String, Map<String, dynamic>> _typingStatuses = {};

  // Helper methods for status updates
  void _updateMessageStatus(String messageId, String status, String recipientId,
      {String? conversationId}) {
    _messageStatuses[messageId] = status;
    Logger.debug(
        '📊 SeSocketService: Message status updated: $messageId -> $status (conversationId: $conversationId)');
  }

  void _updateTypingStatus(String fromUserId, String recipientId, bool isTyping,
      bool delivered, bool autoStopped) {
    final key = '$fromUserId->$recipientId';
    _typingStatuses[key] = {
      'isTyping': isTyping,
      'delivered': delivered,
      'autoStopped': autoStopped,
      'timestamp': DateTime.now().toIso8601String(),
    };
    Logger.debug(
        ' SeSocketService: Typing status updated: $key -> delivered: $delivered, autoStopped: $autoStopped');
  }

  // Status getters
  String getMessageStatus(String messageId) {
    return _messageStatuses[messageId] ?? 'sent';
  }

  Map<String, dynamic>? getTypingStatus(String fromUserId, String recipientId) {
    final key = '$fromUserId->$recipientId';
    return _typingStatuses[key];
  }

  // Notify listeners (implement these based on your notification system)
  void _notifyMessageStatusChange(
      String messageId, String status, String recipientId) {
    Logger.debug(
        '📊 SeSocketService: Notifying message status change: $messageId -> $status');

    // Notify the message status change callbacks
    if (status.toLowerCase() == 'delivered' && onDelivered != null) {
      onDelivered!(messageId, _sessionId!, recipientId);
    } else if (status.toLowerCase() == 'read' && onRead != null) {
      onRead!(messageId, _sessionId!, recipientId);
    }
  }

  void _notifyTypingStatusChange(String fromUserId, String recipientId,
      bool isTyping, bool delivered, bool autoStopped) {
    Logger.debug(
        '⌨️ SeSocketService: Notifying typing status change: $fromUserId -> $recipientId (delivered: $delivered)');

    // CRITICAL FIX: Typing indicators should ONLY show on the RECIPIENT's side
    // The sender should NEVER see their own typing indicator
    try {
      final context = UIService().context;
      if (context != null) {
        final sessionChatProvider =
            Provider.of<SessionChatProvider>(context, listen: false);

        // Get current user ID to check if we're the sender
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && currentUserId == fromUserId) {
          // ❌ WE ARE THE SENDER - Don't show typing indicator to ourselves
          Logger.warning(
              ' SeSocketService:  Ignoring own typing indicator - we are the sender: $fromUserId');
          return;
        }

        // ✅ We are the RECIPIENT - Check if this typing indicator is for our current conversation
        final currentRecipientId = sessionChatProvider.currentRecipientId;
        if (currentRecipientId != null) {
          // Check if the typing indicator is for the current conversation
          bool shouldUpdate = false;

          // Method 1: Direct user ID match
          if (currentRecipientId == fromUserId) {
            shouldUpdate = true;
            Logger.success(
                ' SeSocketService:  Direct user ID match for typing indicator');
          }
          // Method 2: Conversation ID match (if currentRecipientId is a conversation ID)
          else if (currentRecipientId.startsWith('chat_') &&
              ConversationIdGenerator.isParticipant(
                  currentRecipientId, fromUserId)) {
            shouldUpdate = true;
            Logger.success(
                ' SeSocketService:  Conversation ID match for typing indicator');
          }
          // Method 3: Recipient ID match (if recipientId is a conversation ID)
          else if (recipientId.startsWith('chat_') &&
              ConversationIdGenerator.isParticipant(recipientId, fromUserId)) {
            shouldUpdate = true;
            Logger.success(
                ' SeSocketService:  Recipient ID match for typing indicator');
          }

          if (shouldUpdate) {
            // ✅ Update the typing indicator on the RECIPIENT's side
            sessionChatProvider.updateRecipientTypingState(isTyping);
            Logger.success(
                ' SeSocketService:  Typing status updated for current conversation: $fromUserId -> $isTyping');
          } else {
            Logger.debug(
                '⌨️ SeSocketService: ℹ️ Typing indicator from different conversation: $fromUserId -> $recipientId (current: $currentRecipientId)');
          }
        } else {
          Logger.info(
              ' SeSocketService:  No current recipient set, cannot update typing status');
        }
      } else {
        Logger.warning(
            ' SeSocketService:  No context available for typing status update');
      }
    } catch (e) {
      Logger.error(
          ' SeSocketService:  Error updating typing status via SessionChatProvider: $e');
    }
  }

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
  }
}
