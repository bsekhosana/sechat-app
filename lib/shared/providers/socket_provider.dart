import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';

/// Socket Provider
/// Manages socket service state and provides it to the app
class SocketProvider extends ChangeNotifier {
  final SeSocketService _socketService = SeSocketService();

  // Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _currentSessionId;
  String? _connectionError;
  int _reconnectAttempts = 0;

  // Getters
  SeSocketService get socketService => _socketService;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentSessionId => _currentSessionId;
  String? get connectionError => _connectionError;
  int get reconnectAttempts => _reconnectAttempts;

  /// Initialize socket connection
  Future<bool> initialize() async {
    try {
      _isConnecting = true;
      _connectionError = null;
      notifyListeners();

      print('🔌 SocketProvider: Initializing socket...');

      final success = await _socketService.initialize();

      if (success) {
        _isConnected = true;
        _currentSessionId = _socketService.currentSessionId;
        _reconnectAttempts = 0;
        print('🔌 SocketProvider: ✅ Socket initialized successfully');

        // Listen to connection state changes from the socket service
        _setupConnectionStateListener();
      } else {
        _connectionError = 'Failed to initialize socket';
        print('🔌 SocketProvider: ❌ Socket initialization failed');
      }

      _isConnecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isConnecting = false;
      _connectionError = 'Error: $e';
      print('🔌 SocketProvider: ❌ Socket initialization error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Setup connection state listener
  void _setupConnectionStateListener() {
    print('🔌 SocketProvider: Setting up connection state listener...');
    _socketService.connectionStateStream.listen((isConnected) {
      print('🔌 SocketProvider: Connection state changed: $isConnected');
      _isConnected = isConnected;
      if (isConnected) {
        _currentSessionId = _socketService.currentSessionId;
        _connectionError = null;
        _reconnectAttempts = 0;
      }
      notifyListeners();
      print(
          '🔌 SocketProvider: Notified listeners, new state - Connected: $_isConnected, Connecting: $_isConnecting');
    });
    print('🔌 SocketProvider: Connection state listener set up successfully');
  }

  /// Disconnect socket
  Future<void> disconnect() async {
    try {
      print('🔌 SocketProvider: Disconnecting socket...');

      await _socketService.disconnect();

      _isConnected = false;
      _isConnecting = false;
      _currentSessionId = null;
      _connectionError = null;
      _reconnectAttempts = 0;

      print('🔌 SocketProvider: ✅ Socket disconnected');
      notifyListeners();
    } catch (e) {
      print('🔌 SocketProvider: ❌ Error disconnecting socket: $e');
      _connectionError = 'Error disconnecting: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Clean up any active listeners
    super.dispose();
  }

  /// Update connection status
  void updateConnectionStatus({
    bool? isConnected,
    bool? isConnecting,
    String? sessionId,
    String? error,
    int? reconnectAttempts,
  }) {
    bool shouldNotify = false;

    if (isConnected != null && _isConnected != isConnected) {
      _isConnected = isConnected;
      shouldNotify = true;
    }

    if (isConnecting != null && _isConnecting != isConnecting) {
      _isConnecting = isConnecting;
      shouldNotify = true;
    }

    if (sessionId != null && _currentSessionId != sessionId) {
      _currentSessionId = sessionId;
      shouldNotify = true;
    }

    if (error != null && _connectionError != error) {
      _connectionError = error;
      shouldNotify = true;
    }

    if (reconnectAttempts != null && _reconnectAttempts != reconnectAttempts) {
      _reconnectAttempts = reconnectAttempts;
      shouldNotify = true;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  /// Clear connection error
  void clearError() {
    if (_connectionError != null) {
      _connectionError = null;
      notifyListeners();
    }
  }

  /// Sync connection state with socket service
  void syncConnectionState() {
    _isConnected = _socketService.isConnected;
    _isConnecting = _socketService.isConnecting;
    _currentSessionId = _socketService.currentSessionId;
    notifyListeners();
    print(
        '🔌 SocketProvider: Synced connection state - Connected: $_isConnected, Connecting: $_isConnecting');
  }

  /// Force refresh connection state
  void refreshConnectionState() {
    print('🔌 SocketProvider: Refreshing connection state...');
    syncConnectionState();

    // Also check if we need to set up the listener
    if (_isConnected) {
      print('🔌 SocketProvider: Setting up connection state listener...');
      _setupConnectionStateListener();
    }
  }

  /// Get connection status text
  String get connectionStatusText {
    if (_isConnecting) return 'Connecting...';
    if (_isConnected) return 'Connected';
    if (_connectionError != null) return 'Error: $_connectionError';
    if (_reconnectAttempts > 0)
      return 'Reconnecting... (${_reconnectAttempts})';
    return 'Disconnected';
  }

  /// Get connection status color
  String get connectionStatusColor {
    if (_isConnected) return 'green';
    if (_isConnecting) return 'orange';
    if (_connectionError != null) return 'red';
    if (_reconnectAttempts > 0) return 'orange';
    return 'grey';
  }

  /// Manually test connection
  Future<bool> testConnection() async {
    try {
      print('🔌 SocketProvider: Testing connection...');
      final success = await _socketService.testConnection();
      print('🔌 SocketProvider: Connection test result: $success');
      return success;
    } catch (e) {
      print('🔌 SocketProvider: ❌ Connection test error: $e');
      return false;
    }
  }

  /// Force manual connection
  Future<void> forceManualConnection() async {
    try {
      print('🔌 SocketProvider: Force manual connection requested...');
      await _socketService.manualConnect();
      syncConnectionState();
    } catch (e) {
      print('🔌 SocketProvider: ❌ Force manual connection error: $e');
    }
  }

  /// Emergency reconnect
  Future<void> emergencyReconnect() async {
    try {
      print('🔌 SocketProvider: Emergency reconnect requested...');
      await _socketService.emergencyReconnect();
      syncConnectionState();
      notifyListeners();
    } catch (e) {
      print('🔌 SocketProvider: ❌ Emergency reconnect error: $e');
    }
  }

  /// Debug print current state
  void debugPrintState() {
    print('🔌 SocketProvider: === DEBUG STATE ===');
    print('🔌 SocketProvider: isConnected: $_isConnected');
    print('🔌 SocketProvider: isConnecting: $_isConnecting');
    print('🔌 SocketProvider: currentSessionId: $_currentSessionId');
    print('🔌 SocketProvider: connectionError: $_connectionError');
    print('🔌 SocketProvider: reconnectAttempts: $_reconnectAttempts');
    print('🔌 SocketProvider: === END DEBUG STATE ===');

    // Also call the socket service debug method
    _socketService.debugPrintState();
  }
}
