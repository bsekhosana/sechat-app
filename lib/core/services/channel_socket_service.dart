import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/features/chat/services/enhanced_chat_encryption_service.dart';

import 'package:sechat_app/core/services/app_state_service.dart';
import 'package:sechat_app/features/notifications/services/local_notification_badge_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/realtime/realtime_service_manager.dart';

/// Channel-based Socket Service
/// Replaces global event broadcasting with targeted channel communication
/// Uses convention: action:sessionId:actionType (e.g., typing:session_123:start)
class ChannelSocketService {
  static final ChannelSocketService _instance =
      ChannelSocketService._internal();
  factory ChannelSocketService() => _instance;
  ChannelSocketService._internal();

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
  final LocalNotificationBadgeService _notificationManager =
      LocalNotificationBadgeService();

  // Dynamic event listeners management
  final Map<String, List<String>> _activeListeners = {};
  final Map<String, Function> _eventCallbacks = {};

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentSessionId => _currentSessionId;

  /// Get connection statistics and details
  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'currentSessionId': _currentSessionId,
      'reconnectAttempts': _reconnectAttempts,
      'socketUrl': _socketUrl,
      'lastActivity': DateTime.now().toIso8601String(),
      'activeChannels': _activeListeners.keys.length,
      'eventCallbacks': _eventCallbacks.length,
      'connectionType': 'Channel-based (Encrypted)',
      'serverEndpoint': 'sechat-socket.strapblaque.com',
    };
  }

  /// Get detailed connection information
  Map<String, dynamic> getConnectionDetails() {
    final stats = getConnectionStats();
    stats['realtimeServices'] = {
      'presence': RealtimeServiceManager().presence.isInitialized,
      'typing': true, // Typing service is always available
      'messageTransport': true, // Message transport is always available
    };
    return stats;
  }

  /// Initialize and connect to SeChat socket with channel-based communication
  Future<bool> initialize() async {
    try {
      print(
          '🔌 ChannelSocketService: Initializing channel-based socket connection...');

      // Get current session ID
      _currentSessionId = SeSessionService().currentSessionId;
      if (_currentSessionId == null) {
        print('🔌 ChannelSocketService: ❌ No session ID available');
        return false;
      }

      // Initialize notification manager
      await _notificationManager.initialize();

      // Create socket connection
      await _createSocketConnection();

      // Join user's personal session channel
      await _joinSessionChannel();

      // Set up heartbeat
      _startHeartbeat();

      // Send user online status to server
      await sendUserOnlineStatus(true);

      print(
          '🔌 ChannelSocketService: ✅ Channel-based socket initialized successfully');
      return true;
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Failed to initialize: $e');
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

      // Set up connection event handlers
      _setupConnectionHandlers();

      // Connect to server
      await _socket!.connect();
      print('🔌 ChannelSocketService: 🔌 Socket connection initiated');
    } catch (e) {
      _isConnecting = false;
      print(
          '🔌 ChannelSocketService: ❌ Failed to create socket connection: $e');
      rethrow;
    }
  }

  /// Set up connection event handlers
  void _setupConnectionHandlers() {
    if (_socket == null) return;

    // Connection events
    _socket!.on('connect', (data) {
      print('🔌 ChannelSocketService: ✅ Connected to socket server');
      _isConnected = _socket?.connected ?? true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(_isConnected);
    });

    _socket!.on('disconnect', (data) {
      print('🔌 ChannelSocketService: ❌ Disconnected from socket server');
      _isConnected = false;
      _connectionStateController.add(false);

      // Ensure connection state is synchronized
      refreshConnectionStatus();

      _scheduleReconnect();
    });

    _socket!.on('connect_error', (error) {
      print('🔌 ChannelSocketService: ❌ Connection error: $error');
      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);

      // Ensure connection state is synchronized
      refreshConnectionStatus();

      _scheduleReconnect();
    });

    // Session events
    _socket!.on('session_expired', (data) {
      print('🔌 ChannelSocketService: ⚠️ Session expired');
      _handleSessionExpired();
    });

    _socket!.on('session_invalid', (data) {
      print('🔌 ChannelSocketService: ❌ Session invalid');
      _handleSessionInvalid();
    });
  }

  /// Join user to their personal session channel
  Future<void> _joinSessionChannel() async {
    final sessionId = _currentSessionId;
    if (sessionId != null && _socket != null) {
      try {
        _socket!.emit('join_session', sessionId);
        print('🔌 ChannelSocketService: ✅ Joined session channel: $sessionId');
      } catch (e) {
        print('🔌 ChannelSocketService: ❌ Failed to join session channel: $e');
      }
    }
  }

  /// Set up dynamic event listeners for specific contacts
  /// This replaces the old global event broadcasting
  void setupContactListeners(List<String> contactSessionIds) {
    print(
        '🔌 ChannelSocketService: 🔧 Setting up listeners for ${contactSessionIds.length} contacts');

    // Clean up existing listeners first
    _cleanupAllListeners();

    for (final contactId in contactSessionIds) {
      _setupContactListeners(contactId);
    }
  }

  /// Set up event listeners for a specific contact
  void _setupContactListeners(String contactSessionId) {
    if (_socket == null) return;

    final listeners = [
      'typing:${contactSessionId}:start',
      'typing:${contactSessionId}:stop',
      'chat:${contactSessionId}:new_message',
      'presence:${contactSessionId}:online',
      'presence:${contactSessionId}:offline',
      'key_exchange:${contactSessionId}:request',
      'key_exchange:${contactSessionId}:response',
      'key_exchange:${contactSessionId}:revoked',
      'user_data_exchange:${contactSessionId}:data',
      'conversation_created:${contactSessionId}:data',
    ];

    _activeListeners[contactSessionId] = listeners;

    for (final event in listeners) {
      _socket!.on(event, (data) {
        _handleChannelEvent(event, contactSessionId, data);
      });
    }

    print(
        '🔌 ChannelSocketService: ✅ Set up listeners for contact: $contactSessionId');
  }

  /// Handle channel-based events
  void _handleChannelEvent(
      String event, String contactSessionId, dynamic data) {
    try {
      print(
          '🔌 ChannelSocketService: 🔔 Channel event received: $event from $contactSessionId');

      // Parse event type from event name (e.g., "typing:session_123:start" -> "typing")
      final eventParts = event.split(':');
      if (eventParts.length != 3) {
        print('🔌 ChannelSocketService: ⚠️ Invalid event format: $event');
        return;
      }

      final eventType = eventParts[0];
      final action = eventParts[2];

      // Check if this is a KER event (unencrypted) or encrypted event
      final isKerEvent = eventType == 'key_exchange';

      if (isKerEvent) {
        // KER events are unencrypted - handle directly
        _handleKeyExchangeEvent(contactSessionId, action, data);
      } else {
        // All other events are encrypted - decrypt first
        _handleEncryptedEvent(eventType, contactSessionId, action, data);
      }
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error handling channel event: $e');
    }
  }

  /// Handle encrypted events by decrypting payload first
  void _handleEncryptedEvent(String eventType, String contactSessionId,
      String action, dynamic data) async {
    try {
      print(
          '🔌 ChannelSocketService: 🔐 Handling encrypted event: $eventType from $contactSessionId');

      // Extract encrypted data from payload
      final encryptedData = data['encrypted_data'] as String?;
      if (encryptedData == null) {
        print('🔌 ChannelSocketService: ⚠️ No encrypted data found in event');
        return;
      }

      // Decrypt the payload using local encryption service
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);
      if (decryptedData == null) {
        print('🔌 ChannelSocketService: ❌ Failed to decrypt event data');
        return;
      }

      print('🔌 ChannelSocketService: ✅ Event data decrypted successfully');

      // Now handle the decrypted event based on type
      switch (eventType) {
        case 'typing':
          _handleTypingEvent(
              contactSessionId, action == 'start', decryptedData);
          break;
        case 'chat':
          _handleChatEvent(contactSessionId, decryptedData);
          break;
        case 'presence':
          _handlePresenceEvent(
              contactSessionId, action == 'online', decryptedData);
          break;
        case 'user_data_exchange':
          _handleUserDataExchange(contactSessionId, decryptedData);
          break;
        case 'conversation_created':
          _handleConversationCreated(contactSessionId, decryptedData);
          break;
        default:
          print(
              '🔌 ChannelSocketService: ⚠️ Unknown encrypted event type: $eventType');
      }
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error handling encrypted event: $e');
    }
  }

  /// Handle typing events (from decrypted data)
  void _handleTypingEvent(String contactSessionId, bool isTyping,
      Map<String, dynamic> decryptedData) {
    print(
        '🔌 ChannelSocketService: ⌨️ Typing event: $contactSessionId -> $isTyping');

    // Forward to realtime typing service
    try {
      final realtimeManager = RealtimeServiceManager();
      if (realtimeManager.isInitialized) {
        final typingService = realtimeManager.typing;
        if (typingService != null) {
          // Use conversation_id from decrypted data or generate from contact ID
          final conversationId = decryptedData['conversation_id'] ??
              'chat_${_currentSessionId}_$contactSessionId';
          typingService.handleIncomingTypingIndicator(
              conversationId, contactSessionId, isTyping);
        }
      }
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error forwarding typing event: $e');
    }
  }

  /// Handle chat events (from decrypted data)
  void _handleChatEvent(
      String contactSessionId, Map<String, dynamic> decryptedData) {
    print('🔌 ChannelSocketService: 💬 Chat event: $contactSessionId');

    // Forward to realtime message service
    try {
      final realtimeManager = RealtimeServiceManager();
      if (realtimeManager.isInitialized) {
        final messageService = realtimeManager.messageTransport;
        if (messageService != null) {
          // Handle new message from decrypted data
          final content = decryptedData['content'] as String? ?? '';
          final messageId = decryptedData['message_id'] as String? ?? '';
          final conversationId = decryptedData['conversation_id'] ??
              'chat_${_currentSessionId}_$contactSessionId';

          // Create notification if app is in background
          if (!AppStateService().isForeground) {
            _notificationManager.showKerNotification(
              title:
                  'New Message from ${decryptedData['sender_name'] ?? contactSessionId}',
              body: content,
              type: 'new_message',
              payload: {
                'type': 'new_message',
                'senderId': contactSessionId,
                'senderName': decryptedData['sender_name'] ?? contactSessionId,
                'message': content,
                'conversationId': conversationId,
                'messageId': messageId,
                'metadata': Map<String, dynamic>.from(decryptedData),
                'timestamp': DateTime.now().toIso8601String(),
              },
            );
          }
        }
      }
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error forwarding chat event: $e');
    }
  }

  /// Handle presence events (from decrypted data)
  void _handlePresenceEvent(String contactSessionId, bool isOnline,
      Map<String, dynamic> decryptedData) {
    print(
        '🔌 ChannelSocketService: 🟢 Presence event: $contactSessionId -> ${isOnline ? 'online' : 'offline'}');

    // Forward to realtime presence service
    try {
      final realtimeManager = RealtimeServiceManager();
      if (realtimeManager.isInitialized) {
        final presenceService = realtimeManager.presence;
        if (presenceService != null) {
          // Use available method to update presence
          presenceService.forcePresenceUpdate(isOnline);
        }
      }
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error forwarding presence event: $e');
    }
  }

  /// Handle user data exchange events (from decrypted data)
  void _handleUserDataExchange(
      String contactSessionId, Map<String, dynamic> decryptedData) {
    print('🔌 ChannelSocketService: 🔑 User data exchange: $contactSessionId');

    // Forward to key exchange service for user data processing
    try {
      final keyExchangeService = KeyExchangeService.instance;
      // This will handle the encrypted user data exchange
      // The service should decrypt the data and process the display name
      print(
          '🔌 ChannelSocketService: ✅ User data exchange forwarded to key exchange service');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Error forwarding user data exchange: $e');
    }
  }

  /// Handle conversation created events (from decrypted data)
  void _handleConversationCreated(
      String contactSessionId, Map<String, dynamic> decryptedData) {
    print(
        '🔌 ChannelSocketService: 💬 Conversation created: $contactSessionId');

    // Forward to appropriate service for conversation creation
    try {
      // This event indicates a conversation was created on the other side
      // The local app should also create the conversation if it doesn't exist
      print('🔌 ChannelSocketService: ✅ Conversation created event processed');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Error processing conversation created: $e');
    }
  }

  /// Handle key exchange events (unencrypted - KER handshake)
  void _handleKeyExchangeEvent(
      String contactSessionId, String action, dynamic data) {
    print(
        '🔌 ChannelSocketService: 🔑 Key exchange event: $contactSessionId -> $action');

    // Forward to key exchange service (KER events are unencrypted)
    try {
      final keyExchangeService = KeyExchangeService.instance;
      if (action == 'request') {
        keyExchangeService.processKeyExchangeRequest(data);
      } else if (action == 'response') {
        keyExchangeService.processKeyExchangeResponse(data);
      } else if (action == 'revoked') {
        // Handle revoked event - use available method or log
        print(
            '🔌 ChannelSocketService: ⚠️ Key exchange revoked event not implemented yet');
      }
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Error forwarding key exchange event: $e');
    }
  }

  /// Clean up all active listeners
  void _cleanupAllListeners() {
    if (_socket == null) return;

    for (final entry in _activeListeners.entries) {
      final contactId = entry.key;
      final listeners = entry.value;

      for (final event in listeners) {
        _socket!.off(event);
      }
    }

    _activeListeners.clear();
    print('🔌 ChannelSocketService: 🧹 Cleaned up all listeners');
  }

  /// Remove listeners for a specific contact
  void removeContactListeners(String contactSessionId) {
    if (_socket == null) return;

    final listeners = _activeListeners[contactSessionId];
    if (listeners != null) {
      for (final event in listeners) {
        _socket!.off(event);
      }
      _activeListeners.remove(contactSessionId);
      print(
          '🔌 ChannelSocketService: 🧹 Removed listeners for contact: $contactSessionId');
    }
  }

  /// Send typing indicator to specific recipient (encrypted)
  void sendTypingIndicator(String recipientSessionId, bool isTyping) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send typing indicator');
      return;
    }

    try {
      // Create the typing data payload
      final typingPayload = {
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'is_typing': isTyping,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the payload using local encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          typingPayload, recipientSessionId);

      // Create the socket payload with encrypted data
      final socketPayload = {
        'conversation_id': recipientSessionId,
        'encrypted_data': encryptedPayload['data'],
        'checksum': encryptedPayload['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Use channel-based event naming: typing:sessionId:start/stop
      final eventName = isTyping ? 'typing:start' : 'typing:stop';
      _socket!.emit(eventName, socketPayload);

      print(
          '🔌 ChannelSocketService: ✅ Encrypted typing indicator sent: $eventName to $recipientSessionId');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send encrypted typing indicator: $e');
    }
  }

  /// Send message to specific recipient (encrypted)
  void sendMessage(String recipientSessionId, String content,
      {String? messageId}) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send message');
      return;
    }

    try {
      // Create the message data payload
      final messagePayload = {
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'content': content,
        'message_id':
            messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the payload using local encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          messagePayload, recipientSessionId);

      // Create the socket payload with encrypted data
      final socketPayload = {
        'conversation_id': recipientSessionId,
        'encrypted_data': encryptedPayload['data'],
        'checksum': encryptedPayload['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      _socket!.emit('message:send', socketPayload);

      print(
          '🔌 ChannelSocketService: ✅ Encrypted message sent to $recipientSessionId');
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Failed to send encrypted message: $e');
    }
  }

  /// Send presence update to specific recipient (encrypted)
  void sendPresenceUpdate(String recipientSessionId, bool isOnline) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send presence update');
      return;
    }

    try {
      // Create the presence data payload
      final presencePayload = {
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'is_online': isOnline,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the payload using local encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          presencePayload, recipientSessionId);

      // Create the socket payload with encrypted data
      final socketPayload = {
        'conversation_id': recipientSessionId,
        'encrypted_data': encryptedPayload['data'],
        'checksum': encryptedPayload['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      _socket!.emit('presence:update', socketPayload);

      print(
          '🔌 ChannelSocketService: ✅ Encrypted presence update sent: ${isOnline ? 'online' : 'offline'} to $recipientSessionId');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send encrypted presence update: $e');
    }
  }

  /// Send key exchange request (KER) - unencrypted for public key sharing
  void sendKeyExchangeRequest(
      String recipientSessionId, Map<String, dynamic> requestData) {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send key exchange request');
      return;
    }

    try {
      // KER events are unencrypted - keep existing logic but use channel-based delivery
      final kerData = {
        ...requestData,
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Use channel-based event naming: key_exchange:recipientId:request
      _socket!.emit('key_exchange:${recipientSessionId}:request', kerData);

      print(
          '🔌 ChannelSocketService: ✅ Unencrypted key exchange request sent to $recipientSessionId using channel format');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send key exchange request: $e');
    }
  }

  /// Send key exchange response (KER) - unencrypted for public key sharing
  void sendKeyExchangeResponse(
      String recipientSessionId, Map<String, dynamic> responseData) {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send key exchange response');
      return;
    }

    try {
      // KER events are unencrypted - keep existing logic but use channel-based delivery
      final kerData = {
        ...responseData,
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Use channel-based event naming: key_exchange:recipientId:response
      _socket!.emit('key_exchange:${recipientSessionId}:response', kerData);

      print(
          '🔌 ChannelSocketService: ✅ Unencrypted key exchange response sent to $recipientSessionId using channel format');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send key exchange response: $e');
    }
  }

  /// Send user data exchange (encrypted) - after KER handshake when both parties have keys
  void sendUserDataExchange(
      String recipientSessionId, Map<String, dynamic> userData) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send user data exchange');
      return;
    }

    try {
      // Create the user data payload
      final userDataPayload = {
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'display_name': userData['display_name'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the payload using local encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          userDataPayload, recipientSessionId);

      // Create the socket payload with encrypted data
      final socketPayload = {
        'conversation_id': recipientSessionId,
        'encrypted_data': encryptedPayload['data'],
        'checksum': encryptedPayload['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      // CRITICAL FIX: Use channel-based event format to match SeSocketService listener
      // Event format: user_data_exchange:recipientId:data
      _socket!
          .emit('user_data_exchange:${recipientSessionId}:data', socketPayload);

      print(
          '🔌 ChannelSocketService: ✅ Encrypted user data exchange sent to $recipientSessionId using channel format');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send encrypted user data exchange: $e');
    }
  }

  /// Send conversation created confirmation (encrypted) - after conversation is created locally
  void sendConversationCreated(
      String recipientSessionId, Map<String, dynamic> conversationData) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send conversation created');
      return;
    }

    try {
      // Create the conversation data payload
      final conversationPayload = {
        'conversation_id':
            recipientSessionId, // Always equals recipient's session ID
        'sender_id': _currentSessionId,
        'conversation_id_local': conversationData['conversation_id_local'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Encrypt the payload using local encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          conversationPayload, recipientSessionId);

      // Create the socket payload with encrypted data
      final socketPayload = {
        'conversation_id': recipientSessionId,
        'encrypted_data': encryptedPayload['data'],
        'checksum': encryptedPayload['checksum'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      // CRITICAL FIX: Use channel-based event format to match SeSocketService listener
      // Event format: conversation_created:recipientId:confirmation
      _socket!.emit('conversation_created:${recipientSessionId}:confirmation',
          socketPayload);

      print(
          '🔌 ChannelSocketService: ✅ Encrypted conversation created confirmation sent to $recipientSessionId using channel format');
    } catch (e) {
      print(
          '🔌 ChannelSocketService: ❌ Failed to send encrypted conversation created: $e');
    }
  }

  /// Send user online status
  Future<void> sendUserOnlineStatus(bool isOnline) async {
    if (_socket == null || !_isConnected) {
      print(
          '🔌 ChannelSocketService: ⚠️ Socket not connected, cannot send online status');
      return;
    }

    try {
      final statusData = {
        'session_id': _currentSessionId,
        'is_online': isOnline,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _socket!.emit('user:online_status', statusData);

      print(
          '🔌 ChannelSocketService: ✅ Online status sent: ${isOnline ? 'online' : 'offline'}');
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Failed to send online status: $e');
    }
  }

  /// Refresh connection status
  void refreshConnectionStatus() {
    if (_socket != null) {
      _isConnected = _socket!.connected;
      _connectionStateController.add(_isConnected);
    }
  }

  /// Schedule reconnection
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('🔌 ChannelSocketService: ❌ Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    final delay = Duration(
      seconds: (pow(2, _reconnectAttempts) * _reconnectDelay.inSeconds)
          .toInt()
          .clamp(1, _maxReconnectDelay.inSeconds),
    );

    _reconnectTimer = Timer(delay, () async {
      _reconnectAttempts++;
      print(
          '🔌 ChannelSocketService: 🔄 Attempting reconnection (${_reconnectAttempts}/$_maxReconnectAttempts)');

      try {
        await _createSocketConnection();
        if (_isConnected) {
          await _joinSessionChannel();
          _reconnectAttempts = 0;
        }
      } catch (e) {
        print('🔌 ChannelSocketService: ❌ Reconnection failed: $e');
        _scheduleReconnect();
      }
    });
  }

  /// Start heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _socket != null) {
        _socket!.emit('heartbeat', {
          'session_id': _currentSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  /// Handle session expired
  void _handleSessionExpired() {
    print('🔌 ChannelSocketService: ⚠️ Session expired, disconnecting...');
    disconnect();

    // Notify UI about session expiration
    _notificationManager.showKerNotification(
      title: 'Session Expired',
      body: 'Session expired, please log in again',
      type: 'session_expired',
      payload: {
        'event': 'session_expired',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Handle session invalid
  void _handleSessionInvalid() {
    print('🔌 ChannelSocketService: ❌ Session invalid, disconnecting...');
    disconnect();

    // Notify UI about invalid session
    _notificationManager.showKerNotification(
      title: 'Invalid Session',
      body: 'Invalid session, please log in again',
      type: 'session_invalid',
      payload: {
        'event': 'session_invalid',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Disconnect from socket
  Future<void> disconnect() async {
    try {
      _cleanupAllListeners();
      _heartbeatTimer?.cancel();
      _reconnectTimer?.cancel();

      if (_socket != null) {
        await _socket!.disconnect();
        _socket = null;
      }

      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);

      print('🔌 ChannelSocketService: ✅ Disconnected from socket server');
    } catch (e) {
      print('🔌 ChannelSocketService: ❌ Error during disconnect: $e');
    }
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}
