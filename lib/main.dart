import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// Import models for message status updates
import 'features/chat/services/message_status_tracking_service.dart';
import 'features/chat/models/message.dart';

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

// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  print('🔌 Main: Starting SeChat application...');
  print(
      '🔌 Main: Platform: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Web'}');

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

  // Initialize SeSessionService
  final seSessionService = SeSessionService();
  await seSessionService.loadSession();

  // Initialize SeChat socket service
  final socketService = SeSocketService();
  bool socketInitialized = false;

  if (seSessionService.currentSession != null) {
    // Initialize socket connection
    socketInitialized = await socketService.initialize();
    if (socketInitialized) {
      print('🔌 Main: ✅ Socket service initialized successfully');
    } else {
      print('🔌 Main: ❌ Socket service initialization failed');
    }
  }

  // Set up socket callbacks
  _setupSocketCallbacks(socketService);

  // All real-time features now use SeChat socket

  runApp(
    MultiProvider(
      providers: [
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

        // Also notify SessionChatProvider if there's an active chat with this user
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // Check if this is the current recipient in the active chat
          if (sessionChatProvider.currentRecipientId == senderId) {
            // Update the typing state directly
            sessionChatProvider.updateRecipientTypingState(isTyping);
            print(
                '🔌 Main: ✅ Typing indicator forwarded to SessionChatProvider for active chat');
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
    // This will be connected to the KeyExchangeRequestProvider in main_nav_screen
  });

  socketService.setOnKeyExchangeAccepted((data) {
    print('🔌 Main: Key exchange accepted from socket: $data');
    print(
        '🔌 Main: ✅ Key exchange accepted callback triggered - flow should continue automatically');

    // The flow should continue automatically through KeyExchangeService.processKeyExchangeResponse()
    // which will send the initial user data to complete the handshake
  });

  socketService.setOnKeyExchangeDeclined((data) {
    print('🔌 Main: Key exchange declined from socket: $data');
  });

  socketService.setOnConversationCreated((conversation) {
    print('🔌 Main: Conversation created from socket: ${conversation.id}');

    // Notify the ChatListProvider to refresh its data
    // This will be handled by the provider's socket callbacks
    print('🔌 Main: ✅ Conversation created event received from socket');
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

/// Parse message status string to MessageStatus enum
MessageStatus _parseMessageStatus(String status) {
  switch (status.toLowerCase()) {
    case 'sending':
      return MessageStatus.sending;
    case 'sent':
      return MessageStatus.sent;
    case 'delivered':
      return MessageStatus.delivered;
    case 'read':
      return MessageStatus.read;
    case 'failed':
      return MessageStatus.failed;
    case 'deleted':
      return MessageStatus.deleted;
    default:
      return MessageStatus.sent; // Default to sent
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
          final socketService = SeSocketService();
          final socketInitialized = await socketService.initialize();

          if (socketInitialized) {
            print('🔍 AuthChecker: ✅ Socket service initialized successfully');
          } else {
            print('🔍 AuthChecker: ❌ Socket service initialization failed');
          }

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
