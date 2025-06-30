import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'shared/providers/auth_provider.dart';
import 'features/search/providers/search_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/auth/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Hive.initFlutter();
  await Hive.openBox('chats');
  await Hive.openBox('messages');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
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
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          primary: const Color(0xFF23272F), // dark grey
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF3A3F47), // medium grey
          onPrimaryContainer: Colors.white,
          secondary: const Color(0xFFB0B3B8), // light grey
          onSecondary: Colors.black,
          secondaryContainer: const Color(0xFFE4E6EB), // very light grey
          onSecondaryContainer: Colors.black,
          background: Colors.white,
          onBackground: const Color(0xFF23272F),
          surface: Colors.white,
          onSurface: const Color(0xFF23272F),
          error: Colors.red,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme(
          brightness: Brightness.dark,
          primary: const Color(0xFF23272F), // dark grey
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF3A3F47), // medium grey
          onPrimaryContainer: Colors.white,
          secondary: const Color(0xFFB0B3B8), // light grey
          onSecondary: Colors.black,
          secondaryContainer: const Color(0xFF23272F), // dark grey
          onSecondaryContainer: Colors.white,
          background: const Color(0xFF181A1B),
          onBackground: Colors.white,
          surface: const Color(0xFF23272F),
          onSurface: Colors.white,
          error: Colors.red.shade400,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF181A1B),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
