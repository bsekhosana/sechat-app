import 'package:flutter/foundation.dart';

/// Centralized logging utility for the SeChat app
/// Replaces print statements with a production-safe logging mechanism
class Logger {
  static const String _prefix = 'SeChat';

  /// Log debug messages (only in debug mode)
  static void debug(String message, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix $message');
    }
  }

  /// Log info messages (only in debug mode)
  static void info(String message, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix ℹ️ $message');
    }
  }

  /// Log warning messages (only in debug mode)
  static void warning(String message, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix ⚠️ $message');
    }
  }

  /// Log error messages (only in debug mode)
  static void error(String message, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix ❌ $message');
    }
  }

  /// Log success messages (only in debug mode)
  static void success(String message, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix ✅ $message');
    }
  }

  /// Log with custom emoji (only in debug mode)
  static void log(String message, String emoji, [String? tag]) {
    if (kDebugMode) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      print('$_prefix$tagPrefix $emoji $message');
    }
  }
}
