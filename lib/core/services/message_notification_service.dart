import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '/..//../core/utils/logger.dart';

/// Service for handling push notifications for received messages
class MessageNotificationService {
  static final MessageNotificationService _instance =
      MessageNotificationService._internal();
  factory MessageNotificationService() => _instance;
  MessageNotificationService._internal();

  static MessageNotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request notification permissions
      await _requestPermissions();

      // Note: We don't initialize FlutterLocalNotificationsPlugin here
      // because LocalNotificationBadgeService already initializes it with the tap handler
      // We just use the same instance that's already initialized

      _isInitialized = true;
      Logger.debug(
          '🔔 MessageNotificationService: ✅ Initialized successfully (using shared plugin instance)');
    } catch (e) {
      Logger.error(' MessageNotificationService:  Failed to initialize: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      // Request notification permission
      final status = await Permission.notification.request();
      if (status.isGranted) {
        Logger.success(
            ' MessageNotificationService:  Notification permission granted');
      } else {
        Logger.warning(
            ' MessageNotificationService:  Notification permission denied');
      }
    } catch (e) {
      Logger.error(
          ' MessageNotificationService:  Error requesting permissions: $e');
    }
  }

  /// Show push notification for received message
  Future<void> showMessageNotification({
    required String messageId,
    required String senderName,
    required String messageContent,
    required String conversationId,
    required bool isEncrypted,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Always show encrypted message text for privacy
      String displayContent = 'Has Sent You An Encrypted Message';

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'message_channel',
        'Message Notifications',
        channelDescription: 'Notifications for received messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        messageId.hashCode, // Use message ID hash as notification ID
        senderName,
        displayContent,
        platformChannelSpecifics,
        payload: jsonEncode({
          'type': 'new_message',
          'conversationId': conversationId,
          'messageId': messageId,
          'senderName': senderName,
        }), // Pass JSON payload with type and conversation ID
      );

      Logger.success(
          ' MessageNotificationService:  Message notification shown for: $senderName');
    } catch (e) {
      Logger.error(
          ' MessageNotificationService:  Failed to show message notification: $e');
    }
  }

  // Note: Notification tap handling is done by LocalNotificationBadgeService

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
      Logger.success(
          ' MessageNotificationService:  All notifications cancelled');
    } catch (e) {
      Logger.error(
          ' MessageNotificationService:  Failed to cancel notifications: $e');
    }
  }

  /// Cancel specific notification
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(notificationId);
      Logger.success(
          ' MessageNotificationService:  Notification cancelled: $notificationId');
    } catch (e) {
      Logger.error(
          ' MessageNotificationService:  Failed to cancel notification: $e');
    }
  }

  // Note: Navigation is handled by LocalNotificationBadgeService
}
