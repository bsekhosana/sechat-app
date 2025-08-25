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

class SeSocketService {
  SeSocketService._();
  static SeSocketService? _instance;
  static bool _isDestroyed = false; // Track destruction state separately

  static SeSocketService get instance {
    if (_instance == null && !_isDestroyed) {
      _instance = SeSocketService._();
      print('🔌 SeSocketService: 🆕 New instance created');
    } else if (_instance == null && _isDestroyed) {
      // Reset destruction state and create new instance
      _isDestroyed = false;
      _instance = SeSocketService._();
      print('🔌 SeSocketService: 🔄 Instance recreated after destruction');
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
      print('🔌 SeSocketService: 🗑️ Destroying singleton instance...');

      // First dispose the current instance
      _instance!.dispose();

      // Clear all static references
      _instance = null;
      _isDestroyed = true; // Mark as destroyed

      // Force garbage collection hint
      print(
          '🔌 SeSocketService: ✅ Singleton instance destroyed and references cleared');
    }
  }

  // Additional cleanup method for aggressive memory cleanup
  static void forceCleanup() {
    print('🔌 SeSocketService: 🧹 Force cleaning up all socket resources...');

    // Destroy instance if it exists
    destroyInstance();

    // Additional cleanup steps
    print('🔌 SeSocketService: ✅ Force cleanup completed');
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
        print(
            '🔌 SeSocketService: 🔇 Skipping notification for silent event: $eventType');
        return;
      }

      // Skip notifications for connect/disconnect events
      if (eventType == 'connect' ||
          eventType == 'disconnect' ||
          eventType == 'connect_error' ||
          eventType == 'reconnect' ||
          eventType == 'reconnect_failed') {
        print(
            '🔌 SeSocketService: 🔇 Skipping notification for connection event: $eventType');
        return;
      }

      print(
          '🔌 SeSocketService: 🔔 Creating notification for event: $eventType');

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

