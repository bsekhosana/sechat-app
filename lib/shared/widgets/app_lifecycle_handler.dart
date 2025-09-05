import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/services/se_socket_service.dart';
import '../../core/services/app_state_service.dart';
import '../../core/services/background_connection_manager.dart';
import '../../features/notifications/services/local_notification_badge_service.dart';
import '../../realtime/realtime_service_manager.dart';
import '../../features/key_exchange/providers/key_exchange_request_provider.dart';
import '../../main.dart';
import 'package:flutter/services.dart';
import '/../core/utils/logger.dart';

class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({
    super.key,
    required this.child,
  });

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  DateTime? _lastBadgeReset;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set up iOS-specific lifecycle event listeners
    _setupIOSLifecycleHandling();

    // Listen to app focus changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAppFocusListener();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    Logger.info(' AppLifecycleHandler:  Lifecycle state changed to: $state');

    // Track lifecycle state globally
    AppStateService().updateLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        Logger.debug(
            '🔌 AppLifecycleHandler: 🚀 App resumed - foreground active - calling _handleAppResumed()');
        _handleAppResumed();
        break;

      case AppLifecycleState.inactive:
        Logger.debug(' AppLifecycleHandler: App inactive - transitioning');
        break;

      case AppLifecycleState.paused:
        Logger.debug(' AppLifecycleHandler: App paused - background/minimized');
        _handleAppPaused();
        break;

      case AppLifecycleState.detached:
        Logger.debug(' AppLifecycleHandler: App detached - terminating');
        _handleAppDetached();
        break;

      case AppLifecycleState.hidden:
        Logger.debug(' AppLifecycleHandler: App hidden - by system UI');
        break;
    }
  }

  void _handleAppResumed() async {
    Logger.debug(
        '🔄 AppLifecycleHandler: 🚀 _handleAppResumed() method called - starting badge reset and notification clearing...');

    // Stop background connection maintenance when app comes to foreground
    try {
      Logger.debug(
          ' AppLifecycleHandler: 🔧 Stopping background connection maintenance...');
      await BackgroundConnectionManager().stopBackgroundMaintenance();
      Logger.success(
          ' AppLifecycleHandler: ✅ Background connection maintenance stopped');
    } catch (e) {
      Logger.warning(
          ' AppLifecycleHandler: ⚠️ Error stopping background connection maintenance: $e');
    }

    // Reset socket service if it was destroyed
    try {
      if (SeSocketService.isDestroyed) {
        Logger.info(
            ' AppLifecycleHandler:  Socket service was destroyed, resetting...');
        SeSocketService.resetForNewConnection();
        Logger.success(
            ' AppLifecycleHandler:  Socket service reset for resume');
      }
    } catch (e) {
      Logger.warning(
          ' AppLifecycleHandler:  Warning - socket service reset failed: $e');
    }

    // Send online status update via channel socket service
    await _sendOnlineStatusUpdate(true);

    // Refresh channel socket connection state
    try {
      final socketService = SeSocketService.instance;
      if (socketService.isConnected) {
        Logger.success(
            ' AppLifecycleHandler:  SeSocketService connection active');
      } else {
        Logger.warning(
            ' AppLifecycleHandler:  SeSocketService connection inactive');
        // SeSocketService is already initialized when the app starts
      }
    } catch (e) {
      Logger.warning(
          ' AppLifecycleHandler:  Could not refresh channel socket connection: $e');
    }

    // Refresh other services as needed
    // ... existing refresh logic ...

    // Reset app icon badge count to 0 and clear device notification tray
    try {
      // Reset badge count to 0
      await LocalNotificationBadgeService().resetBadgeCount();
      Logger.success(' AppLifecycleHandler:  App icon badge count reset to 0');

      // Clear all notifications from device notification tray
      await LocalNotificationBadgeService().clearAllDeviceNotifications();
      Logger.success(
          ' AppLifecycleHandler:  All device notifications cleared from tray');

      // DON'T reset the IndicatorService badge counts - they should persist
      // Only reset the app badge counter, not the internal navigation badge counts
      Logger.info(
          ' AppLifecycleHandler:  Keeping navigation badge counts intact');

      // Force refresh all providers to update UI
      try {
        // Force refresh KeyExchangeRequestProvider
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);
        await keyExchangeProvider.refresh();
        Logger.success(
            ' AppLifecycleHandler:  KeyExchangeRequestProvider refreshed');
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Failed to refresh KeyExchangeRequestProvider: $e');
      }
    } catch (e) {
      Logger.warning(
          ' AppLifecycleHandler:  Could not reset badge/clear notifications: $e');
    }

    // Check notification permissions on resume (silent, no UI feedback)
    try {
      // Notification permissions are now handled by LocalNotificationBadgeService
      Logger.success(
          ' AppLifecycleHandler:  Notification permissions handled by new system');
    } catch (e) {
      Logger.warning(
          ' AppLifecycleHandler:  Could not check notification permissions: $e');
    }
  }

  void _handleAppPaused() async {
    try {
      Logger.debug(
          ' AppLifecycleHandler: App paused - keeping socket connected for background messages');

      // CRITICAL: Keep socket connected in background to receive messages and trigger push notifications
      try {
        final socketService = SeSocketService.instance;
        Logger.debug(
            ' AppLifecycleHandler: 🔌 Socket service status - isConnected: ${socketService.isConnected}');

        if (socketService.isConnected) {
          Logger.debug(
              ' AppLifecycleHandler: 🔌 App going to background, keeping socket connected for push notifications...');

          // Send offline status for presence, but keep socket connected
          await _sendOnlineStatusUpdate(false);
          Logger.success(
              ' AppLifecycleHandler:  Socket kept connected for background message reception');
        } else {
          Logger.warning(
              ' AppLifecycleHandler: ⚠️ Socket not connected when going to background, attempting to maintain connection...');
          // Try to ensure socket stays connected
          try {
            // Don't reconnect here, just log the status
            Logger.debug(
                ' AppLifecycleHandler: 🔌 Socket will attempt reconnection automatically');
          } catch (e) {
            Logger.warning(
                ' AppLifecycleHandler: ⚠️ Could not maintain socket connection: $e');
          }
        }
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Warning - socket status update failed: $e');
      }

      // Start background connection maintenance
      try {
        Logger.debug(
            ' AppLifecycleHandler: 🔧 Starting background connection maintenance...');
        await BackgroundConnectionManager().startBackgroundMaintenance();
        Logger.success(
            ' AppLifecycleHandler: ✅ Background connection maintenance started');
      } catch (e) {
        Logger.error(
            ' AppLifecycleHandler: ❌ Error starting background connection maintenance: $e');
      }

      // Silent permission check when going to background (no test notifications)
      try {
        // Notification permissions are now handled by LocalNotificationBadgeService
        Logger.success(
            ' AppLifecycleHandler:  Permissions handled by new system when going to background');
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Could not check permissions when going to background: $e');
      }
    } catch (e) {
      Logger.error(' AppLifecycleHandler:  Error handling app pause: $e');
    }
  }

  void _handleAppDetached() async {
    try {
      Logger.debug(
          ' AppLifecycleHandler: App detached - terminating socket services');

      // CRITICAL: Completely destroy socket service to prevent memory leaks
      try {
        final socketService = SeSocketService.instance;
        if (socketService.isConnected) {
          Logger.debug(
              ' AppLifecycleHandler: 🔌 Disconnecting socket service...');
          await socketService.forceDisconnect();
          Logger.success(' AppLifecycleHandler:  Socket service disconnected');
        }

        // Destroy the singleton instance completely
        SeSocketService.destroyInstance();
        Logger.success(
            ' AppLifecycleHandler:  Socket service instance destroyed');
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Warning - socket service cleanup failed: $e');
      }

      // Send offline status update via socket (if still possible)
      try {
        await _sendOnlineStatusUpdate(false);
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Could not send offline status: $e');
      }

      Logger.success(
          ' AppLifecycleHandler:  App termination cleanup completed');
    } catch (e) {
      Logger.error(' AppLifecycleHandler:  Error handling app detach: $e');
    }
  }

  /// Set up iOS-specific lifecycle event handling
  void _setupIOSLifecycleHandling() {
    // Listen to iOS lifecycle events
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      Logger.debug(' AppLifecycleHandler: 📱 iOS Lifecycle event: $msg');

      switch (msg) {
        case 'AppLifecycleState.resumed':
        case 'AppLifecycleState.inactive':
        case 'AppLifecycleState.paused':
        case 'AppLifecycleState.detached':
        case 'AppLifecycleState.hidden':
          // These are handled by Flutter's lifecycle system
          break;
        case 'AppLifecycleState.restartInactive':
        case 'AppLifecycleState.restartPaused':
          // iOS-specific events that might indicate app resume
          Logger.debug(
              '🔌 AppLifecycleHandler: 📱 iOS App resume detected, calling _handleAppResumed()');
          _handleAppResumed();
          break;
        default:
          // Handle other iOS events
          if (msg?.contains('resume') == true ||
              msg?.contains('active') == true) {
            Logger.debug(
                ' AppLifecycleHandler: 📱 iOS App resume detected via event: $msg');
            _handleAppResumed();
          }
          break;
      }

      return null;
    });

    // Also listen to app state changes via platform channel
    SystemChannels.platform.setMethodCallHandler((call) async {
      if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
        // This is often called when app becomes active
        Logger.debug(
            ' AppLifecycleHandler: 📱 iOS System UI change detected, app likely resumed');
        _handleAppResumed();
      }
      return null;
    });
  }

  /// Set up app focus listener to detect when app becomes active
  void _setupAppFocusListener() {
    // Listen to app focus changes
    WidgetsBinding.instance.addObserver(this);

    // Also use a timer to periodically check if app is active
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        // App is active, check if we need to reset badge
        Logger.debug(
            ' AppLifecycleHandler: 📱 App is active, checking if badge reset is needed');
        _checkAndResetBadgeIfNeeded();
      }
    });
  }

  /// Check if badge reset is needed and perform it
  void _checkAndResetBadgeIfNeeded() async {
    try {
      // Only reset if we haven't done it recently
      final now = DateTime.now();
      if (_lastBadgeReset == null ||
          now.difference(_lastBadgeReset!).inMinutes > 1) {
        Logger.debug(' AppLifecycleHandler: 📱 Performing badge reset check');
        _handleAppResumed();
        _lastBadgeReset = now;
      }
    } catch (e) {
      Logger.error(' AppLifecycleHandler:  Error in badge reset check: $e');
    }
  }

  /// Public method to manually trigger badge reset (can be called from other parts of the app)
  Future<void> manualBadgeReset() async {
    Logger.debug(' AppLifecycleHandler: 📱 Manual badge reset requested');
    _handleAppResumed();
  }

  /// Send online status update via realtime presence service
  Future<void> _sendOnlineStatusUpdate(bool isOnline) async {
    try {
      Logger.debug(
          ' AppLifecycleHandler: Sending online status update via realtime service: $isOnline');

      // Try to use realtime service manager first
      try {
        final realtimeManager = RealtimeServiceManager();
        if (realtimeManager.isInitialized) {
          realtimeManager.presence.forcePresenceUpdate(isOnline);
          Logger.success(
              ' AppLifecycleHandler:  Online status updated via realtime service');
        } else {
          Logger.warning(
              ' AppLifecycleHandler:  Realtime service not initialized, using fallback');
          // Fallback to direct socket service
          final socketService = SeSocketService.instance;
          socketService.sendPresenceUpdate('', isOnline);
        }
      } catch (e) {
        Logger.warning(
            ' AppLifecycleHandler:  Realtime service failed, using fallback: $e');
        // Fallback to direct socket service
        final socketService = SeSocketService.instance;
        socketService.sendPresenceUpdate('', isOnline);
      }
    } catch (e) {
      Logger.error(
          ' AppLifecycleHandler:  Error sending online status updates: $e');
    }
  }
}
