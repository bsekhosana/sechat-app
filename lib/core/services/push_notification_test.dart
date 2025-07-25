import 'package:flutter/foundation.dart';
import 'airnotifier_service.dart';
import 'push_notification_handler.dart';

class PushNotificationTest {
  static final PushNotificationTest _instance =
      PushNotificationTest._internal();
  factory PushNotificationTest() => _instance;
  PushNotificationTest._internal();

  static PushNotificationTest get instance => _instance;

  // Test sending a notification
  Future<bool> testSendNotification(String recipientId) async {
    try {
      print('🧪 PushNotificationTest: Testing notification to $recipientId');

      final success = await AirNotifierService.instance.sendTestNotification(
        recipientId: recipientId,
      );

      if (success) {
        print('🧪 PushNotificationTest: ✅ Test notification sent successfully');
        return true;
      } else {
        print('🧪 PushNotificationTest: ❌ Test notification failed');
        return false;
      }
    } catch (e) {
      print('🧪 PushNotificationTest: ❌ Error sending test notification: $e');
      return false;
    }
  }

  // Test invitation notification
  Future<bool> testInvitationNotification(
      String recipientId, String senderName) async {
    try {
      print(
          '🧪 PushNotificationTest: Testing invitation notification to $recipientId');

      final success =
          await AirNotifierService.instance.sendInvitationNotification(
        recipientId: recipientId,
        senderName: senderName,
        invitationId: 'test_inv_${DateTime.now().millisecondsSinceEpoch}',
        message: 'Test invitation message',
      );

      if (success) {
        print(
            '🧪 PushNotificationTest: ✅ Invitation notification sent successfully');
        return true;
      } else {
        print('🧪 PushNotificationTest: ❌ Invitation notification failed');
        return false;
      }
    } catch (e) {
      print(
          '🧪 PushNotificationTest: ❌ Error sending invitation notification: $e');
      return false;
    }
  }

  // Test message notification
  Future<bool> testMessageNotification(
      String recipientId, String senderName) async {
    try {
      print(
          '🧪 PushNotificationTest: Testing message notification to $recipientId');

      final success = await AirNotifierService.instance.sendMessageNotification(
        recipientId: recipientId,
        senderName: senderName,
        message: 'This is a test message from the push notification system',
        conversationId: 'test_conv_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (success) {
        print(
            '🧪 PushNotificationTest: ✅ Message notification sent successfully');
        return true;
      } else {
        print('🧪 PushNotificationTest: ❌ Message notification failed');
        return false;
      }
    } catch (e) {
      print(
          '🧪 PushNotificationTest: ❌ Error sending message notification: $e');
      return false;
    }
  }

  // Test typing indicator notification
  Future<bool> testTypingIndicatorNotification(
      String recipientId, String senderName) async {
    try {
      print(
          '🧪 PushNotificationTest: Testing typing indicator notification to $recipientId');

      final success = await AirNotifierService.instance.sendTypingIndicator(
        recipientId: recipientId,
        senderName: senderName,
        isTyping: true,
      );

      if (success) {
        print(
            '🧪 PushNotificationTest: ✅ Typing indicator notification sent successfully');

        // Wait a bit and send the stop typing notification
        await Future.delayed(const Duration(seconds: 3));

        final stopSuccess =
            await AirNotifierService.instance.sendTypingIndicator(
          recipientId: recipientId,
          senderName: senderName,
          isTyping: false,
        );

        if (stopSuccess) {
          print(
              '🧪 PushNotificationTest: ✅ Stop typing indicator sent successfully');
        } else {
          print('🧪 PushNotificationTest: ❌ Stop typing indicator failed');
        }

        return true;
      } else {
        print(
            '🧪 PushNotificationTest: ❌ Typing indicator notification failed');
        return false;
      }
    } catch (e) {
      print(
          '🧪 PushNotificationTest: ❌ Error sending typing indicator notification: $e');
      return false;
    }
  }

  // Test notification handler
  Future<void> testNotificationHandler() async {
    try {
      print('🧪 PushNotificationTest: Testing notification handler');

      final testData = {
        'type': 'invitation',
        'action': 'invitation_received',
        'senderId': 'test_sender_123',
        'senderName': 'Test User',
        'invitationId': 'test_inv_${DateTime.now().millisecondsSinceEpoch}',
        'message': 'Test invitation',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await PushNotificationHandler.instance.handleNotification(testData);
      print('🧪 PushNotificationTest: ✅ Notification handler test completed');
    } catch (e) {
      print(
          '🧪 PushNotificationTest: ❌ Error testing notification handler: $e');
    }
  }

  // Run all tests
  Future<void> runAllTests(String recipientId, String senderName) async {
    print('🧪 PushNotificationTest: Starting all tests...');

    // Test 1: Basic notification
    await testSendNotification(recipientId);

    // Test 2: Invitation notification
    await testInvitationNotification(recipientId, senderName);

    // Test 3: Message notification
    await testMessageNotification(recipientId, senderName);

    // Test 4: Typing indicator notification
    await testTypingIndicatorNotification(recipientId, senderName);

    // Test 5: Notification handler
    await testNotificationHandler();

    print('🧪 PushNotificationTest: All tests completed');
  }
}
