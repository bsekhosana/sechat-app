import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'dart:io' show Platform;

/// Dialog to guide users to enable notification permissions
class NotificationPermissionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? actionText;
  final VoidCallback? onActionPressed;

  const NotificationPermissionDialog({
    super.key,
    this.title = 'Enable Notifications',
    this.message =
        'To receive important updates and messages, please enable notifications for this app.',
    this.actionText,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 16),
          if (Platform.isIOS) ...[
            const Text(
              'To enable notifications:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Go to Settings > seChat'),
            const Text('2. Tap "Notifications"'),
            const Text('3. Enable "Allow Notifications"'),
            const Text('4. Enable "Sounds", "Badges", and "Alerts"'),
          ] else ...[
            const Text(
              'To enable notifications:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Go to Settings > Apps > seChat'),
            const Text('2. Tap "Notifications"'),
            const Text('3. Enable "Show notifications"'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (onActionPressed != null) {
              onActionPressed!();
            } else {
              // Default action: open app settings
              SimpleNotificationService.instance
                  .openAppSettingsForPermissions();
            }
          },
          child: Text(actionText ?? 'Open Settings'),
        ),
      ],
    );
  }
}

/// Helper to show notification permission dialog when needed
class NotificationPermissionHelper {
  /// Show permission dialog if needed
  static Future<void> showPermissionDialogIfNeeded(BuildContext context) async {
    final notificationService = SimpleNotificationService.instance;

    if (notificationService.shouldShowPermissionDialog) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const NotificationPermissionDialog(
          title: 'Enable Notifications',
          message:
              'To receive key exchange requests, messages, and other important updates, please enable notifications for seChat.',
          actionText: 'Open Settings',
        ),
      );
    }
  }

  /// Check and request permissions
  static Future<void> checkAndRequestPermissions(BuildContext context) async {
    final notificationService = SimpleNotificationService.instance;

    // Refresh permissions first
    await notificationService.refreshPermissions();

    // Show dialog if needed
    await showPermissionDialogIfNeeded(context);
  }
}
