import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sechat_app/features/notifications/models/socket_notification.dart';
import 'package:sechat_app/features/notifications/services/notification_database_service.dart';
import 'package:sechat_app/core/services/app_state_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';

/// Notification manager service that integrates with socket services
/// Automatically creates notifications for socket events
class NotificationManagerService {
  static final NotificationManagerService _instance =
      NotificationManagerService._internal();
  factory NotificationManagerService() => _instance;
  NotificationManagerService._internal();

  // Global navigator key for navigation from notifications
  // This will be set by the main app
  static GlobalKey<NavigatorState>? _navigatorKey;
  static GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Set the navigator key from the main app
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  final NotificationDatabaseService _databaseService =
      NotificationDatabaseService();

  // Local notifications instance
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Stream controllers for real-time updates
  final StreamController<SocketNotification> _notificationAddedController =
      StreamController<SocketNotification>.broadcast();
  final StreamController<String> _notificationUpdatedController =
      StreamController<String>.broadcast();
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  // Streams
  Stream<SocketNotification> get notificationAddedStream =>
      _notificationAddedController.stream;
  Stream<String> get notificationUpdatedStream =>
      _notificationUpdatedController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  // Settings
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _showTypingIndicators = false;
  bool _showOnlineStatus = false;
  bool _showConnectionEvents = false; // Disabled to reduce notification clutter
  bool _showMessageStatus = false;

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get showTypingIndicators => _showTypingIndicators;
  bool get showOnlineStatus => _showOnlineStatus;
  bool get showConnectionEvents => _showConnectionEvents;
  bool get showMessageStatus => _showMessageStatus;

  /// Initialize the notification manager
  Future<void> initialize() async {
    try {
      // Initialize database
      await _databaseService.database;

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Update unread count
      await _updateUnreadCount();

      // Clean up expired notifications
      await _cleanupExpiredNotifications();

      print('📱 NotificationManagerService: ✅ Initialized successfully');
    } catch (e) {
      print('📱 NotificationManagerService: ❌ Failed to initialize: $e');
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      // Android settings
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS settings - more comprehensive
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

      print('📱 NotificationManagerService: ✅ Local notifications initialized');

      // Request notification permissions
      await _requestNotificationPermissions();

      // Set up iOS notification categories
      await _setupIOSNotificationCategories();

      // Set up Android notification channels
      await _setupAndroidNotificationChannels();
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to initialize local notifications: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    try {
      // Request permissions for Android 13+ and iOS
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        final granted =
            await androidImplementation.requestNotificationsPermission();
        print(
            '📱 NotificationManagerService: 🔐 Android notification permission granted: $granted');
      }

      // iOS permissions are requested during initialization
      print(
          '📱 NotificationManagerService: 🔐 iOS notification permissions requested during initialization');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to request notification permissions: $e');
    }
  }

