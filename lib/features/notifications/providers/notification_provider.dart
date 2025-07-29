import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/features/notifications/models/local_notification.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class NotificationProvider extends ChangeNotifier {
  List<LocalNotification> _notifications = [];
  bool _isLoading = false;
  late Box<dynamic> _notificationsBox;

  List<LocalNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationProvider() {
    _initializeNotificationsBox();
    _setupNotificationServiceCallback();
  }

  Future<void> _initializeNotificationsBox() async {
    _notificationsBox = await Hive.openBox('notifications');
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
      // Load notifications from Hive storage
      final notificationsList = <LocalNotification>[];

      for (final value in _notificationsBox.values) {
        try {
          // Convert Map<dynamic, dynamic> to Map<String, dynamic>
          if (value is Map) {
            final Map<String, dynamic> jsonData = {};
            value.forEach((key, val) {
              if (key is String) {
                jsonData[key] = val;
              }
            });
            notificationsList.add(LocalNotification.fromJson(jsonData));
          } else {
            print(
                'Error parsing notification: Invalid data type: ${value.runtimeType}');
          }
        } catch (e) {
          print('Error parsing notification: $e');
        }
      }

      if (notificationsList.isEmpty) {
        // Load sample notifications for first time
        _notifications = [
          LocalNotification(
            id: '1',
            title: 'Welcome to SeChat!',
            body: 'Your secure messaging app is ready to use.',
            type: NotificationType.system,
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
            isRead: false,
            data: null,
          ),
        ];
        await _saveNotifications();
      } else {
        _notifications = notificationsList;
        // Sort by timestamp (newest first) to ensure proper ordering
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (e) {
      print('Error loading notifications: $e');
      // Fallback to sample notifications
      _notifications = [
        LocalNotification(
          id: '1',
          title: 'Welcome to SeChat!',
          body: 'Your secure messaging app is ready to use.',
          type: NotificationType.system,
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          isRead: false,
          data: null,
        ),
      ];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveNotifications() async {
    try {
      // Clear existing notifications
      await _notificationsBox.clear();

      // Save all notifications
      for (final notification in _notifications) {
        await _notificationsBox.put(notification.id, notification.toJson());
      }
    } catch (e) {
      print('Error saving notifications: $e');
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

      // Clear from Hive storage as well
      await _notificationsBox.clear();

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
    required String chatId,
  }) {
    final notification = LocalNotification(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      title: 'New message from $senderName',
      body: message,
      type: NotificationType.message,
      timestamp: DateTime.now(),
      isRead: false,
      data: {
        'senderId': senderId,
        'chatId': chatId,
        'message': message,
      },
    );
    addNotification(notification);
  }

  // Add invitation notification
  void addInvitationNotification({
    required String senderId,
    required String senderName,
    required String message,
  }) {
    final notification = LocalNotification(
      id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Contact request from $senderName',
      body: message,
      type: NotificationType.invitation,
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

  // Add system notification
  void addSystemNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    final notification = LocalNotification(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: NotificationType.system,
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
    );
    addNotification(notification);
  }

  // Add connection status notification
  void addConnectionNotification({
    required String title,
    required String body,
    required bool isConnected,
  }) {
    final notification = LocalNotification(
      id: 'conn_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: NotificationType.system,
      timestamp: DateTime.now(),
      isRead: false,
      data: {
        'isConnected': isConnected,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    addNotification(notification);
  }
}
