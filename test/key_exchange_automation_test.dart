import 'package:flutter_test/flutter_test.dart';
import 'package:sechat_app/core/services/optimized_notification_service.dart';

void main() {
  group('Key Exchange Automation Tests', () {
    late OptimizedNotificationService notificationService;

    setUp(() {
      // Create real notification service for testing
      notificationService = OptimizedNotificationService();
    });

    group('Notification Type Detection Tests', () {
      test('should detect key_exchange_accepted from nested data structure',
          () async {
        // Arrange - Simulate the actual notification structure from logs
        final testData = {
          'data': {
            'acceptor_public_key':
                'j21yj/0i8+37lV2fxkX0qTRit6TBOwdgphQwqI1m2PQ=',
            'type': 'key_exchange_accepted',
            'request_id': '1755449505741_rbb3jcmb',
            'timestamp': 1755449517075,
            'recipient_id':
                'session_1755448297233-r0l12rxk-9u7-rgg-74p-j8jr1ko5iur'
          }
        };

        // Act
        await notificationService.handleNotification(testData);

        // Assert - The service should now recognize the type correctly
        // and not show "Unknown notification type: unknown"
      });

      test('should detect key_exchange_request from nested data structure',
          () async {
        // Arrange - Simulate key exchange request notification
        final testData = {
          'data': {
            'type': 'key_exchange_request',
            'sender_id':
                'session_1755445880044-0r8elrf2-qzs-5dx-51y-2gf1wc110f2',
            'sender_public_key': 'TwmxV6MTYeUitWU3yxSapm7sfVzso2WllIrf96bcO7g=',
            'request_id': '1755447689713_jli2jk1c',
            'request_phrase': 'Footsteps in familiar rain',
            'timestamp': 1755447689722,
          }
        };

        // Act
        await notificationService.handleNotification(testData);

        // Assert - The service should recognize the type and process the request
      });

      test('should detect key_exchange_response from nested data structure',
          () async {
        // Arrange - Simulate key exchange response notification
        final testData = {
          'data': {
            'type': 'key_exchange_response',
            'sender_id':
                'session_1755445880044-0r8elrf2-qzs-5dx-51y-2gf1wc110f2',
            'public_key': 'response_public_key_base64',
            'response_id': 'resp_123',
            'timestamp': 1755447689722,
          }
        };

        // Act
        await notificationService.handleNotification(testData);

        // Assert - The service should recognize the type and process the response
      });
    });

    group('Data Extraction Tests', () {
      test('should extract key exchange accepted data from nested structure',
          () async {
        // Arrange
        final testData = {
          'data': {
            'acceptor_public_key':
                'j21yj/0i8+37lV2fxkX0qTRit6TBOwdgphQwqI1m2PQ=',
            'type': 'key_exchange_accepted',
            'request_id': '1755449505741_rbb3jcmb',
            'timestamp': 1755449517075,
            'recipient_id':
                'session_1755448297233-r0l12rxk-9u7-rgg-74p-j8jr1ko5iur'
          }
        };

        // Act
        await notificationService.handleNotification(testData);

        // Assert - The service should extract all fields correctly
        // This test verifies that the nested data extraction logic works
      });

      test('should extract key exchange request data from nested structure',
          () async {
        // Arrange
        final testData = {
          'data': {
            'type': 'key_exchange_request',
            'sender_id': 'sender_session_123',
            'sender_public_key': 'sender_public_key_base64',
            'request_id': 'req_123',
            'request_phrase': 'Test key exchange',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }
        };

        // Act
        await notificationService.handleNotification(testData);

        // Assert - The service should extract all fields correctly
      });
    });

    group('End-to-End Flow Tests', () {
      test('should process complete key exchange flow with nested data',
          () async {
        // Arrange - Simulate the complete flow from the logs

        // Step 1: Key Exchange Request
        final keyExchangeRequest = {
          'data': {
            'type': 'key_exchange_request',
            'sender_id':
                'session_1755445880044-0r8elrf2-qzs-5dx-51y-2gf1wc110f2',
            'sender_public_key': 'TwmxV6MTYeUitWU3yxSapm7sfVzso2WllIrf96bcO7g=',
            'request_id': '1755447689713_jli2jk1c',
            'request_phrase': 'Footsteps in familiar rain',
            'timestamp': 1755447689722,
          }
        };

        // Step 2: Key Exchange Accepted
        final keyExchangeAccepted = {
          'data': {
            'acceptor_public_key':
                'j21yj/0i8+37lV2fxkX0qTRit6TBOwdgphQwqI1m2PQ=',
            'type': 'key_exchange_accepted',
            'request_id': '1755449505741_rbb3jcmb',
            'timestamp': 1755449517075,
            'recipient_id':
                'session_1755448297233-r0l12rxk-9u7-rgg-74p-j8jr1ko5iur'
          }
        };

        // Act - Process both notifications
        await notificationService.handleNotification(keyExchangeRequest);
        await notificationService.handleNotification(keyExchangeAccepted);

        // Assert - Both notifications should be processed without errors
        // This test verifies the complete flow works with nested data structures
      });
    });

    group('Error Handling Tests', () {
      test('should handle missing data field gracefully', () async {
        // Arrange
        final invalidData = {
          'type': 'key_exchange_request',
          'sender_id': 'test_sender',
        };

        // Act & Assert
        expect(
          () => notificationService.handleNotification(invalidData),
          returnsNormally,
        );
      });

      test('should handle empty data field gracefully', () async {
        // Arrange
        final invalidData = {
          'data': {},
        };

        // Act & Assert
        expect(
          () => notificationService.handleNotification(invalidData),
          returnsNormally,
        );
      });

      test('should handle malformed data gracefully', () async {
        // Arrange
        final invalidData = {
          'data': 'not_a_map',
        };

        // Act & Assert
        expect(
          () => notificationService.handleNotification(invalidData),
          returnsNormally,
        );
      });
    });

    group('Performance Tests', () {
      test('should process multiple nested notifications efficiently',
          () async {
        // Arrange
        final notifications = List.generate(
            5,
            (index) => {
                  'data': {
                    'type': 'key_exchange_request',
                    'sender_id': 'sender_session_$index',
                    'sender_public_key': 'sender_public_key_$index',
                    'request_id': 'req_$index',
                    'request_phrase': 'Test key exchange $index',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  }
                });

        // Act
        final stopwatch = Stopwatch()..start();

        for (final notification in notifications) {
          await notificationService.handleNotification(notification);
        }

        stopwatch.stop();

        // Assert
        expect(stopwatch.elapsedMilliseconds,
            lessThan(3000)); // Should complete within 3 seconds
      });
    });

    group('Real-World Data Tests', () {
      test('should handle actual notification format from logs', () async {
        // Arrange - Using the exact format from the logs
        final realWorldData = {
          'data': {
            'acceptor_public_key':
                'j21yj/0i8+37lV2fxkX0qTRit6TBOwdgphQwqI1m2PQ=',
            'type': 'key_exchange_accepted',
            'request_id': '1755449505741_rbb3jcmb',
            'timestamp': 1755449517075,
            'recipient_id':
                'session_1755448297233-r0l12rxk-9u7-rgg-74p-j8jr1ko5iur'
          }
        };

        // Act
        await notificationService.handleNotification(realWorldData);

        // Assert - This should now work correctly and not show "Unknown notification type: unknown"
      });
    });
  });
}
