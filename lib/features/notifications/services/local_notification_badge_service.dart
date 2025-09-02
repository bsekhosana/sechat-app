import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'local_notification_database_service.dart';
import '../models/local_notification_item.dart';
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

      // Create notification channels for Android (required for foreground notifications)
      await _createNotificationChannels();

      // Request notification permissions for Android
      await _requestNotificationPermissions();

      print(
          '📱 LocalNotificationBadgeService: 🔧 Notification tap handler registered: _onNotificationTapped');

      print(
          '📱 LocalNotificationBadgeService: ✅ Local notifications initialized');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to initialize local notifications: $e');
    }
  }

  /// Create notification channels for Android (required for foreground notifications)
  Future<void> _createNotificationChannels() async {
    try {
      // Create KER notifications channel
      const AndroidNotificationChannel kerChannel = AndroidNotificationChannel(
        'ker_notifications',
        'Key Exchange Requests',
        description: 'Notifications for key exchange requests',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,
        ledColor: Color(0xFFFF6B35),
      );

      // Create badge update channel
      const AndroidNotificationChannel badgeChannel =
          AndroidNotificationChannel(
        'badge_update',
        'Badge Update',
        description: 'Updates app badge count',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      );

      // Create message notifications channel
      const AndroidNotificationChannel messageChannel =
          AndroidNotificationChannel(
        'message_notifications',
        'Message Notifications',
        description: 'Notifications for new messages',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,
        ledColor: Color(0xFFFF6B35),
      );

      // Register channels
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(kerChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(badgeChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(messageChannel);

      print(
          '📱 LocalNotificationBadgeService: ✅ Notification channels created');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to create notification channels: $e');
    }
  }

  /// Request notification permissions for Android
  Future<void> _requestNotificationPermissions() async {
    try {
      // Request permissions for Android
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print(
            '📱 LocalNotificationBadgeService: 🔧 Android notification permission granted: $granted');

        if (granted == true) {
          // Also request exact alarm permission for Android 12+
          final exactAlarmGranted =
              await androidPlugin.requestExactAlarmsPermission();
          print(
              '📱 LocalNotificationBadgeService: 🔧 Android exact alarm permission granted: $exactAlarmGranted');
        }
      }
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to request notification permissions: $e');
    }
  }

  /// Check if app is currently in background
  Future<bool> _isAppInBackground() async {
    try {
      // Import WidgetsBinding to check app lifecycle state
      final binding = WidgetsBinding.instance;
      return binding.lifecycleState == AppLifecycleState.paused ||
          binding.lifecycleState == AppLifecycleState.detached;
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to check app state: $e');
      return false; // Default to foreground if we can't determine
    }
  }

  /// Create notification item in database
  Future<void> _createNotificationItem(
    String title,
    String body,
    String type,
    Map<String, dynamic>? payload,
  ) async {
    try {
      final databaseService = LocalNotificationDatabaseService();
      final notificationItem = LocalNotificationItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        description: body,
        type: type,
        icon: _getIconForType(type),
        status: 'unread',
        direction: 'incoming',
        metadata: payload,
        date: DateTime.now(),
      );
      await databaseService.insertNotification(notificationItem);
      print(
          '📱 LocalNotificationBadgeService: ✅ Notification item created in database');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to create notification item: $e');
    }
  }

  /// Get appropriate icon for notification type
  String _getIconForType(String type) {
    switch (type) {
      case 'key_exchange:request':
        return 'key';
      case 'key_exchange:accept':
        return 'check';
      case 'key_exchange:decline':
        return 'times';
      case 'message_received':
        return 'message';
      default:
        return 'bell';
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

  /// Show local push notification for messages
  Future<void> showMessageNotification({
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    try {
      // Check if app is in background - only increment notification count if in background
      final isInBackground = await _isAppInBackground();

      // Create notification details
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'message_notifications',
        'Message Notifications',
        channelDescription: 'Notifications for new messages',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color(0xFFFF6B35),
        fullScreenIntent: false,
        autoCancel: true,
        ongoing: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge:
            false, // Don't increment badge here - let IndicatorService handle it
        presentSound: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show the notification
      final notificationPayload = payload != null ? jsonEncode(payload) : null;
      print(
          '📱 LocalNotificationBadgeService: 🔧 Creating message notification with payload: $notificationPayload');
      print(
          '📱 LocalNotificationBadgeService: 🔧 App in background: $isInBackground');
      print(
          '📱 LocalNotificationBadgeService: 🔧 Notification details: $notificationDetails');

      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: notificationPayload,
      );

      print(
          '📱 LocalNotificationBadgeService: ✅ Message notification shown with ID: $notificationId');

      // Only create notification item in database if app is in background
      if (isInBackground) {
        await _createNotificationItem(title, body, type, payload);
        print(
            '📱 LocalNotificationBadgeService: ✅ Background message notification item created');
      } else {
        print(
            '📱 LocalNotificationBadgeService: ℹ️ Foreground message notification - no database item created');
      }

      print(
          '📱 LocalNotificationBadgeService: ✅ Message notification shown: $title');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to show message notification: $e');
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
      // Check if app is in background - only increment notification count if in background
      final isInBackground = await _isAppInBackground();

      // Create notification details
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'ker_notifications',
        'Key Exchange Requests',
        channelDescription: 'Notifications for key exchange requests',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color(0xFFFF6B35),
        fullScreenIntent: false,
        autoCancel: true,
        ongoing: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge:
            false, // Don't increment badge here - let IndicatorService handle it
        presentSound: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show the notification
      final notificationPayload = payload != null ? jsonEncode(payload) : null;
      print(
          '📱 LocalNotificationBadgeService: 🔧 Creating notification with payload: $notificationPayload');
      print(
          '📱 LocalNotificationBadgeService: 🔧 App in background: $isInBackground');
      print(
          '📱 LocalNotificationBadgeService: 🔧 Notification details: $notificationDetails');

      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: notificationPayload,
      );

      print(
          '📱 LocalNotificationBadgeService: ✅ Notification shown with ID: $notificationId');

      // Only create notification item in database if app is in background
      if (isInBackground) {
        await _createNotificationItem(title, body, type, payload);
        print(
            '📱 LocalNotificationBadgeService: ✅ Background notification item created');
      } else {
        print(
            '📱 LocalNotificationBadgeService: ℹ️ Foreground notification - no database item created');
      }

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

  /// Set app badge count to a specific number
  Future<void> setBadgeCount(int count) async {
    try {
      // Create notification details for badge update
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'badge_update',
        'Badge Update',
        channelDescription: 'Updates app badge count',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        enableVibration: false,
        playSound: false,
        silent: true,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: true,
        presentSound: false,
        badgeNumber: count,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show a silent notification to update badge
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '', // Empty title
        '', // Empty body
        notificationDetails,
        payload: 'badge_update',
      );

      // Immediately cancel the notification to keep it silent
      await _localNotifications.cancel(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
      );

      print(
          '📱 LocalNotificationBadgeService: ✅ App badge count set to: $count');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to set badge count: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _isInitialized = false;
    print('📱 LocalNotificationBadgeService: ✅ Disposed');
  }
}
