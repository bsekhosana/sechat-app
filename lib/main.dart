import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform, ProcessSignal, Process;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

// Import models for message status updates
import 'features/chat/services/message_status_tracking_service.dart';
import 'features/chat/models/message.dart';
import 'features/chat/models/message_status.dart' as msg_status;

// import feature providers
import 'features/key_exchange/providers/key_exchange_request_provider.dart';
import 'features/chat/providers/chat_list_provider.dart';
import 'features/chat/providers/session_chat_provider.dart';
import 'shared/providers/socket_provider.dart';

// import screens
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';

// import widgets
import 'shared/widgets/app_lifecycle_handler.dart';

// import services
import 'core/services/se_session_service.dart';
import 'core/services/se_shared_preference_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';
import 'features/chat/services/message_storage_service.dart';
import 'core/services/se_socket_service.dart';
import 'core/services/key_exchange_service.dart';
import 'core/services/ui_service.dart';
import 'core/services/presence_manager.dart';
import 'core/services/contact_service.dart';
import 'core/services/app_lifecycle_manager.dart';
import 'features/notifications/services/local_notification_items_service.dart';
import 'features/notifications/services/local_notification_badge_service.dart';
import 'realtime/realtime_service_manager.dart';
import 'realtime/realtime_test.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'core/services/indicator_service.dart';
import 'core/services/encryption_service.dart';
import 'package:sechat_app/shared/providers/socket_status_provider.dart';
import 'package:sechat_app/core/services/network_service.dart';
import 'package:sechat_app/core/services/unified_message_service.dart';

import 'package:sechat_app/core/utils/conversation_id_generator.dart';

// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global variable to track current screen index
int _currentScreenIndex = 0;

/// Update the current screen index (called from MainNavScreen)
void updateCurrentScreenIndex(int index) {
  _currentScreenIndex = index;
  print('🔍 Main: Current screen index updated to: $index');
}

/// CRITICAL: Set up app termination handler to prevent socket service memory leaks
void _setupAppTerminationHandler() {
  // Handle app termination signals
  ProcessSignal.sigterm.watch().listen((_) {
    print('🔌 Main: 🚨 SIGTERM received - cleaning up socket services...');
    _cleanupSocketServices();
  });

  ProcessSignal.sigint.watch().listen((_) {
    print('🔌 Main: 🚨 SIGINT received - cleaning up socket services...');
    _cleanupSocketServices();
  });

  print('🔌 Main: ✅ App termination handlers configured');
}

