import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class WebSocketService {
  static WebSocketService? _instance;
  static WebSocketService get instance => _instance ??= WebSocketService._();

  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isAuthenticated = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  bool _shouldReconnect = true;

  Function(Map<String, dynamic>)? onMessageReceived;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onChatMessageReceived;
  Function(Map<String, dynamic>)? onTypingReceived;
  Function(Map<String, dynamic>)? onReadReceiptReceived;

  WebSocketService._();

  Future<void> connect() async {
    if (_isConnecting || !_shouldReconnect) return;

    // Skip WebSocket connection on web platform during development
    if (kIsWeb) {
      print('🔌 WebSocket: Skipping connection on web platform');
      _isConnecting = false;
      return;
    }

    _isConnecting = true;
    print(
        '🔌 WebSocket: Attempting to connect... (attempt ${_reconnectAttempts + 1})');

    try {
      final deviceId = await _storage.read(key: 'device_id');
      if (deviceId == null) {
        print('🔌 WebSocket: Device ID not found, skipping connection');
        _isConnecting = false;
        return;
      }

      final uri = Uri.parse('ws://sechat.strapblaque.com:6001');
      print('🔌 WebSocket: Connecting to $uri');

      try {
        _channel = WebSocketChannel.connect(uri);
      } catch (e) {
        print('🔌 WebSocket: Failed to create WebSocket connection: $e');
        _isConnecting = false;
        _scheduleReconnect();
        return;
      }

      _channel!.stream.listen(
        (data) {
          try {
            final message = json.decode(data);
            _handleMessage(message);
          } catch (e) {
            print('🔌 WebSocket: Error parsing message: $e');
          }
        },
        onDone: () {
          print('🔌 WebSocket: Connection closed');
          _isAuthenticated = false;
          _isConnecting = false;
          onDisconnected?.call();
          _scheduleReconnect();
        },
        onError: (error) {
          print('🔌 WebSocket: Connection error: $error');
          _isAuthenticated = false;
          _isConnecting = false;
          // Don't call onError for connection failures - they're expected
          _scheduleReconnect();
        },
      );

      print('🔌 WebSocket: Connection established');
      onConnected?.call();

      // Authenticate with device ID
      await _authenticate(deviceId);
    } catch (e) {
      print('🔌 WebSocket: Connection failed: $e');
      _isConnecting = false;
      // Don't call onError for connection failures - they're expected
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts < _maxReconnectAttempts && _shouldReconnect) {
      _reconnectTimer?.cancel();
      final delay = Duration(seconds: 2 * (_reconnectAttempts + 1));
      print('🔌 WebSocket: Scheduling reconnect in ${delay.inSeconds} seconds');
      _reconnectTimer = Timer(delay, () {
        _reconnectAttempts++;
        connect();
      });
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      print(
          '🔌 WebSocket: Max reconnection attempts reached. Stopping reconnection.');
      _shouldReconnect = false;
      // Don't show error to user - WebSocket is optional
      // onError?.call('WebSocket connection failed after $_maxReconnectAttempts attempts. Please check your connection and try again.');
    }
  }

  Future<void> _authenticate(String deviceId) async {
    print('🔌 WebSocket: Authenticating with device ID: $deviceId');
    sendMessage({'type': 'auth', 'device_id': deviceId});
  }

  void _handleMessage(Map<String, dynamic> message) {
    print('🔌 WebSocket: Received message: ${message['type']}');
    onMessageReceived?.call(message);

    switch (message['type']) {
      case 'auth_success':
        _isAuthenticated = true;
        _reconnectAttempts = 0; // Reset reconnect attempts on successful auth
        _shouldReconnect = true; // Re-enable reconnection
        print('🔌 WebSocket: Authentication successful');
        break;
      case 'chat_message':
        onChatMessageReceived?.call(message);
        break;
      case 'typing':
        onTypingReceived?.call(message);
        break;
      case 'read_receipt':
        onReadReceiptReceived?.call(message);
        break;
      case 'message_sent':
        // Handle message sent confirmation
        break;
      case 'error':
        print('🔌 WebSocket: Server error: ${message['error']}');
        onError?.call(message['error'] ?? 'Unknown error');
        break;
    }
  }

  void disconnect() {
    print('🔌 WebSocket: Disconnecting...');
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isAuthenticated = false;
    _isConnecting = false;
  }

  void retryConnection() {
    if (kIsWeb) {
      print('🔌 WebSocket: Retry skipped on web platform');
      return;
    }
    print('🔌 WebSocket: Manual retry requested');
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    connect();
  }

  void sendMessage(Map<String, dynamic> message) {
    if (kIsWeb) {
      print('🔌 WebSocket: Send message skipped on web platform');
      return;
    }

    if (_channel != null) {
      try {
        _channel!.sink.add(json.encode(message));
      } catch (e) {
        print('🔌 WebSocket: Failed to send message: $e');
        // Don't call onError for send failures - they're expected when not connected
      }
    } else {
      print('🔌 WebSocket: Cannot send message - not connected');
    }
  }

  void sendChatMessage({
    required String chatId,
    required String content,
    String type = 'text',
  }) {
    if (!_isAuthenticated) {
      print('🔌 WebSocket: Not authenticated, skipping message send');
      return;
    }

    sendMessage({
      'type': 'chat_message',
      'chat_id': chatId,
      'content': content,
      'message_type': type,
    });
  }

  void sendTypingIndicator({required String chatId, required bool isTyping}) {
    if (!_isAuthenticated) return;

    sendMessage({'type': 'typing', 'chat_id': chatId, 'is_typing': isTyping});
  }

  void sendReadReceipt({required String chatId}) {
    if (!_isAuthenticated) return;

    sendMessage({'type': 'read_receipt', 'chat_id': chatId});
  }

  void sendInvitation({required String recipientId, required String message}) {
    sendMessage({
      'type': 'invitation',
      'recipient_id': recipientId,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void sendCallRequest({
    required String recipientId,
    required String callType,
  }) {
    sendMessage({
      'type': 'call_request',
      'recipient_id': recipientId,
      'call_type': callType,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void sendCallResponse({required String recipientId, required bool accepted}) {
    sendMessage({
      'type': 'call_response',
      'recipient_id': recipientId,
      'accepted': accepted,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  bool get isConnected => _channel != null;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
}
