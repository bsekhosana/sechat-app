import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/features/notifications/models/local_notification.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';

class NotificationProvider extends ChangeNotifier {
  List<LocalNotification> _notifications = [];
  bool _isLoading = false;
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  List<LocalNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationProvider() {
    _setupNotificationServiceCallback();
    loadNotifications();
  }

  void _setupNotificationServiceCallback() {
    SimpleNotificationService.instance.setOnInvitationReceived(
      (senderId, senderName, invitationId) {
        _handleNotificationFromService('New Invitation',
            '$senderName would like to connect', 'invitation', {
          'senderId': senderId,
          'senderName': senderName,
          'invitationId': invitationId,
        });
      },
    );
  }

  void _handleNotificationFromService(
    String title,
    String body,
    String type,
    Map<String, dynamic>? data,
  ) {
    NotificationType notificationType;
    switch (type) {
      case 'invitation':
      case 'invitation_sent':
      case 'invitation_deleted':
      case 'invitation_cancelled':
        notificationType = NotificationType.invitation;
        break;
      case 'message':
        notificationType = NotificationType.message;
        break;
      default:
        notificationType = NotificationType.system;
    }

    final notification = LocalNotification(
      id: '${type}_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: notificationType,
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
    );

    addNotification(notification);
  }

  void loadNotifications() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load notifications from SharedPreferences only
      final notificationsList = <LocalNotification>[];

      // Load from SharedPreferences
      final sharedPrefsNotifications =
          await _prefsService.getJsonList('notifications') ?? [];

      for (final notificationJson in sharedPrefsNotifications) {
        try {
          if (notificationJson is Map<String, dynamic>) {
            // Convert SharedPreferences format to LocalNotification format
            final localNotification = LocalNotification(
              id: notificationJson['id'] ?? '',
              title: notificationJson['title'] ?? '',
              body: notificationJson['body'] ?? '',
              type: _getNotificationType(notificationJson['type'] ?? ''),
              timestamp: DateTime.parse(notificationJson['timestamp'] ??
                  DateTime.now().toIso8601String()),
              isRead: notificationJson['isRead'] ?? false,
              data: notificationJson['data'] ?? {},
            );
            notificationsList.add(localNotification);
          }
        } catch (e) {
          print('Error parsing SharedPreferences notification: $e');
        }
      }

      if (notificationsList.isEmpty) {
        // Check if welcome notification has been shown before
        final hasShownWelcome =
            await _prefsService.getBool('has_shown_welcome_notification') ??
                false;

        if (!hasShownWelcome) {
          // Add welcome notification only if it hasn't been shown before
          notificationsList.add(
            LocalNotification(
              id: 'welcome_notification',
              title: 'Welcome to SeChat!',
              body: 'Your secure messaging app is ready to use.',
              type: NotificationType.system,
              timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
              isRead: false,
              data: null,
            ),
          );

          // Mark that welcome notification has been shown
          await _prefsService.setBool('has_shown_welcome_notification', true);
          await _saveNotifications();
        }
      } else {
        _notifications = notificationsList;
        // Sort by timestamp (newest first) to ensure proper ordering
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (e) {
      print('Error loading notifications: $e');
      // Only add fallback welcome notification if it hasn't been shown before
      final hasShownWelcome =
          await _prefsService.getBool('has_shown_welcome_notification') ??
              false;

      if (!hasShownWelcome) {
        _notifications = [
          LocalNotification(
            id: 'welcome_notification',
            title: 'Welcome to SeChat!',
            body: 'Your secure messaging app is ready to use.',
            type: NotificationType.system,
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
            isRead: false,
            data: null,
          ),
        ];
        // Mark that welcome notification has been shown
        await _prefsService.setBool('has_shown_welcome_notification', true);
      } else {
        _notifications = [];
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  NotificationType _getNotificationType(String type) {
    switch (type) {
      case 'invitation':
      case 'invitation_sent':
      case 'invitation_deleted':
      case 'invitation_cancelled':
      case 'invitation_response':
        return NotificationType.invitation;
      case 'message':
        return NotificationType.message;
      default:
        return NotificationType.system;
    }
  }

  Future<void> _saveNotifications() async {
    try {
      // Convert notifications to JSON format for SharedPreferences
      final notificationsJson = _notifications
          .map((notification) => {
                'id': notification.id,
                'title': notification.title,
                'body': notification.body,
                'type': _getNotificationTypeString(notification.type),
                'timestamp': notification.timestamp.toIso8601String(),
                'isRead': notification.isRead,
                'data': notification.data,
              })
          .toList();

      // Save to SharedPreferences
      await _prefsService.setJsonList('notifications', notificationsJson);
    } catch (e) {
      print('Error saving notifications: $e');
    }
  }

  String _getNotificationTypeString(NotificationType type) {
    switch (type) {
      case NotificationType.invitation:
        return 'invitation';
      case NotificationType.message:
        return 'message';
      case NotificationType.invitationResponse:
        return 'invitation_response';
      case NotificationType.system:
        return 'system';
    }
  }

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _saveNotifications();
      notifyListeners();
    }
  }

  void markAllAsRead() {
    _notifications =
        _notifications.map((n) => n.copyWith(isRead: true)).toList();
    _saveNotifications();
    notifyListeners();
  }

  void addNotification(LocalNotification notification) {
    // Add new notification at the top (index 0)
    _notifications.insert(0, notification);

    // Sort by timestamp (newest first) to ensure proper ordering
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _saveNotifications();
    notifyListeners();
  }

  void removeNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _saveNotifications();
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    _saveNotifications();
    notifyListeners();
  }

  // Clear all data (for account deletion)
  Future<void> clearAllData() async {
    try {
      print('📱 NotificationProvider: Clearing all notification data...');

      _notifications.clear();
      _isLoading = false;

      // Clear from SharedPreferences
      await _prefsService.remove('notifications');

      notifyListeners();
      print('📱 NotificationProvider: ✅ All notification data cleared');
    } catch (e) {
      print('📱 NotificationProvider: Error clearing all data: $e');
    }
  }

  // Add message notification
  void addMessageNotification({
    required String senderId,
    required String senderName,
    required String message,
  }) {
    final notification = LocalNotification(
      id: 'message_${DateTime.now().millisecondsSinceEpoch}',
      title: senderName,
      body: message,
      type: NotificationType.message,
      timestamp: DateTime.now(),
      isRead: false,
      data: {
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
      },
    );

    addNotification(notification);
  }

  // Add invitation notification
  void addInvitationNotification({
    required String senderId,
    required String senderName,
    required String invitationId,
  }) {
    final notification = LocalNotification(
      id: 'invitation_${DateTime.now().millisecondsSinceEpoch}',
      title: 'New Contact Invitation',
      body: '$senderName would like to connect with you',
      type: NotificationType.invitation,
      timestamp: DateTime.now(),
      isRead: false,
      data: {
        'senderId': senderId,
        'senderName': senderName,
        'invitationId': invitationId,
      },
    );

    addNotification(notification);
  }

  // Add system notification
  void addSystemNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    final notification = LocalNotification(
      id: 'system_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: NotificationType.system,
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
    );

    addNotification(notification);
  }
}