/// Clean up socket services to prevent memory leaks
void _cleanupSocketServices() {
  try {
    print('🔌 Main: 🧹 Starting socket service cleanup...');

    // Force cleanup all socket services
    SeSocketService.forceCleanup();
    print('🔌 Main: ✅ Socket services force cleanup completed');
  } catch (e) {
    print('🔌 Main: ❌ Error during socket service cleanup: $e');
  }
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  print('🔌 Main: Starting SeChat application...');
  print(
      '🔌 Main: Platform: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Web'}');

  // CRITICAL: Set up app termination handler to prevent memory leaks
  _setupAppTerminationHandler();

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // Initialize core services in parallel for faster startup
  await Future.wait([
    LocalStorageService.instance.initialize(),
    SeSharedPreferenceService().initialize(),
    MessageStorageService.instance.initialize(),
  ]);

  // Initialize local notification services
  try {
    final localNotificationService = LocalNotificationItemsService();
    final localNotificationBadgeService = LocalNotificationBadgeService();

    // Force reset any old notification counts first
    await localNotificationBadgeService.forceResetAndReinitialize();

    print('🔌 Main: ✅ Local notification services initialized successfully');
  } catch (e) {
    print('🔌 Main: ⚠️ Failed to initialize local notification services: $e');
  }

  // Initialize presence management system
  try {
    final presenceManager = PresenceManager.instance;
    await presenceManager.initialize();
    print('🔌 Main: ✅ Presence management system initialized successfully');
  } catch (e) {
    print('🔌 Main: ❌ Failed to initialize presence management system: $e');
  }

  // Initialize realtime services
  try {
    final realtimeManager = RealtimeServiceManager();
    await realtimeManager.initialize();
    print('🔌 Main: ✅ Realtime services initialized successfully');

    // Run basic tests in debug mode
    if (kDebugMode) {
      try {
        await RealtimeTest.runBasicTests();
        print('🔌 Main: ✅ Realtime service tests passed');
      } catch (e) {
        print('🔌 Main: ⚠️ Realtime service tests failed: $e');
      }
    }
  } catch (e) {
    print('🔌 Main: ❌ Failed to initialize realtime services: $e');
  }

  // Initialize SeSessionService
  final seSessionService = SeSessionService();
  await seSessionService.loadSession();

  // Set up socket callbacks for realtime features
  final socketService = SeSocketService.instance;

  // Ensure socket service is ready for new connections
  if (SeSocketService.isDestroyed) {
    print(
        '🔌 Main: 🔄 Socket service was destroyed, resetting for new session...');
    SeSocketService.resetForNewConnection();
  }

  // CRITICAL: Set up socket callbacks IMMEDIATELY to avoid race conditions
  print('🔌 Main: 🚀 Setting up socket callbacks immediately...');
  _setupSocketCallbacks(socketService);
  print('🔌 Main: ✅ Socket callbacks set up successfully');

  // Verify callback setup
  print('🔌 Main: 🔍 Verifying onKeyExchangeResponse callback setup...');
  if (socketService.onKeyExchangeResponse != null) {
    print('🔌 Main: ✅ onKeyExchangeResponse callback is properly set');
  } else {
    print(
        '🔌 Main: ❌ onKeyExchangeResponse callback is NULL - this will cause issues!');
  }

  // Set up contact listeners for the current user's contacts
  // This will enable receiving typing indicators and other events
  if (seSessionService.currentSession != null) {
    // For now, we'll set up a basic listener
    // In the future, this should be populated with actual contact session IDs
    final currentUserId = seSessionService.currentSessionId;
    if (currentUserId != null) {
      print(
          '🔌 Main: ✅ Channel-based socket service initialized for user: $currentUserId');
    }
  }

  // Note: Typing indicators are now handled through the ChannelSocketService event system
  // The realtime services will automatically receive and process these events

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IndicatorService()),
        ChangeNotifierProvider(create: (_) => SessionChatProvider()),
        ChangeNotifierProvider(create: (_) => KeyExchangeRequestProvider()),
        ChangeNotifierProvider(create: (_) => ContactService.instance),
        ChangeNotifierProvider(create: (_) => PresenceManager.instance),
        ChangeNotifierProvider(create: (_) {
          final provider = SocketProvider();
          // Initialize in the next frame to avoid blocking the UI
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await provider.initialize();
            // Refresh connection state after initialization
            provider.refreshConnectionState();
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) {
          final provider = ChatListProvider();
          // Initialize in the next frame to avoid blocking the UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.initialize();

            // CRITICAL: Set up ChatListProvider to listen to UnifiedMessageService
            final unifiedMessageService = UnifiedMessageService.instance;
            unifiedMessageService.addListener(() {
              print(
                  '🔌 Main: 🔔 ChatListProvider UnifiedMessageService update received');
              // Refresh the chat list to show latest messages
              provider.refreshConversations();
            });
            print(
                '🔌 Main: ✅ ChatListProvider UnifiedMessageService listener set up');
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) {
          final provider = SessionChatProvider();
          // Set up online status callback to ChatListProvider
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);
            chatListProvider
                .setOnOnlineStatusChanged((userId, isOnline, lastSeen) {
              provider.updateRecipientStatus(
                recipientId: userId,
                isOnline: isOnline,
                lastSeen: lastSeen,
              );
            });
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
        ChangeNotifierProvider(create: (_) => LocalStorageService.instance),
        ChangeNotifierProvider(create: (_) => SocketStatusProvider.instance),
      ],
      child: AppLifecycleManager(
        presenceManager: PresenceManager.instance,
        child: const SeChatApp(),
      ),
    ),
  );

  // CRITICAL: Set up global UnifiedMessageService listener after app is built
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final globalSessionChatProvider = Provider.of<SessionChatProvider>(
          navigatorKey.currentContext!,
          listen: false);

      // Set up a global listener for UnifiedMessageService
      final unifiedMessageService = UnifiedMessageService.instance;
      print('🔌 Main: 🔍 Setting up global UnifiedMessageService listener');
      print(
          '🔌 Main: 🔍 Global SessionChatProvider instance: ${globalSessionChatProvider.hashCode}');
      print(
          '🔌 Main: 🔍 UnifiedMessageService instance: ${unifiedMessageService.hashCode}');

      // Add the global provider as a listener
      unifiedMessageService.addListener(() {
        print('🔌 Main: 🔔 Global UnifiedMessageService update received');
        // Notify the global SessionChatProvider to refresh
        globalSessionChatProvider.notifyListeners();
      });

      print(
          '🔌 Main: ✅ Global UnifiedMessageService listener set up successfully');
    } catch (e) {
      print(
          '🔌 Main: ❌ Failed to set up global UnifiedMessageService listener: $e');
    }
  });
}

