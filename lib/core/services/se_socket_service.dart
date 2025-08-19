import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/features/notifications/services/notification_manager_service.dart';
import 'package:sechat_app/core/services/app_state_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';

/// SeSocket Service
/// Core socket functionality for real-time communication
class SeSocketService {
  static final SeSocketService _instance = SeSocketService._internal();
  factory SeSocketService() => _instance;
  SeSocketService._internal();

  // Socket configuration
  static const String _socketUrl = 'https://sechat-socket.strapblaque.com';
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _maxReconnectDelay = Duration(minutes: 5);
  static const int _maxReconnectAttempts = 10;

  // Socket instance
  IO.Socket? _socket;

  // Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _currentSessionId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  // Connection state stream controller
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  // Notification manager
  final NotificationManagerService _notificationManager =
      NotificationManagerService();

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentSessionId => _currentSessionId;

  /// Initialize and connect to SeChat socket
  Future<bool> initialize() async {
    try {
      print('🔌 SeSocketService: Initializing socket connection...');

      // Get current session ID
      _currentSessionId = SeSessionService().currentSessionId;
      if (_currentSessionId == null) {
        print('🔌 SeSocketService: ❌ No session ID available');
        return false;
      }

      // Initialize notification manager
      await _notificationManager.initialize();

      // Create socket connection
      await _createSocketConnection();

      // Set up heartbeat
      _startHeartbeat();

      print('🔌 SeSocketService: ✅ Socket initialized successfully');
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Failed to initialize: $e');
      return false;
    }
  }

