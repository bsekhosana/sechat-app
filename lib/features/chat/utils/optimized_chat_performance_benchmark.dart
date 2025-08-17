import 'dart:async';
import 'package:sechat_app/features/chat/services/optimized_chat_database_service.dart';
import 'package:sechat_app/core/services/optimized_notification_service.dart';

/// Optimized Chat Performance Benchmark
/// Performance testing and benchmarking utilities
class OptimizedChatPerformanceBenchmark {
  static final _databaseService = OptimizedChatDatabaseService();
  static final _notificationService = OptimizedNotificationService();

  /// Run complete performance benchmark
  static Future<Map<String, dynamic>> runCompleteBenchmark() async {
    final results = <String, dynamic>{};

    try {
      print(
          '⚡ OptimizedChatPerformanceBenchmark: 🚀 Starting performance benchmark...');

      // Database performance benchmark
      results['database'] = await _benchmarkDatabasePerformance();

      // Notification service performance benchmark
      results['notification_service'] =
          await _benchmarkNotificationServicePerformance();

      // Overall performance score
      results['overall_performance'] = _calculateOverallPerformance(results);

      print(
          '⚡ OptimizedChatPerformanceBenchmark: ✅ Performance benchmark completed!');
      print(
          '⚡ OptimizedChatPerformanceBenchmark: 📊 Overall Performance Score: ${results['overall_performance']}%');
    } catch (e) {
      print(
          '⚡ OptimizedChatPerformanceBenchmark: ❌ Performance benchmark failed: $e');
      results['error'] = e.toString();
      results['overall_performance'] = 0;
    }

    return results;
  }

  /// Benchmark database performance
  static Future<Map<String, dynamic>> _benchmarkDatabasePerformance() async {
    final results = <String, dynamic>{};

    try {
      // Benchmark database connection
      final connectionStart = DateTime.now();
      await _databaseService.database;
      final connectionTime =
          DateTime.now().difference(connectionStart).inMilliseconds;
      results['connection_time_ms'] = connectionTime;

      // Benchmark read operations
      final readStart = DateTime.now();
      await _databaseService.getDatabaseStats();
      final readTime = DateTime.now().difference(readStart).inMilliseconds;
      results['read_time_ms'] = readTime;

      // Benchmark write operations
      final writeStart = DateTime.now();
      await _databaseService.saveConversation({
        'id': 'benchmark_conv_${DateTime.now().millisecondsSinceEpoch}',
        'participant1_id': 'benchmark_user_1',
        'participant2_id': 'benchmark_user_2',
        'display_name': 'Benchmark Conversation',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_pinned': 0,
      });
      final writeTime = DateTime.now().difference(writeStart).inMilliseconds;
      results['write_time_ms'] = writeTime;

      // Calculate performance score
      final connectionScore =
          _calculateTimeScore(connectionTime, 100); // 100ms threshold
      final readScore = _calculateTimeScore(readTime, 50); // 50ms threshold
      final writeScore = _calculateTimeScore(writeTime, 100); // 100ms threshold

      final avgScore = (connectionScore + readScore + writeScore) / 3;
      results['performance_score'] = avgScore.round();
      results['status'] = avgScore >= 80
          ? 'excellent'
          : avgScore >= 60
              ? 'good'
              : 'needs_improvement';
    } catch (e) {
      results['connection_time_ms'] = -1;
      results['read_time_ms'] = -1;
      results['write_time_ms'] = -1;
      results['performance_score'] = 0;
      results['status'] = 'failed';
    }

    return results;
  }

  /// Benchmark notification service performance
  static Future<Map<String, dynamic>>
      _benchmarkNotificationServicePerformance() async {
    final results = <String, dynamic>{};

    try {
      // Benchmark notification processing
      final processingTimes = <int>[];

      for (int i = 0; i < 10; i++) {
        final start = DateTime.now();
        await _notificationService.handleNotification({
          'type': 'message',
          'senderId': 'benchmark_user_$i',
          'senderName': 'Benchmark User $i',
          'message': 'Benchmark message $i',
          'conversationId': 'benchmark_conv_$i',
          'messageId': 'benchmark_msg_$i',
        });
        final time = DateTime.now().difference(start).inMilliseconds;
        processingTimes.add(time);
      }

      // Calculate statistics
      final avgTime =
          processingTimes.reduce((a, b) => a + b) / processingTimes.length;
      final minTime = processingTimes.reduce((a, b) => a < b ? a : b);
      final maxTime = processingTimes.reduce((a, b) => a > b ? a : b);

      results['avg_processing_time_ms'] = avgTime.round();
      results['min_processing_time_ms'] = minTime;
      results['max_processing_time_ms'] = maxTime;
      results['total_notifications'] = processingTimes.length;

      // Calculate performance score
      final processingScore =
          _calculateTimeScore(avgTime.round(), 20); // 20ms threshold
      results['performance_score'] = processingScore.round();
      results['status'] = processingScore >= 80
          ? 'excellent'
          : processingScore >= 60
              ? 'good'
              : 'needs_improvement';
    } catch (e) {
      results['avg_processing_time_ms'] = -1;
      results['min_processing_time_ms'] = -1;
      results['max_processing_time_ms'] = -1;
      results['total_notifications'] = 0;
      results['performance_score'] = 0;
      results['status'] = 'failed';
    }

    return results;
  }

  /// Calculate time-based performance score
  static int _calculateTimeScore(int timeMs, int thresholdMs) {
    if (timeMs <= thresholdMs) return 100;
    if (timeMs <= thresholdMs * 2) return 80;
    if (timeMs <= thresholdMs * 3) return 60;
    if (timeMs <= thresholdMs * 4) return 40;
    if (timeMs <= thresholdMs * 5) return 20;
    return 0;
  }

