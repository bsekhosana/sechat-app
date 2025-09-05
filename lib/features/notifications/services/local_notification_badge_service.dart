import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'local_notification_database_service.dart';
import '../models/local_notification_item.dart';
import '../../../core/services/indicator_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../features/chat/models/chat_conversation.dart';
import '../../../features/chat/providers/chat_list_provider.dart';
import '../../../features/chat/providers/unified_chat_provider.dart';
import '../../../features/chat/screens/unified_chat_screen.dart';
import '../../../main.dart'; // Import to access global navigator key
import 'package:sechat_app//../core/utils/logger.dart';

/// Service for managing local notification badge counts
class LocalNotificationBadgeService {
  static final LocalNotificationBadgeService _instance =
      LocalNotificationBadgeService._internal();
  factory LocalNotificationBadgeService() {
    Logger.info(
        '📱 LocalNotificationBadgeService: 🔧 Factory constructor called - returning instance: ${_instance.hashCode}');
    return _instance;
  }
  LocalNotificationBadgeService._internal() {
    Logger.info(
        '📱 LocalNotificationBadgeService: 🔧 Internal constructor called - instance: ${this.hashCode}');
  }

  final LocalNotificationDatabaseService _databaseService =
      LocalNotificationDatabaseService();

  // Local notifications instance
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Timer? _cleanupTimer;
  bool _isInitialized = false;

