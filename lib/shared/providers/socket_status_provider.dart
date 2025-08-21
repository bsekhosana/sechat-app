import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/se_socket_service.dart';
import '../../core/services/se_session_service.dart';

/// Provider to manage socket connection status across all screens
class SocketStatusProvider extends ChangeNotifier {
  static SocketStatusProvider? _instance;
  static SocketStatusProvider get instance =>
      _instance ??= SocketStatusProvider._();

  final SeSocketService _socketService = SeSocketService.instance;
  Timer? _statusTimer;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isVisible = false;
  String _statusMessage = '';
  Color _statusColor = Colors.orange;
  DateTime? _lastConnectionAttempt;
  int _reconnectionAttempts = 0;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isVisible => _isVisible;
  String get statusMessage => _statusMessage;
  Color get statusColor => _statusColor;
  DateTime? get lastConnectionAttempt => _lastConnectionAttempt;
  int get reconnectionAttempts => _reconnectionAttempts;

  SocketStatusProvider._() {
    _initialize();
  }

  void _initialize() {
    // Initial status check
    _checkSocketStatus();

    // Start periodic status monitoring
    _startPeriodicCheck();

    // Listen to socket connection changes
    _setupSocketListeners();
  }

  void _startPeriodicCheck() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkSocketStatus();
    });
  }

  void _setupSocketListeners() {
    // Listen to socket connection state changes
    // This will be called whenever the socket state changes
  }

  void _checkSocketStatus() {
    final wasConnected = _isConnected;
    final wasConnecting = _isConnecting;

    _isConnected = _socketService.isConnected;
    _isConnecting = _socketService.isConnecting;

    // Determine status message and color
    if (_isConnected) {
      _statusMessage = 'Connected to SeChat';
      _statusColor = Colors.green;
      _isVisible = false; // Hide when connected
      _reconnectionAttempts = 0; // Reset attempts on successful connection
    } else if (_isConnecting) {
      _statusMessage = 'Connecting to SeChat...';
      _statusColor = Colors.orange;
      _isVisible = true;
    } else {
      _statusMessage = 'Disconnected from SeChat';
      _statusColor = Colors.red;
      _isVisible = true;
    }

    // Only notify if status actually changed
    if (wasConnected != _isConnected || wasConnecting != _isConnecting) {
      notifyListeners();
    }
  }

  /// Attempt to reconnect the socket
  Future<bool> attemptReconnect() async {
    try {
      _isConnecting = true;
      _lastConnectionAttempt = DateTime.now();
      _reconnectionAttempts++;
      notifyListeners();

      print(
          'SocketStatusProvider: Attempting to reconnect (attempt $_reconnectionAttempts)...');

      // Try to reconnect
      await _socketService.connect(SeSessionService().currentSessionId!);

      // Wait a moment for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 1000));

      // Check if reconnection was successful
      _checkSocketStatus();

      if (_isConnected) {
        print('SocketStatusProvider: ✅ Reconnection successful');
        return true;
      } else {
        print('SocketStatusProvider: ❌ Reconnection failed');
        return false;
      }
    } catch (e) {
      print('SocketStatusProvider: ❌ Reconnection error: $e');
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  /// Force refresh the socket status
  void refreshStatus() {
    _checkSocketStatus();
  }

  /// Reset the provider state (used when account is deleted/created)
  void resetState() {
    try {
      print('🔌 SocketStatusProvider: 🔄 Resetting provider state...');

      // Reset all state variables
      _isConnected = false;
      _isConnecting = false;
      _isVisible = false;
      _statusMessage = '';
      _statusColor = Colors.orange;
      _lastConnectionAttempt = null;
      _reconnectionAttempts = 0;

      // Cancel any existing timers
      _statusTimer?.cancel();

      // Notify listeners
      notifyListeners();

      print('🔌 SocketStatusProvider: ✅ Provider state reset');
    } catch (e) {
      print('🔌 SocketStatusProvider: ❌ Error resetting state: $e');
    }
  }

  /// Check if socket is ready for operations
  bool get isReadyForOperations => _isConnected && !_isConnecting;

  /// Get connection status summary for debugging
  Map<String, dynamic> getConnectionStatus() {
    return {
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'isVisible': _isVisible,
      'statusMessage': _statusMessage,
      'reconnectionAttempts': _reconnectionAttempts,
      'lastConnectionAttempt': _lastConnectionAttempt?.toIso8601String(),
      'socketServiceConnected': _socketService.isConnected,
      'socketServiceConnecting': _socketService.isConnecting,
      'socketServiceReady': _socketService.isReadyToSend,
    };
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }
}
