import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

// Simple test client for Session Messenger
class SessionMessengerTestClient {
  WebSocketChannel? _channel;
  String? _sessionId;
  bool _isConnected = false;

  Future<void> connect(String sessionId, {String? name}) async {
    try {
      print('🔌 Connecting to Session Messenger...');

      _sessionId = sessionId;
      _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));

      // Send authentication
      await _sendMessage({
        'type': 'auth',
        'data': {
          'sessionId': sessionId,
          'name': name ?? 'Test User',
          'profilePicture': null,
        },
      });

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) => print('❌ WebSocket error: $error'),
        onDone: () => print('🔌 WebSocket connection closed'),
      );

      _isConnected = true;
      print('✅ Connected as: $sessionId');
    } catch (e) {
      print('❌ Connection failed: $e');
      rethrow;
    }
  }

  Future<void> sendInvitation(String recipientId, String message) async {
    if (!_isConnected) {
      throw Exception('Not connected');
    }

    final invitation = {
      'id': _generateId(),
      'senderId': _sessionId,
      'senderName': 'Test User',
      'recipientId': recipientId,
      'message': message,
      'metadata': {
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    await _sendMessage({
      'type': 'invitation_send',
      'data': invitation,
    });

    print('📨 Invitation sent to: $recipientId');
  }

  Future<void> sendMessage(String recipientId, String content) async {
    if (!_isConnected) {
      throw Exception('Not connected');
    }

    final message = {
      'id': _generateId(),
      'senderId': _sessionId,
      'recipientId': recipientId,
      'content': content,
      'messageType': 'text',
      'metadata': {
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    await _sendMessage({
      'type': 'message_send',
      'data': message,
    });

    print('💬 Message sent to: $recipientId');
  }

  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    if (!_isConnected) {
      throw Exception('Not connected');
    }

    await _sendMessage({
      'type': 'typing_indicator',
      'data': {
        'recipientId': recipientId,
        'isTyping': isTyping,
      },
    });

    print('⌨️ Typing indicator sent: $isTyping');
  }

  Future<void> _sendMessage(Map<String, dynamic> message) async {
    if (_channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = json.decode(data);
      final type = message['type'];
      final messageData = message['data'];

      print('📨 Received: $type');

      switch (type) {
        case 'invitation_received':
          print('📨 Invitation from: ${messageData['senderName']}');
          print('   Message: ${messageData['message']}');
          break;
        case 'invitation_response':
          print('📨 Invitation response: ${messageData['status']}');
          break;
        case 'message_received':
          print('💬 Message from: ${messageData['senderId']}');
          print('   Content: ${messageData['content']}');
          break;
        case 'typing_indicator':
          print('⌨️ Typing from: ${messageData['sessionId']}');
          break;
        case 'contact_online':
          print('🟢 Contact online: ${messageData['sessionId']}');
          break;
        case 'contact_offline':
          print('🔴 Contact offline: ${messageData['sessionId']}');
          break;
        case 'pong':
          // Heartbeat response
          break;
        default:
          print('❓ Unknown message type: $type');
      }
    } catch (e) {
      print('❌ Error handling message: $e');
    }
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    print('🔌 Disconnected');
  }
}

// Test scenarios
Future<void> main() async {
  print('🧪 Session Messenger Test Client');
  print('================================');

  // Create test clients
  final client1 = SessionMessengerTestClient();
  final client2 = SessionMessengerTestClient();

  try {
    // Connect both clients
    await client1.connect('user1', name: 'Alice');
    await Future.delayed(Duration(seconds: 1));

    await client2.connect('user2', name: 'Bob');
    await Future.delayed(Duration(seconds: 1));

    print('\n📨 Testing Invitations...');

    // Send invitation from user1 to user2
    await client1.sendInvitation('user2', 'Would you like to connect?');
    await Future.delayed(Duration(seconds: 2));

    print('\n💬 Testing Messages...');

    // Send message from user1 to user2
    await client1.sendMessage('user2', 'Hello Bob!');
    await Future.delayed(Duration(seconds: 2));

    // Send message from user2 to user1
    await client2.sendMessage('user1', 'Hi Alice!');
    await Future.delayed(Duration(seconds: 2));

    print('\n⌨️ Testing Typing Indicators...');

    // Send typing indicator
    await client1.sendTypingIndicator('user2', true);
    await Future.delayed(Duration(seconds: 1));

    await client1.sendTypingIndicator('user2', false);
    await Future.delayed(Duration(seconds: 1));

    print('\n✅ All tests completed successfully!');

    // Keep connection alive for a bit to see all messages
    await Future.delayed(Duration(seconds: 5));
  } catch (e) {
    print('❌ Test failed: $e');
  } finally {
    // Clean up
    client1.disconnect();
    client2.disconnect();
  }
}
