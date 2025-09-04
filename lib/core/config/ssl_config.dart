import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// SSL Configuration for handling certificate verification
class SSLConfig {
  static bool get _isDevelopment => kDebugMode;
  static bool get _isProduction => !kDebugMode;

  /// Initialize SSL configuration
  static void initialize() {
    if (_isDevelopment) {
      _setupDevelopmentSSL();
    }
  }

  /// Setup SSL for development (bypasses certificate verification)
  static void _setupDevelopmentSSL() {
    HttpOverrides.global = _DevelopmentHttpOverrides();
  }

  /// Setup SSL for production (enforces certificate verification)
  static void _setupProductionSSL() {
    // Production uses default SSL verification
    HttpOverrides.global = null;
  }
}

/// HTTP Overrides for development that bypasses SSL certificate verification
class _DevelopmentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Bypass SSL certificate verification for development
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      Logger.debug(
          '🔒 SSL: Bypassing certificate verification for $host:$port (development mode)');
      return true; // Accept all certificates in development
    };

    return client;
  }
}