  /// Create socket connection
  Future<void> _createSocketConnection() async {
    if (_socket != null) {
      await _socket!.disconnect();
      _socket = null;
    }

    _isConnecting = true;

    try {
      _socket = IO.io(_socketUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
        'reconnection': false, // We'll handle reconnection manually
        'timeout': 10000,
        'forceNew': true,
      });

      // Connect to socket first
      _socket!.connect();

      // Wait for connection to be established
      await _waitForConnection();

      // Ensure connection state is synchronized
      refreshConnectionStatus();

      // Set up event handlers AFTER connection is established
      _setupSocketEventHandlers();

      // Register session
      await _registerSession();
    } catch (e) {
      print('🔌 SeSocketService: ❌ Failed to create socket: $e');
      _isConnecting = false;
      rethrow;
    }
  }

  /// Wait for socket connection
  Future<void> _waitForConnection() async {
    final completer = Completer<void>();

    void onConnect(dynamic data) {
      print('🔌 SeSocketService: 🔗 Socket connected event received');
      // Ensure internal flags reflect connected state immediately
      _isConnected = _socket?.connected ?? true;
      _isConnecting = false;
      _connectionStateController.add(_isConnected);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void onConnectError(dynamic error) {
      print('🔌 SeSocketService: ❌ Socket connection error: $error');
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    _socket!.on('connect', onConnect);
    _socket!.on('connect_error', onConnectError);

    try {
      await completer.future.timeout(const Duration(seconds: 15));
      print('🔌 SeSocketService: ✅ Connection wait completed successfully');
    } finally {
      _socket!.off('connect', onConnect);
      _socket!.off('connect_error', onConnectError);
    }
  }

  /// Register session with socket server
  Future<void> _registerSession() async {
    if (_socket == null || !_socket!.connected) {
      throw Exception('Socket not connected');
    }

    final sessionData = {
      'sessionId': _currentSessionId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _socket!.emit('register_session', sessionData);

    // Wait for registration confirmation
    final completer = Completer<void>();

    void onSessionRegistered(dynamic data) {
      if (data['status'] == 'success') {
        completer.complete();
      } else {
        completer
            .completeError('Session registration failed: ${data['message']}');
      }
    }

    _socket!.once('session_registered', onSessionRegistered);

    try {
      await completer.future.timeout(const Duration(seconds: 10));
      print('🔌 SeSocketService: ✅ Session registered successfully');

      // Ensure connection state is synchronized after session registration
      refreshConnectionStatus();
    } finally {
      _socket!.off('session_registered', onSessionRegistered);
    }
  }

  /// Set up socket event handlers
  void _setupSocketEventHandlers() {
    if (_socket == null) {
      print(
          '🔌 SeSocketService: ❌ Cannot setup event handlers - socket is null');
      return;
    }

    print('🔌 SeSocketService: 🔧 Setting up socket event handlers...');

    // Connection events
    _socket!.on('connect', (data) {
      print('🔌 SeSocketService: ✅ Connected to socket server');
      _isConnected = _socket?.connected ?? true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(_isConnected);

      // Create connection notification
      _notificationManager.createConnectionNotification(
        event: 'connected',
        message: 'Real-time connection established',
      );
    });

    _socket!.on('disconnect', (data) {
      print('🔌 SeSocketService: ❌ Disconnected from socket server');
      _isConnected = false;
      _connectionStateController.add(false);

      // Ensure connection state is synchronized
      refreshConnectionStatus();

      _scheduleReconnect();

      // Create disconnection notification
      _notificationManager.createConnectionNotification(
        event: 'disconnected',
        message: 'Connection lost, attempting to reconnect...',
      );
    });

    _socket!.on('connect_error', (error) {
      print('🔌 SeSocketService: ❌ Connection error: $error');
      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);

      // Ensure connection state is synchronized
      refreshConnectionStatus();

      _scheduleReconnect();

      // Create connection error notification
      _notificationManager.createConnectionNotification(
        event: 'error',
        message: 'Connection error occurred: $error',
      );
    });

    // Session events
    _socket!.on('session_expired', (data) {
      print('🔌 SeSocketService: ⚠️ Session expired');
      _handleSessionExpired();
    });

    _socket!.on('session_invalid', (data) {
      print('🔌 SeSocketService: ❌ Session invalid');
      _handleSessionInvalid();
    });

    // Application events from server
    _socket!.on('new_message', (data) {
      try {
        final senderId = data['senderId'] as String? ?? '';
        final content = data['content'] as String? ?? '';
        final messageId = data['messageId'] as String?;
        final conversationId =
            (data['metadata']?['conversationId'] as String?) ?? '';
        final isSilent = (data['metadata']?['silent'] as bool?) ?? false;
        final senderName =
            (data['metadata']?['senderName'] as String?) ?? senderId;

        // Callback for UI/data updates
        _onMessageReceived?.call(
            senderId, senderName, content, conversationId, messageId ?? '');

        // Decide presentation: snackbar in foreground for non-silent; else create local notification entry
        if (!isSilent) {
          if (AppStateService().isForeground) {
            UIService().showSnack('$senderName: $content');
          } else {
            createMessageNotification(
              senderId: senderId,
              senderName: senderName,
              message: content,
              conversationId: conversationId,
              messageId: messageId,
              metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
            );
          }
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling new_message: $e');
      }
    });

    _socket!.on('key_exchange_request', (data) async {
      print('🔌 SeSocketService: 📥 Received key_exchange_request event!');
      print('🔌 SeSocketService: 📋 Event data: $data');
      print('🔌 SeSocketService: 🔍 Current session ID: $_currentSessionId');
      print('🔌 SeSocketService: 🔍 Socket ID: ${_socket?.id}');
      print('🔌 SeSocketService: 🔍 Socket connected: ${_socket?.connected}');

      try {
        final isSilent = (data['silent'] as bool?) ?? false;

        // Process the key exchange request through KeyExchangeService
        final success =
            await KeyExchangeService.instance.processKeyExchangeRequest(data);

        if (success) {
          print(
              '🔌 SeSocketService: ✅ Key exchange request processed successfully');

          // Notify UI about the received request
          _onKeyExchangeRequestReceived?.call(Map<String, dynamic>.from(data));

          if (!isSilent) {
            if (AppStateService().isForeground) {
              final requestPhrase =
                  data['requestPhrase'] as String? ?? 'No phrase';
              UIService().showSnack(
                'Key exchange request received: "$requestPhrase"',
                duration: const Duration(seconds: 5),
              );
            } else {
              createKeyExchangeNotification(
                type: 'request',
                senderId: (data['senderId'] as String?) ?? '',
                senderName: (data['senderName'] as String?) ?? '',
                message: data['requestPhrase'] as String?,
                metadata: Map<String, dynamic>.from(data),
              );
            }
          }
        } else {
          print('🔌 SeSocketService: ❌ Failed to process key exchange request');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling key_exchange_request: $e');
      }
    });

    _socket!.on('key_exchange_response', (data) async {
      try {
        final isSilent = (data['silent'] as bool?) ?? false;

        print(
            '🔌 SeSocketService: 📥 Received key_exchange_response data: $data');
        print('🔌 SeSocketService: 🔍 Original type field: ${data['type']}');

        // Normalize the response data to match what KeyExchangeService expects
        final normalizedData = {
          'senderId': data['senderId'] ?? data['recipientId'],
          'publicKey': data['publicKey'] ?? data['acceptor_public_key'],
          'type': data['type'] ?? 'key_exchange_response',
          'timestamp': data['timestamp'],
          'responseId': data['responseId'],
          'requestVersion': data['requestVersion'],
        };

        print('🔌 SeSocketService: 🔄 Normalized data: $normalizedData');

        final responseType = normalizedData['type'] as String?;

        // Process the key exchange response through KeyExchangeService
        final success = await KeyExchangeService.instance
            .processKeyExchangeResponse(normalizedData);

        if (success) {
          print(
              '🔌 SeSocketService: ✅ Key exchange response processed successfully');

          // Notify UI about the response based on type
          if (responseType == 'key_exchange_accepted' ||
              responseType == 'key_exchange_response') {
            _onKeyExchangeAccepted?.call(Map<String, dynamic>.from(data));
          } else if (responseType == 'key_exchange_declined') {
            // Handle declined response
            print('🔌 SeSocketService: ℹ️ Key exchange was declined');
          }

          if (!isSilent) {
            if (AppStateService().isForeground) {
              if (responseType == 'key_exchange_declined') {
                UIService().showSnack('Key exchange request was declined',
                    isError: true);
              } else {
                UIService().showSnack('Key exchange completed successfully');
              }
            } else {
              // Create notification for the sender (recipient of the response)
              final recipientId =
                  normalizedData['recipientId'] ?? data['recipientId'];
              if (recipientId != null) {
                createKeyExchangeNotification(
                  type: responseType == 'key_exchange_declined'
                      ? 'declined'
                      : 'accepted',
                  senderId: (data['senderId'] as String?) ?? '',
                  senderName: responseType == 'key_exchange_declined'
                      ? 'Key Exchange Declined'
                      : 'Key Exchange Accepted',
                  message: responseType == 'key_exchange_declined'
                      ? 'Your key exchange request was declined'
                      : 'Your key exchange request was accepted',
                  metadata: Map<String, dynamic>.from(data),
                );
              }
            }
          }
        } else {
          print(
              '🔌 SeSocketService: ❌ Failed to process key exchange response');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling key_exchange_response: $e');
      }
    });

    print('🔌 SeSocketService: 🔧 Setting up user_data_exchange event handler');
    _socket!.on('user_data_exchange', (data) async {
      try {
        final isSilent = (data['silent'] as bool?) ?? false;
        // The payload uses 'recipientId' but this is actually the sender's ID
        final senderId = data['recipientId'] as String?;
        final encryptedData = data['encryptedData'] as String?;
        final conversationId = data['conversationId'] as String?;

        if (senderId == null || encryptedData == null) {
          print('🔌 SeSocketService: ❌ Invalid user data exchange payload');
          print(
              '🔌 SeSocketService: 🔍 Available fields: ${data.keys.toList()}');
          return;
        }

        print(
            '🔌 SeSocketService: 🔑 Processing user data exchange from $senderId');
        print(
            '🔌 SeSocketService: 🔍 Encrypted data length: ${encryptedData.length}');
        print('🔌 SeSocketService: 🔍 Conversation ID: $conversationId');

        // Process the encrypted user data through KeyExchangeService
        final success =
            await KeyExchangeService.instance.processUserDataExchange(
          senderId: senderId,
          encryptedData: encryptedData,
          conversationId: conversationId,
        );

        if (success) {
          print(
              '🔌 SeSocketService: ✅ User data exchange processed successfully');

          if (!isSilent) {
            if (AppStateService().isForeground) {
              UIService().showSnack('New conversation created');
            } else {
              // Create notification for conversation creation
              createKeyExchangeNotification(
                type: 'conversation_created',
                senderId: senderId,
                senderName: 'Conversation Created',
                message:
                    'A conversation has been created between you and ${senderId.substring(0, 8)}...',
                metadata: Map<String, dynamic>.from(data),
              );
            }
          }
        } else {
          print('🔌 SeSocketService: ❌ Failed to process user data exchange');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling user_data_exchange: $e');
      }
    });

    _socket!.on('key_exchange_revoked', (data) {
      try {
        final requestId = data['requestId'] as String? ?? '';
        final senderId = data['senderId'] as String? ?? '';
        final isSilent = (data['silent'] as bool?) ?? false;

        print(
            '🔌 SeSocketService: 🔑 Key exchange request revoked: $requestId by $senderId');

        if (!isSilent) {
          if (AppStateService().isForeground) {
            UIService().showSnack('Key exchange request was revoked');
          } else {
            createKeyExchangeNotification(
              type: 'revoked',
              senderId: senderId,
              senderName: senderId,
              message: 'Key exchange request was revoked',
              metadata: Map<String, dynamic>.from(data),
            );
          }
        }

        // Notify the provider to remove the revoked request
        // This will be handled by the KeyExchangeRequestProvider when it receives the event
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling key_exchange_revoked: $e');
      }
    });

    _socket!.on('user_online', (data) {
      try {
        final userId = data['sessionId'] as String? ?? '';
        _onOnlineStatusUpdate?.call(
            userId, true, DateTime.now().toIso8601String());
      } catch (_) {}
    });

    _socket!.on('user_offline', (data) {
      try {
        final userId = data['sessionId'] as String? ?? '';
        _onOnlineStatusUpdate?.call(
            userId, false, DateTime.now().toIso8601String());
      } catch (_) {}
    });

    _socket!.on('account_deleted', (data) {
      try {
        final sessionId = data['sessionId'] as String? ?? '';
        final clearedCount = data['clearedCount'] as int? ?? 0;
        final message = data['message'] as String? ?? '';

        print(
            '🔌 SeSocketService: ✅ Account deletion confirmed by server for session: $sessionId');
        print('🔌 SeSocketService: ✅ Cleared $clearedCount queued messages');
        print('🔌 SeSocketService: ✅ Server message: $message');

        // Clear local session reference
        _currentSessionId = null;

        // Create notification about account deletion
        _notificationManager.createConnectionNotification(
          event: 'account_deleted',
          message: 'Account deleted successfully - All data cleared',
        );
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling account_deleted: $e');
      }
    });

    _socket!.on('user_deleted', (data) {
      try {
        final sessionId = data['sessionId'] as String? ?? '';
        final message = data['message'] as String? ?? '';

        print('🔌 SeSocketService: ℹ️ User account deleted: $sessionId');
        print('🔌 SeSocketService: ℹ️ Server message: $message');

        // Create notification about user deletion
        _notificationManager.createConnectionNotification(
          event: 'user_deleted',
          message: 'A user account has been deleted',
        );
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling user_deleted: $e');
      }
    });

    print(
        '🔌 SeSocketService: ✅ All socket event handlers configured successfully');
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('🔌 SeSocketService: ❌ Max reconnection attempts reached');
      return;
    }

    if (_reconnectTimer != null) {
      _reconnectTimer!.cancel();
    }

    final delay = Duration(
        seconds: (_reconnectDelay.inSeconds * (1 << _reconnectAttempts))
            .clamp(0, _maxReconnectDelay.inSeconds));

    print(
        '🔌 SeSocketService: 🔄 Scheduling reconnection in ${delay.inSeconds} seconds (attempt ${_reconnectAttempts + 1})');

    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _attemptReconnect();
    });
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (_isConnecting || _isConnected) return;

    print('🔌 SeSocketService: 🔄 Attempting reconnection...');

    try {
      await _createSocketConnection();

      // Update connection state and notify listeners
      _isConnected = _socket?.connected ?? false;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(_isConnected);

      // Create reconnection success notification
      _notificationManager.createConnectionNotification(
        event: 'reconnected',
        message: 'Connection restored successfully',
      );

      print('🔌 SeSocketService: ✅ Reconnection successful, state updated');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Reconnection failed: $e');
      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);
      _scheduleReconnect();
    }
  }

  /// Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _socket != null) {
        _socket!.emit('heartbeat', {
          'sessionId': _currentSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  /// Handle session expired
  void _handleSessionExpired() {
    // Notify SeSessionService to refresh session
    print('🔌 SeSocketService: ⚠️ Session expired - notify SeSessionService');
  }

  /// Handle session invalid
  void _handleSessionInvalid() {
    // Notify SeSessionService to handle invalid session
    print('🔌 SeSocketService: ❌ Session invalid - notify SeSessionService');
  }

  /// Get current socket status for debugging
  Map<String, dynamic> getSocketStatus() {
    return {
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'socketExists': _socket != null,
      'socketConnected': _socket?.connected ?? false,
      'currentSessionId': _currentSessionId,
      'reconnectAttempts': _reconnectAttempts,
      'socketUrl': _socketUrl,
    };
  }

  /// Log current socket status for debugging
  void logSocketStatus() {
    final status = getSocketStatus();
    print('🔌 SeSocketService: 📊 Current Socket Status:');
    status.forEach((key, value) {
      print('🔌 SeSocketService:   $key: $value');
    });
  }

  /// Force refresh connection status
  void refreshConnectionStatus() {
    if (_socket != null) {
      _isConnected = _socket!.connected;
      print(
          '🔌 SeSocketService: 🔄 Refreshed connection status: $_isConnected');
      _connectionStateController.add(_isConnected);
    } else {
      _isConnected = false;
      print(
          '🔌 SeSocketService: 🔄 Refreshed connection status: false (no socket)');
      _connectionStateController.add(false);
    }
  }

  /// Force reconnection if needed
  Future<void> forceReconnect() async {
    print('🔌 SeSocketService: 🔄 Force reconnection requested');
    if (_isConnected) {
      print('🔌 SeSocketService: ℹ️ Already connected, disconnecting first...');
      await disconnect();
    }
    await initialize();
  }

  /// Ensure socket is connected before sending events
  Future<bool> ensureConnection() async {
    if (_isConnected && _socket != null && _socket!.connected) {
      return true;
    }

    print(
        '🔌 SeSocketService: ⚠️ Socket not properly connected, attempting to reconnect...');
    try {
      await forceReconnect();
      return _isConnected;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Failed to ensure connection: $e');
      return false;
    }
  }

  /// Test socket connection by sending a heartbeat
  Future<bool> testConnection() async {
    if (!_isConnected || _socket == null) {
      print('🔌 SeSocketService: ❌ Cannot test connection - not connected');
      return false;
    }

    try {
      print('🔌 SeSocketService: 🧪 Testing connection with heartbeat...');
      _socket!.emit('heartbeat', {
        'sessionId': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'test': true,
      });
      print('🔌 SeSocketService: ✅ Heartbeat test sent successfully');
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Heartbeat test failed: $e');
      return false;
    }
  }

  /// Manually trigger connection setup for testing
  Future<void> manualConnect() async {
    print('🔌 SeSocketService: 🔧 Manual connection requested');
    logSocketStatus();

    if (_socket == null) {
      print('🔌 SeSocketService: 🔧 Creating new socket connection...');
      await _createSocketConnection();
    } else if (!_isConnected) {
      print('🔌 SeSocketService: 🔧 Reconnecting existing socket...');
      await _createSocketConnection();
    } else {
      print('🔌 SeSocketService: ℹ️ Already connected');
    }

    logSocketStatus();
  }

  /// Check if socket is ready to send events
  bool isReadyToSend() {
    // First, sync the connection state with actual socket state
    if (_socket != null && _isConnected != _socket!.connected) {
      print('🔌 SeSocketService: 🔄 Syncing connection state mismatch');
      refreshConnectionStatus();
    }

    final ready = _socket != null && _socket!.connected;
    print('🔌 SeSocketService: 🔍 Socket ready to send: $ready');
    if (!ready) {
      logSocketStatus();
    }
    return ready;
  }

  /// Get connection status for UI display
  String getConnectionStatusText() {
    if (_socket == null) return 'No Socket';
    if (_isConnecting) return 'Connecting...';
    if (_isConnected && _socket!.connected) return 'Connected';
    if (_isConnected && !_socket!.connected) return 'Disconnected';
    return 'Not Connected';
  }

  /// Debug method to print all current state
  void debugPrintState() {
    print('🔌 SeSocketService: 🐛 === DEBUG STATE ===');
    logSocketStatus();
    print(
        '🔌 SeSocketService: 🐛 Connection Status Text: ${getConnectionStatusText()}');
    print('🔌 SeSocketService: 🐛 Ready to Send: ${isReadyToSend()}');
    print('🔌 SeSocketService: 🐛 === END DEBUG STATE ===');
  }

  /// Force a connection status refresh and return current status
  Future<Map<String, dynamic>> forceStatusRefresh() async {
    print('🔌 SeSocketService: 🔄 Force status refresh requested');
    refreshConnectionStatus();

    // Wait a bit for any async operations
    await Future.delayed(const Duration(milliseconds: 100));

    final status = getSocketStatus();
    print('🔌 SeSocketService: 🔄 Status refresh completed');
    return status;
  }

  /// Get a summary of the current connection state
  String getConnectionSummary() {
    final status = getSocketStatus();
    return 'Socket: ${status['socketExists'] ? 'Yes' : 'No'}, '
        'Connected: ${status['isConnected'] ? 'Yes' : 'No'}, '
        'Connecting: ${status['isConnecting'] ? 'Yes' : 'No'}, '
        'Session: ${status['currentSessionId'] ?? 'None'}';
  }

  /// Check if we can send events right now
  bool canSendEvents() {
    final canSend = isReadyToSend();
    if (!canSend) {
      print('🔌 SeSocketService: ⚠️ Cannot send events - connection not ready');
      debugPrintState();
    }
    return canSend;
  }

  /// Emergency connection fix - force a complete reconnection
  Future<void> emergencyReconnect() async {
    print('🔌 SeSocketService: 🚨 Emergency reconnection requested');
    debugPrintState();

    try {
      // Force disconnect everything
      if (_socket != null) {
        await _socket!.disconnect();
        _socket = null;
      }

      _isConnected = false;
      _isConnecting = false;
      _reconnectAttempts = 0;

      // Create fresh connection
      await _createSocketConnection();

      print('🔌 SeSocketService: 🚨 Emergency reconnection completed');
      debugPrintState();
    } catch (e) {
      print('🔌 SeSocketService: ❌ Emergency reconnection failed: $e');
      debugPrintState();
    }
  }

  /// Emit event to socket server
  void emit(String event, dynamic data) {
    print(
        '🔌 SeSocketService: 🚀 Attempting to emit event: $event with data: $data');

    if (isReadyToSend()) {
      print('🔌 SeSocketService: ✅ Emitting event: $event');
      _socket!.emit(event, data);
      print('🔌 SeSocketService: ✅ Event emitted successfully');
    } else {
      print('🔌 SeSocketService: ❌ Cannot emit event - socket not ready');
    }
  }

  /// Create notification for message received
  Future<void> createMessageNotification({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    await _notificationManager.createMessageNotification(
      senderId: senderId,
      senderName: senderName,
      message: message,
      conversationId: conversationId,
      messageId: messageId,
      metadata: metadata,
    );
  }

  /// Create notification for typing indicator
  Future<void> createTypingNotification({
    required String senderId,
    required String senderName,
    required String conversationId,
  }) async {
    await _notificationManager.createTypingNotification(
      senderId: senderId,
      senderName: senderName,
      conversationId: conversationId,
    );
  }

  /// Create notification for online status
  Future<void> createOnlineStatusNotification({
    required String userId,
    required String userName,
    required bool isOnline,
  }) async {
    await _notificationManager.createOnlineStatusNotification(
      userId: userId,
      userName: userName,
      isOnline: isOnline,
    );
  }

  /// Create notification for key exchange
  Future<void> createKeyExchangeNotification({
    required String type,
    required String senderId,
    required String senderName,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    await _notificationManager.createKeyExchangeNotification(
      type: type,
      senderId: senderId,
      senderName: senderName,
      message: message,
      metadata: metadata,
    );
  }

  /// Create notification for message status
  Future<void> createMessageStatusNotification({
    required String status,
    required String senderId,
    required String messageId,
    String? conversationId,
    Map<String, dynamic>? metadata,
  }) async {
    await _notificationManager.createMessageStatusNotification(
      status: status,
      senderId: senderId,
      messageId: messageId,
      conversationId: conversationId,
      metadata: metadata,
    );
  }

  /// Send message via socket
  Future<bool> sendMessage({
    required String recipientId,
    required String message,
    required String conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ⚠️ Cannot send message - socket not connected');
        return false;
      }

      final messageData = {
        'recipientId': recipientId,
        'message': message,
        'conversationId': conversationId,
        'messageId':
            messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      };

      emit('send_message', messageData);
      print('🔌 SeSocketService: ✅ Message sent via socket');
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message: $e');
      return false;
    }
  }

  /// Send typing indicator via socket
  Future<bool> sendTypingIndicator({
    required String recipientId,
    required bool isTyping,
    String? conversationId,
  }) async {
    try {
      if (!_isConnected) {
        return false;
      }

      final typingData = {
        'recipientId': recipientId,
        'isTyping': isTyping,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      emit('typing_indicator', typingData);
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending typing indicator: $e');
      return false;
    }
  }

  /// Send message status update via socket
  Future<bool> sendMessageStatusUpdate({
    required String recipientId,
    required String messageId,
    required String status,
  }) async {
    try {
      if (!_isConnected) {
        return false;
      }

      final statusData = {
        'recipientId': recipientId,
        'messageId': messageId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      };

      emit('message_status_update', statusData);
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message status: $e');
      return false;
    }
  }

  /// Send online status update to all contacts
  Future<bool> sendOnlineStatusToAllContacts(bool isOnline) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ❌ Socket not connected, cannot send online status');
        return false;
      }

      final sessionService = SeSessionService();
      final currentUserId = sessionService.currentSessionId;

      if (currentUserId == null) {
        print('🔌 SeSocketService: ❌ No current session ID available');
        return false;
      }

      // Get all conversations to send status updates
      final messageStorageService = MessageStorageService.instance;
      final conversations =
          await messageStorageService.getUserConversations(currentUserId);

      if (conversations.isEmpty) {
        print(
            '🔌 SeSocketService: ℹ️ No conversations found, skipping online status update');
        return true;
      }

      // Send online status update to all participants via socket
      for (final conversation in conversations) {
        final otherParticipantId =
            conversation.getOtherParticipantId(currentUserId);

        await sendMessageStatusUpdate(
          recipientId: otherParticipantId,
          messageId: 'online_status_${DateTime.now().millisecondsSinceEpoch}',
          status: isOnline ? 'online' : 'offline',
        );
      }

      print(
          '🔌 SeSocketService: ✅ Online status updates sent to ${conversations.length} contacts');
      return true;
    } catch (e) {
      print(
          '🔌 SeSocketService: ❌ Error sending online status to all contacts: $e');
      return false;
    }
  }

  /// Delete this session on the socket server and clear any server-side links/queues
  /// - Attempts a lightweight connect if not already connected, so it can send the commands
  /// - Emits `clear_user_queue` and `delete_account` for the current session
  /// - Clears the local cached session id reference in this service
  Future<void> deleteSessionOnServer({String? sessionId}) async {
    final String? targetSessionId = sessionId ?? _currentSessionId;
    if (targetSessionId == null || targetSessionId.isEmpty) {
      print(
          '🔌 SeSocketService: ⚠️ No sessionId available to delete on server');
      _currentSessionId = null;
      return;
    }

    bool connectedTemporarily = false;
    try {
      // Ensure connection so we can send server-side clean-up events
      if (!_isConnected) {
        final initialized = await initialize();
        connectedTemporarily = initialized;
        if (!initialized) {
          print(
              '🔌 SeSocketService: ❌ Could not connect to server to delete session');
        }
      }

      if (_isConnected) {
        try {
          // Clear any queued messages for this user on the server
          emit('clear_user_queue', {
            'sessionId': targetSessionId,
          });
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Error emitting clear_user_queue: $e');
        }

        try {
          // Notify server that this account/session is deleted
          emit('delete_account', {
            'sessionId': targetSessionId,
          });
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Error emitting delete_account: $e');
        }
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error during deleteSessionOnServer: $e');
    } finally {
      // Clear local reference regardless
      _currentSessionId = null;

      // If we connected only for cleanup, disconnect
      if (connectedTemporarily) {
        try {
          await disconnect();
        } catch (_) {}
      }
    }
  }

  /// Send key exchange request via socket
  Future<bool> sendKeyExchangeRequest({
    required String recipientId,
    required Map<String, dynamic> requestData,
  }) async {
    try {
      print(
          '🔌 SeSocketService: 🚀 sendKeyExchangeRequest called with recipientId: $recipientId');
      print('🔌 SeSocketService: 📋 requestData: $requestData');

      // Check connection status and refresh if needed
      refreshConnectionStatus();

      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ❌ Socket not connected, attempting to ensure connection...');
        logSocketStatus();

        final connected = await ensureConnection();
        if (!connected) {
          print(
              '🔌 SeSocketService: ❌ Failed to establish connection for key exchange request');
          return false;
        }
      }

      // Extract required fields from requestData
      final publicKey = requestData['publicKey'] as String?;
      final requestId = requestData['requestId'] as String?;
      final requestPhrase = requestData['requestPhrase'] as String?;
      final version = requestData['version']?.toString();

      if (publicKey == null || requestId == null || requestPhrase == null) {
        print(
            '🔌 SeSocketService: ❌ Missing required fields in requestData: publicKey, requestId, or requestPhrase');
        return false;
      }

      final keyExchangeData = {
        'recipientId': recipientId,
        'publicKey': publicKey,
        'requestId': requestId,
        'requestPhrase': requestPhrase,
        'version': version ?? '1', // Include version field
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Debug: Check data types
      print('🔌 SeSocketService: 🔍 Data types:');
      print('🔌 SeSocketService:   recipientId: ${recipientId.runtimeType}');
      print('🔌 SeSocketService:   publicKey: ${publicKey.runtimeType}');
      print('🔌 SeSocketService:   requestId: ${requestId.runtimeType}');
      print(
          '🔌 SeSocketService:   requestPhrase: ${requestPhrase.runtimeType}');
      print('🔌 SeSocketService:   version: ${(version ?? '1').runtimeType}');
      print(
          '🔌 SeSocketService:   timestamp: ${DateTime.now().toIso8601String().runtimeType}');

      print(
          '🔌 SeSocketService: 📤 Sending key exchange request to $recipientId with data: $keyExchangeData');
      print(
          '🔌 SeSocketService: 🔍 keyExchangeData keys: ${keyExchangeData.keys.toList()}');
      print(
          '🔌 SeSocketService: 🔍 version field value: ${keyExchangeData['version']}');
      print(
          '🔌 SeSocketService: 🔍 Current user session ID: $_currentSessionId');
      print('🔌 SeSocketService: 🔍 Target recipient ID: $recipientId');

      // Add debug logging for the emit
      print('🔌 SeSocketService: 🔍 About to emit key_exchange_request event');
      print('🔌 SeSocketService: 🔍 Socket connected: ${_socket?.connected}');
      print('🔌 SeSocketService: 🔍 Socket exists: ${_socket != null}');

      emit('key_exchange_request', keyExchangeData);

      print('🔌 SeSocketService: ✅ Event emitted, checking if it was sent...');

      // Verify the event was sent by checking socket state
      if (_socket?.connected == true) {
        print(
            '🔌 SeSocketService: ✅ Socket is connected, event should have been sent');
      } else {
        print(
            '🔌 SeSocketService: ⚠️ Socket connection state after emit: ${_socket?.connected}');
      }

      print(
          '🔌 SeSocketService: ✅ sendKeyExchangeRequest completed successfully');
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending key exchange request: $e');
      return false;
    }
  }

  /// Send key exchange response via socket
  Future<bool> sendKeyExchangeResponse({
    required String recipientId,
    required bool accepted,
    Map<String, dynamic>? responseData,
  }) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ❌ Socket not connected, cannot send key exchange response');
        return false;
      }

      print('🔌 SeSocketService: 📋 Received responseData: $responseData');
      print(
          '🔌 SeSocketService: 🔍 responseData type: ${responseData.runtimeType}');

      // Extract required fields from responseData
      final publicKey = responseData?['publicKey'] as String?;
      final requestVersion = responseData?['requestVersion'] as String?;
      final responseId = responseData?['responseId'] as String?;

      print('🔌 SeSocketService: 🔍 Extracted publicKey: $publicKey');
      print('🔌 SeSocketService: 🔍 Extracted requestVersion: $requestVersion');
      print('🔌 SeSocketService: 🔍 Extracted responseId: $responseId');

      if (publicKey == null || requestVersion == null || responseId == null) {
        print(
            '🔌 SeSocketService: ❌ Missing required fields in responseData: publicKey, requestVersion, or responseId');
        return false;
      }

      final response = {
        'recipientId': recipientId,
        'publicKey': publicKey,
        'requestVersion': requestVersion,
        'responseId': responseId,
        'timestamp': DateTime.now().toIso8601String(),
        'type': responseData?[
            'type'], // Include the type field for proper flow handling
      };

      print(
          '🔌 SeSocketService: 📤 Sending key exchange response to $recipientId with data: $response');
      emit('key_exchange_response', response);
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending key exchange response: $e');
      return false;
    }
  }

  /// Revoke key exchange request via socket
  Future<bool> revokeKeyExchangeRequest({
    required String recipientId,
    required String requestId,
  }) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ❌ Socket not connected, cannot revoke key exchange request');
        return false;
      }

      final revokeData = {
        'recipientId': recipientId,
        'requestId': requestId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print(
          '🔌 SeSocketService: 📤 Revoking key exchange request to $recipientId with data: $revokeData');
      emit('key_exchange_revoked', revokeData);
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error revoking key exchange request: $e');
      return false;
    }
  }

  /// Listen to socket events
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  /// Remove event listener
  void off(String event, Function(dynamic)? handler) {
    if (handler != null) {
      _socket?.off(event, handler);
    } else {
      _socket?.off(event);
    }
  }

  // Callback functions for chat events
  Function(String, String, String, String, String)? _onMessageReceived;
  Function(String, bool)? _onTypingIndicator;
  Function(String, bool, String?)? _onOnlineStatusUpdate;
  Function(String, String, String)? _onMessageStatusUpdate;
  Function(Map<String, dynamic>)? _onKeyExchangeRequestReceived;
  Function(Map<String, dynamic>)? _onKeyExchangeAccepted;
  Function(Map<String, dynamic>)? _onKeyExchangeDeclined;
  Function(dynamic)? _onConversationCreated;

  /// Set message received callback
  void setOnMessageReceived(
      Function(String, String, String, String, String) callback) {
    _onMessageReceived = callback;
  }

  /// Set typing indicator callback
  void setOnTypingIndicator(Function(String, bool) callback) {
    _onTypingIndicator = callback;
  }

  /// Set online status update callback
  void setOnOnlineStatusUpdate(Function(String, bool, String?) callback) {
    _onOnlineStatusUpdate = callback;
  }

  /// Set message status update callback
  void setOnMessageStatusUpdate(Function(String, String, String) callback) {
    _onMessageStatusUpdate = callback;
  }

  /// Set key exchange request callback
  void setOnKeyExchangeRequestReceived(
      Function(Map<String, dynamic>) callback) {
    _onKeyExchangeRequestReceived = callback;
  }

  /// Set key exchange accepted callback
  void setOnKeyExchangeAccepted(Function(Map<String, dynamic>) callback) {
    _onKeyExchangeAccepted = callback;
  }

  /// Set key exchange declined callback
  void setOnKeyExchangeDeclined(Function(Map<String, dynamic>) callback) {
    _onKeyExchangeDeclined = callback;
  }

  /// Set conversation created callback
  void setOnConversationCreated(Function(dynamic) callback) {
    _onConversationCreated = callback;
  }

  /// Disconnect and cleanup
  Future<void> disconnect() async {
    print('🔌 SeSocketService: Disconnecting...');

    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_socket != null) {
      await _socket!.disconnect();
      _socket = null;
    }

    _isConnected = false;
    _isConnecting = false;
    _connectionStateController.add(false);

    print('🔌 SeSocketService: ✅ Disconnected');
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}
