import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_chat_list_provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_session_chat_provider.dart';
import 'package:sechat_app/features/chat/services/optimized_chat_database_service.dart';
import 'package:sechat_app/core/services/optimized_notification_service.dart';
import 'package:sechat_app/features/chat/utils/optimized_chat_demo_data.dart';
import 'package:sechat_app/features/chat/utils/optimized_chat_health_check.dart';
import 'package:sechat_app/features/chat/utils/optimized_chat_performance_benchmark.dart';

/// Optimized Chat Test Screen
/// Test screen to verify all components work together
class OptimizedChatTestScreen extends StatefulWidget {
  const OptimizedChatTestScreen({super.key});

  @override
  State<OptimizedChatTestScreen> createState() =>
      _OptimizedChatTestScreenState();
}

class _OptimizedChatTestScreenState extends State<OptimizedChatTestScreen> {
  final _databaseService = OptimizedChatDatabaseService();
  final _notificationService = OptimizedNotificationService();

  String _testStatus = 'Ready to test';
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimized Chat Test'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildTestButtons(),
            const SizedBox(height: 16),
            _buildDatabaseInfo(),
            const SizedBox(height: 16),
            _buildNotificationInfo(),
          ],
        ),
      ),
    );
  }

  /// Build status card
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Test Status',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _testStatus,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_isTesting) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  /// Build test buttons
  Widget _buildTestButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _isTesting ? null : _testDatabaseConnection,
          child: const Text('Test Database Connection'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _testNotificationService,
          child: const Text('Test Notification Service'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _testProviders,
          child: const Text('Test Providers'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _testEndToEnd,
          child: const Text('Test End-to-End Flow'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _generateDemoData,
          style: ElevatedButton.styleFrom(foregroundColor: Colors.green),
          child: const Text('Generate Demo Data'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _runHealthCheck,
          style: ElevatedButton.styleFrom(foregroundColor: Colors.blue),
          child: const Text('Run Health Check'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _runPerformanceBenchmark,
          style: ElevatedButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text('Run Performance Benchmark'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _runStressTest,
          style: ElevatedButton.styleFrom(foregroundColor: Colors.purple),
          child: const Text('Run Stress Test'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isTesting ? null : _clearTestData,
          style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Clear Test Data'),
        ),
      ],
    );
  }

  /// Build database info card
  Widget _buildDatabaseInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Information',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, int>>(
              future: _databaseService.getDatabaseStats(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }

                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final stats = snapshot.data ?? {};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conversations: ${stats['conversations'] ?? 0}'),
                    Text('Messages: ${stats['messages'] ?? 0}'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build notification info card
  Widget _buildNotificationInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Service',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
                'Processed notifications: ${_notificationService.processedNotificationsCount}'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _clearProcessedNotifications,
              child: const Text('Clear Processed Notifications'),
            ),
          ],
        ),
      ),
    );
  }

  /// Test database connection
  Future<void> _testDatabaseConnection() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Testing database connection...';
    });

    try {
      final stats = await _databaseService.getDatabaseStats();

      setState(() {
        _testStatus = '✅ Database connection successful!\n'
            'Conversations: ${stats['conversations']}\n'
            'Messages: ${stats['messages']}';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ Database connection failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Test notification service
  Future<void> _testNotificationService() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Testing notification service...';
    });

    try {
      // Test message notification
      await _notificationService.handleNotification({
        'type': 'message',
        'senderId': 'test_user_1',
        'senderName': 'Test User 1',
        'message': 'This is a test message',
        'conversationId': 'test_conversation_1',
        'messageId': 'test_message_1',
      });

      // Test typing indicator
      await _notificationService.handleNotification({
        'type': 'typing_indicator',
        'senderId': 'test_user_1',
        'isTyping': true,
      });

      // Test online status
      await _notificationService.handleNotification({
        'type': 'online_status_update',
        'senderId': 'test_user_1',
        'isOnline': true,
        'lastSeen': DateTime.now().toIso8601String(),
      });

      setState(() {
        _testStatus = '✅ Notification service test successful!\n'
            'Processed notifications: ${_notificationService.processedNotificationsCount}';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ Notification service test failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Test providers
  Future<void> _testProviders() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Testing providers...';
    });

    try {
      final chatListProvider = context.read<OptimizedChatListProvider>();
      final sessionChatProvider = context.read<OptimizedSessionChatProvider>();

      // Test chat list provider
      await chatListProvider.initialize();

      // Test session chat provider
      await sessionChatProvider.initialize('test_conversation_1');

      setState(() {
        _testStatus = '✅ Providers test successful!\n'
            'Chat list provider initialized\n'
            'Session chat provider initialized';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ Providers test failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Test end-to-end flow
  Future<void> _testEndToEnd() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Testing end-to-end flow...';
    });

    try {
      // Create test conversation
      await _databaseService.saveConversation({
        'id': 'test_conversation_1',
        'participant1_id': 'test_user_1',
        'participant2_id': 'test_user_2',
        'display_name': 'Test Conversation',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_pinned': 0,
      });

      // Create test message
      await _databaseService.saveMessage({
        'id': 'test_message_1',
        'conversation_id': 'test_conversation_1',
        'sender_id': 'test_user_1',
        'recipient_id': 'test_user_2',
        'content': 'Hello, this is a test message!',
        'message_type': 'text',
        'status': 'delivered',
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      });

      // Test notification processing
      await _notificationService.handleNotification({
        'type': 'message',
        'senderId': 'test_user_1',
        'senderName': 'Test User 1',
        'message': 'Hello, this is a test message!',
        'conversationId': 'test_conversation_1',
        'messageId': 'test_message_1',
      });

      setState(() {
        _testStatus = '✅ End-to-end test successful!\n'
            'Test conversation created\n'
            'Test message created\n'
            'Notification processed';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ End-to-end test failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Generate demo data
  Future<void> _generateDemoData() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Generating demo data...';
    });

    try {
      await OptimizedChatDemoData.generateDemoData();

      setState(() {
        _testStatus = '✅ Demo data generated successfully!\n'
            '4 conversations created\n'
            '15 messages created\n'
            'Ready for testing!';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ Demo data generation failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Run complete health check
  Future<void> _runHealthCheck() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Running complete health check...';
    });

    try {
      final healthResults =
          await OptimizedChatHealthCheck.runCompleteHealthCheck();
      final overallHealth = healthResults['overall_health'] as int;

      setState(() {
        _testStatus = '✅ Health check completed!\n'
            'Overall Health Score: $overallHealth%\n'
            'Check console for detailed report';
      });

      // Print detailed health report to console
      print(OptimizedChatHealthCheck.generateHealthReport(healthResults));
    } catch (e) {
      setState(() {
        _testStatus = '❌ Health check failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Run performance benchmark
  Future<void> _runPerformanceBenchmark() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Running performance benchmark...';
    });

    try {
      final benchmarkResults =
          await OptimizedChatPerformanceBenchmark.runCompleteBenchmark();
      final overallPerformance = benchmarkResults['overall_performance'] as int;

      setState(() {
        _testStatus = '✅ Performance benchmark completed!\n'
            'Overall Performance Score: $overallPerformance%\n'
            'Check console for detailed report';
      });

      // Print detailed performance report to console
      print(OptimizedChatPerformanceBenchmark.generatePerformanceReport(
          benchmarkResults));
    } catch (e) {
      setState(() {
        _testStatus = '❌ Performance benchmark failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Run stress test
  Future<void> _runStressTest() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Running stress test with 100 notifications...';
    });

    try {
      final stressTestResults =
          await OptimizedChatPerformanceBenchmark.runStressTest(
              notificationCount: 100);
      final throughput =
          stressTestResults['throughput_notifications_per_second'] as int;

      setState(() {
        _testStatus = '✅ Stress test completed!\n'
            'Throughput: $throughput notifications/second\n'
            'Check console for detailed results';
      });

      // Print stress test results to console
      print('🧪 STRESS TEST RESULTS:');
      print('Total notifications: ${stressTestResults['total_notifications']}');
      print('Total time: ${stressTestResults['total_time_ms']}ms');
      print(
          'Average processing time: ${stressTestResults['avg_processing_time_ms']}ms');
      print('Throughput: $throughput notifications/second');
    } catch (e) {
      setState(() {
        _testStatus = '❌ Stress test failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Clear test data
  Future<void> _clearTestData() async {
    setState(() {
      _isTesting = true;
      _testStatus = 'Clearing test data...';
    });

    try {
      await _databaseService.clearAllData();
      _notificationService.clearProcessedNotifications();

      setState(() {
        _testStatus = '✅ Test data cleared successfully!';
      });
    } catch (e) {
      setState(() {
        _testStatus = '❌ Failed to clear test data: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// Clear processed notifications
  void _clearProcessedNotifications() {
    _notificationService.clearProcessedNotifications();
    setState(() {});
  }
}
