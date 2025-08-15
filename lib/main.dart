import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// import 'features/search/providers/search_provider.dart'; // Removed search functionality
// import 'features/chat/providers/chat_provider.dart'; // Temporarily disabled
import 'features/key_exchange/providers/key_exchange_request_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
import 'features/chat/providers/chat_list_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'shared/widgets/app_lifecycle_handler.dart';
import 'shared/widgets/notification_permission_dialog.dart';
import 'core/services/simple_notification_service.dart';
import 'core/services/se_session_service.dart';
import 'core/services/se_shared_preference_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';
import 'features/chat/services/message_storage_service.dart';
import 'features/chat/providers/session_chat_provider.dart';

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

  // Initialize notification services
  if (seSessionService.currentSession != null) {
    await seSessionService.initializeNotificationServices();
  } else {
    await SimpleNotificationService.instance.initialize();
  }

  // Set up notification callbacks
  _setupSimpleNotifications();

  // Set up method channel for native communication
  _setupMethodChannels();

  // All real-time features now use silent notifications via AirNotifier

  runApp(
    MultiProvider(
      providers: [
        // ChangeNotifierProvider(create: (_) => SearchProvider()), // Removed search functionality
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
            create: (_) => KeyExchangeRequestProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ChatListProvider()..initialize()),
        // ChangeNotifierProvider(create: (_) => AuthProvider()), // Temporarily disabled
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
        ChangeNotifierProvider(create: (_) => LocalStorageService.instance),
      ],
      child: const SeChatApp(),
    ),
  );
}

// Simple notification setup
void _setupSimpleNotifications() {
  final notificationService = SimpleNotificationService.instance;

  // Set up notification callbacks
  notificationService.setOnMessageReceived((senderId, senderName, message) {
    print('🔔 Main: Message received from $senderName: $message');

    // Route message to ChatListProvider to update UI
    try {
      // We'll need to access ChatListProvider through the Provider system
      // For now, we'll handle this in the notification service itself
      print('🔔 Main: ✅ Message received notification handled');
    } catch (e) {
      print('🔔 Main: ❌ Failed to handle message received: $e');
    }
  });

  notificationService.setOnTypingIndicator((senderId, isTyping) {
    print('🔔 Main: Typing indicator from $senderId: $isTyping');

    // Typing indicator is already handled by SimpleNotificationService
    print('🔔 Main: ✅ Typing indicator handled by notification service');
  });

  // Set up message status update callback for read receipts
  notificationService.setOnMessageStatusUpdate((senderId, messageId, status) {
    print(
        '🔔 Main: Message status update: $messageId -> $status from $senderId');

    // Message status updates are already handled by SimpleNotificationService
    print('🔔 Main: ✅ Message status update handled by notification service');
  });
}

// Set up provider instances for notification service
void _setupNotificationProviders(BuildContext context) {
  // The NotificationProvider is already set up in its constructor
  // No additional setup needed here
  print('🔔 Main: ✅ NotificationProvider already initialized in constructor');
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
          await SimpleNotificationService.instance
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

          // Handle the notification
          await SimpleNotificationService.instance
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
    final notificationService = SimpleNotificationService.instance;
    for (final conversation in conversations) {
      final otherParticipantId =
          conversation.getOtherParticipantId(currentUserId);
      if (otherParticipantId != null) {
        await notificationService.sendOnlineStatusUpdate(
            otherParticipantId, isOnline);
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

    // Handle different argument types safely
    Map<String, dynamic> notificationData;
    if (event is Map) {
      // Convert from Map<dynamic, dynamic> to Map<String, dynamic> safely
      final dynamicMap = event as Map;
      notificationData = <String, dynamic>{};
      dynamicMap.forEach((key, value) {
        if (key is String) {
          notificationData[key] = value;
        }
      });
    } else {
      print('🔔 Main: Event is not a Map: ${event.runtimeType}');
      return;
    }

    print('🔔 Main: Processed notification event data: $notificationData');

    // Handle the notification
    await SimpleNotificationService.instance
        .handleNotification(notificationData);
  } catch (e) {
    print('🔔 Main: Error handling notification event: $e');
    print('🔔 Main: Error stack trace: ${StackTrace.current}');
  }
}

class SeChatApp extends StatelessWidget {
  const SeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleHandler(
      child: MaterialApp(
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
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
