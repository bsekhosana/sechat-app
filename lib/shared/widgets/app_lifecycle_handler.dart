import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/se_socket_service.dart';
import '../../features/chat/services/message_storage_service.dart';
import '../../core/services/app_state_service.dart';
import '../providers/socket_provider.dart';
import '../../features/notifications/services/notification_manager_service.dart';
import '../../core/services/ui_service.dart';

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

    // Send online status update via socket
    await _sendOnlineStatusUpdate(true);

    // Refresh socket connection state to update UI indicators
    try {
      // Import and use SocketProvider to refresh connection state
      final socketProvider =
          Provider.of<SocketProvider>(context, listen: false);
      socketProvider.refreshConnectionState();
      print('🔌 AppLifecycleHandler: ✅ Socket connection state refreshed');
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Could not refresh socket connection state: $e');
    }

    // Refresh other services as needed
    // ... existing refresh logic ...

    // Check notification permissions on resume (silent, no UI feedback)
    try {
      await NotificationManagerService().checkNotificationPermissions();
      print(
          '🔌 AppLifecycleHandler: ✅ Notification permissions checked silently');
    } catch (e) {
      print(
          '🔌 AppLifecycleHandler: ⚠️ Could not check notification permissions: $e');
    }
  }

  void _handleAppPaused() async {
    try {
      // Socket services handle this automatically
      print('🔌 AppLifecycleHandler: App paused - socket services continue');

      // Silent permission check when going to background (no test notifications)
      try {
        await NotificationManagerService().checkNotificationPermissions();
        print(
            '🔌 AppLifecycleHandler: ✅ Permissions checked when going to background');
      } catch (e) {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Could not check permissions when going to background: $e');
      }

      // Send offline status update via socket
      await _sendOnlineStatusUpdate(false);
    } catch (e) {
      print('🔌 AppLifecycleHandler: Error handling app pause: $e');
    }
  }

  void _handleAppDetached() async {
    try {
      // Socket services handle this automatically
      print('🔌 AppLifecycleHandler: App detached - socket services continue');

      // Send offline status update via socket
      await _sendOnlineStatusUpdate(false);
    } catch (e) {
      print('🔌 AppLifecycleHandler: Error handling app detach: $e');
    }
  }

  /// Send online status update via socket
  Future<void> _sendOnlineStatusUpdate(bool isOnline) async {
    try {
      print(
          '🔌 AppLifecycleHandler: Sending online status update via socket: $isOnline');

      // Use SeSocketService to send online status to all contacts
      final socketService = SeSocketService();
      final success =
          await socketService.sendOnlineStatusToAllContacts(isOnline);

      if (success) {
        print(
            '🔌 AppLifecycleHandler: ✅ Online status updates sent via socket to all contacts');
      } else {
        print(
            '🔌 AppLifecycleHandler: ⚠️ Failed to send online status updates via socket');
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