      print('🔌 SeSocketService: ✅ Notification created for event: $eventType');
    } catch (e) {
      print(
          '🔌 SeSocketService: ❌ Failed to create notification for event $eventType: $e');
    }
  }

  // Method to reset the service for new connections
  static void resetForNewConnection() {
    print('🔌 SeSocketService: 🔄 Resetting service for new connection...');

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

        print('🔌 SeSocketService: ✅ Existing instance cleaned up');
      } catch (e) {
        print(
            '🔌 SeSocketService: ⚠️ Warning - error cleaning up existing instance: $e');
      }
    }

    print('🔌 SeSocketService: ✅ Service reset for new connection');
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
      print(
          '🔌 SeSocketService: ⚠️ Warning - could not add connection state event: $e');
    }
  }

  // Heartbeat and stability monitoring
  Timer? _heartbeatTimer;
  Timer? _stabilityTimer;
  Timer? _clientHeartbeatTimer;
  bool _sessionConfirmed = false;

  Function(String messageId)? onMessageAcked;
  Function(String messageId, String fromUserId, String conversationId,
      String body)? onMessageReceived;
  Function(String messageId, String fromUserId, String toUserId)? onDelivered;
  Function(String messageId, String fromUserId, String toUserId)? onRead;
  // 🆕 ADD THIS: Callback for queued message status
  Function(String messageId, String toUserId, String fromUserId)? onQueued;
  Function(String sessionId, bool isOnline, String timestamp)? onPresence;
  Function(String fromUserId, String conversationId, bool isTyping)? onTyping;
  Function(Map<String, dynamic> data)? onKeyExchangeRequest;
  Function(Map<String, dynamic> data)? onKeyExchangeResponse;
  Function(Map<String, dynamic> data)? onKeyExchangeRevoked;
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
      print(
          '🔌 SeSocketService: 🔄 Instance was destroyed, resetting for new connection...');
      SeSocketService.resetForNewConnection();
    }

    if (_socket != null) await disconnect();

    _sessionId = sessionId;
    _isConnecting = true;
    _ready = false;
    _sessionConfirmed = false;

    print('🔌 SeSocketService: Connecting to $_url with session: $sessionId');

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
          print(
              '🔌 SeSocketService: ⚠️ Connection timeout, forcing disconnect');
          _socket?.disconnect();
          _isConnecting = false;
          _addConnectionStateEvent(false);
        }
      });
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error creating socket connection: $e');
      _isConnecting = false;
      _addConnectionStateEvent(false);
      rethrow;
    }
  }

  void _bindCore() {
    _socket!.on('connect', (_) async {
      print('🔌 SeSocketService: ✅ Connected to server');
      _isConnecting = false;
      _reconnectAttempts = 0;
      // Don't set _ready = true here - wait for session_registered confirmation
      _addConnectionStateEvent(
          false); // Still not fully ready until session confirmed

      if (_sessionId != null) {
        print('🔌 SeSocketService: Registering session: $_sessionId');

        // Get the user's public key for session registration
        String? userPublicKey;
        try {
          // Import SeSessionService to get current user's public key
          final sessionService = SeSessionService();
          userPublicKey = sessionService.currentSession?.publicKey;
          if (userPublicKey != null) {
            print(
                '🔌 SeSocketService: ✅ Retrieved user public key for session registration');
          } else {
            print(
                '🔌 SeSocketService: ⚠️ No public key available in current session');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Warning - could not retrieve user public key: $e');
          // Continue without public key, but this may cause key exchange issues
        }

        // Register session with public key as required by API
        final registrationData = <String, dynamic>{
          'sessionId': _sessionId,
        };

        if (userPublicKey != null) {
          registrationData['publicKey'] = userPublicKey;
          print(
              '🔌 SeSocketService: 🔑 Including public key in session registration');
        } else {
          print(
              '🔌 SeSocketService: ⚠️ No public key available for session registration');
        }

        _socket!.emit('register_session', registrationData);

        // FALLBACK: If server doesn't send session_registered within 5 seconds,
        // assume registration was successful and proceed
        Timer(const Duration(seconds: 5), () {
          if (!_sessionConfirmed && _socket?.connected == true) {
            print(
                '🔌 SeSocketService: ⚠️ No session_registered received, assuming success');
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
      print('✅ SeSocketService: Session confirmed: ${data['sessionId']}');

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
      print('🔌 SeSocketService: ❌ Disconnected from server. Reason: $reason');
      _ready = false;
      _isConnecting = false;
      _addConnectionStateEvent(false);

      // Send offline presence before disconnecting
      if (_sessionId != null) {
        try {
          sendPresence(false, []); // Empty array means broadcast to all users
          print('🔌 SeSocketService: ✅ Offline presence sent on disconnect');
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Failed to send offline presence: $e');
        }
      }

      // Stop all timers
      _heartbeatTimer?.cancel();
      _stabilityTimer?.cancel();
      _clientHeartbeatTimer?.cancel();
    });

    _socket!.on('reconnect', (attemptNumber) {
      print(
          '🔌 SeSocketService: 🔄 Reconnected to server. Attempt: $attemptNumber');
      _isConnecting = false;
      _reconnectAttempts = 0;
      // Don't set _ready = true here - wait for session_registered confirmation
      _addConnectionStateEvent(false);

      // CRITICAL: Rebind event handlers after reconnection
      print(
          '🔌 SeSocketService: 🔄 Rebinding event handlers after reconnection');
      _bindCore();

      if (_sessionId != null) {
        print('🔌 SeSocketService: Re-registering session: $_sessionId');
        _socket!.emit('register_session', {'sessionId': _sessionId});

        // FALLBACK: If server doesn't send session_registered within 5 seconds,
        // assume registration was successful and proceed
        Timer(const Duration(seconds: 5), () {
          if (!_sessionConfirmed && _socket?.connected == true) {
            print(
                '🔌 SeSocketService: ⚠️ No session_registered received, assuming success');
            _sessionConfirmed = true;
            _ready = true;
            _startClientHeartbeat();
            _addConnectionStateEvent(true);
          }
        });
      }
    });

    _socket!.on('reconnect_failed', (data) {
      print('🔌 SeSocketService: ❌ Reconnection failed');
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
      print('🔌 SeSocketService: 🔍 Connection stability check received');
      _respondToStabilityCheck(data);
    });

    _socket!.on('connection:ping', (data) {
      print('🔌 SeSocketService: 🔍 Connection ping received');
      _respondToConnectionPing(data);
    });

    // Key exchange events
    _socket!.on('key_exchange:request', (data) async {
      print('🔑 SeSocketService: Key exchange request received');

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
        onKeyExchangeRequest!(data);
      }
    });

    _socket!.on('key_exchange:response', (data) async {
      print('🔑 SeSocketService: 🔍🔍🔍 KEY EXCHANGE RESPONSE EVENT RECEIVED!');
      print('🔑 SeSocketService: 🔍🔍🔍 Event data: $data');
      print('🔑 SeSocketService: 🔍🔍🔍 Data type: ${data.runtimeType}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
      print('🔑 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      print('🔑 SeSocketService: 🔍🔍🔍 Session ID: $_sessionId');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 onKeyExchangeResponse callback: ${onKeyExchangeResponse != null ? 'SET' : 'NULL'}');

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
        print(
            '🔑 SeSocketService: 🚀 Calling onKeyExchangeResponse callback...');
        onKeyExchangeResponse!(data);
        print('🔑 SeSocketService: ✅ onKeyExchangeResponse callback completed');
      } else {
        print('🔑 SeSocketService: ❌ onKeyExchangeResponse callback is NULL!');

        // CRITICAL: Even if callback is null, we need to process this event
        // This prevents the key exchange from failing completely
        print(
            '🔑 SeSocketService: 🚨 CRITICAL: Processing key exchange response without callback');
        print(
            '🔑 SeSocketService: 🔍 This should not happen - callback should be set in main.dart');

        // Try to process the event directly with KeyExchangeService as a fallback
        try {
          print(
              '🔑 SeSocketService: 🔄 Attempting fallback processing with KeyExchangeService...');
          // Import KeyExchangeService to handle the event directly
          // import 'package:sechat_app/core/services/key_exchange_service.dart'; // This import is already at the top
          KeyExchangeService.instance.handleKeyExchangeResponse(data);
          print(
              '🔑 SeSocketService: ✅ Fallback processing completed successfully');
        } catch (e) {
          print('🔑 SeSocketService: ❌ Fallback processing failed: $e');
          print(
              '🔑 SeSocketService: 🚨 This key exchange response will be lost!');
        }
      }
    });

    _socket!.on('key_exchange:revoked', (data) async {
      print('🔑 SeSocketService: Key exchange revoked');

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

    // User data exchange events
    _socket!.on('user_data_exchange:data', (data) async {
      print('🔑 SeSocketService: 🔍🔍🔍 USER DATA EXCHANGE EVENT RECEIVED!');
      print('🔑 SeSocketService: 🔍🔍🔍 Event: user_data_exchange:data');
      print('🔑 SeSocketService: 🔍🔍🔍 Data: $data');
      print('🔑 SeSocketService: 🔍🔍🔍 Data type: ${data.runtimeType}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
      print('🔑 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      print('🔑 SeSocketService: 🔍🔍🔍 Session ID: $_sessionId');
      print('🔑 SeSocketService: 🔍🔍🔍 Session confirmed: $_sessionConfirmed');
      print('🔑 SeSocketService: 🔍🔍🔍 Socket ID: ${_socket?.id}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Socket transport: ${_socket?.io.engine?.transport?.name ?? 'unknown'}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 onUserDataExchange callback: ${onUserDataExchange != null ? 'SET' : 'NULL'}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Current timestamp: ${DateTime.now().toIso8601String()}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Event received on recipient side: ${_sessionId == data['recipientId'] ? 'YES' : 'NO'}');

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
        print('🔑 SeSocketService: 🚀 Calling onUserDataExchange callback...');
        onUserDataExchange!(data);
        print('🔑 SeSocketService: ✅ onUserDataExchange callback completed');
      } else {
        print('🔑 SeSocketService: ❌ onUserDataExchange callback is NULL!');

        // CRITICAL: Even if callback is null, we need to process this event
        // This prevents user data exchange from failing completely
        print(
            '🔑 SeSocketService: 🚨 CRITICAL: Processing user data exchange without callback');
        print(
            '🔑 SeSocketService: 🔍 This should not happen - callback should be set in main.dart');

        // Try to process the event directly with KeyExchangeService as a fallback
        try {
          print(
              '🔑 SeSocketService: 🔄 Attempting fallback processing with KeyExchangeService...');

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
          print(
              '🔑 SeSocketService: ✅ Fallback processing completed successfully');
          } else {
            print(
                '🔑 SeSocketService: ❌ Invalid user data exchange data: senderId=$senderId, encryptedData=${encryptedData != null}');
          }
        } catch (e) {
          print('🔑 SeSocketService: ❌ Fallback processing failed: $e');
          print('🔑 SeSocketService: 🚨 This user data exchange will be lost!');
        }
      }
    });

    // Conversation creation events
    _socket!.on('conversation:created', (data) async {
      print('💬 SeSocketService: Conversation created event received');

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
      print('🗑️ SeSocketService: User deleted event received');

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
      print('✅ SeSocketService: Message acknowledged');
      final id = data['messageId']?.toString() ?? '';
      if (id.isNotEmpty) onMessageAcked?.call(id);
    });

    _socket!.on('message:received', (data) async {
      print('💬 SeSocketService: Message received');

      if (onMessageReceived != null) {
        onMessageReceived!(
          data['messageId'] ?? '',
          data['fromUserId'] ?? '',
          data['conversationId'] ?? '',
          data['body'] ?? '',
        );
      }
    });

    // 🚫 REMOVED: Legacy message:delivered handler - now handled by message:status_update
    // This prevents premature status updates when recipient is offline

    // 🚫 REMOVED: Legacy message:read handler - now handled by message:status_update
    // This prevents premature status updates when recipient is offline

    // Presence events - CONSOLIDATED FLOW
    _socket!.on('presence:update', (data) async {
      print('🟢 SeSocketService: Presence update received');
      print('🟢 SeSocketService: 🔍 Presence data: $data');

      // Create notification for presence update (only if not silent)
      final bool silent = data['silent'] ?? false;
      if (!silent) {
        final bool isOnline = data['isOnline'] ?? false;
        await _createSocketEventNotification(
          eventType: 'presence:update',
          title: isOnline ? 'User Online' : 'User Offline',
          body: isOnline ? 'User came online' : 'User went offline',
          senderId: data['sessionId']?.toString(),
          metadata: data,
          silent: silent,
        );
      }

      // Call the main presence callback (mapped to onPresence via setOnOnlineStatusUpdate)
      if (onPresence != null) {
        print(
            '🟢 SeSocketService: 🔄 Calling onPresence callback (mapped from onOnlineStatusUpdate)');
        onPresence!(
          data['sessionId'] ?? '',
          data['isOnline'] ?? false,
          data['timestamp'] ?? '',
        );
        print('🟢 SeSocketService: ✅ onPresence callback executed');
      } else {
        print(
            '🟢 SeSocketService: ⚠️ onPresence callback is null - presence not processed!');
      }
    });

    // Contact management events
    _socket!.on('contacts:added', (data) async {
      print('🔗 SeSocketService: Contact added event received');
      print('🔗 SeSocketService: 🔍 Contact data: $data');

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
        print('🔗 SeSocketService: ⚠️ onContactAdded callback is null');
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
      print(
          '📬 SeSocketService: ✅ Recipient has actually processed/viewed the message');

      // CRITICAL: Generate conversation ID if missing (server doesn't always send it)
      if (conversationId == null || conversationId.isEmpty) {
        conversationId =
            _generateConsistentConversationId(fromUserId, toUserId);
        print(
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
        print(
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
      final String messageId = data['messageId'];
      final String status = data['status'];
      final String? fromUserId = data['fromUserId'];
      final String? toUserId = data['toUserId'];
      final String? conversationId = data['conversationId'];
      final String? recipientId = data['recipientId'];
      final bool silent = data['silent'] ?? false;
      final bool wasQueued = data['wasQueued'] ?? false;

      print(
          '📊 SeSocketService: [STATUS] Message status update: $messageId -> $status (silent: $silent, queued: $wasQueued)');

      // 🆕 FIXED: Filter out delivered/read status updates from message:status_update
      // These should only come through receipt:delivered and receipt:read events
      if (status.toLowerCase() == 'delivered' ||
          status.toLowerCase() == 'read') {
        print(
            '📊 SeSocketService: ⚠️ Ignoring delivered/read status from message:status_update - waiting for proper receipt events');
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

      print('📬 SeSocketService: Message queued: $messageId (reason: $reason)');

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
      final String fromUserId = data['fromUserId'];
      final String recipientId = data['recipientId'];
      final String conversationId = data['conversationId'] ?? '';
      final String showIndicatorOnSessionId =
          data['showIndicatorOnSessionId'] ?? ''; // NEW: Server field
      final bool isTyping = data['isTyping'];
      final bool delivered = data['delivered'];
      final bool autoStopped = data['autoStopped'] ?? false;
      final bool silent = data['silent'] ?? false;

      print(
          '⌨️ SeSocketService: Typing status update: $fromUserId -> $recipientId (delivered: $delivered, autoStopped: $autoStopped)');
      print('⌨️ SeSocketService: 🔍 Conversation ID: $conversationId');

      // CRITICAL: Only show typing indicator if we are the session that should display it
      final currentSessionId = _sessionId;
      if (currentSessionId != null &&
          showIndicatorOnSessionId == currentSessionId) {
        print(
            '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

        // Update local typing status using the direct recipientId from server
      _updateTypingStatus(
          fromUserId, recipientId, isTyping, delivered, autoStopped);

        // Notify typing status change for UI updates
        _notifyTypingStatusChange(
            fromUserId, recipientId, isTyping, delivered, autoStopped);
      } else {
        print(
            '⌨️ SeSocketService: ℹ️ Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
      }

      // Notify listeners about typing status change (silent)
      if (silent) {
        // Silent updates still need to update the UI
        print('⌨️ SeSocketService: 🔔 Silent typing update - updating UI only');
      } else {}
    });

    _socket!.on('contacts:removed', (data) async {
      print('🔗 SeSocketService: Contact removed event received');
      print('🔗 SeSocketService: 🔍 Contact data: $data');

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
        print('🔗 SeSocketService: ⚠️ onContactRemoved callback is null');
      }
    });

    // Typing events - RECIPIENT receives this when someone types
    _socket!.on('typing:update', (data) async {
      print(
          '⌨️ SeSocketService: 🔔 TYPING UPDATE EVENT RECEIVED (recipient side)');
      print('⌨️ SeSocketService: 🔍 Typing data: $data');
      print(
          '⌨️ SeSocketService: 🔍 onTyping callback: ${onTyping != null ? 'SET' : 'NULL'}');

      // Create notification for typing update (only if not silent)
      final bool silent = data['silent'] ?? false;

      // CRITICAL: Only call typing callback if we should show the typing indicator
      final currentSessionId = _sessionId;
      final showIndicatorOnSessionId = data['showIndicatorOnSessionId'] ?? '';

      if (currentSessionId != null &&
          showIndicatorOnSessionId == currentSessionId) {
        print(
            '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

      if (onTyping != null) {
        onTyping!(
          data['fromUserId'] ?? '',
          data['conversationId'] ?? '',
          data['isTyping'] ?? false,
        );
        print('⌨️ SeSocketService: ✅ Typing callback executed');
      } else {
        print(
            '⌨️ SeSocketService: ❌ onTyping callback is NULL - typing indicator not processed!');
        }
      } else {
        print(
            '⌨️ SeSocketService: ℹ️ Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
      }

      // ✅ FIX: Only call internal handler if we should show the typing indicator
      try {
        final fromUserId = data['fromUserId'] ?? '';
        final conversationId = data['conversationId'] ?? '';
        final showIndicatorOnSessionId =
            data['showIndicatorOnSessionId'] ?? ''; // NEW: Server field
        final isTyping = data['isTyping'] ?? false;

        // CRITICAL: Only show typing indicator if we are the session that should display it
        final currentSessionId = _sessionId;
        if (currentSessionId != null &&
            showIndicatorOnSessionId == currentSessionId) {
          print(
              '⌨️ SeSocketService: ✅ We should show typing indicator (session match)');

        // Call the internal handler to update SessionChatProvider
          // Use the direct recipientId from server for better accuracy
          final recipientId = data['recipientId'] ?? '';
        _notifyTypingStatusChange(
              fromUserId, recipientId, isTyping, true, false);
        print(
            '⌨️ SeSocketService: ✅ Internal typing status change handler called');
        } else {
          print(
              '⌨️ SeSocketService: ℹ️ Not showing typing indicator - session mismatch: current=$currentSessionId, shouldShow=$showIndicatorOnSessionId');
        }
      } catch (e) {
        print(
            '⌨️ SeSocketService: ❌ Error calling internal typing handler: $e');
      }
    });

    // Debug: Log all incoming events (reduced for less clutter)
    _socket!.onAny((event, data) {
      // Always log typing-related events for debugging
      if (event.contains('typing')) {
        print(
            '🔍 SeSocketService: 🔔 TYPING EVENT RECEIVED: $event with data: $data');
      }
      // Only log important events, skip routine stats, admin logs, and heartbeat
      else if (!event.startsWith('server_stats') &&
          !event.startsWith('channel_update') &&
          !event.startsWith('heartbeat') &&
          !event.startsWith('admin_log')) {
        print(
            '🔍 SeSocketService: DEBUG - Received event: $event with data: $data');
      }

      // Special debugging for user data exchange events
      if (event == 'user_data_exchange:data') {
        print('🔍 SeSocketService: 🔍🔍🔍 USER DATA EXCHANGE EVENT RECEIVED!');
        print('🔍 SeSocketService: 🔍🔍🔍 Event: $event');
        print('🔍 SeSocketService: 🔍🔍🔍 Data: $data');
        print('🔍 SeSocketService: 🔍🔍🔍 Current session ID: $_sessionId');
        print(
            '🔍 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
        print('🔍 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      }

      // Debug ALL key exchange related events
      if (event.contains('user_data') ||
          event.contains('conversation') ||
          event.contains('key_exchange')) {
        print('🔍 SeSocketService: 🔍🔍🔍 KEY EXCHANGE EVENT RECEIVED!');
        print('🔍 SeSocketService: 🔍🔍🔍 Event: $event');
        print('🔍 SeSocketService: 🔍🔍🔍 Data: $data');
        print('🔍 SeSocketService: 🔍🔍🔍 Current session ID: $_sessionId');
        print(
            '🔍 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
        print('🔍 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('🔌 SeSocketService: Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer(Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30)), () {
      if (_sessionId != null && !_ready && !_isConnecting) {
        print('🔌 SeSocketService: 🔄 Attempting reconnection...');
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
      print('🔄 SeSocketService: Stability check response sent');
    }
  }

  // CRITICAL: Connection ping response (MUST respond within 1 second)
  void _respondToConnectionPing(dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('connection:pong', {
        'sessionId': _sessionId,
        'timestamp': DateTime.now().toIso8601String()
      });
      print('🏓 SeSocketService: Connection ping response sent');
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
      print(
          '🔌 SeSocketService: ❌ Cannot send presence update - not connected or no session');
      return;
    }

    try {
      final payload = {
        'fromUserId': _sessionId,
        'isOnline': isOnline,
        'toUserIds': toUserIds, // Array of user IDs to notify
        'timestamp': DateTime.now().toIso8601String(),
      };

      print(
          '🔌 SeSocketService: 🟢 Sending presence update: ${isOnline ? 'online' : 'offline'} to ${toUserIds.length} users');
      print('🔌 SeSocketService: 🔍 Payload: $payload');

      _socket!.emit('presence:update', payload);
      print('🔌 SeSocketService: ✅ Presence update sent successfully');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending presence update: $e');
      _scheduleReconnect();
    }
  }

  /// Send typing indicator to a specific user
  void sendTyping(String recipientId, String conversationId, bool isTyping) {
    if (!isConnected || _sessionId == null) {
      print(
          '🔌 SeSocketService: ❌ Cannot send typing indicator - not connected or no session');
      return;
    }

    try {
      // CRITICAL: Use the conversation ID passed from SessionChatProvider
      // According to server docs, this should be the existing conversation ID
      final currentUserId = _sessionId;

      // Validate that we have a valid sender ID
      if (currentUserId == null || currentUserId.isEmpty) {
        print('🔌 SeSocketService: ❌ ERROR: Invalid sender session ID');
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

      final payload = {
        'fromUserId': _sessionId,
        'recipientId': recipientId, // Required by server for direct routing
        'conversationId': finalConversationId, // Use the passed conversation ID
        'isTyping': isTyping,
        'showIndicatorOnSessionId':
            cleanShowIndicatorId, // Clean session ID for display
        'metadata': {
          'encrypted':
              false, // Set to true if you want encrypted typing indicators
          'version': '1.0',
          'encryptionType': 'none'
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
      print(
          '⌨️ SeSocketService: Typing status tracked: $key -> ${isTyping ? 'typing' : 'stopped'}');

      print(
          '🔌 SeSocketService: ⌨️ Sending typing indicator: ${isTyping ? 'started' : 'stopped'} to $recipientId');
      print('🔌 SeSocketService: 🔍 Payload: $payload');
      print(
          '🔌 SeSocketService: 🔍 conversationId (final): $finalConversationId');
      print('🔌 SeSocketService: 🔍 fromUserId (sender): $_sessionId');

      _socket!.emit('typing:update', payload);
      print('🔌 SeSocketService: ✅ Typing indicator sent successfully');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending typing indicator: $e');
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
    print('🔌 SeSocketService: 🔧 sendMessage called with:');
    print('🔌 SeSocketService: 🔍 messageId: $messageId');
    print('🔌 SeSocketService: 🔍 recipientId: $recipientId');
    print('🔌 SeSocketService: 🔍 body: $body');
    print('🔌 SeSocketService: 🔍 conversationId: $conversationId');
    if (!isConnected || _sessionId == null) {
      print(
          '🔌 SeSocketService: ❌ Cannot send message - not connected or no session');
      return;
    }

    try {
      // CRITICAL: Use consistent conversation ID for both users
      final currentUserId = _sessionId;

      // Validate that we have a valid sender ID
      if (currentUserId == null || currentUserId.isEmpty) {
        print('🔌 SeSocketService: ❌ ERROR: Invalid sender session ID');
        return;
      }

      // Use the passed conversationId if provided, otherwise generate one
      final consistentConversationId = conversationId?.isNotEmpty == true
          ? conversationId!
          : _generateConsistentConversationId(currentUserId, recipientId);

      print('🔌 SeSocketService: 🔍 Passed conversationId: $conversationId');
      print(
          '🔌 SeSocketService: 🔍 Generated consistentConversationId: $consistentConversationId');
      print(
          '🔌 SeSocketService: 🔍 Using conversationId: $consistentConversationId');

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
        print('🔌 SeSocketService: ✅ Message encrypted successfully');
      } catch (e) {
        print('🔌 SeSocketService: ❌ Failed to encrypt message: $e');
        return;
      }

      final payload = {
        'type': 'message:send',
        'messageId': messageId,
        'conversationId':
            consistentConversationId, // Use consistent conversation ID
        'fromUserId': _sessionId, // CORRECT: This should be the sender's ID
        'recipientId': recipientId, // Add recipient ID for server routing
        'toUserIds': [recipientId],
        'body': encryptedResult['data']!,
        'checksum': encryptedResult['checksum']!,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'encrypted': true,
          'version': '2.0',
          'encryptionType': 'AES-256-CBC',
          'checksum': encryptedResult['checksum']!,
        },
      };

      // Track message locally for status updates
      _messageStatuses[messageId] = 'sent';
      print('📊 SeSocketService: Message status tracked: $messageId -> sent');

      print(
          '🔌 SeSocketService: 📤 Sending message: $messageId to $recipientId');
      print('🔌 SeSocketService: 🔍 Payload: $payload');
      print(
          '🔌 SeSocketService: 🔍 conversationId (consistent): $consistentConversationId');
      print('🔌 SeSocketService: 🔍 fromUserId (sender): $_sessionId');

      _socket!.emit('message:send', payload);
      print('🔌 SeSocketService: ✅ Message sent successfully');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message: $e');
      _scheduleReconnect();
    }
  }

  void sendReadReceipt(String toUserId, String messageId) {
    if (!isConnected || _sessionId == null) return;

    // CRITICAL: Use consistent conversation ID for both users
    final currentUserId = _sessionId!;
    final consistentConversationId =
        _generateConsistentConversationId(currentUserId, toUserId);

    _socket!.emit('receipt:read', {
      'messageId': messageId,
      'fromUserId': _sessionId,
      'toUserId': toUserId,
      'conversationId':
          consistentConversationId, // Use consistent conversation ID
      'recipientId': toUserId, // Add recipient ID for server routing
      'timestamp': DateTime.now().toIso8601String()
    });
  }

  void sendKeyExchangeRequest(
      {required String recipientId,
      required String publicKey,
      required String requestId,
      required String requestPhrase,
      String version = '1'}) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('key_exchange:request', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'publicKey': publicKey,
      'requestId': requestId,
      'requestPhrase': requestPhrase,
      'version': version
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
    print('🔑 SeSocketService: 🔍🔍🔍 SENDING USER DATA EXCHANGE EVENT!');
    print('🔑 SeSocketService: 🔍🔍🔍 Event: user_data_exchange:send');
    print(
        '🔑 SeSocketService: 🔍🔍🔍 Data: {recipientId: $recipientId, senderId: $_sessionId, encryptedData: ${encryptedData.substring(0, 50)}..., conversationId: $conversationId}');
    print('🔑 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
    print('🔑 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
    print('🔑 SeSocketService: 🔍🔍🔍 Session ID: $_sessionId');
    print('🔑 SeSocketService: 🔍🔍🔍 Session confirmed: $_sessionConfirmed');
    print('🔑 SeSocketService: 🔍🔍🔍 Socket ID: ${_socket?.id}');

    if (!isConnected || _sessionId == null) {
      print(
          '🔑 SeSocketService: ❌ Cannot send - socket not connected or session ID null');
      return;
    }

    try {
    _socket!.emit('user_data_exchange:send', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'encryptedData': encryptedData,
      'conversationId': conversationId ?? ''
    });
      print('🔑 SeSocketService: ✅ User data exchange event sent successfully');
    } catch (e) {
      print(
          '🔑 SeSocketService: ❌ Failed to send user data exchange event: $e');
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
      print(
          '🔌 SeSocketService: 🔄 Instance was destroyed, resetting for cleanup...');
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
        print('🔌 SeSocketService: 🚪 Leaving room/channel: $_sessionId');

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
          print(
              '🔌 SeSocketService: ⚠️ Warning - could not send leaving event: $e');
        }

        // Now disconnect
        _socket!.disconnect();
        _socket!.destroy();
        print('🔌 SeSocketService: ✅ Socket disconnected and room left');
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error during disconnect: $e');
    } finally {
      _socket = null;
    }
  }

  // Compatibility methods for existing code
  void setOnMessageReceived(
      Function(String senderId, String senderName, String message,
              String conversationId, String messageId)?
          callback) {
    // Map the existing callback to the new format
    if (callback != null) {
      onMessageReceived = (messageId, fromUserId, conversationId, body) {
        // Try to get sender name from contact service or use userId as fallback
        String senderName = fromUserId; // Default to userId

        try {
          // Get contact display name from contact service
          final contact = ContactService.instance.getContact(fromUserId);
          if (contact != null && contact.displayName != null) {
            senderName = contact.displayName!;
          }
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Could not get sender name: $e');
        }

        callback(fromUserId, senderName, body, conversationId, messageId);
      };
    }
  }

  void setOnTypingIndicator(
      Function(String senderId, bool isTyping)? callback) {
    print(
        '🔌 SeSocketService: 🔧 Setting typing indicator callback: ${callback != null ? 'SET' : 'NULL'}');

    // Map the existing callback to the new format
    if (callback != null) {
      onTyping = (fromUserId, conversationId, isTyping) {
        print(
            '🔌 SeSocketService: 🔧 onTyping callback mapped: $fromUserId -> $isTyping');
        callback(fromUserId, isTyping);
      };
      print('🔌 SeSocketService: ✅ Typing indicator callback set successfully');
    } else {
      print('🔌 SeSocketService: ⚠️ Typing indicator callback is null');
      onTyping = null;
    }
  }

  // NEW: Enhanced typing indicator callback with showIndicatorOnSessionId
  void setOnTypingIndicatorEnhanced(
      Function(String senderId, bool isTyping, String showIndicatorOnSessionId)?
          callback) {
    print(
        '🔌 SeSocketService: 🔧 Setting ENHANCED typing indicator callback: ${callback != null ? 'SET' : 'NULL'}');

    // Map the enhanced callback to the new format
    if (callback != null) {
      onTyping = (fromUserId, conversationId, isTyping) {
        print(
            '🔌 SeSocketService: 🔧 Enhanced onTyping callback mapped: $fromUserId -> $isTyping');
        callback(fromUserId, isTyping,
            conversationId); // Pass conversationId as showIndicatorOnSessionId for now
      };
      print(
          '🔌 SeSocketService: ✅ Enhanced typing indicator callback set successfully');
    } else {
      print(
          '🔌 SeSocketService: ⚠️ Enhanced typing indicator callback is null');
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

  void setOnKeyExchangeResponse(Function(Map<String, dynamic> data)? callback) {
    if (callback != null) {
      onKeyExchangeResponse = callback;
    }
  }

  void setOnKeyExchangeDeclined(Function(Map<String, dynamic> data)? callback) {
    // This might need to be handled differently since there's no direct decline event
    // For now, we'll map it to a general key exchange event
    if (callback != null) {
      // We could emit a custom event or handle it through the response callback
      print(
          '⚠️ setOnKeyExchangeDeclined: Not implemented in current socket service');
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
      print(
          '🔌 SeSocketService: ℹ️ initialize() called, but SeSocketService uses connect() method');
      print(
          '🔌 SeSocketService: ℹ️ Please use connect($_sessionId) instead of initialize()');
      // Auto-connect if we have a session ID
      await connect(_sessionId!);
    } else {
      print(
          '🔌 SeSocketService: ⚠️ initialize() called but no session ID available');
      print(
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
    print('🔌 SeSocketService: Debug State:');
    print('  - Connected: ${_socket?.connected ?? false}');
    print('  - Ready: $_ready');
    print('  - Session Confirmed: $_sessionConfirmed');
    print('  - Session ID: $_sessionId');
    print('  - Socket ID: ${_socket?.id ?? 'null'}');
    print('  - Is Connecting: $_isConnecting');
    print('  - Reconnect Attempts: $_reconnectAttempts');
  }

  // Method to manually check connection health
  void checkConnectionHealth() {
    print('🔌 SeSocketService: Connection Health Check:');
    print('  - Socket exists: ${_socket != null}');
    if (_socket != null) {
      print('  - Socket connected: ${_socket!.connected}');
      print('  - Socket id: ${_socket!.id}');
      try {
        final engine = _socket!.io.engine;
        if (engine != null) {
          final transport = engine.transport;
          print('  - Socket transport: ${transport?.name ?? 'unknown'}');
        } else {
          print('  - Socket transport: engine is null');
        }
      } catch (e) {
        print('  - Socket transport: error accessing - $e');
      }
    }
    print('  - Ready state: $_ready');
    print('  - Session confirmed: $_sessionConfirmed');
    print('  - Session ID: $_sessionId');
    print(
        '  - Connection state stream active: ${_connectionStateController?.isClosed == false}');
  }

  // Method for testing connections (used by main_nav_screen)
  void emit(String event, Map<String, dynamic> data) {
    if (!isConnected || _sessionId == null) {
      print(
          '🔌 SeSocketService: ❌ Cannot emit event: Socket not connected or session invalid');
      print(
          '🔌 SeSocketService: 🔍 Connection status: isConnected=$isConnected, sessionId=$_sessionId');
      return;
    }

    // Debug logging for key exchange events
    if (event == 'key_exchange:accept') {
      print('🔌 SeSocketService: 🔍🔍🔍 SENDING KEY EXCHANGE ACCEPT EVENT!');
      print('🔌 SeSocketService: 🔍🔍🔍 Event: $event');
      print('🔌 SeSocketService: 🔍🔍🔍 Data: $data');
      print(
          '🔌 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
      print('🔌 SeSocketService: 🔍🔍🔍 Session ID: $_sessionId');
    }

    try {
      _socket!.emit(event, data);

      // Confirm the event was sent
      if (event == 'key_exchange:accept') {
        print(
            '🔌 SeSocketService: ✅ Key exchange accept event sent via socket');
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error emitting event $event: $e');
      print(
          '🔌 SeSocketService: 🔍 This may be due to socket connectivity issues');

      // Try to reconnect if there's a connection issue
      if (_socket?.connected == false) {
        print(
            '🔌 SeSocketService: 🔄 Attempting to reconnect due to emit failure...');
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

      print(
          '🔌 SeSocketService: ✅ Session deletion request sent for: $sessionToDelete');

      // Wait a moment for the server to process the deletion
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending session deletion: $e');
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

      _socket!.emit('message:status_update', {
        'recipientId': recipientId,
        'messageId': messageId,
        'status': status ?? 'sent',
        'conversationId':
            effectiveConversationId, // ✅ Use proper conversation ID
        'timestamp': DateTime.now().toIso8601String(),
      });
      print(
          '🔌 SeSocketService: Message status update sent: $messageId -> $status (conversationId: $effectiveConversationId)');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message status update: $e');
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
      print(
          '📬 SeSocketService: Delivery receipt sent: $messageId -> $recipientId (conversationId: $effectiveConversationId)');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending delivery receipt: $e');
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
    print('🔌 SeSocketService: 🧹 Disposing socket service...');

    // Clean up all timers and resources
    _heartbeatTimer?.cancel();
    _stabilityTimer?.cancel();
    _clientHeartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    // Close stream controller
    try {
      _connectionStateController?.close();
    } catch (e) {
      print(
          '🔌 SeSocketService: ⚠️ Warning - stream controller already closed: $e');
    }

    // Force disconnect socket
    try {
      if (_socket != null) {
        // Disable reconnection to prevent memory leaks
        _socket!.disconnect();
        _socket!.destroy();
        print('🔌 SeSocketService: ✅ Socket destroyed');
      }
    } catch (e) {
      print('🔌 SeSocketService: ⚠️ Warning - socket cleanup failed: $e');
    } finally {
      _socket = null;
    }

    // Clear all state
    _ready = false;
    _isConnecting = false;
    _sessionConfirmed = false;
    _reconnectAttempts = 0;
    _sessionId = null;

    print('🔌 SeSocketService: ✅ Socket service disposed completely');
  }

  // Force disconnect without sending events (for account deletion)
  Future<void> forceDisconnect() async {
    // If instance was destroyed, reset it for cleanup
    if (SeSocketService.isDestroyed) {
      print(
          '🔌 SeSocketService: 🔄 Instance was destroyed, resetting for cleanup...');
      SeSocketService.resetForNewConnection();
    }

    print('🔌 SeSocketService: 🚫 Force disconnecting (no events sent)...');

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
        print('🔌 SeSocketService: ✅ Force disconnect completed');
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error during force disconnect: $e');
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
  void sendTypingIndicator(String recipientId, bool isTyping) {
    // Use recipient's session ID as conversation ID for simplicity
    sendTyping(recipientId, recipientId, isTyping);
  }

  // Method for sending user online status (used by auth screens)
  Future<void> sendUserOnlineStatus(bool isOnline) async {
    if (!isConnected || _sessionId == null) return;

    try {
      // Send presence update to all contacts
      sendPresence(isOnline, []); // Empty list means broadcast to all
      print(
          '🔌 SeSocketService: User online status sent: ${isOnline ? 'online' : 'offline'}');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending user online status: $e');
    }
  }

  // Method for setting up contact listeners (compatibility with old code)
  void setupContactListeners(List<String> contactSessionIds) {
    if (!isConnected || _sessionId == null) return;

    print(
        '🔌 SeSocketService: Setting up listeners for ${contactSessionIds.length} contacts');

    // In the new room-based system, we don't need to set up individual contact listeners
    // The server handles routing based on session IDs
    // This method is kept for compatibility but doesn't need to do anything

    for (final contactId in contactSessionIds) {
      print('🔌 SeSocketService: ✅ Listener ready for contact: $contactId');
    }
  }

  // Test method to verify socket connection and send test events
  Future<bool> testSocketConnection() async {
    try {
      print('🔌 SeSocketService: 🧪 Testing socket connection...');

      if (!isConnected) {
        print('🔌 SeSocketService: ❌ Socket not connected');
        return false;
      }

      if (_sessionId == null) {
        print('🔌 SeSocketService: ❌ No session ID');
        return false;
      }

      print('🔌 SeSocketService: ✅ Socket connected with session: $_sessionId');

      // Test sending a presence update to ourselves
      try {
        sendPresence(true, [_sessionId!]);
        print('🔌 SeSocketService: ✅ Test presence update sent successfully');
        return true;
      } catch (e) {
        print('🔌 SeSocketService: ❌ Test presence update failed: $e');
        return false;
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Test connection failed: $e');
      return false;
    }
  }

  void _onSocketConnected() {
    print('🔌 SeSocketService: ✅ Connected to server');
    _isConnecting = false;
    _ready = false;
    _addConnectionStateEvent(true);

    // Send presence update to indicate we're online
    if (_sessionId != null) {
      try {
        sendPresence(true, []); // Empty array means broadcast to all users
        print('🔌 SeSocketService: ✅ Online presence sent on connection');
      } catch (e) {
        print('🔌 SeSocketService: ⚠️ Failed to send online presence: $e');
      }
    }
  }

  // Helper method to send online presence to all users
  void _sendOnlinePresence() {
    if (_sessionId != null) {
      sendPresence(true, []); // Empty array means broadcast to all users
      print(
          '🔌 SeSocketService: ✅ Online presence sent on session confirmation');
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

        print(
            '🔌 SeSocketService: ✅ Session deletion request sent for: $sessionToDelete');
      } catch (e) {
        print(
            '🔌 SeSocketService: ❌ Error sending session deletion request: $e');
      }
    } else {
      print(
          '🔌 SeSocketService: ❌ Cannot add contact - not connected or no session');
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

        print('🔗 SeSocketService: ✅ Contact added: $contactSessionId');
      } catch (e) {
        print('🔗 SeSocketService: ❌ Error adding contact: $e');
      }
    } else {
      print(
          '🔗 SeSocketService: ❌ Cannot add contact - not connected or no session');
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

        print('🔗 SeSocketService: ✅ Contact removed: $contactSessionId');
      } catch (e) {
        print('🔗 SeSocketService: ❌ Error removing contact: $e');
      }
    } else {
      print(
          '🔗 SeSocketService: ❌ Cannot remove contact - not connected or no session');
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

        print('📡 SeSocketService: ✅ Broadcasting presence to all contacts');
      } catch (e) {
        print('📡 SeSocketService: ❌ Error broadcasting presence: $e');
      }
    } else {
      print(
          '📡 SeSocketService: ❌ Cannot broadcast presence - not connected or no session');
    }
  }

  /// Update presence for specific users or broadcast to all contacts
  void updatePresence(bool isOnline, {List<String>? specificUsers}) {
    if (_socket != null && _sessionId != null) {
      try {
        final payload = {
          'fromUserId': _sessionId,
          'isOnline': isOnline,
          'timestamp': DateTime.now().toIso8601String(),
        };

        // If specific users provided, send to them; otherwise broadcast to all contacts
        if (specificUsers != null && specificUsers.isNotEmpty) {
          payload['toUserIds'] = specificUsers;
          print(
              '📡 SeSocketService: 🟢 Sending presence update: ${isOnline ? 'online' : 'offline'} to ${specificUsers.length} specific users');
        } else {
          payload['toUserIds'] = []; // Empty array = broadcast to all contacts
          print(
              '📡 SeSocketService: 🟢 Broadcasting presence update: ${isOnline ? 'online' : 'offline'} to all contacts');
        }

        print('📡 SeSocketService: 🔍 Presence payload: $payload');
        _socket!.emit('presence:update', payload);
        print('📡 SeSocketService: ✅ Presence update sent successfully');
      } catch (e) {
        print('📡 SeSocketService: ❌ Error sending presence update: $e');
        _scheduleReconnect();
      }
    } else {
      print(
          '📡 SeSocketService: ❌ Cannot send presence update - not connected or no session');
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

        _socket!.emit('presence:request', payload);

        print(
            '🔌 SeSocketService: ✅ Presence status requested for ${contactIds.length} contacts');
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error requesting presence status: $e');
        _scheduleReconnect();
      }
    } else {
      print(
          '🔌 SeSocketService: ❌ Cannot request presence status - socket not connected');
    }
  }

  // Enhanced status tracking fields
  final Map<String, String> _messageStatuses = {};
  final Map<String, Map<String, dynamic>> _typingStatuses = {};

  // Helper methods for status updates
  void _updateMessageStatus(String messageId, String status, String recipientId,
      {String? conversationId}) {
    _messageStatuses[messageId] = status;
    print(
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
    print(
        '⌨️ SeSocketService: Typing status updated: $key -> delivered: $delivered, autoStopped: $autoStopped');
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
    print(
        '📊 SeSocketService: Notifying message status change: $messageId -> $status');
    // TODO: Implement notification system for message status changes
    // This should update the UI without showing user notifications
  }

  void _notifyTypingStatusChange(String fromUserId, String recipientId,
      bool isTyping, bool delivered, bool autoStopped) {
    print(
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
          print(
              '⌨️ SeSocketService: ⚠️ Ignoring own typing indicator - we are the sender: $fromUserId');
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
            print(
                '⌨️ SeSocketService: ✅ Direct user ID match for typing indicator');
          }
          // Method 2: Conversation ID match (if currentRecipientId is a conversation ID)
          else if (currentRecipientId.startsWith('chat_') &&
              ConversationIdGenerator.isParticipant(
                  currentRecipientId, fromUserId)) {
            shouldUpdate = true;
            print(
                '⌨️ SeSocketService: ✅ Conversation ID match for typing indicator');
          }
          // Method 3: Recipient ID match (if recipientId is a conversation ID)
          else if (recipientId.startsWith('chat_') &&
              ConversationIdGenerator.isParticipant(recipientId, fromUserId)) {
            shouldUpdate = true;
            print(
                '⌨️ SeSocketService: ✅ Recipient ID match for typing indicator');
          }

          if (shouldUpdate) {
            // ✅ Update the typing indicator on the RECIPIENT's side
          sessionChatProvider.updateRecipientTypingState(isTyping);
          print(
                '⌨️ SeSocketService: ✅ Typing status updated for current conversation: $fromUserId -> $isTyping');
        } else {
          print(
                '⌨️ SeSocketService: ℹ️ Typing indicator from different conversation: $fromUserId -> $recipientId (current: $currentRecipientId)');
          }
        } else {
          print(
              '⌨️ SeSocketService: ℹ️ No current recipient set, cannot update typing status');
        }
      } else {
        print(
            '⌨️ SeSocketService: ⚠️ No context available for typing status update');
      }
    } catch (e) {
      print(
          '⌨️ SeSocketService: ❌ Error updating typing status via SessionChatProvider: $e');
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
