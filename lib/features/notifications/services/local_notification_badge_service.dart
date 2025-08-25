import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'local_notification_database_service.dart';
import '../../../core/services/indicator_service.dart';
import '../../../main.dart'; // Import to access global navigator key

/// Service for managing local notification badge counts
class LocalNotificationBadgeService {
  static final LocalNotificationBadgeService _instance =
      LocalNotificationBadgeService._internal();
  factory LocalNotificationBadgeService() => _instance;
  LocalNotificationBadgeService._internal();

  final LocalNotificationDatabaseService _databaseService =
      LocalNotificationDatabaseService();

  // Local notifications instance
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Timer? _cleanupTimer;
  bool _isInitialized = false;

  /// Initialize the badge service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize local notifications
      await _initializeLocalNotifications();

      // Set up automatic cleanup timer (every 24 hours)
      _cleanupTimer = Timer.periodic(
        const Duration(hours: 24),
        (_) => _performCleanup(),
      );

      // Perform initial cleanup
      await _performCleanup();

      // Note: Local notification items don't affect app badge counter
      // App badge is managed separately by push notifications

      // Only update badge count if there are actual notifications
      final unreadCount = await getUnreadCount();
      if (unreadCount > 0) {
        await updateBadgeCount();
      }

      _isInitialized = true;
      print(
          '📱 LocalNotificationBadgeService: ✅ Initialized successfully (unread count: $unreadCount)');
    } catch (e) {
      print('📱 LocalNotificationBadgeService: ❌ Failed to initialize: $e');
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      // Android settings
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS settings
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Combined initialization settings
      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      // Initialize the plugin
      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      print(
          '📱 LocalNotificationBadgeService: 🔧 Notification tap handler registered: _onNotificationTapped');

      print(
          '📱 LocalNotificationBadgeService: ✅ Local notifications initialized');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to initialize local notifications: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print(
        '📱 LocalNotificationBadgeService: 🔔 Notification tapped: ${response.payload}');

    // Handle deep linking based on notification type
    try {
      if (response.payload != null) {
        final payload = response.payload!;
        print('📱 LocalNotificationBadgeService: 🔍 Parsing payload: $payload');

        // Try to parse as JSON first
        try {
          final Map<String, dynamic> payloadMap = jsonDecode(payload);
          print(
              '📱 LocalNotificationBadgeService: 🔍 Parsed payload as JSON: $payloadMap');

          if (payloadMap['type'] == 'new_message') {
            final conversationId = payloadMap['conversationId'] as String?;
            if (conversationId != null && conversationId.isNotEmpty) {
              print(
                  '📱 LocalNotificationBadgeService: 🔍 Found conversation ID: $conversationId');
              _navigateToChatScreen(conversationId);
            } else {
              print(
                  '📱 LocalNotificationBadgeService: ⚠️ No conversation ID found in payload');
            }
          } else if (payloadMap['type'] == 'ker_received') {
            print(
                '📱 LocalNotificationBadgeService: 🔍 Navigating to key exchange screen');
            _navigateToKeyExchangeScreen();
          }
        } catch (jsonError) {
          print(
              '📱 LocalNotificationBadgeService: 🔍 Payload is not JSON, trying string parsing: $jsonError');

          // Fallback to string parsing for backward compatibility
          if (payload.contains('type=new_message')) {
            final conversationId = _extractConversationIdFromPayload(payload);
            if (conversationId != null) {
              _navigateToChatScreen(conversationId);
            }
          } else if (payload.contains('type=ker_received')) {
            _navigateToKeyExchangeScreen();
          }
        }
      }
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Error handling notification tap: $e');
    }
  }

  /// Extract conversation ID from notification payload
  String? _extractConversationIdFromPayload(String payload) {
    try {
      // Parse payload to extract conversationId
      if (payload.contains('conversationId=')) {
        final startIndex =
            payload.indexOf('conversationId=') + 'conversationId='.length;
        final endIndex = payload.indexOf(',', startIndex);
        if (endIndex == -1) {
          return payload.substring(startIndex);
        }
        return payload.substring(startIndex, endIndex);
      }
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Error extracting conversation ID: $e');
    }
    return null;
  }

  /// Navigate to chat screen with conversation ID
  void _navigateToChatScreen(String conversationId) {
    try {
      // Use the global navigator key from main.dart
      if (navigatorKey.currentContext != null) {
        // Navigate to chat screen with conversation ID
        Navigator.of(navigatorKey.currentContext!).pushNamed(
          '/chat',
          arguments: {'conversationId': conversationId},
        );
        print(
            '📱 LocalNotificationBadgeService: ✅ Navigated to chat screen: $conversationId');
      }
    } catch (e) {
      print('📱 LocalNotificationBadgeService: ❌ Error navigating to chat: $e');
    }
  }

  /// Navigate to key exchange screen
  void _navigateToKeyExchangeScreen() {
    try {
      // Use the global navigator key from main.dart
      if (navigatorKey.currentContext != null) {
        // Navigate to key exchange screen
        Navigator.of(navigatorKey.currentContext!).pushNamed('/key-exchange');
        print(
            '📱 LocalNotificationBadgeService: ✅ Navigated to key exchange screen');
      }
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ✅ Navigated to key exchange screen');
    }
  }

  /// Get current unread count
  Future<int> getUnreadCount() async {
    try {
      final count = await _databaseService.getUnreadCount();
      print(
          '📱 LocalNotificationBadgeService: 🔍 getUnreadCount() called, returning: $count');
      return count;
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to get unread count: $e');
      return 0;
    }
  }

  /// Update badge count and notify IndicatorService
  Future<void> updateBadgeCount() async {
    try {
      final unreadCount = await getUnreadCount();

      // Update the indicator service with the new count
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(
          unreadNotifications: unreadCount);

      print(
          '📱 LocalNotificationBadgeService: ✅ Badge count updated: $unreadCount');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to update badge count: $e');
    }
  }

  /// Mark notification as read and update badge
  Future<void> markAsReadAndUpdateBadge(String notificationId) async {
    try {
      await _databaseService.markAsRead(notificationId);
      await updateBadgeCount();
      print(
          '📱 LocalNotificationBadgeService: ✅ Notification marked as read and badge updated');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to mark as read and update badge: $e');
    }
  }

  /// Mark multiple notifications as read and update badge
  Future<void> markMultipleAsReadAndUpdateBadge(
      List<String> notificationIds) async {
    try {
      for (final id in notificationIds) {
        await _databaseService.markAsRead(id);
      }
      await updateBadgeCount();
      print(
          '📱 LocalNotificationBadgeService: ✅ Multiple notifications marked as read and badge updated');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to mark multiple as read and update badge: $e');
    }
  }

  /// Mark all notifications as read and update badge
  Future<void> markAllAsReadAndUpdateBadge() async {
    try {
      final unreadNotifications =
          await _databaseService.getUnreadNotifications();
      final unreadIds = unreadNotifications.map((n) => n.id).toList();

      for (final id in unreadIds) {
        await _databaseService.markAsRead(id);
      }

      await updateBadgeCount();
      print(
          '📱 LocalNotificationBadgeService: ✅ All notifications marked as read and badge updated');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to mark all as read and update badge: $e');
    }
  }

  /// Clear all notifications and update badge
  Future<void> clearAllAndUpdateBadge() async {
    try {
      await _databaseService.clearAllNotifications();

      // Update the indicator service to reflect that all notifications are cleared
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(unreadNotifications: 0);

      print(
          '📱 LocalNotificationBadgeService: ✅ All notifications cleared and badge reset to 0');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to clear all and update badge: $e');
    }
  }

  /// Perform cleanup of old notifications
  Future<void> _performCleanup() async {
    try {
      await _databaseService.clearOldNotifications(30);

      // Get the current unread count after cleanup
      final unreadCount = await getUnreadCount();

      // Update the indicator service with the new count
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(
          unreadNotifications: unreadCount);

      print(
          '📱 LocalNotificationBadgeService: ✅ Cleanup completed (unread count: $unreadCount)');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to perform cleanup: $e');
    }
  }

  /// Force cleanup now
  Future<void> forceCleanup() async {
    try {
      await _performCleanup();
      print('📱 LocalNotificationBadgeService: ✅ Force cleanup completed');
    } catch (e) {
      print('📱 LocalNotificationBadgeService: ❌ Failed to force cleanup: $e');
    }
  }

  /// Force reset badge count and reinitialize
  Future<void> forceResetAndReinitialize() async {
    try {
      // Force reset the indicator service
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(unreadNotifications: 0);

      // Reset initialization flag to allow reinitialization
      _isInitialized = false;

      // Reinitialize
      await initialize();

      print(
          '📱 LocalNotificationBadgeService: ✅ Force reset and reinitialization completed');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to force reset and reinitialize: $e');
    }
  }

  /// Show local push notification for KER events
  Future<void> showKerNotification({
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    try {
      // Get current unread count for badge
      final unreadCount = await getUnreadCount();

      // Create notification details
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'ker_notifications',
        'Key Exchange Requests',
        channelDescription: 'Notifications for key exchange requests',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: unreadCount + 1, // Increment badge
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show the notification
      final notificationPayload = payload != null ? jsonEncode(payload) : null;
      print(
          '📱 LocalNotificationBadgeService: 🔧 Creating notification with payload: $notificationPayload');

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        notificationDetails,
        payload: notificationPayload,
      );

      print(
          '📱 LocalNotificationBadgeService: ✅ KER notification shown: $title');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to show KER notification: $e');
    }
  }

  /// Reset app icon badge count to 0
  Future<void> resetBadgeCount() async {
    try {
      // Reset badge count on iOS
      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: true,
        presentSound: false,
        badgeNumber: 0, // Set badge to 0
      );

      // Show a silent notification to update the badge
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '', // Empty title
        '', // Empty body
        NotificationDetails(iOS: iosDetails),
        payload: 'badge_reset',
      );

      // Note: Local notification items don't affect app badge counter
      // App badge is managed separately by push notifications

      print('📱 LocalNotificationBadgeService: ✅ Badge count reset to 0');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to reset badge count: $e');
    }
  }

  /// Clear all notifications from device notification tray
  Future<void> clearAllDeviceNotifications() async {
    try {
      // Cancel all pending notifications
      await _localNotifications.cancelAll();

      print(
          '📱 LocalNotificationBadgeService: ✅ All device notifications cleared from tray');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to clear device notifications: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _isInitialized = false;
    print('📱 LocalNotificationBadgeService: ✅ Disposed');
  }
}
