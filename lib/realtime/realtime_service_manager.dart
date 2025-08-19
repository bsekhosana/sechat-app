import 'dart:async';
import 'presence_service.dart';
import 'typing_service.dart';
import 'message_transport.dart';
import 'socket_client.dart';
import 'realtime_logger.dart';
import '../core/services/se_socket_service.dart';

/// Central manager for all realtime services
/// Provides easy access and coordination between services
class RealtimeServiceManager {
  static RealtimeServiceManager? _instance;
  static RealtimeServiceManager get instance =>
      _instance ??= RealtimeServiceManager._();

  RealtimeServiceManager._();

  // Service instances
  late final PresenceService _presenceService;
  late final TypingService _typingService;
  late final MessageTransportService _messageTransportService;
  late final SocketClientService _socketClientService;

  // State
  bool _isInitialized = false;
  bool _isConnected = false;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;

  // Service access
  PresenceService get presence => _presenceService;
  TypingService get typing => _typingService;
  MessageTransportService get messages => _messageTransportService;
  SocketClientService get socket => _socketClientService;

  /// Initialize all realtime services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      RealtimeLogger.socket('Initializing realtime service manager');

      // Initialize individual services
      _presenceService = PresenceService.instance;
      _typingService = TypingService.instance;
      _messageTransportService = MessageTransportService.instance;
      _socketClientService = SocketClientService.instance;

      // Initialize socket client first (it coordinates others)
      await _socketClientService.initialize();

      // Set up connection state listener
      SeSocketService().connectionStateStream.listen((isConnected) {
        _isConnected = isConnected;
        RealtimeLogger.socket(
            'Realtime manager connection state: ${isConnected ? 'connected' : 'disconnected'}');
      });

      _isInitialized = true;

      RealtimeLogger.socket(
          'Realtime service manager initialized successfully');
    } catch (e) {
      RealtimeLogger.socket('Failed to initialize realtime service manager: $e',
          details: {'error': e.toString()});
      rethrow;
    }
  }

  /// Get comprehensive statistics from all services
  Map<String, dynamic> getAllStats() {
    if (!_isInitialized) {
      return {'error': 'Services not initialized'};
    }

    return {
      'manager': {
        'isInitialized': _isInitialized,
        'isConnected': _isConnected,
      },
      'presence': _presenceService.getPresenceStats(),
      'typing': _typingService.getTypingStats(),
      'messages': _messageTransportService.getDeliveryStats(),
      'socket': _socketClientService.getServiceStats(),
      'logger': RealtimeLogger.getEventStats(),
    };
  }

  /// Dispose all services
  void dispose() {
    if (!_isInitialized) return;

    RealtimeLogger.socket('Disposing realtime service manager');

    _presenceService.dispose();
    _typingService.dispose();
    _messageTransportService.dispose();
    _socketClientService.dispose();

    _isInitialized = false;
    _isConnected = false;

    RealtimeLogger.socket('Realtime service manager disposed');
  }
}

/// Extension methods for easy access to realtime services
extension RealtimeServices on Object {
  /// Get presence service
  PresenceService get presence => RealtimeServiceManager.instance.presence;

  /// Get typing service
  TypingService get typing => RealtimeServiceManager.instance.typing;

  /// Get message transport service
  MessageTransportService get messages =>
      RealtimeServiceManager.instance.messages;

  /// Get socket client service
  SocketClientService get socket => RealtimeServiceManager.instance.socket;

  /// Get realtime service manager
  RealtimeServiceManager get realtime => RealtimeServiceManager.instance;
}
