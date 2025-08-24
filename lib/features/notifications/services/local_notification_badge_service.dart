import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'local_notification_database_service.dart';
import '../../../core/services/indicator_service.dart';

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

      // Force reset the indicator service count first to clear any old values
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(unreadNotifications: 0);

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
    // Handle navigation based on notification type
    // This will be implemented based on your navigation needs
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

      // Update the IndicatorService with the new count
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(
        unreadNotifications: unreadCount,
      );

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

      // Force badge count to zero
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

      // Only update badge count if there are notifications after cleanup
      final unreadCount = await getUnreadCount();
      if (unreadCount > 0) {
        await updateBadgeCount();
      } else {
        // Ensure badge is cleared if no notifications remain
        final indicatorService = IndicatorService();
        indicatorService.updateCountsWithContext(unreadNotifications: 0);
      }

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
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        notificationDetails,
        payload: payload?.toString(),
      );

      print(
          '📱 LocalNotificationBadgeService: ✅ KER notification shown: $title');
    } catch (e) {
      print(
          '📱 LocalNotificationBadgeService: ❌ Failed to show KER notification: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _isInitialized = false;
    print('📱 LocalNotificationBadgeService: ✅ Disposed');
  }
}
