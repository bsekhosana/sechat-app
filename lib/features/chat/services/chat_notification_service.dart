import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/message.dart';
import '../models/chat_conversation.dart';

/// Service for managing chat notifications
class ChatNotificationService {
  static ChatNotificationService? _instance;
  static ChatNotificationService get instance =>
      _instance ??= ChatNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, Timer> _typingTimers = {};
  final Map<String, int> _notificationIds = {};
  final Map<String, List<String>> _conversationNotifications = {};

  ChatNotificationService._();

  /// Initialize the notification service
  Future<void> initialize() async {
    try {
      print('🔔 ChatNotificationService: Initializing notification service');

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permissions
      await _requestPermissions();

      print('🔔 ChatNotificationService: ✅ Notification service initialized');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to initialize: $e');
      rethrow;
    }
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final androidGranted = await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestPermission();

      final iosGranted = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      print('🔔 ChatNotificationService: Android permissions: $androidGranted');
      print('🔔 ChatNotificationService: iOS permissions: $iosGranted');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to request permissions: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    try {
      final payload = response.payload;
      if (payload != null) {
        final data = _parseNotificationPayload(payload);
        if (data != null) {
          _handleDeepLink(data);
        }
      }
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to handle notification tap: $e');
    }
  }

  /// Parse notification payload
  Map<String, dynamic>? _parseNotificationPayload(String payload) {
    try {
      // Simple JSON parsing - in a real app, you'd use proper JSON parsing
      if (payload.startsWith('{') && payload.endsWith('}')) {
        // Extract conversation ID from payload
        final conversationIdMatch = RegExp(r'"conversation_id":"([^"]+)"').firstMatch(payload);
        final messageTypeMatch = RegExp(r'"message_type":"([^"]+)"').firstMatch(payload);
        
        if (conversationIdMatch != null) {
          return {
            'conversation_id': conversationIdMatch.group(1),
            'message_type': messageTypeMatch?.group(1) ?? 'text',
          };
        }
      }
      return null;
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to parse payload: $e');
      return null;
    }
  }

  /// Handle deep link to conversation
  void _handleDeepLink(Map<String, dynamic> data) {
    try {
      final conversationId = data['conversation_id'] as String?;
      if (conversationId != null) {
        // This would integrate with your navigation system
        // For now, we'll just print the action
        print('🔔 ChatNotificationService: Deep linking to conversation: $conversationId');
        
        // In a real app, you would:
        // 1. Navigate to the chat screen
        // 2. Load the conversation
        // 3. Mark messages as read
        // 4. Clear the notification badge
      }
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to handle deep link: $e');
    }
  }

  /// Show generic notification for new message
  Future<void> showMessageNotification({
    required String conversationId,
    required String recipientName,
    required MessageType messageType,
    required bool isFromCurrentUser,
    String? messagePreview,
  }) async {
    try {
      // Don't show notifications for messages from current user
      if (isFromCurrentUser) return;

      // Check if conversation is muted
      final isMuted = await _isConversationMuted(conversationId);
      if (isMuted) return;

      // Get notification settings for this conversation
      final settings = await _getConversationNotificationSettings(conversationId);
      if (!settings['notifications_enabled']) return;

      // Generate generic notification message
      final notificationMessage = _generateGenericMessage(messageType, messagePreview);
      
      // Get or create notification ID for this conversation
      final notificationId = _getNotificationId(conversationId);

      // Create notification details
      final androidDetails = AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: settings['vibration_enabled'] ?? true,
        playSound: settings['sound_enabled'] ?? true,
        sound: const RawResourceAndroidNotificationSound('notification_sound'),
        category: AndroidNotificationCategory.message,
        actions: [
          const AndroidNotificationAction('reply', 'Reply'),
          const AndroidNotificationAction('mark_read', 'Mark as Read'),
        ],
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: settings['sound_enabled'] ?? true,
        sound: 'notification_sound.aiff',
        categoryIdentifier: 'chat_message',
        threadIdentifier: conversationId,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Create payload for deep linking
      final payload = _createNotificationPayload(conversationId, messageType);

      // Show notification
      await _notifications.show(
        notificationId,
        recipientName,
        notificationMessage,
        details,
        payload: payload,
      );

      // Track notification for this conversation
      _trackNotification(conversationId, notificationId.toString());

      // Update app badge
      await _updateAppBadge();

      print('🔔 ChatNotificationService: ✅ Message notification shown');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to show message notification: $e');
    }
  }

