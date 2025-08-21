import 'dart:async';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'presence_service.dart';
import 'typing_service.dart';
import 'message_transport_service.dart';
import 'realtime_logger.dart';

/// Central manager for all realtime services
class RealtimeServiceManager {
  static final RealtimeServiceManager _instance =
      RealtimeServiceManager._internal();
  factory RealtimeServiceManager() => _instance;
  RealtimeServiceManager._internal();

  // Core services
  late final PresenceService _presenceService;
  late final TypingService _typingService;
  late final MessageTransportService _messageTransportService;
  late final SeSocketService _socketService;

  // Session service
  final SeSessionService _sessionService = SeSessionService();

  // Getters
  PresenceService get presence => _presenceService;
  TypingService get typing => _typingService;
  MessageTransportService get messageTransport => _messageTransportService;
  SeSocketService get socket => _socketService;

  /// Initialize all realtime services
  Future<void> initialize() async {
    try {
      RealtimeLogger.socket('Initializing realtime service manager');

      // Initialize core services
      _presenceService = PresenceService.instance;
      _typingService = TypingService.instance;
      _messageTransportService = MessageTransportService();
      _socketService = SeSocketService.instance;

      // Initialize the channel-based socket service
      await _socketService.initialize();

      // Initialize other services
      await _presenceService.initialize();

      RealtimeLogger.socket(
          'Realtime service manager initialized successfully');
    } catch (e) {
      RealtimeLogger.socket('Failed to initialize realtime service manager: $e',
          details: {'error': e.toString()});
      rethrow;
    }
  }

  /// Get service statistics
  Map<String, dynamic> getServiceStats() {
    return {
      'presence': _presenceService.getPresenceStats(),
      'typing': {'isActive': true}, // Simplified for now
      'messageTransport': {'deliveryStates': 0}, // Simplified for now
      'socket': {'isConnected': _socketService.isConnected},
    };
  }

  /// Dispose all services
  void dispose() {
    try {
      _presenceService.dispose();
      _typingService.dispose();
      // MessageTransportService doesn't have dispose method
      _socketService.dispose();
      RealtimeLogger.socket('Realtime service manager disposed');
    } catch (e) {
      RealtimeLogger.socket('Error disposing realtime service manager: $e');
    }
  }

  /// Get current session ID
  String? get currentSessionId => _sessionService.currentSessionId;

  /// Check if services are initialized
  bool get isInitialized => _presenceService.isInitialized;
}

/// Global access to realtime services
class RealtimeServices {
  static PresenceService get presence =>
      RealtimeServiceManager._instance.presence;
  static TypingService get typing => RealtimeServiceManager._instance.typing;
  static MessageTransportService get messageTransport =>
      RealtimeServiceManager._instance.messageTransport;
  static SeSocketService get socket => RealtimeServiceManager._instance.socket;
}
