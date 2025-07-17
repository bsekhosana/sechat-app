import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart';
import 'shared/providers/auth_provider.dart';
import 'features/search/providers/search_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/invitations/providers/invitation_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'core/services/notification_service.dart';
import 'core/services/socket_service.dart';
import 'core/services/network_service.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await Hive.initFlutter();
  await Hive.openBox('chats');
  await Hive.openBox('messages');
  await Hive.openBox('invitations');

  // Initialize notification service
  await NotificationService.instance.initialize();

  // Initialize Socket.IO service
  await SocketService.instance.connect();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => InvitationProvider()),
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
      ],
      child: const SeChatApp(),
    ),
  );
}

class SeChatApp extends StatelessWidget {
  const SeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
          surfaceContainerHighest: const Color(0xFF2C2C2C), // Card backgrounds
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

    final authProvider = context.read<AuthProvider>();

    // Wait until AuthProvider is done loading
    while (authProvider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainNavScreen()),
      );
    } else {
      // Check if user data exists to determine which screen to show
      final hasUserData = await authProvider.userExistsForDevice();

      if (hasUserData) {
        // User data exists, go directly to login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => const LoginScreen(showBackButton: false)),
        );
      } else {
        // Check if we have device ID but missing username
        final hasDeviceIdButNoUsername =
            await authProvider.hasDeviceIdButNoUsername();

        if (hasDeviceIdButNoUsername) {
          // Try to fetch username from database
          final username = await authProvider.fetchUsernameFromDeviceId();

          if (username != null) {
            // Username fetched successfully, go to login screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) =>
                      LoginScreen(showBackButton: false, username: username)),
            );
          } else {
            // Could not fetch username, show welcome screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            );
          }
        } else {
          // No user data, show welcome screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          );
        }
      }
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
