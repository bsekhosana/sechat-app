import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'network_service.dart';

class SocketService {
  static SocketService? _instance;
  static SocketService get instance => _instance ??= SocketService._();

  IO.Socket? _socket;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isAuthenticated = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _shouldReconnect = true;
  String? _currentUserId;
  String? _currentDeviceId;

  // Event callbacks
  Function(Map<String, dynamic>)? onMessageReceived;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onChatMessageReceived;
  Function(Map<String, dynamic>)? onTypingReceived;
  Function(Map<String, dynamic>)? onReadReceiptReceived;
  Function(Map<String, dynamic>)? onUserOnline;
  Function(Map<String, dynamic>)? onUserOffline;
  Function(Map<String, dynamic>)? onUserStatusUpdated;
  Function(Map<String, dynamic>)? onInvitationReceived;
  Function(Map<String, dynamic>)? onInvitationResponse;
  Function(Map<String, dynamic>)? onMessageStatusUpdated;

  SocketService._();

  Future<void> connect() async {
    if (_isConnecting || !_shouldReconnect) return;

    _isConnecting = true;
    print(
        '🔌 Socket.IO: Attempting to connect... (attempt ${_reconnectAttempts + 1})');

    try {
      final deviceId = await _storage.read(key: 'device_id');
      final userId = await _storage.read(key: 'user_id');

      if (deviceId == null || userId == null) {
        print(
            '🔌 Socket.IO: Device ID or User ID not found, skipping connection');
        _isConnecting = false;
        return;
      }

      _currentUserId = userId;
      _currentDeviceId = deviceId;

      // Determine the correct server URL
      String serverUrl;
      if (kIsWeb) {
        // For web, use the same domain as the app
        serverUrl = 'https://sechat.strapblaque.com:3001';
      } else {
        // For mobile, use the socket server
        serverUrl = 'https://sechat.strapblaque.com:3001';
      }

      print('🔌 Socket.IO: Connecting to $serverUrl');

      // Create Socket.IO connection
      _socket = IO.io(serverUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
        'forceNew': true,
        'timeout': 20000,
        'reconnection': false, // We'll handle reconnection manually
      });

      // Set up event listeners
      _setupEventListeners();

      // Connect to the server
      _socket!.connect();
    } catch (e) {
      print('🔌 Socket.IO: Connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _setupEventListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      print('🔌 Socket.IO: Connected to server');
      _isConnecting = false;
      _isAuthenticated = false;

      // Clear reconnecting status
      NetworkService.instance.setReconnecting(false);

      onConnected?.call();

      // Authenticate immediately after connection
      _authenticate();
    });

    _socket!.onDisconnect((_) {
      print('🔌 Socket.IO: Disconnected from server');
      _isAuthenticated = false;
      _isConnecting = false;
      onDisconnected?.call();

      // Check network connectivity before attempting reconnect
      if (NetworkService.instance.isConnected) {
        _scheduleReconnect();
      } else {
        print('🔌 Socket.IO: Network not available, waiting for connection');
        NetworkService.instance.setReconnecting(false);
      }
    });

    _socket!.onConnectError((error) {
      print('🔌 Socket.IO: Connection error: $error');
      _isAuthenticated = false;
      _isConnecting = false;
      _scheduleReconnect();
    });

    _socket!.onError((error) {
      print('🔌 Socket.IO: Socket error: $error');
      onError?.call(error.toString());
    });

    // Authentication events
    _socket!.on('authenticated', (data) {
      print('🔌 Socket.IO: Authentication successful');
      _isAuthenticated = true;
      _reconnectAttempts = 0;
      _shouldReconnect = true;
    });

    _socket!.on('auth_error', (data) {
      print('🔌 Socket.IO: Authentication failed: $data');
      onError?.call('Authentication failed: ${data['message']}');
    });

