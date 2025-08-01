import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// import 'features/search/providers/search_provider.dart'; // Removed search functionality
// import 'features/chat/providers/chat_provider.dart'; // Temporarily disabled
import 'features/invitations/providers/invitation_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'shared/widgets/app_lifecycle_handler.dart';
import 'core/services/simple_notification_service.dart';
import 'core/services/se_session_service.dart';
import 'core/services/se_shared_preference_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  print('🔔 Main: Starting SeChat application...');
  print(
      '🔔 Main: Platform: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Web'}');

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await Hive.initFlutter();

  // Initialize LocalStorageService
  await LocalStorageService.instance.initialize();

  // Initialize SeSharedPreferenceService
  await SeSharedPreferenceService().initialize();

  // Initialize SeSessionService
  print('🔔 Main: Initializing SeSessionService...');
  final seSessionService = SeSessionService();

  // Check for persistent session
  final hasPersistentSession = await seSessionService.hasPersistentSession();
  print('🔔 Main: Has persistent session: $hasPersistentSession');

  // Validate session persistence
  final persistenceValidation =
      await seSessionService.validateSessionPersistence();
  print('🔔 Main: Session persistence validation: $persistenceValidation');

  // Load session and attempt backup restore if needed
  await seSessionService.loadSession();

  // If no current session but backup exists, try to restore
  if (seSessionService.currentSession == null) {
    final restored = await seSessionService.restoreSessionFromBackup();
    if (restored) {
      print('🔔 Main: ✅ Session restored from backup');
    }
  }

  // Create backup of current session if it exists
  if (seSessionService.currentSession != null) {
    await seSessionService.backupSession();
    print('🔔 Main: ✅ Session backup created');
  }

  print('🔔 Main: ✅ SeSessionService initialized');

  // Initialize notification services with SeSessionService
  if (seSessionService.currentSession != null) {
    print(
        '🔔 Main: Initializing notification services with existing session...');
    await seSessionService.initializeNotificationServices();
  } else {
    // Initialize simple notification service (without session ID - will be set later)
    await SimpleNotificationService.instance.initialize();
  }

  // Set up notification callbacks
  _setupSimpleNotifications();

  // Set up provider instances for notification service
  _setupNotificationProviders();

  // Set up method channel for native communication
  _setupMethodChannels();

  // Add a longer delay to ensure native platforms are ready
  print('🔔 Main: Waiting for native platforms to initialize...');
  await Future.delayed(const Duration(seconds: 3));
  print('🔔 Main: Native platform initialization delay complete');

  // All real-time features now use silent notifications via AirNotifier

  runApp(
    MultiProvider(
      providers: [
        // ChangeNotifierProvider(create: (_) => SearchProvider()), // Removed search functionality
        // ChangeNotifierProvider(create: (_) => ChatProvider()), // Temporarily disabled
        ChangeNotifierProvider(create: (_) => InvitationProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
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
  notificationService
      .setOnInvitationReceived((senderId, senderName, invitationId) async {
    print('🔔 Main: Invitation received from $senderName ($senderId)');

    // Force refresh of invitations list by triggering a rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // This will trigger a rebuild of the invitations screen
        print('🔔 Main: ✅ Triggering invitations screen refresh');
      } catch (e) {
        print('🔔 Main: Error refreshing invitations screen: $e');
      }
    });
  });

  notificationService.setOnInvitationResponse(
      (responderId, responderName, status, {conversationGuid}) async {
    print(
        '🔔 Main: Invitation response from $responderName ($responderId): $status');
    if (conversationGuid != null) {
      print('🔔 Main: Conversation GUID provided: $conversationGuid');
    }

    // The invitation response will be handled by the SimpleNotificationService
    // which will show a local notification and trigger UI updates
    // The InvitationProvider will be notified through the notification system
    print('🔔 Main: ✅ Invitation response notification processed');
  });

  notificationService.setOnMessageReceived((senderId, senderName, message) {
    print('🔔 Main: Message received from $senderName ($senderId)');
    // The notification will be handled by the SimpleNotificationService
    // which will show a local notification and trigger UI updates
    print('🔔 Main: ✅ Message notification processed');
  });

  notificationService.setOnTypingIndicator((senderId, isTyping) {
    print('🔔 Main: Typing indicator from $senderId: $isTyping');
    // The notification will be handled by the SimpleNotificationService
    // which will trigger UI updates
    print('🔔 Main: ✅ Typing indicator processed');
  });

  print('🔔 Main: Simple notification service setup complete');
}

// Set up provider instances for notification service
void _setupNotificationProviders() {
  print('🔔 Main: Setting up notification providers...');

  // Note: Provider instances will be set after the app is built
  // This will be handled in the widget tree where providers are available
  print('🔔 Main: Notification providers setup complete');
}

// Set up method channels and event channels for native communication
void _setupMethodChannels() {
  const MethodChannel channel = MethodChannel('push_notifications');
  const EventChannel eventChannel = EventChannel('push_notifications_events');

  // Listen to real-time notifications via EventChannel
  eventChannel.receiveBroadcastStream().listen((dynamic event) {
    print('🔔 Main: Received notification via EventChannel: $event');
    _handleNotificationEvent(event);
  }, onError: (dynamic error) {
    print('🔔 Main: EventChannel error: $error');
  });

  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onDeviceTokenReceived':
        final String deviceToken = call.arguments as String;
        print('🔔 Main: Received device token from native: $deviceToken');

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
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
