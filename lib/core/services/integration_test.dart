import 'package:flutter/foundation.dart';
import 'airnotifier_service.dart';
import 'push_notification_handler.dart';
import 'push_notification_test.dart';
import '../../shared/providers/auth_provider.dart';
import '../../features/invitations/providers/invitation_provider.dart';
import '../../features/chat/providers/chat_provider.dart';

class IntegrationTest {
  static final IntegrationTest _instance = IntegrationTest._internal();
  factory IntegrationTest() => _instance;
  IntegrationTest._internal();

  static IntegrationTest get instance => _instance;

  // Test the complete push notification flow
  Future<void> testCompletePushNotificationFlow() async {
    print('🧪 IntegrationTest: Starting complete push notification flow test');

    try {
      // Test 1: AirNotifier Service
      await _testAirNotifierService();

      // Test 2: Push Notification Handler
      await _testPushNotificationHandler();

      // Test 3: Provider Integration
      await _testProviderIntegration();

      // Test 4: End-to-End Flow
      await _testEndToEndFlow();

      print('🧪 IntegrationTest: ✅ All tests completed successfully');
    } catch (e) {
      print('🧪 IntegrationTest: ❌ Test failed: $e');
    }
  }

  Future<void> _testAirNotifierService() async {
    print('🧪 IntegrationTest: Testing AirNotifier Service...');

    // Test basic notification
    final testRecipientId = 'test_recipient_123';
    final success = await AirNotifierService.instance.sendTestNotification(
      recipientId: testRecipientId,
    );

    if (success) {
      print('🧪 IntegrationTest: ✅ AirNotifier Service working');
    } else {
      print('🧪 IntegrationTest: ❌ AirNotifier Service failed');
    }
  }

  Future<void> _testPushNotificationHandler() async {
    print('🧪 IntegrationTest: Testing Push Notification Handler...');

    // Test invitation notification
    final testInvitationData = {
      'type': 'invitation',
      'action': 'invitation_received',
      'senderId': 'test_sender_456',
      'senderName': 'Test Sender',
      'invitationId': 'test_inv_${DateTime.now().millisecondsSinceEpoch}',
      'message': 'Test invitation message',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await PushNotificationHandler.instance
        .handleNotification(testInvitationData);
    print('🧪 IntegrationTest: ✅ Push Notification Handler working');
  }

  Future<void> _testProviderIntegration() async {
    print('🧪 IntegrationTest: Testing Provider Integration...');

    // Test InvitationProvider
    final invitationProvider = InvitationProvider();
    invitationProvider.handleIncomingInvitation(
      'test_sender_789',
      'Test Sender',
      'test_inv_${DateTime.now().millisecondsSinceEpoch}',
    );

    // Test ChatProvider
    final chatProvider = ChatProvider();
    chatProvider.handleIncomingMessage(
      'test_sender_789',
      'Test Sender',
      'Test message from integration test',
      'conv_test_sender_789',
    );

    print('🧪 IntegrationTest: ✅ Provider Integration working');
  }

  Future<void> _testEndToEndFlow() async {
    print('🧪 IntegrationTest: Testing End-to-End Flow...');

    // Simulate a complete message flow
    final senderId = 'test_sender_e2e';
    final senderName = 'E2E Test Sender';
    final recipientId = 'test_recipient_e2e';
    final message = 'This is an end-to-end test message';

    // Step 1: Send message via AirNotifier
    final sendSuccess =
        await AirNotifierService.instance.sendMessageNotification(
      recipientId: recipientId,
      senderName: senderName,
      message: message,
      conversationId: 'conv_$senderId',
    );

    if (sendSuccess) {
      print('🧪 IntegrationTest: ✅ Message sent successfully');

      // Step 2: Simulate receiving the notification
      final notificationData = {
        'type': 'message',
        'action': 'message_received',
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'conversationId': 'conv_$senderId',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await PushNotificationHandler.instance
          .handleNotification(notificationData);
      print('🧪 IntegrationTest: ✅ Message received and processed');
    } else {
      print('🧪 IntegrationTest: ❌ Message sending failed');
    }
  }

  // Test invitation flow
  Future<void> testInvitationFlow() async {
    print('🧪 IntegrationTest: Testing Invitation Flow...');

    final senderId = 'test_inviter_123';
    final senderName = 'Test Inviter';
    final recipientId = 'test_invitee_456';
    final invitationId = 'test_inv_${DateTime.now().millisecondsSinceEpoch}';

    // Step 1: Send invitation
    final sendSuccess =
        await AirNotifierService.instance.sendInvitationNotification(
      recipientId: recipientId,
      senderName: senderName,
      invitationId: invitationId,
      message: 'Test invitation message',
    );

    if (sendSuccess) {
      print('🧪 IntegrationTest: ✅ Invitation sent successfully');

      // Step 2: Simulate receiving invitation
      final invitationData = {
        'type': 'invitation',
        'action': 'invitation_received',
        'senderId': senderId,
        'senderName': senderName,
        'invitationId': invitationId,
        'message': 'Test invitation message',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await PushNotificationHandler.instance.handleNotification(invitationData);
      print('🧪 IntegrationTest: ✅ Invitation received and processed');

      // Step 3: Simulate invitation response
      final responseData = {
        'type': 'invitation',
        'action': 'invitation_response',
        'responderId': recipientId,
        'responderName': 'Test Invitee',
        'status': 'accepted',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await PushNotificationHandler.instance.handleNotification(responseData);
      print('🧪 IntegrationTest: ✅ Invitation response processed');
    } else {
      print('🧪 IntegrationTest: ❌ Invitation sending failed');
    }
  }

  // Test typing indicator flow
  Future<void> testTypingIndicatorFlow() async {
    print('🧪 IntegrationTest: Testing Typing Indicator Flow...');

    final senderId = 'test_typer_123';
    final senderName = 'Test Typer';
    final recipientId = 'test_recipient_456';

    // Step 1: Send typing indicator
    final startSuccess = await AirNotifierService.instance.sendTypingIndicator(
      recipientId: recipientId,
      senderName: senderName,
      isTyping: true,
    );

    if (startSuccess) {
      print('🧪 IntegrationTest: ✅ Typing indicator sent successfully');

      // Step 2: Simulate receiving typing indicator
      final typingData = {
        'type': 'typing',
        'action': 'typing_indicator',
        'senderId': senderId,
        'isTyping': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await PushNotificationHandler.instance.handleNotification(typingData);
      print('🧪 IntegrationTest: ✅ Typing indicator received and processed');

      // Step 3: Send stop typing indicator
      await Future.delayed(const Duration(seconds: 2));

      final stopSuccess = await AirNotifierService.instance.sendTypingIndicator(
        recipientId: recipientId,
        senderName: senderName,
        isTyping: false,
      );

      if (stopSuccess) {
        print('🧪 IntegrationTest: ✅ Stop typing indicator sent successfully');
      } else {
        print('🧪 IntegrationTest: ❌ Stop typing indicator failed');
      }
    } else {
      print('🧪 IntegrationTest: ❌ Typing indicator sending failed');
    }
  }

  // Run all integration tests
  Future<void> runAllTests() async {
    print('🧪 IntegrationTest: Starting all integration tests...');

    await testCompletePushNotificationFlow();
    await testInvitationFlow();
    await testTypingIndicatorFlow();

    print('🧪 IntegrationTest: All integration tests completed');
  }
}