  /// Initialize the badge service
  Future<void> initialize() async {
    Logger.info(
        '📱 LocalNotificationBadgeService: 🔧 Initialize called - instance: ${this.hashCode}, already initialized: $_isInitialized');
    Logger.info(
        '📱 LocalNotificationBadgeService: 🔧 App lifecycle state: ${WidgetsBinding.instance.lifecycleState}');
    if (_isInitialized) {
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔧 Already initialized, skipping...');
      return;
    }

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
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔧 Marked as initialized - instance: ${this.hashCode}');
      Logger.debug(
          '📱 LocalNotificationBadgeService: ✅ Initialized successfully (unread count: $unreadCount)');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to initialize: $e');
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

      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 Notification tap handler registered: _onNotificationTapped');

      Logger.success(
          '📱 LocalNotificationBadgeService:  Local notifications initialized');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to initialize local notifications: $e');
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

      // Create badge reset channel
      const AndroidNotificationChannel badgeResetChannel =
          AndroidNotificationChannel(
        'badge_reset',
        'Badge Reset',
        description: 'Silent notification for badge reset',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
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

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(badgeResetChannel);

      Logger.success(
          '📱 LocalNotificationBadgeService:  Notification channels created');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to create notification channels: $e');
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
        Logger.debug(
            '📱 LocalNotificationBadgeService: 🔧 Android notification permission granted: $granted');

        // Note: Removed exact alarm permission request as we only need basic notifications
        // for chat messages, not scheduled alarms
      }
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to request notification permissions: $e');
    }
  }

  /// Check if app is currently in background
  Future<bool> _isAppInBackground() async {
    try {
      // Import WidgetsBinding to check app lifecycle state
      final binding = WidgetsBinding.instance;
      final isBackground = binding.lifecycleState == AppLifecycleState.paused ||
          binding.lifecycleState == AppLifecycleState.detached;

      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔍 App lifecycle state: ${binding.lifecycleState}, isBackground: $isBackground');
      return isBackground;
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to check app state: $e');
      return false; // Default to foreground if we can't determine
    }
  }

  /// Ensure notification channel exists
  Future<void> _ensureNotificationChannelExists(String channelId) async {
    try {
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Checking if channel $channelId exists...');
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Check if channel exists
        final existingChannels = await androidPlugin.getNotificationChannels();
        final channelExists =
            existingChannels?.any((channel) => channel.id == channelId) ??
                false;

        Logger.info(
            '📱 LocalNotificationBadgeService: 🔔 Channel $channelId exists: $channelExists');

        if (!channelExists) {
          Logger.warning(
              '📱 LocalNotificationBadgeService: ⚠️ Channel $channelId does not exist, creating it...');
          await _createNotificationChannels();
          Logger.info(
              '📱 LocalNotificationBadgeService: 🔔 Channel creation completed');
        } else {
          Logger.info(
              '📱 LocalNotificationBadgeService: ✅ Channel $channelId exists');
        }
      } else {
        Logger.warning(
            '📱 LocalNotificationBadgeService: ⚠️ Android plugin is null');
      }
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService: ❌ Failed to ensure channel exists: $e');
      Logger.error(
          '📱 LocalNotificationBadgeService: ❌ Error details: ${e.toString()}');
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
      Logger.success(
          '📱 LocalNotificationBadgeService:  Notification item created in database');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to create notification item: $e');
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
    Logger.debug(
        '📱 LocalNotificationBadgeService:  Notification tapped: ${response.payload}');

    // Handle deep linking based on notification type
    try {
      if (response.payload != null) {
        final payload = response.payload!;
        Logger.info(
            '📱 LocalNotificationBadgeService:  Parsing payload: $payload');

        // Handle special payloads that are not JSON
        if (payload == 'badge_update' || payload == 'badge_reset') {
          Logger.info(
              '📱 LocalNotificationBadgeService:  Badge update notification tapped - no action needed');
          return;
        }

        // Try to parse as JSON first
        try {
          final Map<String, dynamic> payloadMap = jsonDecode(payload);
          Logger.info(
              '📱 LocalNotificationBadgeService:  Parsed payload as JSON: $payloadMap');

          if (payloadMap['type'] == 'new_message') {
            final conversationId = payloadMap['conversationId'] as String?;
            if (conversationId != null && conversationId.isNotEmpty) {
              Logger.info(
                  '📱 LocalNotificationBadgeService:  Found conversation ID: $conversationId');
              _navigateToChatScreen(conversationId);
            } else {
              Logger.warning(
                  '📱 LocalNotificationBadgeService:  No conversation ID found in payload');
            }
          } else if (payloadMap['type'] == 'ker_received') {
            Logger.info(
                '📱 LocalNotificationBadgeService:  Navigating to key exchange screen');
            _navigateToKeyExchangeScreen();
          }
        } catch (jsonError) {
          Logger.info(
              '📱 LocalNotificationBadgeService:  Payload is not JSON, trying string parsing: $jsonError');

          // Fallback to string parsing for backward compatibility
          if (payload.contains('type=new_message')) {
            final conversationId = _extractConversationIdFromPayload(payload);
            if (conversationId != null) {
              _navigateToChatScreen(conversationId);
            }
          } else if (payload.contains('type=ker_received')) {
            _navigateToKeyExchangeScreen();
          } else {
            Logger.info(
                '📱 LocalNotificationBadgeService:  Unknown payload format: $payload');
          }
        }
      }
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error handling notification tap: $e');
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
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error extracting conversation ID: $e');
    }
    return null;
  }

  /// Navigate to chat screen with conversation ID
  void _navigateToChatScreen(String conversationId) {
    try {
      Logger.info(
          '📱 LocalNotificationBadgeService:  Attempting to navigate to conversation: $conversationId');

      // Use the global navigator key from main.dart
      final context = navigatorKey.currentContext;
      if (context == null) {
        Logger.error(
            '📱 LocalNotificationBadgeService:  No navigator context available');
        return;
      }
      Logger.success(
          '📱 LocalNotificationBadgeService:  Navigator context available');

      // Get the chat list provider to find the conversation
      final chatListProvider =
          Provider.of<ChatListProvider>(context, listen: false);

      // Find the conversation by ID
      ChatConversation? conversation;
      try {
        conversation = chatListProvider.conversations.firstWhere(
          (conv) => conv.id == conversationId,
        );
        Logger.success(
            '📱 LocalNotificationBadgeService:  Found conversation: ${conversation.id}');
      } catch (e) {
        Logger.warning(
            '📱 LocalNotificationBadgeService:  Conversation not found: $conversationId');
        return;
      }

      // Get the other participant ID (recipient)
      final currentUserId = _getCurrentUserId();
      final recipientId = conversation.getOtherParticipantId(currentUserId);
      if (recipientId.isEmpty) {
        Logger.error(
            '📱 LocalNotificationBadgeService:  Could not determine recipient ID');
        return;
      }
      Logger.success(
          '📱 LocalNotificationBadgeService:  Recipient ID: $recipientId');

      // Get recipient name from contact service
      String recipientName = recipientId; // Default to ID
      try {
        final contact = ContactService.instance.getContact(recipientId);
        if (contact != null && contact.displayName.isNotEmpty) {
          recipientName = contact.displayName;
        }
      } catch (e) {
        Logger.warning(
            '📱 LocalNotificationBadgeService:  Could not get recipient name: $e');
      }
      Logger.success(
          '📱 LocalNotificationBadgeService:  Recipient name: $recipientName');

      // Get online status
      final isOnline = chatListProvider.getRecipientOnlineStatus(recipientId);
      Logger.success(
          '📱 LocalNotificationBadgeService:  Online status: $isOnline');

      // Navigate to the chat screen using the same pattern as ChatListScreen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChangeNotifierProvider(
            create: (context) => UnifiedChatProvider(),
            child: UnifiedChatScreen(
              conversationId: conversationId,
              recipientId: recipientId,
              recipientName: recipientName,
              isOnline: isOnline,
            ),
          ),
        ),
      );

      Logger.success(
          '📱 LocalNotificationBadgeService:  Navigated to chat screen: $conversationId');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error navigating to chat: $e');
    }
  }

  /// Navigate to key exchange screen
  void _navigateToKeyExchangeScreen() {
    try {
      // Use the global navigator key from main.dart
      if (navigatorKey.currentContext != null) {
        // Navigate to key exchange screen
        Navigator.of(navigatorKey.currentContext!).pushNamed('/key-exchange');
        Logger.success(
            '📱 LocalNotificationBadgeService:  Navigated to key exchange screen');
      }
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error navigating to key exchange: $e');
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    try {
      final sessionService = SeSessionService();
      final currentSessionId = sessionService.currentSessionId;
      if (currentSessionId != null && currentSessionId.isNotEmpty) {
        return currentSessionId;
      }
      return 'unknown_user';
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error getting current user ID: $e');
      return 'unknown_user';
    }
  }

  /// Get current unread count
  Future<int> getUnreadCount() async {
    try {
      final count = await _databaseService.getUnreadCount();
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔍 getUnreadCount() called, returning: $count');
      return count;
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to get unread count: $e');
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

      Logger.success(
          '📱 LocalNotificationBadgeService:  Badge count updated: $unreadCount');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to update badge count: $e');
    }
  }

  /// Mark notification as read and update badge
  Future<void> markAsReadAndUpdateBadge(String notificationId) async {
    try {
      await _databaseService.markAsRead(notificationId);
      await updateBadgeCount();
      Logger.success(
          '📱 LocalNotificationBadgeService:  Notification marked as read and badge updated');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to mark as read and update badge: $e');
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
      Logger.success(
          '📱 LocalNotificationBadgeService:  Multiple notifications marked as read and badge updated');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to mark multiple as read and update badge: $e');
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
      Logger.success(
          '📱 LocalNotificationBadgeService:  All notifications marked as read and badge updated');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to mark all as read and update badge: $e');
    }
  }

  /// Clear all notifications and update badge
  Future<void> clearAllAndUpdateBadge() async {
    try {
      await _databaseService.clearAllNotifications();

      // Update the indicator service to reflect that all notifications are cleared
      final indicatorService = IndicatorService();
      indicatorService.updateCountsWithContext(unreadNotifications: 0);

      Logger.success(
          '📱 LocalNotificationBadgeService:  All notifications cleared and badge reset to 0');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to clear all and update badge: $e');
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

      Logger.debug(
          '📱 LocalNotificationBadgeService: ✅ Cleanup completed (unread count: $unreadCount)');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to perform cleanup: $e');
    }
  }

  /// Force cleanup now
  Future<void> forceCleanup() async {
    try {
      await _performCleanup();
      Logger.success(
          '📱 LocalNotificationBadgeService:  Force cleanup completed');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to force cleanup: $e');
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

      Logger.success(
          '📱 LocalNotificationBadgeService:  Force reset and reinitialization completed');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to force reset and reinitialize: $e');
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
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Attempting to show message notification: $title');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification body: $body');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification type: $type');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 App lifecycle state: ${WidgetsBinding.instance.lifecycleState}');

      // Check if app is in background - only increment notification count if in background
      final isInBackground = await _isAppInBackground();
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔍 App in background: $isInBackground');

      // Log notification details for debugging
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔍 Notification title: $title');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔍 Notification body: $body');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔍 Notification type: $type');

      // Create notification details
      final AndroidNotificationDetails androidDetails =
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
        ledOnMs: 1000,
        ledOffMs: 1000,
        fullScreenIntent: false,
        autoCancel: true,
        ongoing: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        // Force notification to show even when app is in foreground
        channelShowBadge: true,
        channelAction: AndroidNotificationChannelAction.createIfNotExists,
        // Additional settings to ensure notifications show in foreground
        ticker: 'New message received',
        showProgress: false,
        maxProgress: 0,
        indeterminate: false,
        onlyAlertOnce: false,
        // Critical settings for foreground notifications
        when: DateTime.now().millisecondsSinceEpoch,
        usesChronometer: false,
        // Ensure notification appears in foreground
        silent: false,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true, // Enable badge for iOS
        interruptionLevel:
            InterruptionLevel.active, // Ensure notification is shown
        presentSound: true,
      );

      // Generate notification ID
      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(100000);

      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Creating notification details...');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification ID: $notificationId');
      Logger.info('📱 LocalNotificationBadgeService: 🔔 Title: $title');
      Logger.info('📱 LocalNotificationBadgeService: 🔔 Body: $body');
      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show the notification
      final notificationPayload = payload != null ? jsonEncode(payload) : null;
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification details created successfully');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 Creating message notification with payload: $notificationPayload');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 App in background: $isInBackground');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 Notification details: $notificationDetails');

      // Ensure notification channel exists before showing notification
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Ensuring notification channel exists...');
      await _ensureNotificationChannelExists('message_notifications');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification channel ensured');

      // Check if notifications are enabled
      final areNotificationsEnabled = await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();

      Logger.info(
          '📱 LocalNotificationBadgeService: 🔍 Notifications enabled: $areNotificationsEnabled');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔍 Platform: ${Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'Other'}');

      if (areNotificationsEnabled == false) {
        Logger.warning(
            '📱 LocalNotificationBadgeService: ⚠️ Notifications are disabled, requesting permissions...');
        await _requestNotificationPermissions();
        Logger.info(
            '📱 LocalNotificationBadgeService: 🔔 Permission request completed');
      } else {
        Logger.info(
            '📱 LocalNotificationBadgeService: 🔔 Notifications are enabled, proceeding...');
      }

      // Show notification (only once, no duplicates)
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Showing notification with ID: $notificationId, title: $title, body: $body');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 About to call _localNotifications.show');

      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: notificationPayload,
      );

      Logger.success(
          '📱 LocalNotificationBadgeService: ✅ Message notification shown with ID: $notificationId');
      Logger.info(
          '📱 LocalNotificationBadgeService: 🔔 Notification show completed successfully');

      // Only create notification item in database if app is in background
      if (isInBackground) {
        await _createNotificationItem(title, body, type, payload);
        Logger.success(
            '📱 LocalNotificationBadgeService:  Background message notification item created');
      } else {
        Logger.info(
            '📱 LocalNotificationBadgeService:  Foreground message notification - no database item created');
      }

      Logger.success(
          '📱 LocalNotificationBadgeService:  Message notification shown: $title');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to show message notification: $e');
      Logger.error(
          '📱 LocalNotificationBadgeService:  Error details: ${e.toString()}');
      Logger.error(
          '📱 LocalNotificationBadgeService:  Stack trace: ${StackTrace.current}');
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
      final AndroidNotificationDetails androidDetails =
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
        ledOnMs: 1000,
        ledOffMs: 1000,
        fullScreenIntent: false,
        autoCancel: true,
        ongoing: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        // Force notification to show even when app is in foreground
        channelShowBadge: true,
        channelAction: AndroidNotificationChannelAction.createIfNotExists,
        // Critical settings for foreground notifications
        when: DateTime.now().millisecondsSinceEpoch,
        usesChronometer: false,
        // Ensure notification appears in foreground
        silent: false,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true, // Enable badge for iOS
        interruptionLevel:
            InterruptionLevel.active, // Ensure notification is shown
        presentSound: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show the notification
      final notificationPayload = payload != null ? jsonEncode(payload) : null;
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 Creating notification with payload: $notificationPayload');
      Logger.debug(
          '📱 LocalNotificationBadgeService: 🔧 App in background: $isInBackground');
      Logger.debug(
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

      Logger.success(
          '📱 LocalNotificationBadgeService:  Notification shown with ID: $notificationId');

      // Only create notification item in database if app is in background
      if (isInBackground) {
        await _createNotificationItem(title, body, type, payload);
        Logger.success(
            '📱 LocalNotificationBadgeService:  Background notification item created');
      } else {
        Logger.info(
            '📱 LocalNotificationBadgeService:  Foreground notification - no database item created');
      }

      Logger.success(
          '📱 LocalNotificationBadgeService:  KER notification shown: $title');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to show KER notification: $e');
    }
  }

  /// Reset app icon badge count to 0
  Future<void> resetBadgeCount() async {
    try {
      // Create Android notification details for badge reset
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'badge_reset',
        'Badge Reset',
        channelDescription: 'Silent notification for badge reset',
        importance: Importance.min,
        priority: Priority.min,
        showWhen: false,
        enableVibration: false,
        playSound: false,
        silent: true,
        visibility: NotificationVisibility.private,
        category: AndroidNotificationCategory.status,
      );

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
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: 'badge_reset',
      );

      // Note: Local notification items don't affect app badge counter
      // App badge is managed separately by push notifications

      Logger.success(
          '📱 LocalNotificationBadgeService:  Badge count reset to 0');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to reset badge count: $e');
    }
  }

  /// Clear all notifications from device notification tray
  Future<void> clearAllDeviceNotifications() async {
    try {
      // Cancel all pending notifications
      await _localNotifications.cancelAll();

      Logger.success(
          '📱 LocalNotificationBadgeService:  All device notifications cleared from tray');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to clear device notifications: $e');
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
        visibility: NotificationVisibility.private,
        category: AndroidNotificationCategory.status,
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

      Logger.success(
          '📱 LocalNotificationBadgeService:  App badge count set to: $count');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationBadgeService:  Failed to set badge count: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _isInitialized = false;
    Logger.success('📱 LocalNotificationBadgeService:  Disposed');
  }
}
