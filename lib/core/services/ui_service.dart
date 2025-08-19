import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UIService
/// Provides global helpers to show SnackBars from non-widget layers
class UIService {
  UIService._internal();
  static final UIService _instance = UIService._internal();
  factory UIService() => _instance;

  GlobalKey<NavigatorState>? _navigatorKey;

  void attachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  BuildContext? get _context => _navigatorKey?.currentContext;

  void showSnack(String message, {bool isError = false, Duration? duration}) {
    final context = _context;
    if (context == null) return;

    // Trigger vibration and sound for non-error messages
    if (!isError) {
      HapticFeedback.lightImpact();
      // Note: Sound would require additional audio packages
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: isError
            ? Colors.red
            : const Color(0xFFFF6B35), // Orange default, red for errors
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }
}
