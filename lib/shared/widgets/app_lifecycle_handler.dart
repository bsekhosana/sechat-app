import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/secure_notification_service.dart';
import '../../features/chat/services/message_storage_service.dart';
import 'notification_permission_dialog.dart';

class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({
    Key? key,
    required this.child,
  }) : super(key: key);

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

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 AppLifecycleHandler: App resumed - foreground active');
        _handleAppResumed();
        break;

      case AppLifecycleState.inactive:
        print('📱 AppLifecycleHandler: App inactive - transitioning');
        break;

      case AppLifecycleState.paused:
        print('📱 AppLifecycleHandler: App paused - background/minimized');
        _handleAppPaused();
        break;

      case AppLifecycleState.detached:
        print('📱 AppLifecycleHandler: App detached - terminating');
        _handleAppDetached();
        break;

      case AppLifecycleState.hidden:
        print('📱 AppLifecycleHandler: App hidden - by system UI');
        break;

      default:
        print('📱 AppLifecycleHandler: Unknown app lifecycle state: $state');
        break;
    }
  }

  void _handleAppResumed() async {
    print('🔄 AppLifecycleHandler: App resumed, refreshing services...');

    // Refresh notification permissions
    SecureNotificationService.instance.refreshPermissions();

    // Validate permission status for iOS
    SecureNotificationService.instance.validatePermissionStatus();

    // Show permission dialog if needed
    NotificationPermissionHelper.showPermissionDialogIfNeeded();

    // Send online status update
    await _sendOnlineStatusUpdate(true);

    // Refresh other services as needed
    // ... existing refresh logic ...
  }

  void _handleAppPaused() async {
    try {
      // SeSessionService doesn't have lifecycle methods
      // Notification services handle this automatically
      print(
          '📱 AppLifecycleHandler: App paused - notification services continue');

      // Send offline status update
      await _sendOnlineStatusUpdate(false);
    } catch (e) {
      print('📱 AppLifecycleHandler: Error handling app pause: $e');
    }
  }

  void _handleAppDetached() async {
    try {
      // SeSessionService doesn't have lifecycle methods
      // Notification services handle this automatically
      print(
          '📱 AppLifecycleHandler: App detached - notification services continue');
    } catch (e) {
      print('📱 AppLifecycleHandler: Error handling app detach: $e');
    }
  }

  /// Send online status update to all contacts
  Future<void> _sendOnlineStatusUpdate(bool isOnline) async {
    try {
      print('📱 AppLifecycleHandler: Sending online status update: $isOnline');

      // Get current user ID
      final sessionService = SeSessionService();
      final currentUserId = sessionService.currentSessionId;

      if (currentUserId == null) {
        print('📱 AppLifecycleHandler: ❌ No current session ID available');
        return;
      }

      // Get all conversations to send status updates
      final messageStorageService = MessageStorageService.instance;
      final conversations =
          await messageStorageService.getUserConversations(currentUserId);

      // Send online status update to all participants
      final notificationService = SecureNotificationService.instance;
      for (final conversation in conversations) {
        final otherParticipantId =
            conversation.getOtherParticipantId(currentUserId);
        if (otherParticipantId != null) {
          await notificationService.sendOnlineStatusUpdate(
              otherParticipantId, isOnline);
        }
      }

      print(
          '📱 AppLifecycleHandler: ✅ Online status updates sent to ${conversations.length} contacts');
    } catch (e) {
      print(
          '📱 AppLifecycleHandler: ❌ Error sending online status updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
