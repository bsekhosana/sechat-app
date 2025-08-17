import 'package:flutter/material.dart';
import 'package:sechat_app/features/chat/optimized_chat_feature.dart';

/// Main App for Optimized Chat Testing
/// Entry point to test the complete optimized chat system
void main() {
  runApp(const OptimizedChatApp());
}

/// Optimized Chat App
class OptimizedChatApp extends StatelessWidget {
  const OptimizedChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeChat - Optimized Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const OptimizedChatFeature(),
      debugShowCheckedModeBanner: false,
    );
  }
}