    // Chat events
    _socket!.on('new_message', (data) {
      print('🔌 Socket.IO: New message received: $data');
      onChatMessageReceived?.call(data);
    });

    _socket!.on('message_sent', (data) {
      print('🔌 Socket.IO: Message sent confirmation: $data');
      onMessageReceived?.call(data);
    });

    _socket!.on('user_typing', (data) {
      print('🔌 Socket.IO: User typing: $data');
      onTypingReceived?.call(data);
    });

    // User status events
    _socket!.on('user_online', (data) {
      print('🔌 Socket.IO: User online: $data');
      onUserOnline?.call(data);
    });

    _socket!.on('user_offline', (data) {
      print('🔌 Socket.IO: User offline: $data');
      onUserOffline?.call(data);
    });

    _socket!.on('user_status_updated', (data) {
      print('🔌 Socket.IO: User status updated: $data');
      onUserStatusUpdated?.call(data);
    });

    // Invitation events
    _socket!.on('invitation_received', (data) {
      print('🔌 Socket.IO: Invitation received: $data');
      onInvitationReceived?.call(data);
    });

    _socket!.on('invitation_response', (data) {
      print('🔌 Socket.IO: Invitation response: $data');
      onInvitationResponse?.call(data);
    });

    // Message status events
    _socket!.on('message_status_updated', (data) {
      print('🔌 Socket.IO: Message status updated: $data');
      onMessageStatusUpdated?.call(data);
    });

    // Error events
    _socket!.on('message_error', (data) {
      print('🔌 Socket.IO: Message error: $data');
      onError?.call('Message error: ${data['message']}');
    });

    _socket!.on('message_status_error', (data) {
      print('🔌 Socket.IO: Message status error: $data');
      onError?.call('Message status error: ${data['message']}');
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts < _maxReconnectAttempts && _shouldReconnect) {
      _reconnectTimer?.cancel();
      final delay = Duration(seconds: 2 * (_reconnectAttempts + 1));
      print('🔌 Socket.IO: Scheduling reconnect in ${delay.inSeconds} seconds');

      // Set reconnecting status
      NetworkService.instance.setReconnecting(true);

      _reconnectTimer = Timer(delay, () {
        _reconnectAttempts++;
        connect();
      });
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      print(
          '🔌 Socket.IO: Max reconnection attempts reached. Stopping reconnection.');
      _shouldReconnect = false;
      NetworkService.instance.setReconnecting(false);
    }
  }

  void _authenticate() {
    if (_currentUserId == null || _currentDeviceId == null) {
      print('🔌 Socket.IO: Cannot authenticate - missing user or device ID');
      return;
    }

    print(
        '🔌 Socket.IO: Authenticating with user ID: $_currentUserId, device ID: $_currentDeviceId');
    _socket!.emit('authenticate', {
      'userId': int.parse(_currentUserId!),
      'deviceId': _currentDeviceId!,
    });
  }

  void disconnect() {
    print('🔌 Socket.IO: Disconnecting...');
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isAuthenticated = false;
    _isConnecting = false;
  }

  void retryConnection() {
    print('🔌 Socket.IO: Manual retry requested');
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    connect();
  }

  // Handle network reconnection
  void handleNetworkReconnection() {
    if (!_isAuthenticated && _shouldReconnect) {
      print(
          '🔌 Socket.IO: Network reconnected, attempting socket reconnection');
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      connect();
    }
  }

  // Send message to a specific user
  void sendMessage({
    required String receiverId,
    required String message,
    String messageType = 'text',
  }) {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Not authenticated, skipping message send');
      return;
    }

