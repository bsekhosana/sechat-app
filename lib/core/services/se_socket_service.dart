import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/features/notifications/services/notification_manager_service.dart';
import 'package:sechat_app/core/services/app_state_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/realtime/realtime_service_manager.dart';

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

      // Send user online status to server
      await sendUserOnlineStatus(true);

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

    // REMOVED: Old user_online/user_offline events - replaced by presence:update
    // These events are now handled by the new realtime protocol

    // REMOVED: Old typing_indicator event - replaced by typing:update
    // This event is now handled by the new realtime protocol

    // NEW: Listen for typing:update events (new protocol)
    _socket!.on('typing:update', (data) {
      try {
        final conversationId = data['conversationId'] as String? ?? '';
        final fromUserId = data['fromUserId'] as String? ?? '';
        final isTyping = data['isTyping'] as bool? ?? false;
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: ⌨️ Typing update received: $fromUserId -> $isTyping in conversation $conversationId');

        // Trigger the typing indicator callback
        if (_onTypingIndicator != null) {
          _onTypingIndicator!(fromUserId, isTyping);
          print(
              '🔌 SeSocketService: ✅ Typing update callback triggered for $fromUserId');
        } else {
          print('🔌 SeSocketService: ⚠️ No typing indicator callback set');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling typing update: $e');
      }
    });

    // NEW: Listen for message:acked events (new protocol)
    _socket!.on('message:acked', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 📨 Message acknowledged by server: $messageId at $timestamp');

        // Update message delivery state via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages.handleServerAck(messageId);
            print(
                '🔌 SeSocketService: ✅ Message ack forwarded to realtime service');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Could not forward message ack to realtime service: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling message ack: $e');
      }
    });

    // NEW: Listen for message:delivered events (new protocol)
    _socket!.on('message:delivered', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 📨 Message delivered: $messageId at $timestamp');

        // Update message delivery state via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages.handleDeliveryConfirmation(messageId);
            print(
                '🔌 SeSocketService: ✅ Message delivery forwarded to realtime service');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Could not forward message delivery to realtime service: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling message delivery: $e');
      }
    });

    // NEW: Listen for message:read events (new protocol)
    _socket!.on('message:read', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print('🔌 SeSocketService: 📨 Message read: $messageId at $timestamp');

        // Update message delivery state via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages.handleReadReceipt(messageId);
            print(
                '🔌 SeSocketService: ✅ Message read receipt forwarded to realtime service');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Could not forward message read receipt to realtime service: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling message read receipt: $e');
      }
    });

    // REMOVED: Old online_status_update event - replaced by presence:update
    // This event is now handled by the new realtime protocol

    // NEW: Listen for presence:update events (new protocol)
    _socket!.on('presence:update', (data) {
      try {
        final sessionId = data['sessionId'] as String? ?? '';
        final isOnline = data['isOnline'] as bool? ?? false;
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 🟢 Presence update received: $sessionId -> ${isOnline ? 'online' : 'offline'} at $timestamp');

        // Trigger the online status update callback
        if (_onOnlineStatusUpdate != null) {
          _onOnlineStatusUpdate!(sessionId, isOnline, timestamp);
          print(
              '🔌 SeSocketService: ✅ Presence update callback triggered for $sessionId');
        } else {
          print('🔌 SeSocketService: ⚠️ No online status update callback set');
        }

        // If this is the current user coming online, handle queued events
        if (isOnline && sessionId == _currentSessionId) {
          print(
              '🔌 SeSocketService: 🔄 Current user came online, processing queued events...');
          _handleUserOnline();
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling presence update: $e');
      }
    });

    // Handle queued events when user comes online
    _socket!.on('queued_events', (data) {
      try {
        final sessionId = data['sessionId'] as String? ?? '';
        final events = data['events'] as List<dynamic>? ?? [];
        final eventCount = events.length;

        print(
            '🔌 SeSocketService: 📦 Received $eventCount queued events for session: $sessionId');

        // Process each queued event
        for (final event in events) {
          _processQueuedEvent(event);
        }

        print('🔌 SeSocketService: ✅ Processed $eventCount queued events');
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling queued events: $e');
      }
    });

    // Handle queued message delivery
    _socket!.on('queued_message_delivered', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final senderId = data['senderId'] as String? ?? '';
        final recipientId = data['recipientId'] as String? ?? '';
        final message = data['message'] as String? ?? '';
        final conversationId = data['conversationId'] as String? ?? '';
        final timestamp = data['timestamp'] as String? ?? '';

        print(
            '🔌 SeSocketService: 📨 Queued message delivered: $messageId from $senderId to $recipientId');

        // Trigger message received callback
        if (_onMessageReceived != null) {
          _onMessageReceived!(senderId ?? '', 'Unknown User', message ?? '',
              conversationId ?? '', messageId ?? '');
          print('🔌 SeSocketService: ✅ Queued message processed via callback');
        }
      } catch (e) {
        print(
            '🔌 SeSocketService: ❌ Error handling queued message delivery: $e');
      }
    });

    // NEW: Listen for receipt:delivered events (new protocol)
    _socket!.on('receipt:delivered', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final fromUserId = data['fromUserId'] as String? ?? '';
        final toUserId = data['toUserId'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 📨 Receipt delivered: $messageId from $fromUserId to $toUserId');

        // Update message delivery state via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages.handleDeliveryConfirmation(messageId);
            print(
                '🔌 SeSocketService: ✅ Receipt delivered forwarded to realtime service');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Could not forward receipt delivered to realtime service: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling receipt delivered: $e');
      }
    });

    // NEW: Listen for receipt:read events (new protocol)
    _socket!.on('receipt:read', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final fromUserId = data['fromUserId'] as String? ?? '';
        final toUserId = data['toUserId'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 📨 Receipt read: $messageId from $fromUserId to $toUserId');

        // Update message delivery state via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages.handleReadReceipt(messageId);
            print(
                '🔌 SeSocketService: ✅ Receipt read forwarded to realtime service');
          }
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Could not forward receipt read to realtime service: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling receipt read: $e');
      }
    });

    // NEW: Listen for message:received events (new protocol)
    _socket!.on('message:received', (data) {
      try {
        final messageId = data['messageId'] as String? ?? '';
        final fromUserId = data['fromUserId'] as String? ?? '';
        final conversationId = data['conversationId'] as String? ?? '';
        final body = data['body'] as String? ?? '';
        final timestamp =
            data['timestamp'] as String? ?? DateTime.now().toIso8601String();

        print(
            '🔌 SeSocketService: 📨 Message received via new protocol: $messageId from $fromUserId');

        // Trigger message received callback
        if (_onMessageReceived != null) {
          _onMessageReceived!(fromUserId ?? '', 'Unknown User', body ?? '',
              conversationId ?? '', messageId ?? '');
          print(
              '🔌 SeSocketService: ✅ New protocol message processed via callback');
        }

        // Send delivery receipt
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.messages
                .sendDeliveryReceipt(messageId, fromUserId ?? '');
            print(
                '🔌 SeSocketService: ✅ Delivery receipt sent via realtime service');
          }
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Could not send delivery receipt: $e');
        }
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling new protocol message: $e');
      }
    });

    // Handle queued key exchange request delivery
    _socket!.on('queued_key_exchange_delivered', (data) {
      try {
        final requestId = data['requestId'] as String? ?? '';
        final senderId = data['senderId'] as String? ?? '';
        final recipientId = data['recipientId'] as String? ?? '';
        final publicKey = data['publicKey'] as String? ?? '';
        final requestPhrase = data['requestPhrase'] as String? ?? '';
        final version = data['version'] as String? ?? '1';

        print(
            '🔌 SeSocketService: 🔑 Queued key exchange request delivered: $requestId from $senderId to $recipientId');

        // Trigger key exchange request callback
        if (_onKeyExchangeRequestReceived != null) {
          final requestData = {
            'requestId': requestId,
            'senderId': senderId,
            'recipientId': recipientId,
            'publicKey': publicKey,
            'requestPhrase': requestPhrase,
            'version': version,
            'timestamp': data['timestamp'] ?? DateTime.now().toIso8601String(),
            'wasQueued': true,
          };

          _onKeyExchangeRequestReceived!(requestData);
          print(
              '🔌 SeSocketService: ✅ Queued key exchange request processed via callback');
        }
      } catch (e) {
        print(
            '🔌 SeSocketService: ❌ Error handling queued key exchange delivery: $e');
      }
    });

    // Handle queue status response
    _socket!.on('queue_status_response', (data) {
      try {
        final recipientId = data['recipientId'] as String? ?? '';
        final hasQueuedEvents = data['hasQueuedEvents'] as bool? ?? false;
        final queuedEventCount = data['queuedEventCount'] as int? ?? 0;
        final lastQueuedAt = data['lastQueuedAt'] as String? ?? '';

        print(
            '🔌 SeSocketService: 📊 Queue status for $recipientId: $queuedEventCount events, last at $lastQueuedAt');

        // You can add a callback here if you want to handle queue status updates
        // For now, just log the information
      } catch (e) {
        print('🔌 SeSocketService: ❌ Error handling queue status response: $e');
      }
    });

    // Handle queue statistics response
    _socket!.on('queue_statistics_response', (data) {
      try {
        final sessionId = data['sessionId'] as String? ?? '';
        final totalQueuedEvents = data['totalQueuedEvents'] as int? ?? 0;
        final pendingDeliveries = data['pendingDeliveries'] as int? ?? 0;
        final successfulDeliveries = data['successfulDeliveries'] as int? ?? 0;
        final failedDeliveries = data['failedDeliveries'] as int? ?? 0;

        print('🔌 SeSocketService: 📊 Queue statistics for $sessionId:');
        print('🔌 SeSocketService:   Total queued: $totalQueuedEvents');
        print('🔌 SeSocketService:   Pending: $pendingDeliveries');
        print('🔌 SeSocketService:   Successful: $successfulDeliveries');
        print('🔌 SeSocketService:   Failed: $failedDeliveries');

        // You can add a callback here if you want to handle queue statistics updates
        // For now, just log the information
      } catch (e) {
        print(
            '🔌 SeSocketService: ❌ Error handling queue statistics response: $e');
      }
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

      // iOS-specific: Validate the connection after reconnect
      if (defaultTargetPlatform == TargetPlatform.iOS && _isConnected) {
        print('🔌 SeSocketService: 🍎 iOS - Validating reconnection...');
        await Future.delayed(
            const Duration(milliseconds: 500)); // Give iOS time to stabilize
        refreshConnectionStatus(); // Double-check the connection
      }

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
      final actualConnected = _socket!.connected;
      final wasConnected = _isConnected;

      // iOS-specific: Double-check connection state consistency
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // On iOS, sometimes the socket.connected state can be stale
        // Force a more thorough check
        if (_isConnected != actualConnected) {
          print(
              '🔌 SeSocketService: 🍎 iOS connection state mismatch detected! Internal: $_isConnected, Socket: $actualConnected');

          // If socket says it's connected but we think it's not, test the connection
          if (actualConnected && !_isConnected) {
            print(
                '🔌 SeSocketService: 🍎 iOS - Socket claims connected, validating...');
            _validateiOSConnection();
          }
        }
      }

      _isConnected = actualConnected;

      // Only notify if the state actually changed
      if (wasConnected != _isConnected) {
        print(
            '🔌 SeSocketService: 🔄 Refreshed connection status: $_isConnected');
        _connectionStateController.add(_isConnected);
      }
    } else {
      _isConnected = false;
      print(
          '🔌 SeSocketService: 🔄 Refreshed connection status: false (no socket)');
      _connectionStateController.add(false);
    }
  }

  /// iOS-specific connection validation
  void _validateiOSConnection() {
    if (_socket != null && _socket!.connected) {
      // Send a lightweight ping to validate the connection
      try {
        _socket!.emit('ping', {
          'sessionId': _currentSessionId,
          'timestamp': DateTime.now().toIso8601String(),
          'platform': 'iOS',
        });
        print('🔌 SeSocketService: 🍎 iOS connection validation ping sent');
      } catch (e) {
        print('🔌 SeSocketService: 🍎 iOS connection validation failed: $e');
        // Don't override connection state on validation failure
        // Just log the issue for debugging
      }
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

  /// Send message via socket with queuing support
  Future<bool> sendMessage({
    required String recipientId,
    required String message,
    required String conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final messageData = {
        'type': 'message:send',
        'messageId':
            messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'conversationId': conversationId,
        'fromUserId': _currentSessionId,
        'toUserIds': [recipientId],
        'body': message,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      };

      // If socket is connected, send immediately
      if (_isConnected) {
        emit('message:send', messageData);
        print(
            '🔌 SeSocketService: ✅ Message sent immediately via new protocol');
        return true;
      } else {
        // If socket is not connected, attempt to queue the message
        print(
            '🔌 SeSocketService: ⚠️ Socket not connected, attempting to queue message...');

        // Try to establish connection for queuing
        final connected = await ensureConnection();
        if (connected) {
          emit('message:send', messageData);
          print(
              '🔌 SeSocketService: ✅ Message queued via socket after connection');
          return true;
        } else {
          // If connection fails, emit a queue event that the server should handle
          emit('queue_message', messageData);
          print('🔌 SeSocketService: ✅ Message queued for offline recipient');
          return true;
        }
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending message: $e');
      return false;
    }
  }

  // REMOVED: Old sendTypingIndicator method - replaced by realtime typing service
  // This functionality is now handled by the new realtime protocol

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

  // REMOVED: Old sendOnlineStatusToAllContacts method - replaced by realtime presence service
  // This functionality is now handled by the new realtime protocol

  /// Send user online status to server (for queuing system)
  Future<bool> sendUserOnlineStatus(bool isOnline) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ⚠️ Cannot send user online status - socket not connected');
        return false;
      }

      final statusData = {
        'type': 'presence:update',
        'sessionId': _currentSessionId,
        'isOnline': isOnline,
        'timestamp': DateTime.now().toIso8601String(),
        'deviceInfo': {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'version': '1.0.0',
        },
      };

      emit('presence:update', statusData);
      print(
          '🔌 SeSocketService: ✅ User presence update sent: ${isOnline ? "online" : "offline"}');
      return true;
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error sending user online status: $e');
      return false;
    }
  }

  /// Handle user coming online and process queued events
  void _handleUserOnline() {
    try {
      print(
          '🔌 SeSocketService: 🔄 Processing queued events for user: $_currentSessionId');

      // Request queued events from server
      emit('request_queued_events', {
        'sessionId': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('🔌 SeSocketService: ✅ Requested queued events from server');
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error handling user online: $e');
    }
  }

  /// Process individual queued event
  void _processQueuedEvent(Map<String, dynamic> event) {
    try {
      final eventType = event['type'] as String? ?? '';
      final eventData = event['data'] as Map<String, dynamic>? ?? {};

      print('🔌 SeSocketService: 🔄 Processing queued event type: $eventType');

      switch (eventType) {
        case 'message':
          _processQueuedMessage(eventData);
          break;
        case 'key_exchange_request':
          _processQueuedKeyExchangeRequest(eventData);
          break;
        case 'typing_indicator':
          _processQueuedTypingIndicator(eventData);
          break;
        default:
          print('🔌 SeSocketService: ⚠️ Unknown queued event type: $eventType');
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error processing queued event: $e');
    }
  }

  /// Process queued message event
  void _processQueuedMessage(Map<String, dynamic> eventData) {
    try {
      final messageId = eventData['messageId'] as String? ?? '';
      final senderId = eventData['senderId'] as String? ?? '';
      final message = eventData['message'] as String? ?? '';
      final conversationId = eventData['conversationId'] as String? ?? '';

      print(
          '🔌 SeSocketService: 📨 Processing queued message: $messageId from $senderId');

      // Trigger message received callback
      if (_onMessageReceived != null) {
        _onMessageReceived!(senderId ?? '', 'Unknown User', message ?? '',
            conversationId ?? '', messageId ?? '');
        print('🔌 SeSocketService: ✅ Queued message processed');
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error processing queued message: $e');
    }
  }

  /// Process queued key exchange request event
  void _processQueuedKeyExchangeRequest(Map<String, dynamic> eventData) {
    try {
      final requestId = eventData['requestId'] as String? ?? '';
      final senderId = eventData['senderId'] as String? ?? '';
      final publicKey = eventData['publicKey'] as String? ?? '';
      final requestPhrase = eventData['requestPhrase'] as String? ?? '';
      final version = eventData['version'] as String? ?? '1';

      print(
          '🔌 SeSocketService: 🔑 Processing queued key exchange request: $requestId from $senderId');

      // Trigger key exchange request callback
      if (_onKeyExchangeRequestReceived != null) {
        final requestData = {
          'requestId': requestId,
          'senderId': senderId,
          'publicKey': publicKey,
          'requestPhrase': requestPhrase,
          'version': version,
          'timestamp':
              eventData['timestamp'] ?? DateTime.now().toIso8601String(),
          'wasQueued': true,
        };

        _onKeyExchangeRequestReceived!(requestData);
        print('🔌 SeSocketService: ✅ Queued key exchange request processed');
      }
    } catch (e) {
      print(
          '🔌 SeSocketService: ❌ Error processing queued key exchange request: $e');
    }
  }

  /// Process queued typing indicator event
  void _processQueuedTypingIndicator(Map<String, dynamic> eventData) {
    try {
      final senderId = eventData['senderId'] as String? ?? '';
      final isTyping = eventData['isTyping'] as bool? ?? false;

      print(
          '🔌 SeSocketService: ⌨️ Processing queued typing indicator: $senderId -> $isTyping');

      // Trigger typing indicator callback
      if (_onTypingIndicator != null) {
        _onTypingIndicator!(senderId ?? '', isTyping);
        print('🔌 SeSocketService: ✅ Queued typing indicator processed');
      }
    } catch (e) {
      print(
          '🔌 SeSocketService: ❌ Error processing queued typing indicator: $e');
    }
  }

  /// Check queue status for a specific recipient
  Future<Map<String, dynamic>?> checkQueueStatus(String recipientId) async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ⚠️ Cannot check queue status - socket not connected');
        return null;
      }

      final requestData = {
        'recipientId': recipientId,
        'sessionId': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      emit('check_queue_status', requestData);
      print(
          '🔌 SeSocketService: ✅ Queue status check requested for: $recipientId');

      // Note: Server should respond with 'queue_status_response' event
      return {'status': 'requested'};
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error checking queue status: $e');
      return null;
    }
  }

  /// Get queue statistics for current user
  Future<Map<String, dynamic>?> getQueueStatistics() async {
    try {
      if (!_isConnected) {
        print(
            '🔌 SeSocketService: ⚠️ Cannot get queue statistics - socket not connected');
        return null;
      }

      final requestData = {
        'sessionId': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      emit('get_queue_statistics', requestData);
      print('🔌 SeSocketService: ✅ Queue statistics requested');

      // Note: Server should respond with 'queue_statistics_response' event
      return {'status': 'requested'};
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error getting queue statistics: $e');
      return null;
    }
  }

  /// Delete this session on the socket server and clear EVERYTHING
  /// - Attempts a lightweight connect if not already connected, so it can send the commands
  /// - Emits comprehensive cleanup commands to server
  /// - Clears all local data and references
  /// - Resets socket service to initial state
  Future<void> deleteSessionOnServer(
      {String? sessionId, bool clearEverything = true}) async {
    final String? targetSessionId = sessionId ?? _currentSessionId;
    if (targetSessionId == null || targetSessionId.isEmpty) {
      print(
          '🔌 SeSocketService: ⚠️ No sessionId available to delete on server');
      _clearLocalState();
      return;
    }

    print(
        '🔌 SeSocketService: 🗑️ Starting comprehensive account deletion for session: $targetSessionId');

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
          // Send offline status before deletion
          await sendUserOnlineStatus(false);
          print('🔌 SeSocketService: ✅ Sent offline status before deletion');
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Error sending offline status: $e');
        }

        try {
          // Clear any queued messages for this user on the server
          emit('clear_user_queue', {
            'sessionId': targetSessionId,
            'clearAll': true,
          });
          print('🔌 SeSocketService: ✅ Requested server queue clearance');
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Error emitting clear_user_queue: $e');
        }

        try {
          // Clear all conversations and messages for this user
          emit('clear_user_conversations', {
            'sessionId': targetSessionId,
            'clearAll': true,
          });
          print(
              '🔌 SeSocketService: ✅ Requested server conversation clearance');
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Error emitting clear_user_conversations: $e');
        }

        try {
          // Clear all key exchange data for this user
          emit('clear_user_key_exchanges', {
            'sessionId': targetSessionId,
            'clearAll': true,
          });
          print(
              '🔌 SeSocketService: ✅ Requested server key exchange clearance');
        } catch (e) {
          print(
              '🔌 SeSocketService: ⚠️ Error emitting clear_user_key_exchanges: $e');
        }

        try {
          // Notify server that this account/session is deleted
          emit('delete_account', {
            'sessionId': targetSessionId,
            'permanent': clearEverything,
            'timestamp': DateTime.now().toIso8601String(),
          });
          print('🔌 SeSocketService: ✅ Requested server account deletion');
        } catch (e) {
          print('🔌 SeSocketService: ⚠️ Error emitting delete_account: $e');
        }
      }
    } catch (e) {
      print('🔌 SeSocketService: ❌ Error during deleteSessionOnServer: $e');
    } finally {
      // Clear all local state
      _clearLocalState();

      // If we connected only for cleanup, disconnect
      if (connectedTemporarily) {
        try {
          await disconnect();
        } catch (_) {}
      }

      print('🔌 SeSocketService: ✅ Account deletion completed');
    }
  }

  /// Clear all local state and reset service
  void _clearLocalState() {
    print('🔌 SeSocketService: 🧹 Clearing all local state...');

    // Clear session reference
    _currentSessionId = null;

    // Reset connection state
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;

    // Cancel all timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Clear callbacks
    _onMessageReceived = null;
    _onTypingIndicator = null;
    _onOnlineStatusUpdate = null;
    _onMessageStatusUpdate = null;
    _onKeyExchangeRequestReceived = null;
    _onKeyExchangeAccepted = null;
    _onKeyExchangeDeclined = null;
    _onConversationCreated = null;

    // Notify connection state change
    _connectionStateController.add(false);

    print('🔌 SeSocketService: ✅ Local state cleared');
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

      // If socket is connected, send immediately
      if (_isConnected) {
        emit('key_exchange_request', keyExchangeData);
        print(
            '🔌 SeSocketService: ✅ Key exchange request sent immediately via socket');
      } else {
        // If socket is not connected, attempt to queue the request
        print(
            '🔌 SeSocketService: ⚠️ Socket not connected, attempting to queue key exchange request...');

        // Try to establish connection for queuing
        final connected = await ensureConnection();
        if (connected) {
          emit('key_exchange_request', keyExchangeData);
          print(
              '🔌 SeSocketService: ✅ Key exchange request queued via socket after connection');
        } else {
          // If connection fails, emit a queue event that the server should handle
          emit('queue_key_exchange_request', keyExchangeData);
          print(
              '🔌 SeSocketService: ✅ Key exchange request queued for offline recipient');
        }
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

    // Send offline status to server before disconnecting
    if (_isConnected && _currentSessionId != null) {
      try {
        await sendUserOnlineStatus(false);
        print('🔌 SeSocketService: ✅ Offline status sent to server');
      } catch (e) {
        print('🔌 SeSocketService: ⚠️ Failed to send offline status: $e');
      }
    }

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
