import '../models/local_notification_item.dart';
import '../models/notification_types.dart';
import '../models/notification_icons.dart';
import 'local_notification_database_service.dart';
import 'local_notification_badge_service.dart';
import '../../../core/services/se_session_service.dart';

/// Service for creating and managing local notification items
class LocalNotificationItemsService {
  static final LocalNotificationItemsService _instance =
      LocalNotificationItemsService._internal();
  factory LocalNotificationItemsService() => _instance;
  LocalNotificationItemsService._internal();

  final LocalNotificationDatabaseService _databaseService =
      LocalNotificationDatabaseService();
  final LocalNotificationBadgeService _badgeService =
      LocalNotificationBadgeService();

  /// Create welcome notification for new user
  Future<void> createWelcomeNotification(String userId) async {
    try {
      // Check if welcome notification already exists
      final hasWelcome = await _databaseService.hasWelcomeNotification(userId);
      if (hasWelcome) {
        print(
            '📱 LocalNotificationItemsService: ℹ️ Welcome notification already exists for user: $userId');
        return;
      }

      final notification = LocalNotificationItem(
        type: NotificationType.welcome,
        icon: NotificationIcons.getIconNameForType(NotificationType.welcome),
        title: 'Welcome to SeChat!',
        description:
            'Your session has been created successfully. You can now start exchanging keys and chatting securely.',
        status: NotificationStatus.unread,
        direction: NotificationDirection.incoming,
        recipientId: userId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'welcome',
          'timestamp': DateTime.now().toIso8601String(),
          'userId': userId,
        },
      );

      await _databaseService.insertNotification(notification);
      print(
          '📱 LocalNotificationItemsService: ✅ Welcome notification created for user: $userId');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create welcome notification: $e');
    }
  }

  /// Create KER sent notification
  Future<void> createKerSentNotification({
    required String senderId,
    required String recipientId,
    required String requestPhrase,
    String? conversationId,
  }) async {
    try {
      final notification = LocalNotificationItem(
        type: NotificationType.kerSent,
        icon: NotificationIcons.getIconNameForType(NotificationType.kerSent),
        title: 'Key Exchange Request Sent',
        description:
            'You sent a key exchange request to start a secure conversation.',
        status: NotificationStatus.unread,
        direction: NotificationDirection.outgoing,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'ker_sent',
          'requestPhrase': requestPhrase,
          'timestamp': DateTime.now().toIso8601String(),
          'senderId': senderId,
          'recipientId': recipientId,
          'conversationId': conversationId,
        },
      );

      await _databaseService.insertNotification(notification);
      print(
          '📱 LocalNotificationItemsService: ✅ KER sent notification created');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create KER sent notification: $e');
    }
  }

  /// Create KER received notification
  Future<void> createKerReceivedNotification({
    required String senderId,
    required String recipientId,
    required String requestPhrase,
    String? conversationId,
  }) async {
    try {
      final notification = LocalNotificationItem(
        type: NotificationType.kerReceived,
        icon:
            NotificationIcons.getIconNameForType(NotificationType.kerReceived),
        title: 'New Key Exchange Request',
        description:
            'You received a key exchange request to start a secure conversation.',
        status: NotificationStatus.unread,
        direction: NotificationDirection.incoming,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'ker_received',
          'requestPhrase': requestPhrase,
          'timestamp': DateTime.now().toIso8601String(),
          'senderId': senderId,
          'recipientId': recipientId,
          'conversationId': conversationId,
        },
      );

      // Only create the database notification item, no push notification
      // Push notifications are handled separately by the socket service
      await _databaseService.insertNotification(notification);

      print(
          '📱 LocalNotificationItemsService: ✅ KER received notification created (database only)');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create KER received notification: $e');
    }
  }

  /// Create KER accepted notification
  Future<void> createKerAcceptedNotification({
    required String senderId,
    required String recipientId,
    required String requestPhrase,
    String? conversationId,
  }) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      final isRequester = currentUserId == senderId;

      String title;
      String description;
      String direction;

      if (isRequester) {
        // For the person who sent the request
        title = 'Key Exchange Request Accepted';
        description =
            'Your key exchange request was accepted. You can now start chatting securely.';
        direction = NotificationDirection.incoming;
      } else {
        // For the person who accepted the request
        title = 'You Accepted Key Exchange Request';
        description =
            'You accepted a key exchange request. You can now start chatting securely.';
        direction = NotificationDirection.outgoing;
      }

      final notification = LocalNotificationItem(
        type: NotificationType.kerAccepted,
        icon:
            NotificationIcons.getIconNameForType(NotificationType.kerAccepted),
        title: title,
        description: description,
        status: NotificationStatus.unread,
        direction: direction,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'ker_accepted',
          'requestPhrase': requestPhrase,
          'timestamp': DateTime.now().toIso8601String(),
          'senderId': senderId,
          'recipientId': recipientId,
          'conversationId': conversationId,
          'acceptedBy': recipientId,
        },
      );

      await _databaseService.insertNotification(notification);
      print(
          '📱 LocalNotificationItemsService: ✅ KER accepted notification created');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create KER accepted notification: $e');
    }
  }

  /// Create KER declined notification
  Future<void> createKerDeclinedNotification({
    required String senderId,
    required String recipientId,
    required String requestPhrase,
    String? conversationId,
  }) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      final isRequester = currentUserId == senderId;

      String title = '';
      String description = '';
      String direction = '';

      if (isRequester) {
        // For the person who sent the request
        title = 'Key Exchange Request Declined';
        description = 'Your key exchange request was declined.';
        direction = NotificationDirection.incoming;
      } else {
        // For the person who declined the request
        title = 'You Declined Key Exchange Request';
        description = 'You declined a key exchange request.';
        direction = NotificationDirection.outgoing;
      }

      final notification = LocalNotificationItem(
        type: NotificationType.kerDeclined,
        icon:
            NotificationIcons.getIconNameForType(NotificationType.kerDeclined),
        title: title,
        description: description,
        status: NotificationStatus.unread,
        direction: direction,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'ker_declined',
          'requestPhrase': requestPhrase,
          'timestamp': DateTime.now().toIso8601String(),
          'senderId': senderId,
          'recipientId': recipientId,
          'conversationId': conversationId,
          'declinedBy': recipientId,
        },
      );

      await _databaseService.insertNotification(notification);
      print(
          '📱 LocalNotificationItemsService: ✅ KER declined notification created');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create KER declined notification: $e');
    }
  }

  /// Create KER resent notification
  Future<void> createKerResentNotification({
    required String senderId,
    required String recipientId,
    required String requestPhrase,
    String? conversationId,
  }) async {
    try {
      final notification = LocalNotificationItem(
        type: NotificationType.kerResent,
        icon: NotificationIcons.getIconNameForType(NotificationType.kerResent),
        title: 'Key Exchange Request Resent',
        description: 'You resent a key exchange request.',
        status: NotificationStatus.unread,
        direction: NotificationDirection.outgoing,
        senderId: senderId,
        recipientId: recipientId,
        conversationId: conversationId,
        date: DateTime.now(),
        metadata: {
          'notificationType': 'ker_resent',
          'requestPhrase': requestPhrase,
          'timestamp': DateTime.now().toIso8601String(),
          'senderId': senderId,
          'recipientId': recipientId,
          'conversationId': conversationId,
        },
      );

      await _databaseService.insertNotification(notification);
      print(
          '📱 LocalNotificationItemsService: ✅ KER resent notification created');
    } catch (e) {
      print(
          '📱 LocalNotificationItemsService: ❌ Failed to create KER resent notification: $e');
    }
  }

  /// Get all notifications
  Future<List<LocalNotificationItem>> getAllNotifications() async {
    return await _databaseService.getAllNotifications();
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    return await _databaseService.getUnreadCount();
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    await _databaseService.markAsRead(notificationId);
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    await _databaseService.clearAllNotifications();
  }

  /// Clear old notifications (older than 30 days)
  Future<void> clearOldNotifications() async {
    await _databaseService.clearOldNotifications(30);
  }
}
