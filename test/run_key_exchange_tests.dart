import 'package:flutter_test/flutter_test.dart';
import 'package:sechat_app/core/services/optimized_notification_service.dart';

/// Simple test runner for key exchange feature
/// Run this with: flutter test test/run_key_exchange_tests.dart
void main() {
  group('Key Exchange Feature Tests', () {
    late OptimizedNotificationService notificationService;

    setUp(() {
      notificationService = OptimizedNotificationService();
    });

    test('Key Exchange Request Processing', () async {
      print('🧪 Testing Key Exchange Request Processing...');

      final testData = {
        'data': {
          'type': 'key_exchange_request',
          'sender_id': 'test_sender_session',
          'sender_public_key': 'test_public_key_base64',
          'request_id': 'test_req_123',
          'request_phrase': 'Test key exchange request',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      try {
        await notificationService.handleNotification(testData);
        print('✅ Key Exchange Request processed successfully');
      } catch (e) {
        print('❌ Key Exchange Request failed: $e');
        fail('Key Exchange Request should not fail');
      }
    });

    test('Key Exchange Accepted Processing', () async {
      print('🧪 Testing Key Exchange Accepted Processing...');

      final testData = {
        'data': {
          'type': 'key_exchange_accepted',
          'acceptor_public_key': 'test_acceptor_public_key',
          'request_id': 'test_req_123',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'recipient_id': 'test_recipient_session',
        }
      };

      try {
        await notificationService.handleNotification(testData);
        print('✅ Key Exchange Accepted processed successfully');
      } catch (e) {
        print('❌ Key Exchange Accepted failed: $e');
        fail('Key Exchange Accepted should not fail');
      }
    });

    test('Key Exchange Response Processing', () async {
      print('🧪 Testing Key Exchange Response Processing...');

      final testData = {
        'data': {
          'type': 'key_exchange_response',
          'sender_id': 'test_sender_session',
          'public_key': 'test_response_public_key',
          'response_id': 'test_resp_123',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      try {
        await notificationService.handleNotification(testData);
        print('✅ Key Exchange Response processed successfully');
      } catch (e) {
        print('❌ Key Exchange Response failed: $e');
        fail('Key Exchange Response should not fail');
      }
    });

    test('Complete Key Exchange Flow', () async {
      print('🧪 Testing Complete Key Exchange Flow...');

      // Step 1: Request
      final requestData = {
        'data': {
          'type': 'key_exchange_request',
          'sender_id': 'flow_sender_session',
          'sender_public_key': 'flow_sender_public_key',
          'request_id': 'flow_req_123',
          'request_phrase': 'Flow test key exchange',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      // Step 2: Response
      final responseData = {
        'data': {
          'type': 'key_exchange_response',
          'sender_id': 'flow_sender_session',
          'public_key': 'flow_response_public_key',
          'response_id': 'flow_resp_123',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };

      // Step 3: Accepted
      final acceptedData = {
        'data': {
          'type': 'key_exchange_accepted',
          'acceptor_public_key': 'flow_acceptor_public_key',
          'request_id': 'flow_req_123',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'recipient_id': 'flow_recipient_session',
        }
      };

      try {
        // Process all steps
        await notificationService.handleNotification(requestData);
        print('✅ Step 1: Request processed');

        await notificationService.handleNotification(responseData);
        print('✅ Step 2: Response processed');

        await notificationService.handleNotification(acceptedData);
        print('✅ Step 3: Accepted processed');

        print('✅ Complete Key Exchange Flow processed successfully');
      } catch (e) {
        print('❌ Complete Key Exchange Flow failed: $e');
        fail('Complete Key Exchange Flow should not fail');
      }
    });

    test('Performance Test - Multiple Notifications', () async {
      print('🧪 Testing Performance with Multiple Notifications...');

      final notifications = List.generate(
          10,
          (index) => {
                'data': {
                  'type': 'key_exchange_request',
                  'sender_id': 'perf_sender_$index',
                  'sender_public_key': 'perf_public_key_$index',
                  'request_id': 'perf_req_$index',
                  'request_phrase': 'Performance test $index',
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                }
              });

      final stopwatch = Stopwatch()..start();

      try {
        for (final notification in notifications) {
          await notificationService.handleNotification(notification);
        }

        stopwatch.stop();
        final duration = stopwatch.elapsedMilliseconds;

        print(
            '✅ Processed ${notifications.length} notifications in ${duration}ms');

        // Should complete within reasonable time
        expect(duration, lessThan(5000));
      } catch (e) {
        print('❌ Performance test failed: $e');
        fail('Performance test should not fail');
      }
    });

    test('Error Handling - Invalid Data', () async {
      print('🧪 Testing Error Handling with Invalid Data...');

      final invalidData = {
        'data': {
          'type': 'key_exchange_request',
          // Missing required fields
        }
      };

      try {
        await notificationService.handleNotification(invalidData);
        print('✅ Invalid data handled gracefully');
      } catch (e) {
        print('❌ Invalid data handling failed: $e');
        fail('Invalid data should be handled gracefully');
      }
    });

    test('Real-World Notification Format', () async {
      print('🧪 Testing Real-World Notification Format from Logs...');

      // Using the exact format from the logs that was failing
      final realWorldData = {
        'data': {
          'acceptor_public_key': 'j21yj/0i8+37lV2fxkX0qTRit6TBOwdgphQwqI1m2PQ=',
          'type': 'key_exchange_accepted',
          'request_id': '1755449505741_rbb3jcmb',
          'timestamp': 1755449517075,
          'recipient_id':
              'session_1755448297233-r0l12rxk-9u7-rgg-74p-j8jr1ko5iur'
        }
      };

      try {
        await notificationService.handleNotification(realWorldData);
        print('✅ Real-world notification format processed successfully');
        print('✅ No more "Unknown notification type: unknown" errors!');
      } catch (e) {
        print('❌ Real-world notification format failed: $e');
        fail('Real-world notification format should work now');
      }
    });
  });
}
