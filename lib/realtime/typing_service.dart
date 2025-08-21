import 'dart:async';
import 'dart:io';
import '../core/services/se_socket_service.dart';
import '../core/services/se_session_service.dart';
import 'realtime_logger.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';

/// Service to manage typing indicators with debouncing and heartbeat
class TypingService {
  static TypingService? _instance;
  static TypingService get instance => _instance ??= TypingService._();

  TypingService._();

  final SeSocketService _socketService = SeSocketService.instance;
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
      _sendTypingIndicator(conversationId, true);

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
      _sendTypingIndicator(conversationId, false);

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
      _sendTypingIndicator(conversationId, true);

      RealtimeLogger.typing('Typing session extended via heartbeat',
          convoId: conversationId);
    } catch (e) {
      RealtimeLogger.typing('Failed to extend typing session: $e',
          convoId: conversationId, details: {'error': e.toString()});
    }
  }

  /// Send typing indicator to the server
  void _sendTypingIndicator(String conversationId, bool isTyping) async {
    try {
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        print(
            '📝 TypingService: ❌ No session ID available for typing indicator');
        return;
      }

      // Get the recipient ID from the conversation ID
      final recipientId = ConversationIdGenerator.getOtherParticipant(
          conversationId, currentUserId);
      if (recipientId == null) {
        print(
            '📝 TypingService: ❌ Could not determine recipient from conversation: $conversationId');
        return;
      }

      // Use the new channel-based socket service
      final socketService = SeSocketService.instance;
      socketService.sendTypingIndicator(recipientId, isTyping);

      print(
          '📝 TypingService: ✅ Typing indicator sent via channel socket: $isTyping to $recipientId');
    } catch (e) {
      print('📝 TypingService: ❌ Failed to send typing indicator: $e');
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

  /// Handle incoming typing indicator from server/peer
  /// This method is called when we receive a typing indicator from another user
  void handleIncomingTypingIndicator(
      String conversationId, String fromUserId, bool isTyping) {
    try {
      RealtimeLogger.typing('Incoming typing indicator received',
          convoId: conversationId,
          peerId: fromUserId,
          details: {'isTyping': isTyping});

      print(
          '🔄 TypingService: 🔔 Incoming typing indicator: $fromUserId -> $isTyping in conversation $conversationId');
      print(
          '🔄 TypingService: 🔍 Current stream listeners: ${_typingController.hasListener ? 'Yes' : 'No'}');

      // Emit typing update for UI consumption
      _typingController.add(TypingUpdate(
        conversationId: conversationId,
        isTyping: isTyping,
        timestamp: DateTime.now(),
        source: 'peer', // This is from another user
      ));

      print('🔄 TypingService: ✅ Typing update emitted to stream');
      RealtimeLogger.typing('Incoming typing indicator processed',
          convoId: conversationId, peerId: fromUserId);
    } catch (e) {
      print(
          '🔄 TypingService: ❌ Failed to handle incoming typing indicator: $e');
      RealtimeLogger.typing('Failed to handle incoming typing indicator: $e',
          convoId: conversationId,
          peerId: fromUserId,
          details: {'error': e.toString()});
    }
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
