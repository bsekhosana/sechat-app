import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import '../../features/notifications/services/notification_manager_service.dart';
import 'indicator_service.dart';

/// Service to handle socket event notifications (local snackbars and push notifications)
class SocketNotificationService {
  static SocketNotificationService? _instance;
  static SocketNotificationService get instance =>
      _instance ??= SocketNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  SocketNotificationService._();

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize local notifications
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(initSettings);
      _isInitialized = true;

      print('🔔 SocketNotificationService: ✅ Initialized successfully');
    } catch (e) {
      print('🔔 SocketNotificationService: ❌ Initialization failed: $e');
    }
  }

  /// Show a local snackbar notification
  void showLocalNotification(
    BuildContext context,
    String message, {
    Color backgroundColor = Colors.blue,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration,
          action: action,
        ),
      );
    }
  }

  /// Show a push notification (when app is in background)
  Future<void> showPushNotification({
    required String title,
    required String body,
    String? payload,
    int? badgeNumber,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'socket_events',
        'Socket Events',
        channelDescription: 'Notifications for socket events',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: badgeNumber,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: payload,
      );

      print('🔔 SocketNotificationService: ✅ Push notification sent: $title');
    } catch (e) {
      print(
          '🔔 SocketNotificationService: ❌ Failed to send push notification: $e');
    }
  }

  /// Handle key exchange request received
  void handleKeyExchangeRequestReceived(
      BuildContext context, Map<String, dynamic> data) {
    final senderId = data['senderId'] ?? 'Unknown User';
    final requestPhrase = data['requestPhrase'] ?? 'New key exchange request';

    final message = 'Key exchange request from ${senderId.substring(0, 8)}...';

    // Show local notification
    showLocalNotification(
      context,
      message,
      backgroundColor: Colors.orange,
      action: SnackBarAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Navigate to key exchange screen
          Navigator.of(context).pushNamed('/key-exchange');
        },
      ),
    );

    // Show push notification if app is in background
    _showBackgroundNotification(
      'Key Exchange Request',
      message,
      'key_exchange_request',
      data,
    );

    // Update badge counts
    _updateBadgeCounts(context, keyExchangeCount: 1);
  }

  /// Handle key exchange accepted
  void handleKeyExchangeAccepted(
      BuildContext context, Map<String, dynamic> data) {
    final message = 'Key exchange request accepted!';

    showLocalNotification(
      context,
      message,
      backgroundColor: Colors.green,
    );

    _showBackgroundNotification(
      'Key Exchange Accepted',
      message,
      'key_exchange_accepted',
      data,
    );

    _updateBadgeCounts(context, keyExchangeCount: -1);
  }

  /// Handle new message received
  void handleNewMessageReceived(
      BuildContext context, Map<String, dynamic> data) {
    final senderId = data['senderId'] ?? 'Unknown User';
    final message = data['body'] ?? 'New message';

    final displayMessage = 'New message from ${senderId.substring(0, 8)}...';

    showLocalNotification(
      context,
      displayMessage,
      backgroundColor: Colors.blue,
      action: SnackBarAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Navigate to chat screen
          final conversationId = data['conversationId'];
          if (conversationId != null) {
            Navigator.of(context).pushNamed('/chat/$conversationId');
          }
        },
      ),
    );

    _showBackgroundNotification(
      'New Message',
      displayMessage,
      'new_message',
      data,
    );

    _updateBadgeCounts(context, chatCount: 1);
  }

  /// Handle conversation created
  void handleConversationCreated(
      BuildContext context, Map<String, dynamic> data) {
    final message = 'New conversation created!';

    showLocalNotification(
      context,
      message,
      backgroundColor: Colors.green,
    );

    _showBackgroundNotification(
      'New Conversation',
      message,
      'conversation_created',
      data,
    );
  }

  /// Handle socket connection status changes
  void handleConnectionStatusChange(
      BuildContext context, bool isConnected, String status) {
    if (!isConnected) {
      final message = 'Connection lost: $status';

      showLocalNotification(
        context,
        message,
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            // Trigger reconnection
            // This will be handled by the socket service
          },
        ),
      );
    } else {
      showLocalNotification(
        context,
        'Connected to SeChat',
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Show background notification with proper badge counting
  void _showBackgroundNotification(
      String title, String body, String type, Map<String, dynamic> data) {
    // Get current badge counts
    final currentBadgeCount = _getCurrentBadgeCount();

    showPushNotification(
      title: title,
      body: body,
      payload: type,
      badgeNumber: currentBadgeCount + 1,
    );
  }

  /// Update badge counts using IndicatorService
  void _updateBadgeCounts(
    BuildContext context, {
    int? chatCount,
    int? keyExchangeCount,
    int? notificationCount,
  }) {
    try {
      final indicatorService =
          Provider.of<IndicatorService>(context, listen: false);

      if (chatCount != null) {
        indicatorService.updateCounts(
            unreadChats: indicatorService.unreadChatsCount + chatCount);
      }

      if (keyExchangeCount != null) {
        indicatorService.updateCounts(
            pendingKeyExchange:
                indicatorService.pendingKeyExchangeCount + keyExchangeCount);
      }

      if (notificationCount != null) {
        indicatorService.updateCounts(
            unreadNotifications:
                indicatorService.unreadNotificationsCount + notificationCount);
      }

      print('🔔 SocketNotificationService: ✅ Badge counts updated');
    } catch (e) {
      print(
          '🔔 SocketNotificationService: ❌ Failed to update badge counts: $e');
    }
  }

  /// Get current total badge count
  int _getCurrentBadgeCount() {
    // This would typically get the current badge count from the system
    // For now, return a default value
    return 0;
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    if (!_isInitialized) return;

    try {
      await _localNotifications.cancelAll();
      print('🔔 SocketNotificationService: ✅ All notifications cleared');
    } catch (e) {
      print('🔔 SocketNotificationService: ✅ All notifications cleared');
    }
  }
}
