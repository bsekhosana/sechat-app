import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WebSocketService {
  static WebSocketService? _instance;
  static WebSocketService get instance => _instance ??= WebSocketService._();

  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isAuthenticated = false;

  Function(Map<String, dynamic>)? onMessageReceived;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onChatMessageReceived;
  Function(Map<String, dynamic>)? onTypingReceived;
  Function(Map<String, dynamic>)? onReadReceiptReceived;

  WebSocketService._();

  Future<void> connect() async {
    try {
      final deviceId = await _storage.read(key: 'device_id');
      if (deviceId == null) throw Exception('Device ID not found');

      final uri = Uri.parse('ws://sechat.strapblaque.com:6001');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          final message = json.decode(data);
          _handleMessage(message);
        },
        onDone: () {
          _isAuthenticated = false;
          onDisconnected?.call();
        },
        onError: (error) {
          _isAuthenticated = false;
          onError?.call(error.toString());
        },
      );

      onConnected?.call();

      // Authenticate with device ID
      await _authenticate(deviceId);
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  Future<void> _authenticate(String deviceId) async {
    sendMessage({'type': 'auth', 'device_id': deviceId});
  }

  void _handleMessage(Map<String, dynamic> message) {
    onMessageReceived?.call(message);

    switch (message['type']) {
      case 'auth_success':
        _isAuthenticated = true;
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
        onError?.call(message['error'] ?? 'Unknown error');
        break;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isAuthenticated = false;
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  void sendChatMessage({
    required String chatId,
    required String content,
    String type = 'text',
  }) {
    if (!_isAuthenticated) {
      onError?.call('Not authenticated');
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
}
