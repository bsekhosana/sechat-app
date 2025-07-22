import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'features/search/providers/search_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'shared/providers/auth_provider.dart';
import 'features/invitations/providers/invitation_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  await Hive.initFlutter();

  // Initialize LocalStorageService
  await LocalStorageService.instance.initialize();

  // Initialize notification service
  await NotificationService.instance.initialize();

  // Socket.IO service will be initialized after user authentication

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthProvider.instance),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => InvitationProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
        Provider.value(value: SessionService.instance),
        ChangeNotifierProvider(create: (_) => LocalStorageService.instance),
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

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();

    // Wait until AuthProvider is done loading
    while (authProvider.isLoading && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    try {
      if (authProvider.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainNavScreen()),
        );
      } else {
        // User not authenticated, show welcome screen
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
