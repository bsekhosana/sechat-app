import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/services/se_socket_service.dart';
import '../../core/services/app_state_service.dart';
import '../../features/notifications/services/local_notification_badge_service.dart';
import '../../realtime/realtime_service_manager.dart';
import '../../core/services/indicator_service.dart';
import '../../features/key_exchange/providers/key_exchange_request_provider.dart';
import '../../main.dart';
import 'package:flutter/services.dart';

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

    print('🔌 AppLifecycleHandler: 🔄 Lifecycle state changed to: $state');

    // Track lifecycle state globally
    AppStateService().updateLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print(
            '🔌 AppLifecycleHandler: 🚀 App resumed - foreground active - calling _handleAppResumed()');
        _handleAppResumed();
        break;

      case AppLifecycleState.inactive:
        print('🔌 AppLifecycleHandler: App inactive - transitioning');
        break;

      case AppLifecycleState.paused:
        print('🔌 AppLifecycleHandler: App paused - background/minimized');
        _handleAppPaused();
        break;

      case AppLifecycleState.detached:
        print('🔌 AppLifecycleHandler: App detached - terminating');
        _handleAppDetached();
        break;

      case AppLifecycleState.hidden:
        print('🔌 AppLifecycleHandler: App hidden - by system UI');
        break;

      default:
        print('🔌 AppLifecycleHandler: Unknown app lifecycle state: $state');
        break;
    }
  }

  void _handleAppResumed() async {
    print(
        '🔄 AppLifecycleHandler: 🚀 _handleAppResumed() method called - starting badge reset and notification clearing...');

    // Reset socket service if it was destroyed
    try {
      if (SeSocketService.isDestroyed) {
        print(
            '🔌 AppLifecycleHandler: 🔄 Socket service was destroyed, resetting...');
        SeSocketService.resetForNewConnection();
        print('🔌 AppLifecycleHandler: ✅ Socket service reset for resume');
      }
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Warning - socket service reset failed: $e');
    }

    // Send online status update via channel socket service
    await _sendOnlineStatusUpdate(true);

    // Refresh channel socket connection state
    try {
      final socketService = SeSocketService.instance;
      if (socketService.isConnected) {
        print('🔌 AppLifecycleHandler: ✅ SeSocketService connection active');
      } else {
        print('🔌 AppLifecycleHandler: ⚠️ SeSocketService connection inactive');
        // SeSocketService is already initialized when the app starts
      }
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Could not refresh channel socket connection: $e');
    }

    // Refresh other services as needed
    // ... existing refresh logic ...

    // Reset app icon badge count to 0 and clear device notification tray
    try {
      // Reset badge count to 0
      await LocalNotificationBadgeService().resetBadgeCount();
      print('🔌 AppLifecycleHandler: ✅ App icon badge count reset to 0');

      // Clear all notifications from device notification tray
      await LocalNotificationBadgeService().clearAllDeviceNotifications();
      print(
          '🔌 AppLifecycleHandler: ✅ All device notifications cleared from tray');

      // DON'T reset the IndicatorService badge counts - they should persist
      // Only reset the app badge counter, not the internal navigation badge counts
      print(
          '🔌 AppLifecycleHandler: ℹ️ Keeping navigation badge counts intact');

      // Force refresh all providers to update UI
      try {
        // Force refresh KeyExchangeRequestProvider
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);
        await keyExchangeProvider.refresh();
        print('🔌 AppLifecycleHandler: ✅ KeyExchangeRequestProvider refreshed');
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Failed to refresh KeyExchangeRequestProvider: $e');
      }
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Could not reset badge/clear notifications: $e');
    }

    // Check notification permissions on resume (silent, no UI feedback)
    try {
      // Notification permissions are now handled by LocalNotificationBadgeService
      print(
          '🔌 AppLifecycleHandler: ✅ Notification permissions handled by new system');
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Could not check notification permissions: $e');
    }
  }

  void _handleAppPaused() async {
    try {
      print(
          '🔌 AppLifecycleHandler: App paused - keeping socket connected for background messages');

      // CRITICAL: Keep socket connected in background to receive messages and trigger push notifications
      try {
        final socketService = SeSocketService.instance;
        if (socketService.isConnected) {
          print(
              '🔌 AppLifecycleHandler: 🔌 App going to background, keeping socket connected for push notifications...');

          // Send offline status for presence, but keep socket connected
          await _sendOnlineStatusUpdate(false);
          print(
              '🔌 AppLifecycleHandler: ✅ Socket kept connected for background message reception');
        }
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Warning - socket status update failed: $e');
      }

      // Silent permission check when going to background (no test notifications)
      try {
        // Notification permissions are now handled by LocalNotificationBadgeService
        print(
            '🔌 AppLifecycleHandler: ✅ Permissions handled by new system when going to background');
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Could not check permissions when going to background: $e');
      }
    } catch (e) {
      print('🔌 AppLifecycleHandler: ❌ Error handling app pause: $e');
    }
  }

  void _handleAppDetached() async {
    try {
      print(
          '🔌 AppLifecycleHandler: App detached - terminating socket services');

      // CRITICAL: Completely destroy socket service to prevent memory leaks
      try {
        final socketService = SeSocketService.instance;
        if (socketService.isConnected) {
          print('🔌 AppLifecycleHandler: 🔌 Disconnecting socket service...');
          await socketService.forceDisconnect();
          print('🔌 AppLifecycleHandler: ✅ Socket service disconnected');
        }

        // Destroy the singleton instance completely
        SeSocketService.destroyInstance();
        print('🔌 AppLifecycleHandler: ✅ Socket service instance destroyed');
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Warning - socket service cleanup failed: $e');
      }

      // Send offline status update via socket (if still possible)
      try {
        await _sendOnlineStatusUpdate(false);
      } catch (e) {
        print('🔌 AppLifecycleHandler: ⚠️ Could not send offline status: $e');
      }

      print('🔌 AppLifecycleHandler: ✅ App termination cleanup completed');
    } catch (e) {
      print('🔌 AppLifecycleHandler: ❌ Error handling app detach: $e');
    }
  }

  /// Set up iOS-specific lifecycle event handling
  void _setupIOSLifecycleHandling() {
    // Listen to iOS lifecycle events
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      print('🔌 AppLifecycleHandler: 📱 iOS Lifecycle event: $msg');

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
          print(
              '🔌 AppLifecycleHandler: 📱 iOS App resume detected, calling _handleAppResumed()');
          _handleAppResumed();
          break;
        default:
          // Handle other iOS events
          if (msg?.contains('resume') == true ||
              msg?.contains('active') == true) {
            print(
                '🔌 AppLifecycleHandler: 📱 iOS App resume detected via event: $msg');
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
        print(
            '🔌 AppLifecycleHandler: 📱 iOS System UI change detected, app likely resumed');
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
        print(
            '🔌 AppLifecycleHandler: 📱 App is active, checking if badge reset is needed');
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
        print('🔌 AppLifecycleHandler: 📱 Performing badge reset check');
        _handleAppResumed();
        _lastBadgeReset = now;
      }
    } catch (e) {
      print('🔌 AppLifecycleHandler: ❌ Error in badge reset check: $e');
    }
  }

  /// Public method to manually trigger badge reset (can be called from other parts of the app)
  Future<void> manualBadgeReset() async {
    print('🔌 AppLifecycleHandler: 📱 Manual badge reset requested');
    _handleAppResumed();
  }

  /// Send online status update via realtime presence service
  Future<void> _sendOnlineStatusUpdate(bool isOnline) async {
    try {
      print(
          '🔌 AppLifecycleHandler: Sending online status update via realtime service: $isOnline');

      // Try to use realtime service manager first
      try {
        final realtimeManager = RealtimeServiceManager();
        if (realtimeManager.isInitialized) {
          realtimeManager.presence.forcePresenceUpdate(isOnline);
          print(
              '🔌 AppLifecycleHandler: ✅ Online status updated via realtime service');
        } else {
          print(
              '🔌 AppLifecycleHandler: ⚠️ Realtime service not initialized, using fallback');
          // Fallback to direct socket service
          final socketService = SeSocketService.instance;
          socketService.sendPresenceUpdate('', isOnline);
        }
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Realtime service failed, using fallback: $e');
        // Fallback to direct socket service
        final socketService = SeSocketService.instance;
        socketService.sendPresenceUpdate('', isOnline);
      }
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ❌ Error sending online status updates: $e');
    }
  }
}