/// Show push notification for received message
Future<void> _showMessageNotification(
    String senderName, String messageId, String conversationId) async {
  try {
    // Show notification using our new local notification system
    final localNotificationBadgeService = LocalNotificationBadgeService();

    await localNotificationBadgeService.showMessageNotification(
      title: senderName,
      body: 'Has sent you an encrypted message',
      type: 'message_received',
      payload: {
        'type': 'new_message',
        'senderName': senderName,
        'messageId': messageId,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    print('🔔 Main: ✅ Push notification sent for message: $messageId');
  } catch (e) {
    print('🔔 Main: ❌ Failed to send push notification: $e');
  }
}

// Set up socket callbacks
void _setupSocketCallbacks(SeSocketService socketService) {
  // Set up callbacks for the socket service
  socketService.setOnMessageReceived(
      (senderId, senderName, message, conversationId, messageId) {
    print(
        '🔌 Main: Message received callback from socket: $senderName: $message');

    // CRITICAL: Save incoming message to database via UnifiedMessageService
    try {
      final unifiedMessageService = UnifiedMessageService.instance;
      print(
          '🔌 Main: 🔍 Using UnifiedMessageService instance: ${unifiedMessageService.hashCode}');

      // Check if message is encrypted (default to true for security)
      bool isEncrypted = true;
      String? checksum;

      // CRITICAL: Declare conversation ID outside the if block for use in callback
      String? actualConversationId;

      // If the message payload contains encryption info, extract it
      // This would come from the socket event data structure
      if (messageId.isNotEmpty && message.isNotEmpty) {
        // CRITICAL: Use consistent conversation ID for both users
        final currentUserId = SeSessionService().currentSessionId ?? '';
        actualConversationId =
            _generateConsistentConversationId(currentUserId, senderId);

        print('🔌 Main: 🔍 Socket conversationId: $conversationId');
        print('🔌 Main: 🔍 SenderId: $senderId');
        print('🔌 Main: 🔍 Using conversationId: $actualConversationId');

        // CRITICAL: Ensure conversation exists before saving message
        _ensureConversationExists(actualConversationId, senderId, senderName);

        // Store message to database with encrypted text only
        unifiedMessageService.handleIncomingMessage(
          messageId: messageId,
          fromUserId: senderId,
          conversationId: actualConversationId,
          body: message,
          timestamp: DateTime.now(),
          isEncrypted: isEncrypted,
          checksum: checksum,
        );
        print(
            '🔌 Main: ✅ Incoming message saved to database via UnifiedMessageService');

        // Show push notification with sender name and generic body
        _showMessageNotification(
            senderName, messageId, actualConversationId ?? '');

        // CRITICAL: Update conversation with new message and decrypt preview
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            final indicatorService = Provider.of<IndicatorService>(
                navigatorKey.currentContext!,
                listen: false);

            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            try {
              // Call handleIncomingMessage to decrypt the message preview
              if (actualConversationId != null) {
                chatListProvider.handleIncomingMessage(
                  senderId: senderId,
                  senderName: senderName,
                  message: message,
                  conversationId: actualConversationId,
                  messageId: messageId,
                );
                print(
                    '🔌 Main: ✅ Conversation updated with decrypted message preview');

                // CRITICAL: Also update chat list in real-time with new message
                chatListProvider.handleNewMessageArrival(
                  messageId: messageId,
                  senderId: senderId,
                  content: message,
                  conversationId: actualConversationId,
                  timestamp: DateTime.now(),
                  messageType: MessageType.text,
                );
                print(
                    '🔌 Main: ✅ Chat list updated in real-time with new message');
              }
            } catch (e) {
              print(
                  '🔌 Main: ⚠️ Failed to update conversation with decrypted preview: $e');
            }

            // Count unread conversations
            final unreadCount = chatListProvider.conversations
                .where((conv) => conv.unreadCount > 0)
                .length;

            // Update the indicator service
            indicatorService.updateCounts(unreadChats: unreadCount);
            print('🔌 Main: ✅ Chat badge count updated for new message');

            // Show push notification for the message
            if (actualConversationId != null) {
              _showMessageNotification(
                senderName,
                messageId,
                actualConversationId,
              );
            }
          } catch (e) {
            print('🔌 Main: ❌ Failed to update chat badge count: $e');
          }
        });
      } else {
        print('🔌 Main: ⚠️ Invalid message data received');
      }
    } catch (e) {
      print('🔌 Main: ❌ Failed to save incoming message to database: $e');
    }
  });

  print('🔌 Main: 🔧 Setting up typing indicator callback...');
  socketService.setOnTypingIndicator((senderId, isTyping) {
    print(
        '🔌 Main: 🔔 Typing indicator callback EXECUTED: $senderId -> $isTyping');

    // CRITICAL: Filter out own typing indicators
    final currentUserId = SeSessionService().currentSessionId;
    if (currentUserId != null && senderId == currentUserId) {
      print('🔌 Main: ⚠️ Ignoring own typing indicator from: $senderId');
      return; // Don't process own typing indicator
    }

    // Forward typing indicator to both SessionChatProvider and ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Update ChatListProvider for chat list items
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Find conversation by participant ID and update typing indicator
        // This will show the typing indicator on the recipient's side (not the sender's)
        chatListProvider.updateTypingIndicatorByParticipant(senderId, isTyping);

        // Also notify SessionChatProvider if there's an active chat
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // Check if this typing indicator is for the current conversation
          if (sessionChatProvider.currentRecipientId != null) {
            final currentRecipientId = sessionChatProvider.currentRecipientId;

            // CRITICAL: The typing indicator should be shown when:
            // 1. The sender is the current recipient (meaning we're seeing someone else type)
            // 2. The currentRecipientId contains the sender ID (conversation match)
            bool shouldUpdate = false;

            if (currentRecipientId == senderId) {
              // Direct match with current recipient - show typing indicator
              shouldUpdate = true;
            } else if (currentRecipientId?.startsWith('chat_') == true &&
                currentRecipientId?.contains(senderId) == true) {
              // Conversation ID contains the sender ID - show typing indicator
              shouldUpdate = true;
            }

            if (shouldUpdate) {
              // CRITICAL: Only show typing indicator if the sender is NOT the current user
              final currentUserId = SeSessionService().currentSessionId;
              if (currentUserId != null && senderId != currentUserId) {
                sessionChatProvider.updateRecipientTypingState(isTyping);
                print(
                    '🔌 Main: ✅ Typing indicator updated for current conversation: $senderId -> $isTyping');
              } else {
                print(
                    '🔌 Main: ⚠️ Not showing typing indicator for own typing: $senderId');
              }
            } else {
              print(
                  '🔌 Main: ℹ️ Typing indicator from different conversation: $senderId (current: $currentRecipientId)');
            }
          } else {
            print('🔌 Main: ℹ️ No active chat conversation');
          }
        } catch (e) {
          print('🔌 Main: ⚠️ SessionChatProvider not available: $e');
        }

        print('🔌 Main: ✅ Typing indicator processed successfully');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process typing indicator: $e');
      }
    });
  });
  print('🔌 Main: ✅ Typing indicator callback setup complete');

  // Handle presence updates (online/offline status)
  socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
    print(
        '🔌 Main: Presence update received: $senderId -> ${isOnline ? 'online' : 'offline'} (lastSeen: $lastSeen)');

    // Update ChatListProvider for chat list items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        print('🔌 Main: 🔍 Starting presence update processing...');

        // Update ContactService for presence management
        try {
          print('🔌 Main: 🔍 Attempting to get ContactService from context...');
          final contactService = Provider.of<ContactService>(
              navigatorKey.currentContext!,
              listen: false);

          print('🔌 Main: ✅ ContactService obtained successfully');
          // 🆕 FIXED: Use existing lastSeen from ContactService when server doesn't provide one
          DateTime lastSeenDateTime;
          if (lastSeen != null) {
            lastSeenDateTime = DateTime.parse(lastSeen);
          } else {
            // Try to get existing lastSeen from ContactService to preserve offline time
            try {
              final existingContact = contactService.getContact(senderId);
              lastSeenDateTime = existingContact?.lastSeen ??
                  DateTime.now().subtract(Duration(hours: 1));
            } catch (e) {
              // Fallback to 1 hour ago if we can't get existing contact
              lastSeenDateTime = DateTime.now().subtract(Duration(hours: 1));
            }
          }

          print('🔌 Main: 🔍 Calling contactService.updateContactPresence...');
          contactService.updateContactPresence(
              senderId, isOnline, lastSeenDateTime);
          print(
              '🔌 Main: ✅ Presence update sent to ContactService for: $senderId -> ${isOnline ? 'online' : 'offline'}');
        } catch (e) {
          print('🔌 Main: ❌ ContactService error: $e');
          print('🔌 Main: 🔍 Stack trace: ${StackTrace.current}');
        }

        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Update conversation online status
        chatListProvider.updateConversationOnlineStatus(
            senderId, isOnline, lastSeen);
        print(
            '🔌 Main: ✅ Conversation online status updated for: $senderId -> ${isOnline ? 'online' : 'offline'}');

        // Also notify SessionChatProvider if there's an active chat
        try {
          print('🔌 Main: 🔍 Attempting to get SessionChatProvider...');
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          print('🔌 Main: ✅ SessionChatProvider obtained');
          print(
              '🔌 Main: 🔍 Current recipient ID: ${sessionChatProvider.currentRecipientId}');
          print('🔌 Main: 🔍 Sender ID: $senderId');

          // If the sender is the current recipient, update their online state
          if (sessionChatProvider.currentRecipientId == senderId) {
            print(
                '🔌 Main: 🔄 Updating SessionChatProvider recipient status...');
            sessionChatProvider.updateRecipientStatus(
              recipientId: senderId,
              isOnline: isOnline,
              lastSeen: lastSeen != null ? DateTime.parse(lastSeen) : null,
            );
            print(
                '🔌 Main: ✅ Presence update forwarded to SessionChatProvider for current recipient: $senderId');
          } else {
            print(
                '🔌 Main: ℹ️ Sender is not current recipient, skipping SessionChatProvider update');
          }
        } catch (e) {
          print('🔌 Main: ❌ SessionChatProvider error: $e');
          print('🔌 Main: 🔍 Stack trace: ${StackTrace.current}');
        }

        print(
            '🔌 Main: ✅ Presence update processed successfully for: $senderId');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process presence update: $e');
      }
    });
  });

  socketService.setOnMessageStatusUpdate(
      (senderId, messageId, status, conversationId, recipientId) {
    print(
        '🔌 Main: Message status update from socket: $messageId -> $status (conversationId: $conversationId, recipientId: $recipientId)');

    // 🆕 FIXED: Only process certain status updates, ignore delivered/read from message:status_update
    // These should only come through receipt:delivered and receipt:read events
    if (status.toLowerCase() == 'delivered' || status.toLowerCase() == 'read') {
      print(
          '🔌 Main: ⚠️ Ignoring delivered/read status from message:status_update - waiting for proper receipt events');
      return; // Don't process delivered/read status from message:status_update
    }

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Parse the status string to enum
        msg_status.MessageDeliveryStatus parsedStatus;
        switch (status.toLowerCase()) {
          case 'sent':
            parsedStatus = msg_status.MessageDeliveryStatus.sent;
            break;
          case 'queued':
            parsedStatus = msg_status
                .MessageDeliveryStatus.sent; // Keep as sent until delivered
            break;
          default:
            parsedStatus = msg_status.MessageDeliveryStatus.sent;
            print('🔌 Main: ⚠️ Unknown status: $status, defaulting to sent');
            break;
        }

        // Create a MessageStatusUpdate with enhanced data for better conversation lookup
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: parsedStatus,
          timestamp: DateTime.now(),
          senderId: senderId,
        );

        // Pass additional data for conversation lookup via a custom method
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate,
            conversationId: conversationId, recipientId: recipientId);
        print(
            '🔌 Main: ✅ Message status updated in ChatListProvider with enhanced lookup data: $status');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process message status update: $e');
      }
    });
  });

  // Set up key exchange callbacks
  socketService.setOnKeyExchangeRequestReceived((data) {
    print('🔌 Main: 🔥 Key exchange request received from socket: $data');
    print('🔌 Main: 🔥 Callback is being triggered!');

    // Process the received key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the received key exchange request
        keyExchangeProvider.processReceivedKeyExchangeRequest(data);
        print('🔌 Main: ✅ Key exchange request processed by provider');
        print(
            '🔌 Main: 📊 Provider received requests count: ${keyExchangeProvider.receivedRequests.length}');

        // Force refresh the provider to ensure UI updates
        await keyExchangeProvider.refresh();
        print('🔌 Main: ✅ Provider refreshed after processing request');

        // Update badge counts in real-time ONLY if user is not on K.Exchange screen
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Check if user is currently on K.Exchange screen (index 1)
        final isOnKeyExchangeScreen = _currentScreenIndex == 1;

        // Always update badge count using context-aware method
        // The indicator service will handle screen context internally
        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        print('🔌 Main: 🔥 Updating badge count to: $pendingCount');
        print('🔌 Main: 🔥 Current screen index: $_currentScreenIndex');

        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        print(
            '🔌 Main: ✅ Badge count updated for new key exchange request using context-aware method');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process key exchange request: $e');
      }
    });
  });

  socketService.setOnKeyExchangeDeclined((data) {
    print('🔌 Main: Key exchange declined from socket: $data');

    // Process the declined key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the declined key exchange request
        await keyExchangeProvider.handleKeyExchangeDeclined(data);
        print('🔌 Main: ✅ Key exchange decline processed by provider');

        // Update badge counts
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after decline
        final keyExchangeProvider2 = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // For decline, we need to update the sent requests count (decline affects sent requests)
        final pendingSentCount = keyExchangeProvider2.sentRequests
            .where((req) => req.status == 'pending' || req.status == 'sent')
            .length;

        // Also update received requests count
        final pendingReceivedCount = keyExchangeProvider2.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        // Update badge with the total pending count
        final totalPendingCount = pendingSentCount + pendingReceivedCount;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: totalPendingCount);
        print(
            '🔌 Main: ✅ Badge count updated for key exchange decline (sent: $pendingSentCount, received: $pendingReceivedCount, total: $totalPendingCount)');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process key exchange decline: $e');
      }
    });
  });

  socketService.setOnKeyExchangeAccepted((data) {
    print('🔌 Main: Key exchange accepted from socket: $data');

    // Process the accepted key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the accepted key exchange request
        await keyExchangeProvider.handleKeyExchangeAccepted(data);
        print('🔌 Main: ✅ Key exchange acceptance processed by provider');

        // Update badge counts
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after acceptance
        final keyExchangeProvider2 = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // For acceptance, we need to update the sent requests count (acceptance affects sent requests)
        final pendingSentCount = keyExchangeProvider2.sentRequests
            .where((req) => req.status == 'pending' || req.status == 'sent')
            .length;

        // Also update received requests count
        final pendingReceivedCount = keyExchangeProvider2.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        // Update badge with the total pending count
        final totalPendingCount = pendingSentCount + pendingReceivedCount;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: totalPendingCount);
        print(
            '🔌 Main: ✅ Badge count updated after key exchange accepted using context-aware method');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process key exchange acceptance: $e');
      }
    });
  });

  // Handle key exchange response (when someone accepts/declines our request)
  socketService.setOnKeyExchangeResponse((data) {
    print('🔌 Main: 🔍🔍🔍 KEY EXCHANGE RESPONSE RECEIVED!');
    print('🔌 Main: 🔍🔍🔍 Full data: $data');
    print('🔌 Main: 🔍🔍🔍 Data type: ${data.runtimeType}');
    print('🔌 Main: 🔍🔍🔍 Data keys: ${data.keys.toList()}');

    // Process the key exchange response using KeyExchangeService
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        print('🔌 Main: 🚀 Processing key exchange response...');
        await KeyExchangeService.instance.processKeyExchangeResponse(data);
        print('🔌 Main: ✅ Key exchange response processed successfully');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process key exchange response: $e');
        print('🔌 Main: ❌ Stack trace: ${StackTrace.current}');
      }
    });
  });

  // CRITICAL: Verify the callback was set up correctly
  print('🔌 Main: 🔍 Verifying onKeyExchangeResponse callback after setup...');
  if (socketService.onKeyExchangeResponse != null) {
    print('🔌 Main: ✅ onKeyExchangeResponse callback successfully configured');
  } else {
    print(
        '🔌 Main: ❌ CRITICAL ERROR: onKeyExchangeResponse callback failed to set up!');
    // Try to set it up again as a fallback
    print('🔌 Main: 🔄 Attempting fallback callback setup...');
    socketService.setOnKeyExchangeResponse((data) {
      print('🔌 Main: 🚨 FALLBACK: Key exchange response received: $data');
      // Process with KeyExchangeService
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await KeyExchangeService.instance.processKeyExchangeResponse(data);
          print('🔌 Main: ✅ Fallback callback processed successfully');
        } catch (e) {
          print('🔌 Main: ❌ Fallback callback failed: $e');
        }
      });
    });
    print('🔌 Main: 🔄 Fallback callback setup completed');
  }

  // CRITICAL: Check all callback statuses for debugging
  print('🔌 Main: 🔍 Checking all socket callback statuses...');
  final callbackStatus = socketService.getCallbackStatus();
  callbackStatus.forEach((callbackName, value) {
    // Handle both boolean and string values safely
    final isSet = value == true || (value is String && value.isNotEmpty);
    final status = isSet ? '✅ SET' : '❌ NULL';
    print('🔌 Main: $status - $callbackName');
  });
  print('🔌 Main: 🔍 Callback status check completed');

  // CRITICAL: Handle user data exchange to complete key exchange flow
  socketService.setOnUserDataExchange((data) {
    print('🔑 Main: User data exchange received from socket: $data');
    print('🔑 Main: 🔍 Data type: ${data.runtimeType}');
    print('🔑 Main: 🔍 Data keys: ${data.keys.toList()}');

    // Process the user data exchange and create conversation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        print('🔑 Main: 🚀 Starting to process user data exchange...');

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
          print('🔑 Main: ✅ User data exchange processed successfully');
        } else {
          print(
              '🔑 Main: ❌ Invalid user data exchange data: senderId=$senderId, encryptedData=${encryptedData != null}');
        }

        // CRITICAL: Also update the conversation display name in ChatListProvider
        try {
          final senderId = data['senderId']?.toString();
          final displayName = data['displayName']?.toString() ?? 'Unknown User';

          if (senderId != null) {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            // Update the conversation display name
            chatListProvider.handleUserDataExchange(senderId, displayName);
            print(
                '🔑 Main: ✅ Conversation display name updated via ChatListProvider');
          }
        } catch (e) {
          print(
              '🔑 Main: ⚠️ Warning: Failed to update conversation display name: $e');
        }
      } catch (e) {
        print('🔑 Main: ❌ Failed to process user data exchange: $e');
        print('🔑 Main: ❌ Stack trace: ${StackTrace.current}');
      }
    });
  });

  // Handle conversation creation events from other users
  // REMOVED: This is now handled in ChatListProvider to avoid duplicate callbacks
  // socketService.setOnConversationCreated((data) {
  //   print('💬 Main: Conversation created event received from socket: $data');

  //   // Process the conversation creation with requester's user data
  //   WidgetsBinding.instance.addPostFrameCallback((_) async {
  //     try {
  //       // This will handle the conversation creation on the acceptor's side
  //       // when they receive the conversation:created event with requester's user data
  //       await KeyExchangeService.instance.handleConversationCreated(data);
  //       print('💬 Main: ✅ Conversation created event processed successfully');
  //     } catch (e) {
  //       print('💬 Main: ❌ Failed to process conversation created event: $e');
  //     }
  //   });
  // });

  // CRITICAL: Connect KeyExchangeService with ChatListProvider for real-time UI updates
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      KeyExchangeService.instance.setOnConversationCreated((conversation) {
        print('🔑 Main: 🚀 Conversation created, updating UI...');

        // Create notification item for conversation created
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final notificationService = LocalNotificationItemsService();
            await notificationService.createConversationCreatedNotification(
              conversationId: conversation.id,
              participantName: conversation.displayName ?? 'Unknown User',
              participantId: conversation.participant2Id,
            );
            print('🔑 Main: ✅ Conversation created notification item created');
          } catch (e) {
            print('🔑 Main: ❌ Failed to create conversation notification: $e');
          }
        });

        // Show push notification for conversation created
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final localNotificationBadgeService =
                LocalNotificationBadgeService();
            await localNotificationBadgeService.showKerNotification(
              title: 'New Conversation',
              body:
                  'You can now chat with ${conversation.displayName ?? 'Unknown User'}',
              type: 'conversation_created',
              payload: {
                'type': 'conversation_created',
                'conversationId': conversation.id,
                'participantName': conversation.displayName ?? 'Unknown User',
                'participantId': conversation.participant2Id,
                'timestamp': DateTime.now().toIso8601String(),
              },
            );
            print('🔑 Main: ✅ Conversation created push notification sent');
          } catch (e) {
            print(
                '🔑 Main: ❌ Failed to send conversation push notification: $e');
          }
        });

        // Update the ChatListProvider to refresh the UI
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            // Add the new conversation to the provider
            chatListProvider.addConversation(conversation);
            print(
                '🔑 Main: ✅ Conversation added to ChatListProvider, UI will update');
          } catch (e) {
            print('🔑 Main: ❌ Failed to update ChatListProvider: $e');
          }
        });
      });

      // CRITICAL: Connect user data exchange to update conversation display names
      // This is now handled directly in the socket service callback to avoid conflicts
      print(
          '🔑 Main: ℹ️ User data exchange callback handled by socket service directly');

      print('🔑 Main: ✅ KeyExchangeService conversation callback connected');
    } catch (e) {
      print('🔑 Main: ❌ Failed to connect KeyExchangeService callback: $e');
    }
  });

  // Handle message acknowledgment events
  socketService.setOnMessageAcked((messageId) {
    print('✅ Main: Message acknowledged: $messageId');

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for acknowledgment
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.sent,
          timestamp: DateTime.now(),
        );

        // Update the message status in the provider
        chatListProvider.processMessageStatusUpdate(statusUpdate);
        print('🔌 Main: ✅ Message status updated in ChatListProvider');
      } catch (e) {
        print('🔌 Main: ❌ Failed to update message status: $e');
      }
    });
  });

  // Handle key exchange revoked events
  socketService.setOnKeyExchangeRevoked((data) {
    print('🔑 Main: Key exchange revoked event received: $data');

    // Update badge counts for revoked requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after revocation
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        print(
            '🔌 Main: ✅ Badge count updated after key exchange revoked using context-aware method');
      } catch (e) {
        print('🔌 Main: ❌ Failed to update badge count after revoke: $e');
      }
    });
  });

  // Handle user deleted events
  socketService.setOnUserDeleted((data) {
    print('🗑️ Main: User deleted event received: $data');

    // Handle user deletion cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        print('🔌 Main: ✅ User deletion event processed');
        // Note: Conversation cleanup will be handled by the socket service
        // when it receives the user:deleted event
      } catch (e) {
        print('🔌 Main: ❌ Failed to handle user deletion: $e');
      }
    });
  });

  // Handle conversation created events from other users
  socketService.setOnConversationCreated((data) {
    print('💬 Main: Conversation created event received from socket: $data');

    // Process the conversation creation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await KeyExchangeService.instance.handleConversationCreated(data);
        print('💬 Main: ✅ Conversation created event processed successfully');
      } catch (e) {
        print('💬 Main: ❌ Failed to process conversation created event: $e');
      }
    });
  });

  // Handle message delivery status events
  socketService.setOnMessageDelivered((messageId, fromUserId, toUserId) {
    print(
        '✅ Main: Message delivered: $messageId from $fromUserId to $toUserId');

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for delivery
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.delivered,
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        // Use enhanced method with context for better conversation lookup
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate);
        print(
            '✅ Main: Message delivery status processed successfully with enhanced context');
      } catch (e) {
        print('❌ Main: Failed to process message delivery status: $e');
      }
    });
  });

  // Handle message read status events
  socketService.setOnMessageRead((messageId, fromUserId, toUserId) {
    print('👁️ Main: Message read: $messageId from $fromUserId to $toUserId');

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for read status
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.read,
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        // Use enhanced method with context for better conversation lookup
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate);
        print(
            '👁️ Main: Message read status processed successfully with enhanced context');
      } catch (e) {
        print('❌ Main: Failed to process message read status: $e');
      }
    });
  });

  // 🆕 ADD THIS: Handle queued message events
  socketService.setOnMessageQueued((messageId, toUserId, fromUserId) {
    print('📬 Main: Message queued: $messageId from $fromUserId to $toUserId');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for queued status
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status
              .MessageDeliveryStatus.sent, // Keep as sent until delivered
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate);
        print('📬 Main: ✅ Queued message status processed successfully');
      } catch (e) {
        print('📬 Main: ❌ Failed to process queued message status: $e');
      }
    });
  });

  // Handle key exchange revocation events
  socketService.setOnKeyExchangeRevoked((data) {
    print('🔑 Main: Key exchange revoked: $data');

    // Update badge counts when key exchange is revoked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Update counts using context-aware method
        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        print(
            '🔑 Main: ✅ Badge count updated after key exchange revoked using context-aware method');
      } catch (e) {
        print('🔑 Main: ❌ Failed to update badge count after revocation: $e');
      }
    });
  });

  // Handle user deletion events
  socketService.setOnUserDeleted((data) {
    print('🗑️ Main: User deleted event received: $data');

    // Handle user deletion - this might involve cleaning up local data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // This could involve:
        // 1. Removing conversations with the deleted user
        // 2. Cleaning up any cached data
        // 3. Updating UI to reflect the deletion

        print('🗑️ Main: User deletion event processed successfully');
      } catch (e) {
        print('❌ Main: Failed to process user deletion event: $e');
      }
    });
  });

  // Handle session registration confirmation
  socketService.setOnSessionRegistered((data) {
    print('🔌 Main: ✅ Session registered: ${data['sessionId']}');

    // Initialize presence management system for the new session
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final presenceManager = Provider.of<PresenceManager>(
            navigatorKey.currentContext!,
            listen: false);

        // Set up presence system for the new session
        presenceManager.onSessionRegistered();

        // Create welcome notification for the new user
        try {
          final sessionId = data['sessionId'] as String?;
          if (sessionId != null) {
            final notificationService = LocalNotificationItemsService();
            await notificationService.createWelcomeNotification(sessionId);
            print(
                '🔌 Main: ✅ Welcome notification created for new user: $sessionId');
          }
        } catch (e) {
          print('🔌 Main: ⚠️ Failed to create welcome notification: $e');
        }

        print('🔌 Main: ✅ Presence system initialized for new session');
      } catch (e) {
        print('🔌 Main: ⚠️ Failed to initialize presence system: $e');
      }
    });
  });
}

