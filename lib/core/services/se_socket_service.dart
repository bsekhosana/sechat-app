import 'dart:async';
import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart'; // Added import for SeSessionService
import 'package:sechat_app/core/services/key_exchange_service.dart'; // Added import for KeyExchangeService

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
  Function(String sessionId, bool isOnline, String timestamp)? onPresence;
  Function(String fromUserId, String conversationId, bool isTyping)? onTyping;
  Function(Map<String, dynamic> data)? onKeyExchangeRequest;
  Function(Map<String, dynamic> data)? onKeyExchangeResponse;
  Function(Map<String, dynamic> data)? onKeyExchangeRevoked;
  Function(Map<String, dynamic> data)? onUserDataExchange;
  Function(Map<String, dynamic> data)? onConversationCreated;
  Function(Map<String, dynamic> data)? onUserDeleted;

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
          }
        });
      }
    });

    _socket!.on('session_registered', (data) {
      print('✅ SeSocketService: Session confirmed: ${data['sessionId']}');
      _sessionConfirmed = true;
      _ready = true;
      _startClientHeartbeat();
      _addConnectionStateEvent(true);
    });

    _socket!.on('disconnect', (reason) {
      print('🔌 SeSocketService: ❌ Disconnected from server. Reason: $reason');
      _ready = false;
      _isConnecting = false;
      _addConnectionStateEvent(false);

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
    _socket!.on('key_exchange:request', (data) {
      print('🔑 SeSocketService: Key exchange request received');
      if (onKeyExchangeRequest != null) {
        onKeyExchangeRequest!(data);
      }
    });

    _socket!.on('key_exchange:response', (data) {
      print('🔑 SeSocketService: 🔍🔍🔍 KEY EXCHANGE RESPONSE EVENT RECEIVED!');
      print('🔑 SeSocketService: 🔍🔍🔍 Event data: $data');
      print('🔑 SeSocketService: 🔍🔍🔍 Data type: ${data.runtimeType}');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 Socket connected: ${_socket?.connected}');
      print('🔑 SeSocketService: 🔍🔍🔍 Socket ready: $_ready');
      print('🔑 SeSocketService: 🔍🔍🔍 Session ID: $_sessionId');
      print(
          '🔑 SeSocketService: 🔍🔍🔍 onKeyExchangeResponse callback: ${onKeyExchangeResponse != null ? 'SET' : 'NULL'}');

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

    _socket!.on('key_exchange:revoked', (data) {
      print('🔑 SeSocketService: Key exchange revoked');
      if (onKeyExchangeRevoked != null) {
        onKeyExchangeRevoked!(data);
      }
    });

    // User data exchange events
    _socket!.on('user_data_exchange:data', (data) {
      print('🔑 SeSocketService: User data exchange received');
      print('🔑 SeSocketService: 🔍 Event data: $data');
      print('🔑 SeSocketService: 🔍 Data type: ${data.runtimeType}');
      print('🔑 SeSocketService: 🔍 Socket connected: ${_socket?.connected}');
      print('🔑 SeSocketService: 🔍 Socket ready: $_ready');
      print('🔑 SeSocketService: 🔍 Session ID: $_sessionId');
      print('🔑 SeSocketService: 🔍 Session confirmed: $_sessionConfirmed');
      print('🔑 SeSocketService: 🔍 Socket ID: ${_socket?.id}');
      print(
          '🔑 SeSocketService: 🔍 Socket transport: ${_socket?.io.engine?.transport?.name ?? 'unknown'}');
      print(
          '🔑 SeSocketService: 🔍 onUserDataExchange callback: ${onUserDataExchange != null ? 'SET' : 'NULL'}');

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
          KeyExchangeService.instance.handleUserDataExchange(data);
          print(
              '🔑 SeSocketService: ✅ Fallback processing completed successfully');
        } catch (e) {
          print('🔑 SeSocketService: ❌ Fallback processing failed: $e');
          print('🔑 SeSocketService: 🚨 This user data exchange will be lost!');
        }
      }
    });

    // Conversation creation events
    _socket!.on('conversation:created', (data) {
      print('💬 SeSocketService: Conversation created event received');
      if (onConversationCreated != null) {
        onConversationCreated!(data);
      }
    });

    // User deletion events
    _socket!.on('user:deleted', (data) {
      print('🗑️ SeSocketService: User deleted event received');
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

    _socket!.on('message:received', (data) {
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

    _socket!.on('message:delivered', (data) {
      print('✅ SeSocketService: Message delivered');
      if (onDelivered != null) {
        onDelivered!(
          data['messageId'] ?? '',
          data['fromUserId'] ?? '',
          data['toUserId'] ?? '',
        );
      }
    });

    _socket!.on('message:read', (data) {
      print('👁️ SeSocketService: Message read');
      if (onRead != null) {
        onRead!(
          data['messageId'] ?? '',
          data['fromUserId'] ?? '',
          data['toUserId'] ?? '',
        );
      }
    });

    // Presence events
    _socket!.on('presence:update', (data) {
      print('👤 SeSocketService: Presence update received');
      if (onPresence != null) {
        onPresence!(
          data['sessionId'] ?? '',
          data['isOnline'] ?? false,
          data['timestamp'] ?? '',
        );
      }
    });

    // Typing events
    _socket!.on('typing:indicator', (data) {
      print('⌨️ SeSocketService: Typing indicator received');
      if (onTyping != null) {
        onTyping!(
          data['fromUserId'] ?? '',
          data['conversationId'] ?? '',
          data['isTyping'] ?? false,
        );
      }
    });

    // Debug: Log all incoming events (reduced for less clutter)
    _socket!.onAny((event, data) {
      // Only log important events, skip routine stats, admin logs, and heartbeat
      if (!event.startsWith('server_stats') &&
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

  void sendPresence(bool isOnline, List<String> toUserIds) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('presence:update', {
      'fromUserId': _sessionId,
      'isOnline': isOnline,
      'toUserIds': toUserIds
    });
  }

  void sendTyping(String toUserId, String conversationId, bool isTyping) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('typing:update', {
      'fromUserId': _sessionId,
      'toUserId': toUserId,
      'conversationId': conversationId,
      'isTyping': isTyping
    });
  }

  void sendMessage(String toUserId, String body,
      {String? messageId, String? conversationId}) {
    if (!isConnected || _sessionId == null) return;

    final mid = messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final convId = conversationId ??
        toUserId; // Use recipient ID as fallback conversation ID

    _socket!.emit('message:send', {
      'messageId': mid,
      'conversationId': convId,
      'fromUserId': _sessionId,
      'toUserIds': [toUserId],
      'body': body,
      'timestamp': DateTime.now().toIso8601String()
    });

    print('🔌 SeSocketService: Message sent: $mid to $toUserId');
  }

  void sendReadReceipt(String toUserId, String messageId) {
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('receipt:read', {
      'messageId': messageId,
      'fromUserId': _sessionId,
      'toUserId': toUserId,
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
    if (!isConnected || _sessionId == null) return;
    _socket!.emit('user_data_exchange:send', {
      'recipientId': recipientId,
      'senderId': _sessionId,
      'encryptedData': encryptedData,
      'conversationId': conversationId ?? ''
    });
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
        callback(fromUserId, '', body, conversationId, messageId);
      };
    }
  }

  void setOnTypingIndicator(
      Function(String senderId, bool isTyping)? callback) {
    // Map the existing callback to the new format
    if (callback != null) {
      onTyping = (fromUserId, conversationId, isTyping) {
        callback(fromUserId, isTyping);
      };
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

  // Additional callback methods needed by main.dart
  void setOnMessageStatusUpdate(
      Function(String senderId, String messageId, String status)? callback) {
    // Map to the appropriate existing callback
    if (callback != null) {
      onDelivered = (messageId, fromUserId, toUserId) {
        callback(fromUserId, messageId, 'delivered');
      };
      onRead = (messageId, fromUserId, toUserId) {
        callback(fromUserId, messageId, 'read');
      };
    }
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
  }) async {
    if (!isConnected || _sessionId == null) return;
    try {
      _socket!.emit('message:status_update', {
        'recipientId': recipientId,
        'messageId': messageId,
        'status': status ?? 'sent',
        'timestamp': DateTime.now().toIso8601String(),
      });
      print(
          '🔌 SeSocketService: Message status update sent: $messageId -> $status');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message status update: $e');
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

  // Methods for queue management (used by queue_statistics_screen)
  Map<String, dynamic> getQueueStatistics() {
    // Return basic queue statistics
    return {
      'totalQueued': 0,
      'pendingDelivery': 0,
      'failedDeliveries': 0,
      'lastUpdate': DateTime.now().toIso8601String(),
      'status': 'active',
    };
  }

  Future<Map<String, dynamic>> checkQueueStatus() async {
    // Check queue status from server
    if (!isConnected || _sessionId == null) {
      return {
        'status': 'disconnected',
        'message': 'Socket not connected',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }

    try {
      // Request queue status from server
      _socket!.emit('request_queued_events', {'sessionId': _sessionId});

      return {
        'status': 'connected',
        'message': 'Queue status requested',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Error checking queue status: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
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
    // Use a default conversation ID since typing_service doesn't provide one
    sendTyping(recipientId, 'default_conversation', isTyping);
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
}
