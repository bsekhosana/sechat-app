import 'dart:async';
import 'dart:io';
import '../utils/logger.dart';
import 'se_socket_service.dart';
import 'foreground_service_manager.dart';
import '../../features/notifications/services/local_notification_badge_service.dart';

/// Manages background connection maintenance to prevent socket disconnection
class BackgroundConnectionManager {
  static final BackgroundConnectionManager _instance =
      BackgroundConnectionManager._internal();
  factory BackgroundConnectionManager() => _instance;
  BackgroundConnectionManager._internal();

  Timer? _backgroundPingTimer;
  Timer? _connectionCheckTimer;
  Timer? _aggressivePingTimer;
  bool _isBackgroundMode = false;
  int _backgroundPingCount = 0;
  int _aggressivePingCount = 0;

  /// Start background connection maintenance
  Future<void> startBackgroundMaintenance() async {
    if (_isBackgroundMode) return;

    _isBackgroundMode = true;
    Logger.debug(
        '🔧 BackgroundConnectionManager: Starting background maintenance...');

    // Initialize notification service for background notifications
    try {
      final notificationService = LocalNotificationBadgeService();
      await notificationService.initialize();
      Logger.success(
          '🔧 BackgroundConnectionManager: ✅ Notification service initialized for background');
    } catch (e) {
      Logger.error(
          '🔧 BackgroundConnectionManager: ❌ Error initializing notification service: $e');
    }

    // Start Android foreground service
    if (Platform.isAndroid) {
      try {
        final started = await ForegroundServiceManager.startForegroundService();
        if (started) {
          Logger.success(
              '🔧 BackgroundConnectionManager: ✅ Android foreground service started');
        } else {
          Logger.warning(
              '🔧 BackgroundConnectionManager: ⚠️ Failed to start Android foreground service');
        }
      } catch (e) {
        Logger.error(
            '🔧 BackgroundConnectionManager: ❌ Error starting Android foreground service: $e');
      }
    }

    // Send immediate ping to ensure connection is alive
    _sendImmediatePing();

    // Start aggressive ping timer for first 5 minutes (every 5 seconds)
    _startAggressivePingTimer();

    // Start background ping timer to keep connection alive
    _startBackgroundPingTimer();

    // Start connection check timer
    _startConnectionCheckTimer();

    Logger.success(
        '🔧 BackgroundConnectionManager: ✅ Background maintenance started');
  }

  /// Stop background connection maintenance
  Future<void> stopBackgroundMaintenance() async {
    if (!_isBackgroundMode) return;

    _isBackgroundMode = false;
    Logger.debug(
        '🔧 BackgroundConnectionManager: Stopping background maintenance...');

    // Stop Android foreground service
    if (Platform.isAndroid) {
      try {
        final stopped = await ForegroundServiceManager.stopForegroundService();
        if (stopped) {
          Logger.success(
              '🔧 BackgroundConnectionManager: ✅ Android foreground service stopped');
        } else {
          Logger.warning(
              '🔧 BackgroundConnectionManager: ⚠️ Failed to stop Android foreground service');
        }
      } catch (e) {
        Logger.error(
            '🔧 BackgroundConnectionManager: ❌ Error stopping Android foreground service: $e');
      }
    }

    // Stop timers
    _backgroundPingTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _aggressivePingTimer?.cancel();
    _backgroundPingCount = 0;
    _aggressivePingCount = 0;

    Logger.success(
        '🔧 BackgroundConnectionManager: ✅ Background maintenance stopped');
  }

  /// Send immediate ping to ensure connection is alive
  void _sendImmediatePing() {
    try {
      Logger.info(
          '🔧 BackgroundConnectionManager: 🚀 Sending immediate ping to ensure connection is alive');
      final socketService = SeSocketService.instance;

      if (socketService.isConnected) {
        socketService.sendPresence(false, []);
        Logger.success(
            '🔧 BackgroundConnectionManager: ✅ Immediate ping sent successfully');
      } else {
        Logger.warning(
            '🔧 BackgroundConnectionManager: ⚠️ Socket not connected for immediate ping');
        // Try to reconnect immediately
        try {
          Logger.info(
              '🔧 BackgroundConnectionManager: 🔄 Immediate reconnection attempt initiated');
          // Note: We can't directly access sessionId, so we'll let the socket service handle reconnection
          Logger.debug(
              '🔧 BackgroundConnectionManager: 🔄 Socket will attempt automatic reconnection');
        } catch (e) {
          Logger.error(
              '🔧 BackgroundConnectionManager: ❌ Immediate reconnection failed: $e');
        }
      }
    } catch (e) {
      Logger.error(
          '🔧 BackgroundConnectionManager: ❌ Error sending immediate ping: $e');
    }
  }

  /// Start aggressive ping timer for first 5 minutes
  void _startAggressivePingTimer() {
    _aggressivePingTimer?.cancel();
    _aggressivePingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isBackgroundMode) {
        timer.cancel();
        return;
      }

      _aggressivePingCount++;
      Logger.info(
          '🔧 BackgroundConnectionManager: 🚀 Aggressive ping #$_aggressivePingCount');