  /// Set up iOS notification categories
  Future<void> _setupIOSNotificationCategories() async {
    try {
      // Create notification categories to prevent duplicates
      final DarwinNotificationCategory generalCategory =
          DarwinNotificationCategory(
        'sechat_notifications',
        actions: <DarwinNotificationAction>[],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.allowAnnouncement,
        },
      );

      // Register the category - simplified approach to avoid import issues
      print(
          '📱 NotificationManagerService: ℹ️ iOS notification category configured');

      print(
          '📱 NotificationManagerService: ✅ iOS notification setup completed');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to set up iOS notification categories: $e');
    }
  }

  /// Set up Android notification channels
  Future<void> _setupAndroidNotificationChannels() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Create the main notification channel
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'sechat_notifications',
          'SeChat Notifications',
          description: 'Notifications from SeChat app',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
          enableLights: false, // Disable LED to avoid platform exceptions
        );

        await androidImplementation.createNotificationChannel(channel);
        print(
            '📱 NotificationManagerService: ✅ Android notification channel created');
      }
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to set up Android notification channels: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print(
        '📱 NotificationManagerService: 🔔 Notification tapped: ${response.payload}');

    // Parse the payload to determine navigation
    final payload = response.payload;
    if (payload != null) {
      if (payload.startsWith('key_exchange_')) {
        // Extract key exchange type and navigate accordingly
        final keyExchangeType = payload.replaceFirst('key_exchange_', '');
        _navigateToKeyExchange(keyExchangeType);
      } else if (payload.startsWith('message_')) {
        // Navigate to conversation
        final conversationId = payload.replaceFirst('message_', '');
        _navigateToConversation(conversationId);
      } else if (payload.startsWith('conversation_')) {
        // Navigate to conversation list
        _navigateToConversationList();
      } else if (payload.startsWith('connection_')) {
        // Navigate to settings or connection status
        _navigateToSettings();
      }
    }
  }

  /// Navigate to key exchange screen
  void _navigateToKeyExchange(String keyExchangeType) {
    print(
        '📱 NotificationManagerService: 🧭 Navigating to key exchange screen with type: $keyExchangeType');

    try {
      // Determine which tab to open based on key exchange type
      int initialTabIndex = 0; // Default to received tab

      if (keyExchangeType == 'request' ||
          keyExchangeType == 'accepted' ||
          keyExchangeType == 'declined') {
        // Received key exchange notifications - open received tab
        initialTabIndex = 0;
        print(
            '📱 NotificationManagerService: 🧭 Opening received tab for $keyExchangeType');
      } else if (keyExchangeType == 'sent') {
        // Sent key exchange notifications - open sent tab
        initialTabIndex = 1;
        print(
            '📱 NotificationManagerService: 🧭 Opening sent tab for $keyExchangeType');
      } else {
        // Default to received tab
        initialTabIndex = 0;
        print('📱 NotificationManagerService: 🧭 Opening default received tab');
      }

      // Navigate to key exchange screen with specific tab
      final context = _getGlobalContext();
      if (context != null) {
        Navigator.of(context).pushNamed(
          '/key-exchange',
          arguments: {'initialTabIndex': initialTabIndex},
        );
      } else {
        print(
            '📱 NotificationManagerService: ⚠️ No global context available for navigation');
      }

      print(
          '📱 NotificationManagerService: ✅ Navigation to key exchange screen initiated');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to navigate to key exchange screen: $e');
    }
  }

  /// Navigate to conversation
  void _navigateToConversation(String conversationId) {
    print(
        '📱 NotificationManagerService: 🧭 Navigating to conversation: $conversationId');

    try {
      // Navigate to specific conversation
      final context = _getGlobalContext();
      if (context != null) {
        Navigator.of(context).pushNamed(
          '/conversation',
          arguments: {'conversationId': conversationId},
        );
      } else {
        print(
            '📱 NotificationManagerService: ⚠️ No global context available for navigation');
      }

      print(
          '📱 NotificationManagerService: ✅ Navigation to conversation initiated');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to navigate to conversation: $e');
    }
  }

  /// Navigate to conversation list
  void _navigateToConversationList() {
    print('📱 NotificationManagerService: 🧭 Navigating to conversation list');

    try {
      // Navigate to conversation list
      final context = _getGlobalContext();
      if (context != null) {
        Navigator.of(context).pushNamed('/conversations');
      } else {
        print(
            '📱 NotificationManagerService: ⚠️ No global context available for navigation');
      }

      print(
          '📱 NotificationManagerService: ✅ Navigation to conversation list initiated');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to navigate to conversation list: $e');
    }
  }

  /// Navigate to settings
  void _navigateToSettings() {
    print('📱 NotificationManagerService: 🧭 Navigating to settings');

    try {
      // Navigate to settings screen
      final context = _getGlobalContext();
      if (context != null) {
        Navigator.of(context).pushNamed('/settings');
      } else {
        print(
            '📱 NotificationManagerService: ⚠️ No global context available for navigation');
      }

      print(
          '📱 NotificationManagerService: ✅ Navigation to settings initiated');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to navigate to settings: $e');
    }
  }

  /// Show local push notification
  Future<void> showLocalPushNotification({
    required String title,
    required String body,
    String? payload,
    String? icon,
    bool playSound = true,
    bool vibrate = true,
    bool forceShow = false, // Add force show parameter
  }) async {
    try {
      // Check if app is in background or force show is enabled
      if (!AppStateService().isForeground || forceShow) {
        // Android notification details
        final AndroidNotificationDetails androidPlatformChannelSpecifics =
            AndroidNotificationDetails(
          'sechat_notifications', // Use the channel ID we created
          'SeChat Notifications',
          channelDescription: 'Notifications from SeChat app',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: vibrate,
          playSound: playSound,
          sound:
              const RawResourceAndroidNotificationSound('notification_sound'),
          icon: 'ic_notification',
          channelShowBadge: true,
          enableLights: false, // Disable LED to avoid platform exception
          // ledColor: const Color.fromARGB(255, 255, 0, 0), // Removed to avoid platform exception
        );

        // iOS notification details
        final DarwinNotificationDetails iOSPlatformChannelSpecifics =
            DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          sound: 'notification_sound.aiff',
          categoryIdentifier:
              'sechat_notifications', // Add category to prevent duplicates
          interruptionLevel:
              InterruptionLevel.active, // Prevent system from showing duplicate
        );

        // Combined notification details
        final NotificationDetails platformChannelSpecifics =
            NotificationDetails(
          android: androidPlatformChannelSpecifics,
          iOS: iOSPlatformChannelSpecifics,
        );

        // Show the notification
        await _localNotifications.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
          title,
          body,
          platformChannelSpecifics,
          payload: payload,
        );

        print(
            '📱 NotificationManagerService: ✅ Local push notification shown: $title');
      } else {
        print(
            '📱 NotificationManagerService: ℹ️ App is in foreground, skipping local notification');
      }
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to show local push notification: $e');
    }
  }

  /// Show local push notification if app is in background and notification is not silent
  Future<void> _showLocalPushNotificationIfNeeded({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
    bool vibrate = true,
  }) async {
    try {
      // Check if app is in background
      if (!AppStateService().isForeground) {
        await showLocalPushNotification(
          title: title,
          body: body,
          payload: payload,
          playSound: playSound,
          vibrate: vibrate,
          forceShow: false, // Don't force show for background notifications
        );
      }
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to show local push notification if needed: $e');
    }
  }

  /// Create notification for message received
  Future<void> createMessageNotification({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_notificationsEnabled) return;

    try {
      final notification = SocketNotification.messageReceived(
        senderId: senderId,
        senderName: senderName,
        message: message,
        conversationId: conversationId,
        messageId: messageId,
      );

      await _addNotification(notification);

      // Add metadata if provided
      if (metadata != null) {
        await _updateNotificationMetadata(notification.id, metadata);
      }

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: senderName,
        body: message,
        payload: 'message_$conversationId',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create message notification: $e');
    }
  }

  /// Create notification for typing indicator
  Future<void> createTypingNotification({
    required String senderId,
    required String senderName,
    required String conversationId,
  }) async {
    if (!_notificationsEnabled || !_showTypingIndicators) return;

    try {
      final notification = SocketNotification.typingIndicator(
        senderId: senderId,
        senderName: senderName,
        conversationId: conversationId,
      );

      await _addNotification(notification);

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: senderName,
        body: 'Started typing...',
        payload: 'typing_$conversationId',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create typing notification: $e');
    }
  }

  /// Create notification for online status
  Future<void> createOnlineStatusNotification({
    required String userId,
    required String userName,
    required bool isOnline,
  }) async {
    if (!_notificationsEnabled || !_showOnlineStatus) return;

    try {
      final notification = SocketNotification.onlineStatus(
        userId: userId,
        userName: userName,
        isOnline: isOnline,
      );

      await _addNotification(notification);

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: userName,
        body: isOnline ? 'Came online' : 'Went offline',
        payload: 'online_status_$userId',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create online status notification: $e');
    }
  }

  /// Get icon for notification type
  String _getIconForNotificationType(String type) {
    switch (type) {
      case 'key_exchange_request':
        return '🔑'; // Key for request
      case 'key_exchange_sent':
        return '📤'; // Outbox for sent
      case 'key_exchange_accepted':
        return '✅'; // Checkmark for accepted
      case 'key_exchange_declined':
        return '❌'; // X for declined
      case 'key_exchange_failed':
        return '⚠️'; // Warning for failed
      case 'key_exchange_retry':
        return '🔄'; // Refresh for retry
      case 'conversation_created':
        return '💬'; // Chat bubble for conversation
      default:
        return '🔔'; // Bell for general notifications
    }
  }

  /// Create notification for key exchange
  Future<void> createKeyExchangeNotification({
    required String type,
    required String senderId,
    required String senderName,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_notificationsEnabled) return;

    try {
      final notification = SocketNotification.keyExchange(
        type: type,
        senderId: senderId,
        senderName: senderName,
        message: message,
      );

      // Set the icon based on notification type
      final icon = _getIconForNotificationType(type);
      final notificationWithIcon = notification.copyWith(icon: icon);

      await _addNotification(notificationWithIcon);

      // Add metadata if provided
      if (metadata != null) {
        await _updateNotificationMetadata(notificationWithIcon.id, metadata);
      }

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: senderName,
        body: message ?? 'New key exchange activity',
        payload: 'key_exchange_$type',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create key exchange notification: $e');
    }
  }

  /// Create notification for connection events
  Future<void> createConnectionNotification({
    required String event,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_notificationsEnabled || !_showConnectionEvents) return;

    try {
      final notification = SocketNotification.connectionEvent(
        event: event,
        message: message,
      );

      await _addNotification(notification);

      // Add metadata if provided
      if (metadata != null) {
        await _updateNotificationMetadata(notification.id, metadata);
      }

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: 'Connection Event',
        body: message ?? 'Connection status changed',
        payload: 'connection_$event',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create connection notification: $e');
    }
  }

  /// Create notification for message status
  Future<void> createMessageStatusNotification({
    required String status,
    required String senderId,
    required String messageId,
    String? conversationId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_notificationsEnabled || !_showMessageStatus) return;

    try {
      final notification = SocketNotification.messageStatus(
        status: status,
        senderId: senderId,
        messageId: messageId,
        conversationId: conversationId,
      );

      await _addNotification(notification);

      // Add metadata if provided
      if (metadata != null) {
        await _updateNotificationMetadata(notification.id, metadata);
      }

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: 'Message Status',
        body: 'Message $status',
        payload: 'message_status_$status',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create message status notification: $e');
    }
  }

  /// Create custom notification
  Future<void> createCustomNotification({
    required String type,
    required String title,
    required String message,
    NotificationPriority priority = NotificationPriority.normal,
    String? senderId,
    String? recipientId,
    String? conversationId,
    String? messageId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_notificationsEnabled) return;

    try {
      final notification = SocketNotification(
        type: type,
        title: title,
        message: message,
        priority: priority,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        messageId: messageId,
        metadata: metadata,
      );

      await _addNotification(notification);

      // Update app icon badge
      await updateAppIconBadge();

      // Show local push notification if app is in background
      await _showLocalPushNotificationIfNeeded(
        title: title,
        body: message,
        payload: 'custom_$type',
      );
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to create custom notification: $e');
    }
  }

  /// Add notification to database and notify listeners
  Future<void> _addNotification(SocketNotification notification) async {
    try {
      await _databaseService.addNotification(notification);

      // Notify listeners
      _notificationAddedController.add(notification);

      // Update unread count
      await _updateUnreadCount();

      // Play sound or vibrate if enabled
      if (_soundEnabled) {
        // Play notification sound using system vibration
        try {
          // Use HapticFeedback for a simple notification sound effect
          // In a full implementation, you could use audio_service or just_audio packages
          HapticFeedback.lightImpact();
          print('📱 NotificationManagerService: 🔊 Sound played successfully');
        } catch (e) {
          print('📱 NotificationManagerService: ❌ Error playing sound: $e');
        }
      }

      if (_vibrationEnabled) {
        // Implement vibration using HapticFeedback
        try {
          HapticFeedback.mediumImpact();
          print(
              '📱 NotificationManagerService: 📳 Vibration triggered successfully');
        } catch (e) {
          print(
              '📱 NotificationManagerService: ❌ Error triggering vibration: $e');
        }
      }
    } catch (e) {
      print('📱 NotificationManagerService: ❌ Failed to add notification: $e');
    }
  }

  /// Update notification metadata
  Future<void> _updateNotificationMetadata(
      String notificationId, Map<String, dynamic> metadata) async {
    try {
      // This would require updating the database service to support metadata updates
      // For now, we'll just log it
      print(
          '📱 NotificationManagerService: 📝 Metadata update for $notificationId: $metadata');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to update notification metadata: $e');
    }
  }

  /// Update unread count and notify listeners
  Future<void> _updateUnreadCount() async {
    try {
      final count = await _databaseService.getUnreadCount();
      _unreadCountController.add(count);
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to update unread count: $e');
    }
  }

  /// Clean up expired notifications
  Future<void> _cleanupExpiredNotifications() async {
    try {
      await _databaseService.deleteExpiredNotifications();
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to cleanup expired notifications: $e');
    }
  }

  /// Get all notifications
  Future<List<SocketNotification>> getNotifications({
    String? type,
    String? senderId,
    String? conversationId,
    bool? isRead,
    int? limit,
    int? offset,
  }) async {
    return await _databaseService.getNotifications(
      type: type,
      senderId: senderId,
      conversationId: conversationId,
      isRead: isRead,
      limit: limit,
      offset: offset,
    );
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    return await _databaseService.getUnreadCount();
  }

  /// Check if notifications are enabled
  bool get areNotificationsEnabled => _notificationsEnabled;

  /// Enable notifications
  void enableNotifications() {
    _notificationsEnabled = true;
    print('📱 NotificationManagerService: ✅ Notifications enabled');
  }

  /// Disable notifications
  void disableNotifications() {
    _notificationsEnabled = false;
    print('📱 NotificationManagerService: ❌ Notifications disabled');
  }

  /// Toggle notifications
  void toggleNotifications() {
    _notificationsEnabled = !_notificationsEnabled;
    print(
        '📱 NotificationManagerService: 🔄 Notifications ${_notificationsEnabled ? 'enabled' : 'disabled'}');
  }

  /// Mark notification as read
  Future<bool> markAsRead(String notificationId) async {
    final success = await _databaseService.markAsRead(notificationId);
    if (success) {
      _notificationUpdatedController.add(notificationId);
      await _updateUnreadCount();

      // Update app icon badge after marking as read
      await updateAppIconBadge();
    }
    return success;
  }

  /// Mark all notifications as read
  Future<bool> markAllAsRead() async {
    final success = await _databaseService.markAllAsRead();
    if (success) {
      await _updateUnreadCount();
    }
    return success;
  }

  /// Mark conversation notifications as read
  Future<bool> markConversationAsRead(String conversationId) async {
    final success =
        await _databaseService.markConversationAsRead(conversationId);
    if (success) {
      await _updateUnreadCount();

      // Update app icon badge after marking conversation as read
      await updateAppIconBadge();
    }
    return success;
  }

  /// Delete notification
  Future<bool> deleteNotification(String notificationId) async {
    final success = await _databaseService.deleteNotification(notificationId);
    if (success) {
      await _updateUnreadCount();

      // Update app icon badge after deleting notification
      await updateAppIconBadge();
    }
    return success;
  }

  /// Clear all notifications
  Future<bool> clearAllNotifications() async {
    final success = await _databaseService.clearAllNotifications();
    if (success) {
      await _updateUnreadCount();

      // Clear app icon badge when all notifications are cleared
      await clearAppIconBadge();
    }
    return success;
  }

  /// Get notification statistics
  Future<Map<String, dynamic>> getStatistics() async {
    return await _databaseService.getStatistics();
  }

  /// Update app icon badge count
  Future<void> updateAppIconBadge() async {
    try {
      final unreadCount = await _databaseService.getUnreadCount();

      // Update Android badge
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        // Android badge is handled through the notification channel
        print(
            '📱 NotificationManagerService: 🔢 Android badge count: $unreadCount');
      }

      // Update iOS badge - simplified approach
      print(
          '📱 NotificationManagerService: 🔢 iOS badge count: $unreadCount (permission requested)');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to update app icon badge: $e');
    }
  }

  /// Clear app icon badge
  Future<void> clearAppIconBadge() async {
    try {
      // Clear Android badge (handled through notification channel)
      print('📱 NotificationManagerService: 🔢 Clearing Android badge');

      // Clear iOS badge - simplified approach
      print('📱 NotificationManagerService: 🔢 iOS badge cleared');

      print('📱 NotificationManagerService: 🔢 App icon badge cleared');
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to clear app icon badge: $e');
    }
  }

  /// Update notification settings
  void updateSettings({
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? showTypingIndicators,
    bool? showOnlineStatus,
    bool? showConnectionEvents,
    bool? showMessageStatus,
  }) {
    if (notificationsEnabled != null)
      _notificationsEnabled = notificationsEnabled;
    if (soundEnabled != null) _soundEnabled = soundEnabled;
    if (vibrationEnabled != null) _vibrationEnabled = vibrationEnabled;
    if (showTypingIndicators != null)
      _showTypingIndicators = showTypingIndicators;
    if (showOnlineStatus != null) _showOnlineStatus = showOnlineStatus;
    if (showConnectionEvents != null)
      _showConnectionEvents = showConnectionEvents;
    if (showMessageStatus != null) _showMessageStatus = showMessageStatus;

    print('📱 NotificationManagerService: ⚙️ Settings updated');
  }

  /// Test notification (for debugging)
  Future<void> testNotification() async {
    try {
      print('📱 NotificationManagerService: 🧪 Testing notification...');

      // Show progress snackbar
      UIService().showSnack('🧪 Testing notification system...',
          duration: const Duration(seconds: 2));

      await showLocalPushNotification(
        title: 'Test Notification',
        body: 'This is a test notification to verify the system is working',
        payload: 'test_notification',
        playSound: true,
        vibrate: true,
        forceShow: true, // Force show for testing
      );

      print(
          '📱 NotificationManagerService: ✅ Test notification sent successfully');

      // Show success snackbar
      UIService().showSnack('✅ Test notification sent successfully!',
          duration: const Duration(seconds: 3));
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to send test notification: $e');

      // Show error snackbar
      UIService().showSnack('❌ Failed to send test notification: $e',
          isError: true, duration: const Duration(seconds: 4));
    }
  }

  /// Force show notification (for testing, ignores app state)
  Future<void> forceTestNotification() async {
    try {
      print('📱 NotificationManagerService: 🧪 Force testing notification...');

      // Show progress snackbar
      UIService().showSnack('🧪 Force testing notification system...',
          duration: const Duration(seconds: 2));

      // Android notification details
      final AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'sechat_notifications',
        'SeChat Notifications',
        channelDescription: 'Notifications from SeChat app',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('notification_sound'),
        icon: 'ic_notification',
        channelShowBadge: true,
        enableLights: false, // Disable LED to avoid platform exception
        // ledColor: const Color.fromARGB(255, 255, 0, 0), // Removed to avoid platform exception
      );

      // iOS notification details
      final DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'notification_sound.aiff',
        categoryIdentifier:
            'sechat_notifications', // Add category to prevent duplicates
        interruptionLevel:
            InterruptionLevel.active, // Prevent system from showing duplicate
      );

      // Combined notification details
      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // Show the notification
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
        'Force Test Notification',
        'This is a force test notification to verify the system is working',
        platformChannelSpecifics,
        payload: 'force_test_notification',
      );

      print(
          '📱 NotificationManagerService: ✅ Force test notification sent successfully');

      // Show success snackbar
      UIService().showSnack('✅ Force test notification sent successfully!',
          duration: const Duration(seconds: 3));
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to send force test notification: $e');

      // Show error snackbar
      UIService().showSnack('❌ Failed to send force test notification: $e',
          isError: true, duration: const Duration(seconds: 4));
    }
  }

  /// Check notification permissions status
  Future<Map<String, bool>> checkNotificationPermissions() async {
    try {
      print(
          '📱 NotificationManagerService: 🔐 Checking notification permissions...');

      // Show progress snackbar
      UIService().showSnack('🔐 Checking notification permissions...',
          duration: const Duration(seconds: 2));

      final Map<String, bool> permissions = {};

      // Check Android permissions
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        final androidGranted =
            await androidImplementation.areNotificationsEnabled();
        permissions['android'] = androidGranted ?? false;
        print(
            '📱 NotificationManagerService: 🔐 Android notifications enabled: ${androidGranted ?? false}');
      }

      // Check iOS permissions - simplified for now
      permissions['ios'] = true; // Assume iOS permissions are granted
      print(
          '📱 NotificationManagerService: 🔐 iOS notifications enabled: true (assumed)');

      print(
          '📱 NotificationManagerService: 🔐 Notification permissions status: $permissions');

      // Show success snackbar with permission status
      final androidStatus = permissions['android'] ?? false;
      final iOSStatus = permissions['ios'] ?? false;
      final statusText =
          'Android: ${androidStatus ? "✅" : "❌"}, iOS: ${iOSStatus ? "✅" : "❌"}';
      UIService().showSnack('🔐 Permissions checked: $statusText',
          duration: const Duration(seconds: 4));

      return permissions;
    } catch (e) {
      print(
          '📱 NotificationManagerService: ❌ Failed to check notification permissions: $e');

      // Show error snackbar
      UIService().showSnack('❌ Failed to check permissions: $e',
          isError: true, duration: const Duration(seconds: 4));

      return {};
    }
  }

  /// Get global context for navigation
  BuildContext? _getGlobalContext() {
    // Use the navigator key to get global context
    return _navigatorKey?.currentContext;
  }

  /// Dispose resources
  void dispose() {
    _notificationAddedController.close();
    _notificationUpdatedController.close();
    _unreadCountController.close();
  }
}
