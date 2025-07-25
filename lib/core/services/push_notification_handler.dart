import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'notification_service.dart';
import 'airnotifier_service.dart';
import 'notification_data_sync_service.dart';

class PushNotificationHandler {
  static final PushNotificationHandler _instance =
      PushNotificationHandler._internal();
  factory PushNotificationHandler() => _instance;
  PushNotificationHandler._internal();

  static PushNotificationHandler get instance => _instance;

  // Callback functions for different notification types
  Function(String, String, String)? _onInvitationReceived;
  Function(String, String, String)? _onInvitationResponse;
  Function(String, String, String)? _onMessageReceived;
  Function(String, bool)? _onTypingIndicator;
  Function(String, bool)? _onConnectionStatus;

  // Set callbacks
  void setOnInvitationReceived(
      Function(String senderId, String senderName, String invitationId)
          callback) {
    _onInvitationReceived = callback;
  }

  void setOnInvitationResponse(
      Function(String responderId, String responderName, String status)
          callback) {
    _onInvitationResponse = callback;
  }

  void setOnMessageReceived(
      Function(String senderId, String senderName, String message) callback) {
    _onMessageReceived = callback;
  }

  void setOnTypingIndicator(Function(String senderId, bool isTyping) callback) {
    _onTypingIndicator = callback;
  }

  void setOnConnectionStatus(
      Function(String userId, bool isConnected) callback) {
    _onConnectionStatus = callback;
  }

  // Handle incoming push notification
  Future<void> handleNotification(Map<String, dynamic> data) async {
    try {
      final type = data['type'] as String?;
      final action = data['action'] as String?;
      final timestamp = data['timestamp'] as int?;

      print(
          '📱 PushNotificationHandler: Received notification - type: $type, action: $action');

      if (type == null || action == null) {
        print(
            '📱 PushNotificationHandler: Invalid notification data - missing type or action');
        return;
      }

      // Process notification and update local database
      await NotificationDataSyncService.instance.processNotification(data);

      // Handle UI updates based on notification type
      switch (type) {
        case 'invitation':
          await _handleInvitationNotification(data);
          break;
        case 'invitation_response':
          await _handleInvitationResponseNotification(data);
          break;
        case 'message':
          await _handleMessageNotification(data);
          break;
        case 'typing_indicator':
          await _handleTypingIndicatorNotification(data);
          break;
        case 'connection_status':
          await _handleConnectionStatusNotification(data);
          break;
        case 'message_read':
          await _handleMessageReadNotification(data);
          break;
        case 'invitation_update':
          await _handleInvitationUpdateNotification(data);
          break;
        case 'message_delivery_status':
          await _handleMessageDeliveryStatusNotification(data);
          break;
        case 'online_status_update':
          await _handleOnlineStatusUpdateNotification(data);
          break;
        default:
          print('📱 PushNotificationHandler: Unknown notification type: $type');
      }
    } catch (e) {
      print('📱 PushNotificationHandler: Error handling notification: $e');
    }
  }

  // Handle invitation notification
  Future<void> _handleInvitationNotification(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final senderName = data['senderName'] as String?;
    final invitationId = data['invitationId'] as String?;
    final message = data['message'] as String?;

    if (senderId == null || senderName == null || invitationId == null) {
      print('📱 PushNotificationHandler: Invalid invitation notification data');
      return;
    }

    // Show local notification
    await NotificationService.instance.showInvitationReceivedNotification(
      senderUsername: senderName,
      invitationId: invitationId,
      message: message ?? '',
    );

    // Trigger callback
    if (_onInvitationReceived != null) {
      _onInvitationReceived!(senderId, senderName, invitationId);
    }
  }

  // Handle invitation response notification
  Future<void> _handleInvitationResponseNotification(
      Map<String, dynamic> data) async {
    final responderId = data['responderId'] as String?;
    final responderName = data['responderName'] as String?;
    final status = data['status'] as String?;
    final invitationId = data['invitationId'] as String?;

    if (responderId == null || responderName == null || status == null) {
      print(
          '📱 PushNotificationHandler: Invalid invitation response notification data');
      return;
    }

    // Show local notification
    await NotificationService.instance.showInvitationResponseNotification(
      username: responderName,
      status: status,
      invitationId: invitationId ?? '',
    );

    // Trigger callback
    if (_onInvitationResponse != null) {
      _onInvitationResponse!(responderId, responderName, status);
    }
  }

  // Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final senderName = data['senderName'] as String?;
    final message = data['message'] as String?;
    final conversationId = data['conversationId'] as String?;

    if (senderId == null || senderName == null || message == null) {
      print('📱 PushNotificationHandler: Invalid message notification data');
      return;
    }

    // Show local notification
    await NotificationService.instance.showMessageNotification(
      senderName: senderName,
      message: message,
      conversationId: conversationId ?? '',
    );

    // Trigger callback
    if (_onMessageReceived != null) {
      _onMessageReceived!(senderId, senderName, message);
    }
  }

  // Handle typing indicator notification
  Future<void> _handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final isTyping = data['isTyping'] as bool?;

    if (senderId == null || isTyping == null) {
      print(
          '📱 PushNotificationHandler: Invalid typing indicator notification data');
      return;
    }

    // Trigger callback (no local notification for typing indicators)
    if (_onTypingIndicator != null) {
      _onTypingIndicator!(senderId, isTyping);
    }
  }

  // Handle connection status notification
  Future<void> _handleConnectionStatusNotification(
      Map<String, dynamic> data) async {
    final userId = data['userId'] as String?;
    final isConnected = data['isConnected'] as bool?;

    if (userId == null || isConnected == null) {
      print(
          '📱 PushNotificationHandler: Invalid connection status notification data');
      return;
    }

    // Trigger callback
    if (_onConnectionStatus != null) {
      _onConnectionStatus!(userId, isConnected);
    }
  }

  // Handle message read notification
  Future<void> _handleMessageReadNotification(Map<String, dynamic> data) async {
    final messageId = data['messageId'] as String?;
    final conversationId = data['conversationId'] as String?;
    final readerId = data['readerId'] as String?;

    if (messageId == null || conversationId == null || readerId == null) {
      print(
          '📱 PushNotificationHandler: Invalid message read notification data');
      return;
    }

    // Handle message read receipt (no local notification needed)
    print(
        '📱 PushNotificationHandler: Message $messageId marked as read by $readerId');
  }

  // Test notification handling
  Future<void> handleTestNotification() async {
    final testData = {
      'type': 'test',
      'action': 'test_notification',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await handleNotification(testData);
  }

  // Handle invitation update notification (silent)
  Future<void> _handleInvitationUpdateNotification(
      Map<String, dynamic> data) async {
    final invitationId = data['invitationId'] as String?;
    final action = data['action'] as String?;
    final senderName = data['senderName'] as String?;
    final senderId = data['senderId'] as String?;
    final message = data['message'] as String?;

    if (invitationId == null ||
        action == null ||
        senderName == null ||
        senderId == null) {
      print(
          '📱 PushNotificationHandler: Invalid invitation update notification data');
      return;
    }

    print(
        '📱 PushNotificationHandler: Invitation update - $action from $senderName');

    // Handle based on action
    switch (action) {
      case 'received':
        // Handle invitation received
        if (_onInvitationReceived != null) {
          _onInvitationReceived!(senderId, senderName, invitationId);
        }
        break;
      case 'accepted':
      case 'declined':
        // Handle invitation response
        if (_onInvitationResponse != null) {
          _onInvitationResponse!(senderId, senderName, action);
        }
        break;
      default:
        print('📱 PushNotificationHandler: Unknown invitation action: $action');
    }
  }

  // Handle message delivery status notification (silent)
  Future<void> _handleMessageDeliveryStatusNotification(
      Map<String, dynamic> data) async {
    final messageId = data['messageId'] as String?;
    final status = data['status'] as String?;
    final conversationId = data['conversationId'] as String?;
    final senderId = data['senderId'] as String?;

    if (messageId == null ||
        status == null ||
        conversationId == null ||
        senderId == null) {
      print(
          '📱 PushNotificationHandler: Invalid message delivery status notification data');
      return;
    }

    print(
        '📱 PushNotificationHandler: Message delivery status - $messageId: $status');
    // Handle message delivery status (no local notification needed)
  }

  // Handle online status update notification (silent)
  Future<void> _handleOnlineStatusUpdateNotification(
      Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final isOnline = data['isOnline'] as bool?;
    final lastSeen = data['lastSeen'] as String?;

    if (senderId == null || isOnline == null || lastSeen == null) {
      print(
          '📱 PushNotificationHandler: Invalid online status update notification data');
      return;
    }

    print(
        '📱 PushNotificationHandler: Online status update - $senderId: $isOnline');
    // Handle online status update (no local notification needed)
  }
}
