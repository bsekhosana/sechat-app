import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// import feature providers
import 'features/key_exchange/providers/key_exchange_request_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
import 'features/chat/providers/optimized_chat_list_provider.dart';
import 'features/chat/providers/optimized_session_chat_provider.dart';

// import screens
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';

// import widgets
import 'shared/widgets/app_lifecycle_handler.dart';
import 'shared/widgets/notification_permission_dialog.dart';

// import services
import 'core/services/secure_notification_service.dart';
import 'core/services/optimized_notification_service.dart';
import 'core/services/airnotifier_service.dart';
import 'core/services/se_session_service.dart';
import 'core/services/se_shared_preference_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';
import 'features/chat/services/message_storage_service.dart';

// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  print('🔔 Main: Starting SeChat application...');
  print(
      '🔔 Main: Platform: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Web'}');

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // Hive initialization removed - using SharedPreferences only

  // Initialize core services in parallel for faster startup
  await Future.wait([
    LocalStorageService.instance.initialize(),
    SeSharedPreferenceService().initialize(),
    MessageStorageService.instance.initialize(),
  ]);

  // Initialize SeSessionService
  final seSessionService = SeSessionService();
  await seSessionService.loadSession();

  // Initialize optimized notification service
  final optimizedNotificationService = OptimizedNotificationService();

  // Initialize notification services
  if (seSessionService.currentSession != null) {
    await seSessionService.initializeNotificationServices();
  }

  // Set up notification callbacks for the optimized service
  _setupOptimizedNotificationCallbacks(optimizedNotificationService);

  // Set up notification callbacks
  _setupSimpleNotifications();

  // Set up method channel for native communication
  _setupMethodChannels();

  // All real-time features now use silent notifications via AirNotifier

  runApp(
    MultiProvider(
      providers: [
        // ChangeNotifierProvider(create: (_) => SearchProvider()), // Removed search functionality
        ChangeNotifierProvider(create: (_) => OptimizedSessionChatProvider()),
        ChangeNotifierProvider(create: (_) => KeyExchangeRequestProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) {
          final provider = OptimizedChatListProvider();
          // Initialize in the next frame to avoid blocking the UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.initialize();
            // Set up the conversation created callback
            OptimizedChatListProvider.setConversationCreatedCallback(() {
              provider.refresh();
            });
          });
          return provider;
        }),
        // ChangeNotifierProvider(create: (_) => AuthProvider()), // Temporarily disabled
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
        ChangeNotifierProvider(create: (_) => LocalStorageService.instance),
      ],
      child: const SeChatApp(),
    ),
  );
}

// Set up optimized notification callbacks
void _setupOptimizedNotificationCallbacks(
    OptimizedNotificationService service) {
  // Set up callbacks for the optimized notification service
  service.setOnMessageReceived(
      (senderId, senderName, message, conversationId, messageId) {
    print(
        '🔔 Main: Message received callback from optimized service: $senderName: $message');
  });

  service.setOnTypingIndicator((senderId, isTyping) {
    print(
        '🔔 Main: Typing indicator from optimized service: $senderId: $isTyping');
  });

  service.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
    print(
        '🔔 Main: Online status update from optimized service: $senderId: $isOnline');
  });

  service.setOnMessageStatusUpdate((senderId, messageId, status) {
    print(
        '🔔 Main: Message status update from optimized service: $messageId -> $status');
  });

  // Set up key exchange callbacks
  service.setOnKeyExchangeRequestReceived((data) {
    print(
        '🔔 Main: Key exchange request received from optimized service: $data');
    // This will be connected to the KeyExchangeRequestProvider in main_nav_screen
  });

  service.setOnKeyExchangeAccepted((data) {
    print('🔔 Main: Key exchange accepted from optimized service: $data');
  });

  service.setOnKeyExchangeDeclined((data) {
    print('🔔 Main: Key exchange declined from optimized service: $data');
  });

  service.setOnConversationCreated((conversation) {
    print(
        '🔔 Main: Conversation created from optimized service: ${conversation.id}');

    // Notify the OptimizedChatListProvider to refresh its data
    OptimizedChatListProvider.notifyConversationCreated();
    print(
        '🔔 Main: ✅ Notified OptimizedChatListProvider to refresh conversations');
  });
}

