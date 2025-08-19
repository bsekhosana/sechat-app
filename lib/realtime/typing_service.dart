import 'dart:async';
import 'dart:io';
import '../core/services/se_socket_service.dart';
import '../core/services/se_session_service.dart';
import 'realtime_logger.dart';

/// Service to manage typing indicators with debouncing and heartbeat
class TypingService {
  static TypingService? _instance;
  static TypingService get instance => _instance ??= TypingService._();

  TypingService._();

  final SeSocketService _socketService = SeSocketService();
  final SeSessionService _sessionService = SeSessionService();

  // Typing state per conversation
  final Map<String, TypingState> _typingStates = {};

  // Timers for debouncing and auto-stop
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, Timer> _autoStopTimers = {};

  // Constants
  static const Duration _debounceDelay = Duration(milliseconds: 250);
  static const Duration _heartbeatInterval = Duration(seconds: 3);
  static const Duration _autoStopDelay =
      Duration(seconds: 2); // Increased from 700ms to 2s
  static const Duration _serverTimeout = Duration(seconds: 4);

  // Stream controllers for typing updates
  final StreamController<TypingUpdate> _typingController =
      StreamController<TypingUpdate>.broadcast();

  // Getters
  Stream<TypingUpdate> get typingStream => _typingController.stream;

