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

  // iOS validation throttling
  DateTime? _lastiOSValidation;

  // Connection state logging throttling
  DateTime? _lastConnectionStateLog;

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
      // Throttle logging to prevent spam
      final now = DateTime.now();
      if (_lastConnectionStateLog == null ||
          now.difference(_lastConnectionStateLog!).inSeconds >= 2) {
        print('🔌 SocketProvider: Connection state changed: $isConnected');
        _lastConnectionStateLog = now;
      }

      // Force sync all state from socket service to ensure consistency
      _syncAllStateFromSocketService();

      // Additional iOS-specific state validation
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _validateiOSConnectionState();
      }

      // Always notify listeners when state changes
      notifyListeners();

      // Log the final state after sync
      print(
          '🔌 SocketProvider: Final state after sync - Connected: $_isConnected, Connecting: $_isConnecting');
    });
    print('🔌 SocketProvider: Connection state listener set up successfully');
  }

  /// Sync all state from socket service to ensure consistency
  void _syncAllStateFromSocketService() {
    final wasConnected = _isConnected;
    final wasConnecting = _isConnecting;

    _isConnected = _socketService.isConnected;
    _isConnecting = _socketService.isConnecting;
    _currentSessionId = _socketService.currentSessionId;

    if (_isConnected) {
      _connectionError = null;
      _reconnectAttempts = 0;
    }

    // Always log state changes, but throttle repeated identical states
    final now = DateTime.now();
    if (_lastConnectionStateLog == null ||
        now.difference(_lastConnectionStateLog!).inSeconds >= 2 ||
        wasConnected != _isConnected ||
        wasConnecting != _isConnecting) {
      print(
          '🔌 SocketProvider: State synced from socket service - Connected: $_isConnected, Connecting: $_isConnecting');
      _lastConnectionStateLog = now;
    }
  }

  /// iOS-specific connection state validation
  void _validateiOSConnectionState() {
    // Only validate if we haven't done so recently (throttle to prevent spam)
    final now = DateTime.now();
    if (_lastiOSValidation != null &&
        now.difference(_lastiOSValidation!).inSeconds < 10) {
      return; // Skip validation if done recently
    }

    // On iOS, socket state can sometimes be inconsistent
    // Force a status refresh from the socket service
    _socketService.refreshConnectionStatus();

    // Double-check the actual socket connection state
    final actualSocketState = _socketService.getSocketStatus();
    final actualConnected =
        actualSocketState['socketConnected'] as bool? ?? false;

    if (_isConnected != actualConnected) {
      print(
          '🔌 SocketProvider: iOS state mismatch detected! Provider: $_isConnected, Socket: $actualConnected');
      _isConnected = actualConnected;
    }

    _lastiOSValidation = now;
    print('🔌 SocketProvider: iOS connection state validated');
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
    _syncAllStateFromSocketService();

    // Additional iOS-specific validation
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _validateiOSConnectionState();
    }

    notifyListeners();
    print(
        '🔌 SocketProvider: Synced connection state - Connected: $_isConnected, Connecting: $_isConnecting');
  }

  /// Force refresh connection state
  void refreshConnectionState() {
    print('🔌 SocketProvider: Refreshing connection state...');

    // Force the socket service to refresh its status first
    _socketService.refreshConnectionStatus();

    // Then sync our state
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

      // Wait a bit for the socket to stabilize
      await Future.delayed(const Duration(milliseconds: 500));

      // Force a complete state refresh
      syncConnectionState();

      // Double-check the state after a delay
      Future.delayed(const Duration(seconds: 1), () {
        print('🔌 SocketProvider: Double-checking state after reconnect...');
        syncConnectionState();
      });

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
