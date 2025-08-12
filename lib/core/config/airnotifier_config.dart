import 'package:flutter/foundation.dart';

/// AirNotifier configuration for different environments
class AirNotifierConfig {
  // Environment detection
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;

  // Server URLs
  static const String _devServer = 'http://41.76.111.100:1337';
  static const String _prodServer = 'https://push.strapblaque.com';

  // App credentials
  static const String appName = 'sechat';
  static const String appKey = 'ebea679133a7adfb9c4cd1f8b6a4fdc9';

  // Get base URL based on environment
  static String get baseUrl {
    return _prodServer;
  }

  // Get server info for debugging
  static Map<String, dynamic> get serverInfo => {
        'environment': isDevelopment ? 'development' : 'production',
        'baseUrl': baseUrl,
        'appName': appName,
        'sslEnabled': baseUrl.startsWith('https://'),
      };

  // SSL configuration
  static bool get sslEnabled => baseUrl.startsWith('https://');
  static bool get sslVerificationRequired => isProduction;

  // Connection timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration responseTimeout = Duration(seconds: 60);

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Debug information
  static void printConfig() {
    print(
        '🔧 AirNotifierConfig: Environment: ${isDevelopment ? "Development" : "Production"}');
    print('🔧 AirNotifierConfig: Base URL: $baseUrl');
    print('🔧 AirNotifierConfig: SSL Enabled: $sslEnabled');
    print(
        '🔧 AirNotifierConfig: SSL Verification Required: $sslVerificationRequired');
    print('🔧 AirNotifierConfig: App Name: $appName');
    print('🔧 AirNotifierConfig: Connection Timeout: $connectionTimeout');
    print('🔧 AirNotifierConfig: Max Retries: $maxRetries');
  }
}