    print('🔌 Socket.IO: Sending message to $receiverId: $message');
    _socket!.emit('send_message', {
      'senderId': int.parse(_currentUserId!),
      'receiverId': int.parse(receiverId),
      'message': message,
      'messageType': messageType,
    });
  }

  // Send typing indicator
  void sendTypingIndicator({
    required String receiverId,
    required bool isTyping,
  }) {
    if (!_isAuthenticated || _currentUserId == null) return;

    final event = isTyping ? 'typing_start' : 'typing_stop';
    _socket!.emit(event, {
      'senderId': int.parse(_currentUserId!),
      'receiverId': int.parse(receiverId),
    });
  }

  // Update message status
  void updateMessageStatus({
    required String messageId,
    required String status, // 'sent', 'delivered', 'read'
  }) {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Not authenticated, skipping message status update');
      return;
    }

    print('🔌 Socket.IO: Updating message $messageId status to $status');
    _socket!.emit('update_message_status', {
      'messageId': messageId,
      'status': status,
      'userId': int.parse(_currentUserId!),
    });
  }

  // Update user status
  void updateStatus(String status) {
    if (!_isAuthenticated || _currentUserId == null) return;

    _socket!.emit('update_status', {
      'userId': int.parse(_currentUserId!),
      'status': status,
    });
  }

  // Send invitation
  void sendInvitation({
    required String recipientId,
    required String message,
  }) {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Not authenticated, skipping invitation send');
      return;
    }

    print('🔌 Socket.IO: Sending invitation to $recipientId');
    _socket!.emit('send_invitation', {
      'senderId': int.parse(_currentUserId!),
      'recipientId': int.parse(recipientId),
      'message': message,
    });
  }

  // Emit custom event for real-time updates
  void emitCustomEvent(String event, Map<String, dynamic> data) {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Not authenticated, skipping custom event emit');
      return;
    }

    print('🔌 Socket.IO: Emitting custom event: $event with data: $data');
    _socket!.emit(event, data);
  }

  // Respond to invitation
  void respondToInvitation({
    required String invitationId,
    required String response, // 'accept' or 'decline'
  }) {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Not authenticated, skipping invitation response');
      return;
    }

    print(
        '🔌 Socket.IO: Responding to invitation $invitationId with $response');
    _socket!.emit('respond_invitation', {
      'invitationId': invitationId,
      'response': response,
      'userId': int.parse(_currentUserId!),
    });
  }

  // Get online users
  Future<List<Map<String, dynamic>>> getOnlineUsers() async {
    try {
      final response = await _makeHttpRequest('GET', '/api/online-users');
      return List<Map<String, dynamic>>.from(response['online_users'] ?? []);
    } catch (e) {
      print('🔌 Socket.IO: Failed to get online users: $e');
      return [];
    }
  }

  // Get user status
  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    try {
      final response =
          await _makeHttpRequest('GET', '/api/user-status/$userId');
      return response;
    } catch (e) {
      print('🔌 Socket.IO: Failed to get user status: $e');
      return null;
    }
  }

  // Make HTTP request to socket server
  Future<Map<String, dynamic>> _makeHttpRequest(
      String method, String endpoint) async {
    // This would need to be implemented with http package
    // For now, we'll return empty data
    return {};
  }

  // Getters
  bool get isConnected => _socket?.connected ?? false;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
  String? get currentUserId => _currentUserId;
  String? get currentDeviceId => _currentDeviceId;

  // Manual connection for testing
  Future<void> manualConnect() async {
    print('🔌 Socket.IO: Manual connection requested');
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    await connect();
  }

  // Manual disconnect for testing
  void manualDisconnect() {
    print('🔌 Socket.IO: Manual disconnect requested');
    disconnect();
  }

  // Test message sending
  void sendTestMessage() {
    if (!_isAuthenticated || _currentUserId == null) {
      print('🔌 Socket.IO: Cannot send test message - not authenticated');
      return;
    }

    print('🔌 Socket.IO: Sending test message');
    _socket!.emit('send_message', {
      'senderId': int.parse(_currentUserId!),
      'receiverId': int.parse(_currentUserId!), // Send to self for testing
      'message': 'Test message from Flutter app',
      'messageType': 'text',
    });
  }
}