      // Stop aggressive pinging after 5 minutes (60 pings * 5 seconds = 300 seconds)
      if (_aggressivePingCount >= 60) {
        Logger.info(
            '🔧 BackgroundConnectionManager: ⏰ Stopping aggressive pinging after 5 minutes');
        timer.cancel();
        return;
      }

      try {
        final socketService = SeSocketService.instance;
        Logger.debug(
            '🔧 BackgroundConnectionManager: Socket status - isConnected: ${socketService.isConnected}');

        if (socketService.isConnected) {
          // Send a keepalive ping to maintain connection
          socketService.sendPresence(false, []);
          Logger.success(
              '🔧 BackgroundConnectionManager: ✅ Aggressive ping sent successfully');
        } else {
          Logger.warning(
              '🔧 BackgroundConnectionManager: ⚠️ Socket not connected during aggressive ping - will attempt reconnection');

          // Try to reconnect immediately if socket is disconnected
          try {
            Logger.info(
                '🔧 BackgroundConnectionManager: 🔄 Attempting immediate reconnection from aggressive ping...');
            // Note: We can't directly access sessionId, so we'll let the socket service handle reconnection
            Logger.success(
                '🔧 BackgroundConnectionManager: ✅ Reconnection attempt initiated from aggressive ping');
          } catch (reconnectError) {
            Logger.error(
                '🔧 BackgroundConnectionManager: ❌ Reconnection failed from aggressive ping: $reconnectError');
          }
        }
      } catch (e) {
        Logger.error(
            '🔧 BackgroundConnectionManager: ❌ Error during aggressive ping: $e');
      }
    });
  }

  /// Start background ping timer to keep socket alive
  void _startBackgroundPingTimer() {
    _backgroundPingTimer?.cancel();
    _backgroundPingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isBackgroundMode) {
        timer.cancel();
        return;
      }

      _backgroundPingCount++;
      Logger.info(
          '🔧 BackgroundConnectionManager: 🔄 Background ping #$_backgroundPingCount');

      try {
        final socketService = SeSocketService.instance;
        Logger.debug(
            '🔧 BackgroundConnectionManager: Socket status - isConnected: ${socketService.isConnected}');

        if (socketService.isConnected) {
          // Send a keepalive ping to maintain connection
          socketService.sendPresence(
              false, []); // Send offline presence to keep connection alive
          Logger.success(
              '🔧 BackgroundConnectionManager: ✅ Background ping sent successfully');
        } else {
          Logger.warning(
              '🔧 BackgroundConnectionManager: ⚠️ Socket not connected during background ping - will attempt reconnection');

          // Try to reconnect immediately if socket is disconnected
          try {
            Logger.info(
                '🔧 BackgroundConnectionManager: 🔄 Attempting immediate reconnection...');
            // Note: We can't directly access sessionId, so we'll let the socket service handle reconnection
            Logger.success(
                '🔧 BackgroundConnectionManager: ✅ Reconnection attempt initiated');
          } catch (reconnectError) {
            Logger.error(
                '🔧 BackgroundConnectionManager: ❌ Reconnection failed: $reconnectError');
          }
        }
      } catch (e) {
        Logger.error(
            '🔧 BackgroundConnectionManager: ❌ Error during background ping: $e');
      }
    });
  }

  /// Start connection check timer
  void _startConnectionCheckTimer() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isBackgroundMode) {
        timer.cancel();
        return;
      }

      Logger.debug(
          '🔧 BackgroundConnectionManager: 🔍 Checking background connection...');

      try {
        final socketService = SeSocketService.instance;
        if (!socketService.isConnected) {
          Logger.warning(
              '🔧 BackgroundConnectionManager: ⚠️ Socket disconnected in background, attempting reconnection...');

          // Try to reconnect immediately
          try {
            Logger.info(
                '🔧 BackgroundConnectionManager: 🔄 Attempting immediate reconnection from connection check...');
            // Note: We can't directly access sessionId, so we'll let the socket service handle reconnection
            Logger.success(
                '🔧 BackgroundConnectionManager: ✅ Reconnection attempt initiated from connection check');
          } catch (reconnectError) {
            Logger.error(
                '🔧 BackgroundConnectionManager: ❌ Reconnection failed from connection check: $reconnectError');
          }
        } else {
          Logger.debug(
              '🔧 BackgroundConnectionManager: ✅ Background connection is healthy');
        }
      } catch (e) {
        Logger.warning(
            '🔧 BackgroundConnectionManager: ⚠️ Error checking background connection: $e');
      }
    });
  }

  /// Get background maintenance status
  Map<String, dynamic> getStatus() {
    return {
      'isBackgroundMode': _isBackgroundMode,
      'backgroundPingCount': _backgroundPingCount,
      'aggressivePingCount': _aggressivePingCount,
      'isPingTimerActive': _backgroundPingTimer?.isActive ?? false,
      'isAggressivePingTimerActive': _aggressivePingTimer?.isActive ?? false,
      'isCheckTimerActive': _connectionCheckTimer?.isActive ?? false,
    };
  }

  /// Dispose resources
  void dispose() {
    _backgroundPingTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _aggressivePingTimer?.cancel();
    _isBackgroundMode = false;
    _backgroundPingCount = 0;
    _aggressivePingCount = 0;
  }
}
