import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/se_socket_service.dart';
import '../../features/chat/services/message_storage_service.dart';
import '../../core/services/app_state_service.dart';

import '../../core/services/ui_service.dart';
import '../../realtime/realtime_service_manager.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Track lifecycle state globally
    AppStateService().updateLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('🔌 AppLifecycleHandler: App resumed - foreground active');
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
    print('🔄 AppLifecycleHandler: App resumed, refreshing services...');

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
      print('🔌 AppLifecycleHandler: App paused - cleaning up socket services');

      // CRITICAL: More aggressive cleanup when app goes to background
      try {
        final socketService = SeSocketService.instance;
        if (socketService.isConnected) {
          print(
              '🔌 AppLifecycleHandler: 🔌 App going to background, disconnecting socket...');

          // Send offline status first
          await _sendOnlineStatusUpdate(false);

          // Force disconnect to prevent background socket activity
          await socketService.forceDisconnect();
          print('🔌 AppLifecycleHandler: ✅ Socket disconnected for background');
        }
      } catch (e) {
        print('🔌 AppLifecycleHandler: ⚠️ Warning - socket cleanup failed: $e');
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

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
