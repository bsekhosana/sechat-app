import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _selectedNotificationPayload;
  Function(String?)? _onNotificationTap;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Skip initialization on web platforms
    if (kIsWeb) {
      _isInitialized = true;
      print('📱 NotificationService: Skipped initialization on web platform');
      return;
    }

    // Request permissions
    if (Platform.isAndroid) {
      await _requestAndroidPermissions();
    } else if (Platform.isIOS) {
      await _requestIOSPermissions();
    }

    // Initialize notification settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    _isInitialized = true;
    print('📱 NotificationService: Initialized successfully');
  }

  Future<void> _requestAndroidPermissions() async {
    final permission = await Permission.notification.request();
    if (permission.isDenied) {
      print('📱 NotificationService: Android notification permission denied');
    }
  }

  Future<void> _requestIOSPermissions() async {
    final permission = await Permission.notification.request();
    if (permission.isDenied) {
      print('📱 NotificationService: iOS notification permission denied');
    }
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    _selectedNotificationPayload = response.payload;
    if (_onNotificationTap != null) {
      _onNotificationTap!(response.payload);
    }
    print(
        '📱 NotificationService: Notification tapped with payload: ${response.payload}');
  }

  void setOnNotificationTap(Function(String?) callback) {
    _onNotificationTap = callback;
  }

  Future<void> showInvitationReceivedNotification({
    required String senderUsername,
    required String message,
    required String invitationId,
  }) async {
    if (kIsWeb) return; // Skip on web
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'invitation_received',
      'Invitation Received',
      channelDescription: 'Notifications for received invitations',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF6B35),
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      invitationId.hashCode,
      'New Invitation from $senderUsername',
      message,
      notificationDetails,
      payload: 'invitation_received:$invitationId',
    );

    print(
        '📱 NotificationService: Invitation received notification sent for $senderUsername');
  }

  Future<void> showInvitationResponseNotification({
    required String username,
    required String status, // 'accepted' or 'declined'
    required String invitationId,
  }) async {
    if (kIsWeb) return; // Skip on web
    if (!_isInitialized) await initialize();

    final statusText = status == 'accepted' ? 'accepted' : 'declined';
    final statusEmoji = status == 'accepted' ? '✅' : '❌';

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'invitation_response',
      'Invitation Response',
      channelDescription: 'Notifications for invitation responses',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF6B35),
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      invitationId.hashCode,
      '$statusEmoji Invitation $statusText',
      '$username $statusText your invitation',
      notificationDetails,
      payload: 'invitation_response:$invitationId:$status',
    );

    print(
        '📱 NotificationService: Invitation response notification sent for $username - $status');
  }

  Future<void> showInvitationDeletedNotification({
    required String username,
    required String invitationId,
    required String deletedBy,
  }) async {
    if (kIsWeb) return; // Skip on web
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'invitation_deleted',
      'Invitation Deleted',
      channelDescription: 'Notifications for deleted invitations',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF5555),
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      invitationId.hashCode,
      '🗑️ Invitation Deleted',
      '$username deleted the invitation',
      notificationDetails,
      payload: 'invitation_deleted:$invitationId:$deletedBy',
    );

    print(
        '📱 NotificationService: Invitation deleted notification sent for $username');
  }

  Future<void> showInvitationCancelledNotification({
    required String username,
    required String invitationId,
    required String cancelledBy,
  }) async {
    if (kIsWeb) return; // Skip on web
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'invitation_cancelled',
      'Invitation Cancelled',
      channelDescription: 'Notifications for cancelled invitations',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFFAA00),
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      invitationId.hashCode,
      '❌ Invitation Cancelled',
      '$username cancelled the invitation',
      notificationDetails,
      payload: 'invitation_cancelled:$invitationId:$cancelledBy',
    );

    print(
        '📱 NotificationService: Invitation cancelled notification sent for $username');
  }

  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  String? getSelectedNotificationPayload() {
    final payload = _selectedNotificationPayload;
    _selectedNotificationPayload = null;
    return payload;
  }

  Map<String, dynamic>? parseNotificationPayload(String? payload) {
    if (payload == null) return null;

    try {
      final parts = payload.split(':');
      if (parts.length < 2) return null;

      final type = parts[0];
      final invitationId = parts[1];

      switch (type) {
        case 'invitation_received':
          return {
            'type': 'invitation_received',
            'invitation_id': invitationId,
            'tab': 'received',
          };
        case 'invitation_response':
          final status = parts.length > 2 ? parts[2] : 'unknown';
          return {
            'type': 'invitation_response',
            'invitation_id': invitationId,
            'status': status,
            'tab': 'sent',
          };
        default:
          return null;
      }
    } catch (e) {
      print('📱 NotificationService: Error parsing payload: $e');
      return null;
    }
  }
}