// Simple notification setup
void _setupSimpleNotifications() {
  final notificationService = OptimizedNotificationService();

  // Set up notification callbacks
  // NOTE: Message handling is now done directly in SecureNotificationService
  // to avoid duplicate processing. This callback is kept for future use if needed.
  notificationService.setOnMessageReceived(
      (senderId, senderName, message, conversationId, messageId) {
    print(
        '🔔 Main: Message received callback (handled by SecureNotificationService)');
    // Message is already handled by SecureNotificationService
    // No need to route again to avoid duplication
  });

  notificationService.setOnTypingIndicator((senderId, isTyping) {
    print('🔔 Main: Typing indicator from $senderId: $isTyping');

    // Typing indicator is already handled by SecureNotificationService
    print('🔔 Main: ✅ Typing indicator handled by notification service');
  });

  // Set up message status update callback for read receipts
  notificationService.setOnMessageStatusUpdate((senderId, messageId, status) {
    print(
        '🔔 Main: Message status update: $messageId -> $status from $senderId');

    // Message status updates are already handled by SecureNotificationService
    print('🔔 Main: ✅ Message status update handled by notification service');
  });
}

// Set up method channels and event channels for native communication
void _setupMethodChannels() {
  const MethodChannel channel = MethodChannel('push_notifications');
  const EventChannel eventChannel = EventChannel('push_notifications_events');

  // App lifecycle handling is done by AppLifecycleHandler widget
  // Online status updates will be sent when the app goes to background/foreground

  // Listen to real-time notifications via EventChannel
  eventChannel.receiveBroadcastStream().listen((dynamic event) {
    _handleNotificationEvent(event);
  }, onError: (dynamic error) {
    print('🔔 Main: EventChannel error: $error');
  });

  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onDeviceTokenReceived':
        final String deviceToken = call.arguments as String;

        // Handle device token received from native platform
        try {
          // For now, we'll use the secure notification service for device token handling
          // as the optimized service doesn't have this method yet
          await SecureNotificationService.instance
              .handleDeviceTokenReceived(deviceToken);
          print('🔔 Main: ✅ Device token handled successfully');
        } catch (e) {
          print('🔔 Main: Error handling device token: $e');
        }
        return null;

      case 'onRemoteNotificationReceived':
        print(
            '🔔 Main: Received remote notification call with arguments: ${call.arguments}');

        try {
          // Handle different argument types safely
          Map<String, dynamic> notificationData;
          if (call.arguments is Map) {
            // Convert from Map<dynamic, dynamic> to Map<String, dynamic> safely
            final dynamicMap = call.arguments as Map;
            notificationData = <String, dynamic>{};
            dynamicMap.forEach((key, value) {
              if (key is String) {
                notificationData[key] = value;
              }
            });
          } else {
            print(
                '🔔 Main: Arguments is not a Map: ${call.arguments.runtimeType}');
            return null;
          }

          print('🔔 Main: Processed notification data: $notificationData');

          // Handle the notification using optimized service
          await OptimizedNotificationService()
              .handleNotification(notificationData);
        } catch (e) {
          print('🔔 Main: Error handling remote notification: $e');
          print('🔔 Main: Error stack trace: ${StackTrace.current}');
        }
        return null;

      case 'requestDeviceToken':
        print('🔔 Main: Native platform requested device token');
        // This is handled by the native platform automatically
        return null;

      default:
        print('🔔 Main: Unknown method call: ${call.method}');
        return null;
    }
  });

  print('🔔 Main: Method channels setup complete');
}

/// Send online status update to all contacts
Future<void> _sendOnlineStatusUpdate(bool isOnline) async {
  try {
    print('🔔 Main: Sending online status update: $isOnline');

    // Get current user ID
    final sessionService = SeSessionService();
    final currentUserId = sessionService.currentSessionId;

    if (currentUserId == null) {
      print('🔔 Main: ❌ No current session ID available');
      return;
    }

    // Get all conversations to send status updates
    final messageStorageService = MessageStorageService.instance;
    final conversations =
        await messageStorageService.getUserConversations(currentUserId);

    // Send online status update to all participants
    for (final conversation in conversations) {
      final otherParticipantId =
          conversation.getOtherParticipantId(currentUserId);
      if (otherParticipantId != null) {
        // Use AirNotifierService directly for online status updates
        // as the optimized service doesn't have this method yet
        await AirNotifierService.instance.sendOnlineStatusUpdate(
            recipientId: otherParticipantId, isOnline: isOnline);
      }
    }

    print(
        '🔔 Main: ✅ Online status updates sent to ${conversations.length} contacts');
  } catch (e) {
    print('🔔 Main: ❌ Error sending online status updates: $e');
  }
}