  /// Calculate overall performance score
  static int _calculateOverallPerformance(Map<String, dynamic> results) {
    int totalScore = 0;
    int componentCount = 0;

    for (final component in results.values) {
      if (component is Map<String, dynamic> &&
          component.containsKey('performance_score')) {
        totalScore += component['performance_score'] as int;
        componentCount++;
      }
    }

    if (componentCount == 0) return 0;
    return (totalScore / componentCount).round();
  }

  /// Generate performance report
  static String generatePerformanceReport(
      Map<String, dynamic> benchmarkResults) {
    final buffer = StringBuffer();

    buffer.writeln('⚡ OPTIMIZED CHAT PERFORMANCE REPORT');
    buffer.writeln('====================================');
    buffer.writeln();

    // Overall performance
    final overallPerformance = benchmarkResults['overall_performance'] as int;
    buffer.writeln('📊 OVERALL PERFORMANCE SCORE: $overallPerformance%');
    buffer.writeln();

    // Database performance
    final database = benchmarkResults['database'] as Map<String, dynamic>;
    buffer.writeln('🗄️ DATABASE PERFORMANCE: ${database['status']}');
    buffer.writeln('   Connection Time: ${database['connection_time_ms']}ms');
    buffer.writeln('   Read Time: ${database['read_time_ms']}ms');
    buffer.writeln('   Write Time: ${database['write_time_ms']}ms');
    buffer.writeln('   Performance Score: ${database['performance_score']}%');
    buffer.writeln();

    // Notification service performance
    final notificationService =
        benchmarkResults['notification_service'] as Map<String, dynamic>;
    buffer.writeln(
        '🔔 NOTIFICATION SERVICE PERFORMANCE: ${notificationService['status']}');
    buffer.writeln(
        '   Average Processing Time: ${notificationService['avg_processing_time_ms']}ms');
    buffer.writeln(
        '   Min Processing Time: ${notificationService['min_processing_time_ms']}ms');
    buffer.writeln(
        '   Max Processing Time: ${notificationService['max_processing_time_ms']}ms');
    buffer.writeln(
        '   Total Notifications: ${notificationService['total_notifications']}');
    buffer.writeln(
        '   Performance Score: ${notificationService['performance_score']}%');
    buffer.writeln();

    // Performance recommendations
    buffer.writeln('💡 PERFORMANCE RECOMMENDATIONS:');
    if (overallPerformance >= 90) {
      buffer.writeln('   ✅ Performance is excellent - no optimizations needed');
    } else if (overallPerformance >= 70) {
      buffer.writeln('   ⚠️ Performance is good but could be improved');
    } else if (overallPerformance >= 50) {
      buffer.writeln(
          '   ⚠️ Performance needs improvement - consider optimizations');
    } else {
      buffer.writeln(
          '   ❌ Performance is poor - significant optimizations required');
    }

    // Specific recommendations
    if (database['performance_score'] < 80) {
      buffer.writeln('   🗄️ Consider database query optimization or indexing');
    }
    if (notificationService['performance_score'] < 80) {
      buffer.writeln('   🔔 Consider notification processing optimization');
    }

    return buffer.toString();
  }

  /// Quick performance check
  static Future<bool> isPerformanceAcceptable() async {
    try {
      final benchmarkResults = await runCompleteBenchmark();
      final overallPerformance = benchmarkResults['overall_performance'] as int;
      return overallPerformance >= 70; // 70% threshold for acceptable
    } catch (e) {
      print(
          '⚡ OptimizedChatPerformanceBenchmark: ❌ Quick performance check failed: $e');
      return false;
    }
  }

  /// Stress test with multiple notifications
  static Future<Map<String, dynamic>> runStressTest(
      {int notificationCount = 100}) async {
    final results = <String, dynamic>{};

    try {
      print(
          '⚡ OptimizedChatPerformanceBenchmark: 🧪 Starting stress test with $notificationCount notifications...');

      final startTime = DateTime.now();
      final processingTimes = <int>[];

      for (int i = 0; i < notificationCount; i++) {
        final notificationStart = DateTime.now();
        await _notificationService.handleNotification({
          'type': 'message',
          'senderId': 'stress_test_user_$i',
          'senderName': 'Stress Test User $i',
          'message': 'Stress test message $i',
          'conversationId': 'stress_test_conv_$i',
          'messageId': 'stress_test_msg_$i',
        });
        final time =
            DateTime.now().difference(notificationStart).inMilliseconds;
        processingTimes.add(time);
      }

      final totalTime = DateTime.now().difference(startTime);
      final avgTime =
          processingTimes.reduce((a, b) => a + b) / processingTimes.length;

      results['total_notifications'] = notificationCount;
      results['total_time_ms'] = totalTime.inMilliseconds;
      results['avg_processing_time_ms'] = avgTime.round();
      results['throughput_notifications_per_second'] =
          (notificationCount / (totalTime.inMilliseconds / 1000)).round();
      results['status'] = 'completed';

      print('⚡ OptimizedChatPerformanceBenchmark: ✅ Stress test completed!');
      print(
          '⚡ OptimizedChatPerformanceBenchmark: 📊 Throughput: ${results['throughput_notifications_per_second']} notifications/second');
    } catch (e) {
      results['status'] = 'failed';
      results['error'] = e.toString();
      print('⚡ OptimizedChatPerformanceBenchmark: ❌ Stress test failed: $e');
    }

    return results;
  }
}
