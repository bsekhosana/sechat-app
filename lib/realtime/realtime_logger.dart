import 'package:flutter/foundation.dart';

/// Structured logging for realtime features with feature tags and counters
class RealtimeLogger {
  static const String _tag = '🔄';

  // Feature tags for structured logging
  static const String _presenceTag = 'presence';
  static const String _typingTag = 'typing';
  static const String _messageTag = 'message';
  static const String _socketTag = 'socket';

  // Event counters
  static final Map<String, int> _eventCounters = {};

  /// Log presence-related events
  static void presence(
    String message, {
    String? convoId,
    String? peerId,
    Map<String, dynamic>? details,
  }) {
    _log(_presenceTag, message,
        convoId: convoId, peerId: peerId, details: details);
  }

  /// Log typing-related events
  static void typing(
    String message, {
    String? convoId,
    String? peerId,
    Map<String, dynamic>? details,
  }) {
    _log(_typingTag, message,
        convoId: convoId, peerId: peerId, details: details);
  }

  /// Log message-related events
  static void message(
    String message, {
    String? convoId,
    String? peerId,
    String? messageId,
    Map<String, dynamic>? details,
  }) {
    _log(_messageTag, message,
        convoId: convoId, peerId: peerId, details: details);
  }

  /// Log socket-related events
  static void socket(
    String message, {
    String? convoId,
    String? peerId,
    Map<String, dynamic>? details,
  }) {
    _log(_socketTag, message,
        convoId: convoId, peerId: peerId, details: details);
  }

  /// Internal logging method with structured format
  static void _log(
    String feature,
    String message, {
    String? convoId,
    String? peerId,
    String? messageId,
    Map<String, dynamic>? details,
  }) {
    // Increment event counter
    final counterKey = '${feature}_${message.split(' ').first}';
    _eventCounters[counterKey] = (_eventCounters[counterKey] ?? 0) + 1;

    // Build structured log message
    final tags = <String>[];
    if (convoId != null) tags.add('convo:$convoId');
    if (peerId != null) tags.add('peer:$peerId');
    if (messageId != null) tags.add('msg:$messageId');

    final tagString = tags.isNotEmpty ? ' [${tags.join(', ')}]' : '';
    final counterString = ' (${_eventCounters[counterKey]})';

    // Only log in debug mode or when LOG_LEVEL is set
    if (kDebugMode ||
        const bool.fromEnvironment('LOG_LEVEL', defaultValue: false)) {
      print('$_tag [$feature]$tagString $message$counterString');
      if (details != null && details.isNotEmpty) {
        print('$_tag [$feature] Details: $details');
      }
    }
  }

  /// Get event statistics
  static Map<String, int> getEventStats() => Map.from(_eventCounters);

  /// Reset event counters
  static void resetCounters() => _eventCounters.clear();
}