  /// Show typing indicator notification (silent)
  Future<void> showTypingNotification({
    required String conversationId,
    required String recipientName,
  }) async {
    try {
      // Cancel any existing typing timer for this conversation
      _typingTimers[conversationId]?.cancel();

      // Check if conversation is muted
      final isMuted = await _isConversationMuted(conversationId);
      if (isMuted) return;

      // Get notification settings
      final settings = await _getConversationNotificationSettings(conversationId);
      if (!settings['typing_indicators_enabled']) return;

      // Create silent notification for typing indicator
      final androidDetails = AndroidNotificationDetails(
        'typing_indicators',
        'Typing Indicators',
        channelDescription: 'Silent notifications for typing indicators',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        enableVibration: false,
        playSound: false,
        silent: true,
        ongoing: true,
        autoCancel: false,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        silent: true,
        threadIdentifier: conversationId,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show silent notification
      await _notifications.show(
        _getTypingNotificationId(conversationId),
        recipientName,
        'Typing...',
        details,
        payload: _createNotificationPayload(conversationId, MessageType.text),
      );

      // Set timer to remove typing notification after 10 seconds
      _typingTimers[conversationId] = Timer(
        const Duration(seconds: 10),
        () => _removeTypingNotification(conversationId),
      );

      print('🔔 ChatNotificationService: ✅ Typing notification shown');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to show typing notification: $e');
    }
  }

  /// Remove typing notification
  Future<void> _removeTypingNotification(String conversationId) async {
    try {
      await _notifications.cancel(_getTypingNotificationId(conversationId));
      _typingTimers.remove(conversationId);
      print('🔔 ChatNotificationService: ✅ Typing notification removed');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to remove typing notification: $e');
    }
  }

  /// Show notification for message status updates
  Future<void> showStatusNotification({
    required String conversationId,
    required String recipientName,
    required MessageStatus status,
  }) async {
    try {
      // Only show status notifications for important statuses
      if (status != MessageStatus.delivered && status != MessageStatus.read) {
        return;
      }

      // Check if conversation is muted
      final isMuted = await _isConversationMuted(conversationId);
      if (isMuted) return;

      // Get notification settings
      final settings = await _getConversationNotificationSettings(conversationId);
      if (!settings['read_receipts_enabled']) return;

      final statusMessage = status == MessageStatus.delivered
          ? 'Message delivered'
          : 'Message read';

      final androidDetails = AndroidNotificationDetails(
        'message_status',
        'Message Status',
        channelDescription: 'Notifications for message status updates',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: true,
        enableVibration: false,
        playSound: false,
        silent: true,
        autoCancel: true,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        silent: true,
        threadIdentifier: conversationId,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        _getStatusNotificationId(conversationId, status),
        recipientName,
        statusMessage,
        details,
        payload: _createNotificationPayload(conversationId, MessageType.text),
      );

      print('🔔 ChatNotificationService: ✅ Status notification shown');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to show status notification: $e');
    }
  }

  /// Clear all notifications for a conversation
  Future<void> clearConversationNotifications(String conversationId) async {
    try {
      // Cancel all notifications for this conversation
      final notificationIds = _conversationNotifications[conversationId] ?? [];
      for (final id in notificationIds) {
        await _notifications.cancel(int.parse(id));
      }

      // Remove typing notification
      await _notifications.cancel(_getTypingNotificationId(conversationId));

      // Clear tracking
      _conversationNotifications.remove(conversationId);
      _typingTimers[conversationId]?.cancel();
      _typingTimers.remove(conversationId);

      // Update app badge
      await _updateAppBadge();

      print('🔔 ChatNotificationService: ✅ Conversation notifications cleared');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to clear conversation notifications: $e');
    }
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    try {
      await _notifications.cancelAll();
      _conversationNotifications.clear();
      _typingTimers.values.forEach((timer) => timer.cancel());
      _typingTimers.clear();
      await _updateAppBadge();
      print('🔔 ChatNotificationService: ✅ All notifications cleared');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to clear all notifications: $e');
    }
  }

  /// Update app badge count
  Future<void> _updateAppBadge() async {
    try {
      final totalUnread = await _getTotalUnreadCount();
      
      // Update iOS badge
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      // Set badge count
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.getNotificationAppLaunchDetails();

      print('🔔 ChatNotificationService: ✅ App badge updated: $totalUnread');
    } catch (e) {
      print('🔔 ChatNotificationService: ❌ Failed to update app badge: $e');
    }
  }

  /// Generate generic message for notification
  String _generateGenericMessage(MessageType messageType, String? messagePreview) {
    switch (messageType) {
      case MessageType.text:
        return messagePreview ?? 'New message';
      case MessageType.voice:
        return 'Voice message';
      case MessageType.video:
        return 'Video message';
      case MessageType.image:
        return 'Image';
      case MessageType.document:
        return 'Document';
      case MessageType.location:
        return 'Location';
      case MessageType.contact:
        return 'Contact';
      case MessageType.emoticon:
        return 'Emoticon';
      case MessageType.reply:
        return 'Reply: ${messagePreview ?? 'New message'}';
      case MessageType.system:
        return 'System message';
      default:
        return 'New message';
    }
  }

  /// Create notification payload for deep linking
  String _createNotificationPayload(String conversationId, MessageType messageType) {
    return '{"conversation_id":"$conversationId","message_type":"${messageType.name}"}';
  }

  /// Get notification ID for conversation
  int _getNotificationId(String conversationId) {
    if (!_notificationIds.containsKey(conversationId)) {
      _notificationIds[conversationId] = DateTime.now().millisecondsSinceEpoch % 100000;
    }
    return _notificationIds[conversationId]!;
  }

  /// Get typing notification ID
  int _getTypingNotificationId(String conversationId) {
    return _getNotificationId(conversationId) + 100000;
  }

  /// Get status notification ID
  int _getStatusNotificationId(String conversationId, MessageStatus status) {
    return _getNotificationId(conversationId) + 200000 + status.index;
  }

  /// Track notification for conversation
  void _trackNotification(String conversationId, String notificationId) {
    if (!_conversationNotifications.containsKey(conversationId)) {
      _conversationNotifications[conversationId] = [];
    }
    _conversationNotifications[conversationId]!.add(notificationId);
  }

  /// Check if conversation is muted
  Future<bool> _isConversationMuted(String conversationId) async {
    // This would check the conversation settings
    // For now, return false
    return false;
  }

  /// Get conversation notification settings
  Future<Map<String, dynamic>> _getConversationNotificationSettings(String conversationId) async {
    // This would load from the conversation settings
    // For now, return default settings
    return {
      'notifications_enabled': true,
      'sound_enabled': true,
      'vibration_enabled': true,
      'typing_indicators_enabled': true,
      'read_receipts_enabled': true,
    };
  }

  /// Get total unread count
  Future<int> _getTotalUnreadCount() async {
    // This would query the database for total unread messages
    // For now, return 0
    return 0;
  }

  /// Dispose of resources
  void dispose() {
    _typingTimers.values.forEach((timer) => timer.cancel());
    _typingTimers.clear();
    _conversationNotifications.clear();
    _notificationIds.clear();
    print('🔔 ChatNotificationService: ✅ Service disposed');
  }
}