// Handle notification events from EventChannel
void _handleNotificationEvent(dynamic event) async {
  try {
    print('🔔 Main: Processing notification event: $event');
    print('🔔 Main: Event type: ${event.runtimeType}');
    print('🔔 Main: Event keys: ${event is Map ? event.keys : 'Not a Map'}');

    // Handle different argument types safely
    Map<String, dynamic> notificationData;
    if (event is Map) {
      // Convert from Map<dynamic, dynamic> to Map<String, dynamic> safely
      notificationData = <String, dynamic>{};
      event.forEach((key, value) {
        if (key is String) {
          notificationData[key] = value;
        }
      });

      // Add debug logging for nested data structures
      if (notificationData.containsKey('data') &&
          notificationData['data'] is Map) {
        final nestedData = notificationData['data'] as Map;
        print('🔔 Main: 🔍 Nested data found: ${nestedData.keys}');
        print('🔔 Main: 🔍 Nested data type: ${nestedData['type']}');
      }
    } else {
      print('🔔 Main: Event is not a Map: ${event.runtimeType}');
      return;
    }

    print('🔔 Main: Processed notification event data: $notificationData');

    // CRITICAL: Add duplicate prevention for EventChannel notifications
    // This prevents the same notification from being processed multiple times
    print(
        '🔔 Main: 🔍 About to generate notification ID for duplicate prevention');
    final notificationId = _generateNotificationId(notificationData);
    print('🔔 Main: 🔍 Generated notification ID: $notificationId');

    if (_processedEventNotifications.contains(notificationId)) {
      print(
          '🔔 Main: ⚠️ Duplicate EventChannel notification detected, skipping: $notificationId');
      return;
    }
    _processedEventNotifications.add(notificationId);
    print(
        '🔔 Main: 🔍 Added notification ID to processed set: $notificationId');

    // Handle the notification using optimized service
    print(
        '🔔 Main: 🔍 About to call OptimizedNotificationService.handleNotification');
    print(
        '🔔 Main: 🔍 Final notification data being passed: $notificationData');
    await OptimizedNotificationService().handleNotification(notificationData);
    print(
        '🔔 Main: 🔍 OptimizedNotificationService.handleNotification completed');
  } catch (e) {
    print('🔔 Main: Error handling notification event: $e');
    print('🔔 Main: Error stack trace: ${StackTrace.current}');
  }
}

// Track processed EventChannel notifications to prevent duplicates
final Set<String> _processedEventNotifications = <String>{};

// Generate unique notification ID for duplicate prevention
String _generateNotificationId(Map<String, dynamic> notificationData) {
  print(
      '🔔 Main: 🔍 _generateNotificationId called with: ${notificationData.keys}');

  // Handle both direct and nested data structures
  String type = 'unknown';
  String messageId = DateTime.now().millisecondsSinceEpoch.toString();
  String senderId = 'unknown';

  if (notificationData['type'] != null) {
    // Direct structure
    type = notificationData['type'] as String? ?? 'unknown';
    messageId = notificationData['messageId'] as String? ??
        notificationData['message_id'] as String? ??
        DateTime.now().millisecondsSinceEpoch.toString();
    senderId = notificationData['senderId'] as String? ??
        notificationData['sender_id'] as String? ??
        'unknown';
    print(
        '🔔 Main: 🔍 Using direct structure - type: $type, messageId: $messageId, senderId: $senderId');
  } else if (notificationData['data'] != null &&
      notificationData['data'] is Map) {
    // Nested structure - handle Map<Object?, Object?> from native platform
    final nestedData = notificationData['data'] as Map;
    print('🔔 Main: 🔍 Found nested data with keys: ${nestedData.keys}');
    type = nestedData['type'] as String? ?? 'unknown';
    messageId = nestedData['messageId'] as String? ??
        nestedData['message_id'] as String? ??
        nestedData['request_id'] as String? ?? // For key exchange notifications
        DateTime.now().millisecondsSinceEpoch.toString();
    senderId = nestedData['senderId'] as String? ??
        nestedData['sender_id'] as String? ??
        nestedData['recipient_id'] as String? ?? // For key exchange accepted
        'unknown';
    print(
        '🔔 Main: 🔍 Using nested structure - type: $type, messageId: $messageId, senderId: $senderId');
  } else {
    print('🔔 Main: 🔍 No type or nested data found, using defaults');
  }

  final result = '${type}_${senderId}_$messageId';
  print('🔔 Main: 🔍 Generated notification ID: $result');
  return result;
}

class SeChatApp extends StatelessWidget {
  const SeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          // User is logged in, initialize notification services and go to main screen
          print(
              '🔍 AuthChecker: User is logged in, initializing notification services...');
          await seSessionService.initializeNotificationServices();

          // Check notification permissions after services are initialized
          print('🔍 AuthChecker: Checking notification permissions...');
          await _checkNotificationPermissions();

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

  /// Check notification permissions and show dialog if needed
  Future<void> _checkNotificationPermissions() async {
    if (!mounted) return;

    try {
      // Small delay to ensure the app is fully loaded
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      // Check and show permission dialog if needed
      await NotificationPermissionHelper.checkAndRequestPermissions(context);
    } catch (e) {
      print('🔍 AuthChecker: Error checking notification permissions: $e');
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
