import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/features/notifications/models/local_notification.dart';
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
  }

  Future<void> _initializeNotificationsBox() async {
    _notificationsBox = await Hive.openBox('notifications');
    loadNotifications();
  }

  void loadNotifications() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load notifications from Hive storage
      final notificationsList = <LocalNotification>[];

      for (final value in _notificationsBox.values) {
        try {
          notificationsList.add(LocalNotification.fromJson(value));
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
    _notifications.insert(0, notification);
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
}
