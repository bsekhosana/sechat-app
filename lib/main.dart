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
import 'features/notifications/services/notification_manager_service.dart';
import 'realtime/realtime_service_manager.dart';
import 'realtime/realtime_test.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'core/services/indicator_service.dart';
import 'core/services/encryption_service.dart';

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
    NotificationManagerService().initialize(),
  ]);

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

  // Set up socket callbacks
  _setupSocketCallbacks(socketService);

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
      ],
      child: const SeChatApp(),
    ),
  );
}

// Set up socket callbacks
void _setupSocketCallbacks(SeSocketService socketService) {
  // Set up callbacks for the socket service
  socketService.setOnMessageReceived(
      (senderId, senderName, message, conversationId, messageId) {
    print(
        '🔌 Main: Message received callback from socket: $senderName: $message');

    // Update badge counts for new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Count unread conversations
        final unreadCount = chatListProvider.conversations
            .where((conv) => conv.unreadCount > 0)
            .length;

        // Update the indicator service
        indicatorService.updateCounts(unreadChats: unreadCount);
        print('🔌 Main: ✅ Chat badge count updated for new message');
      } catch (e) {
        print('🔌 Main: ❌ Failed to update chat badge count: $e');
      }
    });
  });

  socketService.setOnTypingIndicator((senderId, isTyping) {
    print('🔌 Main: Typing indicator from socket: $senderId: $isTyping');

    // Forward typing indicator to both SessionChatProvider and ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Update ChatListProvider for chat list items
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Find conversation by participant ID and update typing indicator
        chatListProvider.updateTypingIndicatorByParticipant(senderId, isTyping);

        // Also notify SessionChatProvider if there's an active chat
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // FIXED: Forward ALL typing indicators to SessionChatProvider for bidirectional communication
          // This allows both users to see typing indicators from each other
          if (sessionChatProvider.currentRecipientId != null) {
            // If the sender is the current recipient, update their typing state
            if (sessionChatProvider.currentRecipientId == senderId) {
              sessionChatProvider.updateRecipientTypingState(isTyping);
              print(
                  '🔌 Main: ✅ Typing indicator forwarded to SessionChatProvider for current recipient: $senderId');
            } else {
              // If the sender is someone else (e.g., current user typing), still process it
              // This allows the current user to see their own typing state in the UI if needed
              print(
                  '🔌 Main: ℹ️ Typing indicator from different user: $senderId (current recipient: ${sessionChatProvider.currentRecipientId})');
            }

            // CRITICAL: Forward typing indicator to realtime typing service for proper UI updates
            try {
              final realtimeManager = RealtimeServiceManager();
              print(
                  '🔌 Main: 🔍 Realtime manager initialized: ${realtimeManager.isInitialized}');
              print(
                  '🔌 Main: 🔍 Current conversation ID: ${sessionChatProvider.currentConversationId}');

              if (realtimeManager.isInitialized &&
                  sessionChatProvider.currentConversationId != null) {
                final typingService = realtimeManager.typing;
                print(
                    '🔌 Main: 🔍 Typing service available: ${typingService != null}');

                typingService.handleIncomingTypingIndicator(
                  sessionChatProvider.currentConversationId!,
                  senderId,
                  isTyping,
                );
                print(
                    '🔌 Main: ✅ Typing indicator forwarded to realtime typing service');
              } else {
                print(
                    '🔌 Main: ⚠️ Cannot forward to realtime service: manager=${realtimeManager.isInitialized}, conversationId=${sessionChatProvider.currentConversationId}');
              }
            } catch (e) {
              print(
                  '🔌 Main: ❌ Error forwarding to realtime typing service: $e');
            }
          }
        } catch (e) {
          print('🔌 Main: ⚠️ SessionChatProvider not available: $e');
        }

        print('🔌 Main: ✅ Typing indicator forwarded to ChatListProvider');
      } catch (e) {
        print('🔌 Main: ❌ Failed to forward typing indicator: $e');
      }
    });
  });

  socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
    print('🔌 Main: Online status update from socket: $senderId: $isOnline');

    // Update online status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Update the conversation's online status directly
        chatListProvider.updateConversationOnlineStatus(
            senderId, isOnline, lastSeen);
        print(
            '🔌 Main: ✅ Online status update processed: $senderId -> $isOnline');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process online status update: $e');
      }
    });
  });

  socketService.setOnMessageStatusUpdate((senderId, messageId, status) {
    print('🔌 Main: Message status update from socket: $messageId -> $status');

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate and process it
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: _parseMessageStatus(status),
          timestamp: DateTime.now(),
          senderId: senderId,
        );

        chatListProvider.processMessageStatusUpdate(statusUpdate);
        print(
            '🔌 Main: ✅ Message status update processed: $messageId -> $status');
      } catch (e) {
        print('🔌 Main: ❌ Failed to process message status update: $e');
      }
    });
  });

  // Set up key exchange callbacks
  socketService.setOnKeyExchangeRequestReceived((data) {
    print('🔌 Main: Key exchange request received from socket: $data');

    // Update badge counts in real-time ONLY if user is not on K.Exchange screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Check if user is currently on K.Exchange screen (index 1)
        final isOnKeyExchangeScreen = _currentScreenIndex == 1;

        if (!isOnKeyExchangeScreen) {
          // Only update badge if user is not on K.Exchange screen
          final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
              navigatorKey.currentContext!,
              listen: false);

          final pendingCount = keyExchangeProvider.receivedRequests.length;
          indicatorService.updateCounts(pendingKeyExchange: pendingCount);
          print('🔌 Main: ✅ Badge count updated for new key exchange request');
        } else {
          print(
              '🔌 Main: ℹ️ User is on K.Exchange screen, skipping badge update');
        }
      } catch (e) {
        print('🔌 Main: ❌ Failed to update badge count: $e');
      }
    });
  });

  socketService.setOnKeyExchangeAccepted((data) {
    print('🔌 Main: Key exchange accepted from socket: $data');

    // Update badge counts when key exchange is completed ONLY if user is not on K.Exchange screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Check if user is currently on K.Exchange screen (index 1)
        final isOnKeyExchangeScreen = _currentScreenIndex == 1;

        if (!isOnKeyExchangeScreen) {
          // Only update badge if user is not on K.Exchange screen
          final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
              navigatorKey.currentContext!,
              listen: false);

          final pendingCount = keyExchangeProvider.receivedRequests.length;
          indicatorService.updateCounts(pendingKeyExchange: pendingCount);
          print('🔌 Main: ✅ Badge count updated after key exchange accepted');
        } else {
          print(
              '🔌 Main: ℹ️ User is on K.Exchange screen, skipping badge update');
        }
      } catch (e) {
        print('🔌 Main: ❌ Failed to update badge count after acceptance: $e');
      }
    });
  });

  socketService.setOnKeyExchangeDeclined((data) {
    print('🔌 Main: Key exchange declined from socket: $data');

    // Update badge counts when key exchange is declined ONLY if user is not on K.Exchange screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Check if user is currently on K.Exchange screen (index 1)
        final isOnKeyExchangeScreen = _currentScreenIndex == 1;

        if (!isOnKeyExchangeScreen) {
          // Only update badge if user is not on K.Exchange screen
          final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
              navigatorKey.currentContext!,
              listen: false);

          final pendingCount = keyExchangeProvider.receivedRequests.length;
          indicatorService.updateCounts(pendingKeyExchange: pendingCount);
          print('🔌 Main: ✅ Badge count updated after key exchange declined');
        } else {
          print(
              '🔌 Main: ℹ️ User is on K.Exchange screen, skipping badge update');
        }
      } catch (e) {
        print('🔌 Main: ❌ Failed to update badge count after decline: $e');
      }
    });
  });

  // Handle key exchange response (when someone accepts/declines our request)
  socketService.setOnKeyExchangeResponse((data) {
    print('🔌 Main: 🔍🔍🔍 KEY EXCHANGE RESPONSE RECEIVED!');
    print('🔌 Main: 🔍🔍🔍 Full data: $data');
    print('🔌 Main: 🔍🔍🔍 Data type: ${data.runtimeType}');
    print('🔌 Main: 🔍🔍🔍 Data keys: ${data.keys.toList()}');

    // Extract the responder's public key and store it for future encryption
    final responderId =
        data['senderId'] as String? ?? data['sender_id'] as String?;
    final responderPublicKey =
        data['publicKey'] as String? ?? data['sender_public_key'] as String?;
    final response = data['response'] as String? ?? data['status'] as String?;

    print('🔌 Main: 🔍🔍🔍 Extracted values:');
    print('🔌 Main: 🔍🔍🔍 - responderId: $responderId');
    print('🔌 Main: 🔍🔍🔍 - responderPublicKey: $responderPublicKey');
    print('🔌 Main: 🔍🔍🔍 - response: $response');

    if (responderId != null &&
        responderPublicKey != null &&
        response == 'accepted') {
      print('🔌 Main: 🔑 Storing responder public key for: $responderId');

      // Store the responder's public key for future encryption
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await EncryptionService.storeRecipientPublicKey(
              responderId, responderPublicKey);
          print('🔌 Main: ✅ Responder public key stored successfully');
        } catch (e) {
          print('🔌 Main: ❌ Failed to store responder public key: $e');
        }
      });
    } else {
      print(
          '🔌 Main: ⚠️ Invalid key exchange response data: responderId=$responderId, hasPublicKey=${responderPublicKey != null}, response=$response');
    }
  });

  // CRITICAL: Handle user data exchange to complete key exchange flow
  socketService.setOnUserDataExchange((data) {
    print('🔑 Main: User data exchange received from socket: $data');
    print('🔑 Main: 🔍 Data type: ${data.runtimeType}');
    print('🔑 Main: 🔍 Data keys: ${data.keys.toList()}');

    // Process the user data exchange and create conversation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        print('🔑 Main: 🚀 Starting to process user data exchange...');
        await KeyExchangeService.instance.handleUserDataExchange(data);
        print('🔑 Main: ✅ User data exchange processed successfully');
      } catch (e) {
        print('🔑 Main: ❌ Failed to process user data exchange: $e');
        print('🔑 Main: ❌ Stack trace: ${StackTrace.current}');
      }
    });
  });

  // Handle conversation creation events from other users
  socketService.setOnConversationCreated((data) {
    print('💬 Main: Conversation created event received from socket: $data');

    // Process the conversation creation with requester's user data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // This will handle the conversation creation on the acceptor's side
        // when they receive the conversation:created event with requester's user data
        await KeyExchangeService.instance.handleConversationCreated(data);
        print('💬 Main: ✅ Conversation created event processed successfully');
      } catch (e) {
        print('💬 Main: ❌ Failed to process conversation created event: $e');
      }
    });
  });

  // CRITICAL: Connect KeyExchangeService with ChatListProvider for real-time UI updates
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      KeyExchangeService.instance.setOnConversationCreated((conversation) {
        print('🔑 Main: 🚀 Conversation created, updating UI...');

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
          senderId: '', // Will be filled by the provider
        );

        chatListProvider.processMessageStatusUpdate(statusUpdate);
        print('✅ Main: Message acknowledgment processed successfully');
      } catch (e) {
        print('❌ Main: Failed to process message acknowledgment: $e');
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

        chatListProvider.processMessageStatusUpdate(statusUpdate);
        print('✅ Main: Message delivery status processed successfully');
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

        chatListProvider.processMessageStatusUpdate(statusUpdate);
        print('👁️ Main: Message read status processed successfully');
      } catch (e) {
        print('❌ Main: Failed to process message read status: $e');
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

        // Update counts based on current state
        final pendingCount = keyExchangeProvider.receivedRequests.length;
        indicatorService.updateCounts(pendingKeyExchange: pendingCount);
        print('🔑 Main: ✅ Badge count updated after key exchange revoked');
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

  // Set up KeyExchangeService callback for conversation creation
  KeyExchangeService.instance.setOnConversationCreated((conversation) {
    print(
        '🔑 Main: Conversation created via KeyExchangeService: ${conversation.id}');

    // Get the ChatListProvider from the provider and add the new conversation
    // This will be handled in the next frame when the provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);
        chatListProvider.addConversation(conversation);
        print('🔑 Main: ✅ ChatListProvider updated with new conversation');
      } catch (e) {
        print('🔑 Main: ❌ Failed to update ChatListProvider: $e');
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
    NotificationManagerService.setNavigatorKey(navigatorKey);

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
