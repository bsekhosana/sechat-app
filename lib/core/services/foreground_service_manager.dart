import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// Manages Android foreground service to keep socket connection alive in background
class ForegroundServiceManager {
  static const MethodChannel _channel =
      MethodChannel('com.strapblaque.sechat/foreground_service');

  static final ForegroundServiceManager _instance =
      ForegroundServiceManager._internal();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._internal();

  /// Start the foreground service to keep socket alive in background
  static Future<bool> startForegroundService() async {
    try {
      Logger.debug(
          '🔧 ForegroundServiceManager: Starting foreground service...');
      final bool result = await _channel.invokeMethod('startForegroundService');
      if (result) {
        Logger.success(
            '🔧 ForegroundServiceManager: ✅ Foreground service started successfully');
      } else {
        Logger.warning(
            '🔧 ForegroundServiceManager: ⚠️ Failed to start foreground service');
      }
      return result;
    } catch (e) {
      Logger.error(
          '🔧 ForegroundServiceManager: ❌ Error starting foreground service: $e');
      return false;
    }
  }

  /// Stop the foreground service
  static Future<bool> stopForegroundService() async {
    try {
      Logger.debug(
          '🔧 ForegroundServiceManager: Stopping foreground service...');
      final bool result = await _channel.invokeMethod('stopForegroundService');
      if (result) {
        Logger.success(
            '🔧 ForegroundServiceManager: ✅ Foreground service stopped successfully');
      } else {
        Logger.warning(
            '🔧 ForegroundServiceManager: ⚠️ Failed to stop foreground service');
      }
      return result;
    } catch (e) {
      Logger.error(
          '🔧 ForegroundServiceManager: ❌ Error stopping foreground service: $e');
      return false;
    }
  }

  /// Check if foreground service is running
  static Future<bool> isForegroundServiceRunning() async {
    try {
      final bool result =
          await _channel.invokeMethod('isForegroundServiceRunning');
      Logger.debug(
          '🔧 ForegroundServiceManager: Foreground service running: $result');
      return result;
    } catch (e) {
      Logger.error(
          '🔧 ForegroundServiceManager: ❌ Error checking foreground service status: $e');
      return false;
    }
  }
}