/// Parse message status string to MessageDeliveryStatus enum
msg_status.MessageDeliveryStatus _parseMessageStatus(String status) {
  switch (status.toLowerCase()) {
    case 'sending':
      return msg_status.MessageDeliveryStatus.pending;
    case 'sent':
      return msg_status.MessageDeliveryStatus.sent;
    case 'delivered':
      return msg_status.MessageDeliveryStatus.delivered;
    case 'read':
      return msg_status.MessageDeliveryStatus.read;
    case 'failed':
      return msg_status.MessageDeliveryStatus.failed;
    case 'deleted':
      return msg_status.MessageDeliveryStatus.failed; // Map deleted to failed
    default:
      return msg_status.MessageDeliveryStatus.sent; // Default to sent
  }
}

class SeChatApp extends StatelessWidget {
  const SeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Attach navigator key for global UI access
    UIService().attachNavigatorKey(navigatorKey);

    // Set navigator key for notification deep linking
    // Navigator key is set globally, no need for NotificationManagerService

    return AppLifecycleHandler(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'SeChat',
        theme: ThemeData(
          colorScheme: ColorScheme.dark(
            brightness: Brightness.dark,
            primary: const Color(0xFFFF6B35), // Orange from designs
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFF2C2C2C), // Dark grey containers
            onPrimaryContainer: Colors.white,
            secondary: const Color(0xFF666666), // Medium grey
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFF1A1A1A), // Very dark grey
            onSecondaryContainer: Colors.white,
            surface: const Color(0xFF1E1E1E), // Dark surface
            onSurface: Colors.white,
            surfaceContainerHighest:
                const Color(0xFF2C2C2C), // Card backgrounds
            onSurfaceVariant: const Color(0xFFCCCCCC), // Text on cards
            outline: const Color(0xFF404040), // Borders
            error: const Color(0xFFFF5555),
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
          fontFamily: 'System',
        ),
        home: const AuthChecker(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Generate consistent conversation ID that both users will have
/// This ensures messages appear in the same conversation for both users
/// Updated to match server's new consistent ID format
String _generateConsistentConversationId(String user1Id, String user2Id) {
  return ConversationIdGenerator.generateConsistentConversationId(
      user1Id, user2Id);
}

/// Ensure conversation exists before saving message
Future<void> _ensureConversationExists(
    String conversationId, String senderId, String senderName) async {
  try {
    // Get ChatListProvider to create/update conversation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create conversation if it doesn't exist
        await chatListProvider.ensureConversationExists(
            conversationId, senderId, senderName);
        print('🔌 Main: ✅ Conversation ensured: $conversationId');
      } catch (e) {
        print('🔌 Main: ❌ Failed to ensure conversation: $e');
      }
    });
  } catch (e) {
    print('🔌 Main: ❌ Error in _ensureConversationExists: $e');
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    // Remove native splash screen (only on mobile)
    if (!kIsWeb) {
      FlutterNativeSplash.remove();
    }

    // Small delay for smooth transition
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    try {
      final seSessionService = SeSessionService();
      final session = await seSessionService.loadSession();

      print('🔍 AuthChecker: Session loaded: ${session != null}');
      if (session != null) {
        print('🔍 AuthChecker: Session ID: ${session.sessionId}');
        print('🔍 AuthChecker: Display Name: ${session.displayName}');
        print(
            '🔍 AuthChecker: Has encrypted private key: ${session.encryptedPrivateKey.isNotEmpty}');
      }

      if (session != null) {
        // Session exists, check if user is currently logged in
        final isLoggedIn = await seSessionService.isUserLoggedIn();
        print('🔍 AuthChecker: Is user logged in: $isLoggedIn');

        if (isLoggedIn) {
          // User is logged in, initialize socket services and go to main screen
          print(
              '🔍 AuthChecker: User is logged in, initializing socket services...');

          // Initialize socket connection
          final socketService = SeSocketService.instance;
          await socketService.connect(session!.sessionId);

          print('🔍 AuthChecker: ✅ Socket service initialized successfully');

          print('🔍 AuthChecker: User is logged in, navigating to main screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainNavScreen()),
          );
        } else {
          // Session exists but user needs to login, go to login screen
          print(
              '🔍 AuthChecker: Session exists but user needs login, navigating to login screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        // No session exists, go to welcome screen
        print('🔍 AuthChecker: No session found, navigating to welcome screen');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
    } catch (e) {
      // Handle any errors by showing welcome screen
      print('🔍 AuthChecker: Error during auth check: $e');

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