  /// Start typing in a conversation
  void startTyping(String conversationId, List<String> toUserIds) {
    try {
      RealtimeLogger.typing('Start typing requested',
          convoId: conversationId, peerId: toUserIds.join(','));

      // Get or create typing state
      final state = _typingStates.putIfAbsent(
          conversationId,
          () => TypingState(
                conversationId: conversationId,
                toUserIds: toUserIds,
                isTyping: false,
                lastActivity: DateTime.now(),
              ));

      // Update state
      state.isTyping = true;
      state.lastActivity = DateTime.now();

      // Cancel existing timers
      _cancelTimers(conversationId);

      // Send typing start immediately
      _sendTypingIndicator(conversationId, toUserIds, true);

      // Start heartbeat timer
      _startHeartbeatTimer(conversationId, toUserIds);

      // Start auto-stop timer
      _startAutoStopTimer(conversationId);

      // Notify listeners
      _typingController.add(TypingUpdate(
        conversationId: conversationId,
        isTyping: true,
        timestamp: DateTime.now(),
        source: 'local',
      ));

      RealtimeLogger.typing('Typing started successfully',
          convoId: conversationId);
    } catch (e) {
      RealtimeLogger.typing('Failed to start typing: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Stop typing in a conversation
  void stopTyping(String conversationId) {
    try {
      RealtimeLogger.typing('Stop typing requested', convoId: conversationId);

      final state = _typingStates[conversationId];
      if (state == null || !state.isTyping) return;

      // Update state
      state.isTyping = false;
      state.lastActivity = DateTime.now();

      // Cancel all timers
      _cancelTimers(conversationId);

      // Send typing stop immediately
      _sendTypingIndicator(conversationId, state.toUserIds, false);

      // Notify listeners
      _typingController.add(TypingUpdate(
        conversationId: conversationId,
        isTyping: false,
        timestamp: DateTime.now(),
        source: 'local',
      ));

      RealtimeLogger.typing('Typing stopped successfully',
          convoId: conversationId);
    } catch (e) {
      RealtimeLogger.typing('Failed to stop typing: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Handle text input activity (debounced)
  void onTextInput(String conversationId, List<String> toUserIds) {
    try {
      final state = _typingStates[conversationId];
      if (state == null) {
        // Create new state and start typing
        startTyping(conversationId, toUserIds);
        return;
      }

      // Update last activity
      state.lastActivity = DateTime.now();

      // Cancel existing debounce timer
      _debounceTimers[conversationId]?.cancel();

      // Start new debounce timer
      _debounceTimers[conversationId] = Timer(_debounceDelay, () {
        if (state.isTyping) {
          // Extend typing session
          _extendTypingSession(conversationId, toUserIds);
        } else {
          // Start typing
          startTyping(conversationId, toUserIds);
        }
      });

      RealtimeLogger.typing('Text input activity registered',
          convoId: conversationId,
          details: {'debounceDelay': _debounceDelay.inMilliseconds});
    } catch (e) {
      RealtimeLogger.typing('Failed to handle text input: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Extend typing session (called by heartbeat)
  void _extendTypingSession(String conversationId, List<String> toUserIds) {
    try {
      final state = _typingStates[conversationId];
      if (state == null || !state.isTyping) return;

      // Check if still active (within auto-stop window)
      final timeSinceLastActivity =
          DateTime.now().difference(state.lastActivity);
      if (timeSinceLastActivity > _autoStopDelay) {
        // Auto-stop typing
        stopTyping(conversationId);
        return;
      }

      // Send heartbeat typing indicator
      _sendTypingIndicator(conversationId, toUserIds, true);

      RealtimeLogger.typing('Typing session extended via heartbeat',
          convoId: conversationId);
    } catch (e) {
      RealtimeLogger.typing('Failed to extend typing session: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Send typing indicator to server
  void _sendTypingIndicator(
      String conversationId, List<String> toUserIds, bool isTyping) {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) {
        RealtimeLogger.typing('No session ID available for typing indicator');
        return;
      }

      final typingData = {
        'type': 'typing',
        'conversationId': conversationId,
        'fromUserId': sessionId,
        'toUserIds': toUserIds,
        'isTyping': isTyping,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (_socketService.isConnected) {
        _socketService.emit('typing', typingData);
        RealtimeLogger.typing(
            'Typing indicator sent to server: ${isTyping ? 'start' : 'stop'}',
            convoId: conversationId,
            peerId: toUserIds.join(','));
      } else {
        RealtimeLogger.typing('Socket not connected, typing indicator queued',
            convoId: conversationId);
        // Note: Server will handle TTL if socket is disconnected
      }
    } catch (e) {
      RealtimeLogger.typing('Failed to send typing indicator: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Start heartbeat timer
  void _startHeartbeatTimer(String conversationId, List<String> toUserIds) {
    _heartbeatTimers[conversationId]?.cancel();

    _heartbeatTimers[conversationId] =
        Timer.periodic(_heartbeatInterval, (timer) {
      final state = _typingStates[conversationId];
      if (state == null || !state.isTyping) {
        timer.cancel();
        return;
      }

      _extendTypingSession(conversationId, toUserIds);
    });

    RealtimeLogger.typing(
        'Heartbeat timer started (${_heartbeatInterval.inSeconds}s)',
        convoId: conversationId);
  }

  /// Start auto-stop timer
  void _startAutoStopTimer(String conversationId) {
    _autoStopTimers[conversationId]?.cancel();

    _autoStopTimers[conversationId] = Timer(_autoStopDelay, () {
      final state = _typingStates[conversationId];
      if (state != null && state.isTyping) {
        // Auto-stop typing after idle period
        stopTyping(conversationId);
        RealtimeLogger.typing('Typing auto-stopped due to inactivity',
            convoId: conversationId);
      }
    });

    RealtimeLogger.typing(
        'Auto-stop timer started (${_autoStopDelay.inMilliseconds}ms)',
        convoId: conversationId);
  }

  /// Cancel all timers for a conversation
  void _cancelTimers(String conversationId) {
    _debounceTimers[conversationId]?.cancel();
    _heartbeatTimers[conversationId]?.cancel();
    _autoStopTimers[conversationId]?.cancel();

    _debounceTimers.remove(conversationId);
    _heartbeatTimers.remove(conversationId);
    _autoStopTimers.remove(conversationId);
  }

  /// Get typing state for a conversation
  TypingState? getTypingState(String conversationId) {
    return _typingStates[conversationId];
  }

  /// Check if user is typing in a conversation
  bool isTyping(String conversationId) {
    return _typingStates[conversationId]?.isTyping ?? false;
  }

  /// Get typing statistics
  Map<String, dynamic> getTypingStats() {
    final activeConversations =
        _typingStates.values.where((state) => state.isTyping).length;

    return {
      'activeConversations': activeConversations,
      'totalConversations': _typingStates.length,
      'debounceDelay': _debounceDelay.inMilliseconds,
      'heartbeatInterval': _heartbeatInterval.inSeconds,
      'autoStopDelay': _autoStopDelay.inMilliseconds,
      'serverTimeout': _serverTimeout.inSeconds,
    };
  }

  /// Dispose the service
  void dispose() {
    // Cancel all timers
    for (final conversationId in _typingStates.keys) {
      _cancelTimers(conversationId);
    }

    _typingController.close();
    _typingStates.clear();

    RealtimeLogger.typing('Typing service disposed');
  }
}

/// Typing state for a conversation
class TypingState {
  final String conversationId;
  final List<String> toUserIds;
  bool isTyping;
  DateTime lastActivity;

  TypingState({
    required this.conversationId,
    required this.toUserIds,
    required this.isTyping,
    required this.lastActivity,
  });

  @override
  String toString() =>
      'TypingState(conversationId: $conversationId, isTyping: $isTyping)';
}

/// Typing update event
class TypingUpdate {
  final String conversationId;
  final bool isTyping;
  final DateTime timestamp;
  final String source; // 'local', 'server', 'peer'

  TypingUpdate({
    required this.conversationId,
    required this.isTyping,
    required this.timestamp,
    required this.source,
  });

  @override
  String toString() =>
      'TypingUpdate(conversationId: $conversationId, isTyping: $isTyping, source: $source)';
}
