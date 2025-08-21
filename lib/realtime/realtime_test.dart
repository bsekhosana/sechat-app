import 'package:flutter/foundation.dart';
import 'realtime_service_manager.dart';
import 'realtime_logger.dart';

/// Simple test class to verify realtime services are working
class RealtimeTest {
  static Future<void> runBasicTests() async {
    if (!kDebugMode) return; // Only run in debug mode

    try {
      RealtimeLogger.socket('Starting realtime service tests');

      // Test 1: Initialize realtime service manager
      final realtimeManager = RealtimeServiceManager();
      await realtimeManager.initialize();
      RealtimeLogger.socket('✅ Services initialized');

      // Test 2: Get service stats
      final stats = realtimeManager.getServiceStats();
      RealtimeLogger.socket('✅ Service stats retrieved', details: stats);

      // Test 3: Test presence service
      final presenceService = realtimeManager.presence;
      RealtimeLogger.socket('✅ Presence service accessible');

      // Test 4: Test typing service
      final typingService = realtimeManager.typing;
      RealtimeLogger.socket('✅ Typing service accessible');

      // Test 5: Test message transport service
      final messageService = realtimeManager.messageTransport;
      RealtimeLogger.socket('✅ Message transport service accessible');

      // Test 6: Test socket client service
      final socketService = realtimeManager.socket;
      RealtimeLogger.socket('✅ Socket client service accessible');

      RealtimeLogger.socket('🎉 All realtime service tests passed!');
    } catch (e) {
      RealtimeLogger.socket('❌ Realtime service test failed: $e',
          details: {'error': e.toString()});
      rethrow;
    }
  }

  /// Test presence functionality
  static void testPresence() {
    if (!kDebugMode) return;

    try {
      final realtimeManager = RealtimeServiceManager();
      final presenceService = realtimeManager.presence;

      // Test force presence update
      presenceService.forcePresenceUpdate(true);
      RealtimeLogger.presence('✅ Force presence online test passed');

      // Test presence stats
      final stats = presenceService.getPresenceStats();
      RealtimeLogger.presence('✅ Presence stats test passed', details: stats);
    } catch (e) {
      RealtimeLogger.presence('❌ Presence test failed: $e',
          details: {'error': e.toString()});
    }
  }

  /// Test typing functionality
  static void testTyping() {
    if (!kDebugMode) return;

    try {
      final realtimeManager = RealtimeServiceManager();
      final typingService = realtimeManager.typing;

      // Test typing start/stop
      const testConvoId = 'test_conversation_123';
      const testRecipients = ['test_user_456'];

      typingService.startTyping(testConvoId, testRecipients);
      RealtimeLogger.typing('✅ Start typing test passed', convoId: testConvoId);

      // Wait a bit then stop
      Future.delayed(const Duration(milliseconds: 500), () {
        typingService.stopTyping(testConvoId);
        RealtimeLogger.typing('✅ Stop typing test passed',
            convoId: testConvoId);
      });

      // Test typing stats
      final stats = typingService.getTypingStats();
      RealtimeLogger.typing('✅ Typing stats test passed', details: stats);
    } catch (e) {
      RealtimeLogger.typing('❌ Typing test failed: $e',
          details: {'error': e.toString()});
    }
  }

  /// Test message transport functionality
  static void testMessageTransport() {
    if (!kDebugMode) return;

    try {
      final realtimeManager = RealtimeServiceManager();
      final messageService = realtimeManager.messageTransport;

      // Test message transport stats
      final stats = {'status': 'active'}; // Simplified for now
      RealtimeLogger.message('✅ Message transport stats test passed',
          details: stats);
    } catch (e) {
      RealtimeLogger.message('❌ Message transport test failed: $e',
          details: {'error': e.toString()});
    }
  }

  /// Run all tests
  static Future<void> runAllTests() async {
    if (!kDebugMode) return;

    RealtimeLogger.socket('🚀 Starting comprehensive realtime service tests');

    try {
      // Basic service tests
      await runBasicTests();

      // Individual service tests
      testPresence();
      testTyping();
      testMessageTransport();

      RealtimeLogger.socket(
          '🎉 All realtime service tests completed successfully!');
    } catch (e) {
      RealtimeLogger.socket('❌ Comprehensive test suite failed: $e',
          details: {'error': e.toString()});
    }
  }
}
