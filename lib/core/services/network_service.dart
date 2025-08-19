import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkService extends ChangeNotifier {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _reconnectionTimer;
  Timer? _connectionTestTimer;
  int _reconnectionCountdown = 0;
  final bool _isPollingEnabled = true;

  bool _isConnected = true;
  bool _isReconnecting = false;
  bool _isInternetAvailable = true;
  String? _lastError;
  bool _hasNotifiedReconnection = false;
  bool _hasNotifiedDisconnection = false;
  DateTime? _lastConnectionLoss;
  DateTime? _lastReconnection;

  NetworkService._() {
    _initConnectivity();
    _startInternetConnectivityTesting();
  }

  void _initConnectivity() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        // Take the first result or check if any connection is available
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;
        _updateConnectionStatus(result);
      },
      onError: (error) {
        print('🌐 NetworkService: Connectivity error: $error');
        _handleConnectionLoss('Network connectivity error');
      },
    );
  }

  void _startInternetConnectivityTesting() {
    // Test internet connectivity every 10 seconds
    _connectionTestTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _testInternetConnectivity();
    });
  }

  Future<void> _testInternetConnectivity() async {
    try {
      // Test with a reliable host
      final result = await InternetAddress.lookup('google.com');
      final hasInternet =
          result.isNotEmpty && result.first.rawAddress.isNotEmpty;

      if (!hasInternet && _isInternetAvailable) {
        _handleConnectionLoss('Internet connectivity lost');
      } else if (hasInternet && !_isInternetAvailable) {
        _handleInternetReconnection();
      }

      _isInternetAvailable = hasInternet;
    } catch (e) {
      if (_isInternetAvailable) {
        _handleConnectionLoss('Internet connectivity test failed');
      }
      _isInternetAvailable = false;
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final wasConnected = _isConnected;

    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
        _isConnected = true;
        _lastError = null;
        _isReconnecting = false;
        _stopReconnectionPolling();
        print('🌐 NetworkService: Network connected via ${result.name}');

        // Only notify if this was a reconnection and we haven't already notified
        if (!wasConnected && !_hasNotifiedReconnection) {
          print('🌐 NetworkService: Network reconnection successful');
          _hasNotifiedReconnection = true;
          _handleInternetReconnection();
        }
        break;
      case ConnectivityResult.none:
        _handleConnectionLoss('No internet connection available');
        break;
      default:
        _handleConnectionLoss('Unknown network status');
    }

    // Always notify listeners when status changes
    if (wasConnected != _isConnected) {
      print(
          '🌐 NetworkService: Connection status changed from $wasConnected to $_isConnected');
      notifyListeners();
    }
  }

  void _handleConnectionLoss(String reason) {
    final wasConnected = _isConnected;
    _isConnected = false;
    _isInternetAvailable = false;
    _lastError = reason;
    _lastConnectionLoss = DateTime.now();
    _hasNotifiedDisconnection = false;
    _startReconnectionPolling();
    print('🌐 NetworkService: Connection lost - $reason');

    if (wasConnected) {
      notifyListeners();
    }
  }

  void _handleInternetReconnection() {
    _isConnected = true;
    _isInternetAvailable = true;
    _lastError = null;
    _isReconnecting = false;
    _lastReconnection = DateTime.now();
    _hasNotifiedReconnection = true;
    _stopReconnectionPolling();
    print('🌐 NetworkService: Internet reconnection successful');

    // Reset the flag after a delay to allow for future reconnections
    Timer(const Duration(seconds: 5), () {
      _hasNotifiedReconnection = false;
    });

    notifyListeners();
  }

  void _startReconnectionPolling() {
    if (!_isPollingEnabled || _reconnectionTimer != null) return;

    _reconnectionCountdown = 30;
    _isReconnecting = true;
    print('🌐 NetworkService: Starting 30-second reconnection polling');

    _reconnectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isConnected) {
        _stopReconnectionPolling();
        return;
      }

      _reconnectionCountdown--;

      if (_reconnectionCountdown <= 0) {
        // Attempt reconnection
        _attemptReconnection();
        _reconnectionCountdown = 30; // Reset countdown
      }

      notifyListeners();
    });

    notifyListeners();
  }

  void _stopReconnectionPolling() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _reconnectionCountdown = 0;
    _isReconnecting = false;
    print('🌐 NetworkService: Stopped reconnection polling');
    notifyListeners();
  }

  void _attemptReconnection() async {
    print('🌐 NetworkService: Attempting reconnection...');
    try {
      final results = await _connectivity.checkConnectivity();
      final result =
          results.isNotEmpty ? results.first : ConnectivityResult.none;
      _updateConnectionStatus(result);
    } catch (e) {
      print('🌐 NetworkService: Reconnection attempt failed: $e');
    }
  }

  // Method to handle successful reconnection
  void handleSuccessfulReconnection() {
    print('🌐 NetworkService: Handling successful reconnection');
    _isReconnecting = false;
    _lastError = null;
    _stopReconnectionPolling();
    notifyListeners();
  }

  // Method to handle API connection errors
  void handleApiConnectionError(String error) {
    if (error.contains('Failed to fetch') ||
        error.contains('net::ERR_CONNECTION_CLOSED') ||
        error.contains('ClientException')) {
      _isConnected = false;
      _lastError = 'Server connection failed';
      _startReconnectionPolling();
      print('🌐 NetworkService: API connection error detected: $error');
      notifyListeners();
    }
  }

  Future<void> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final result =
          results.isNotEmpty ? results.first : ConnectivityResult.none;
      _updateConnectionStatus(result);
    } catch (e) {
      print('🌐 NetworkService: Error checking connectivity: $e');
      _isConnected = false;
      _lastError = 'Failed to check network status';
      _startReconnectionPolling();
      notifyListeners();
    }
  }

  void setReconnecting(bool reconnecting) {
    _isReconnecting = reconnecting;
    notifyListeners();
  }

  void setLastError(String? error) {
    _lastError = error;
    notifyListeners();
  }

  // Manual reconnection trigger
  void triggerReconnection() {
    print('🌐 NetworkService: Manual reconnection triggered');
    _reconnectionCountdown =
        0; // Reset countdown to trigger immediate reconnection
    _attemptReconnection();
  }

  // Get user-friendly error message
  String getUserFriendlyErrorMessage(String? technicalError) {
    if (!_isConnected) {
      return 'No internet connection. Please check your network settings and try again.';
    }

    if (technicalError != null) {
      if (technicalError.contains('Failed to fetch') ||
          technicalError.contains('Network error') ||
          technicalError.contains('SocketException')) {
        return 'Unable to connect to the server. Please check your internet connection and try again.';
      }

      if (technicalError.contains('timeout') ||
          technicalError.contains('TimeoutException')) {
        return 'Request timed out. Please check your connection and try again.';
      }

      if (technicalError.contains('404')) {
        return 'The requested resource was not found. Please try again later.';
      }

      if (technicalError.contains('500') ||
          technicalError.contains('502') ||
          technicalError.contains('503') ||
          technicalError.contains('504')) {
        return 'Server is temporarily unavailable. Please try again in a few moments.';
      }

      if (technicalError.contains('401') || technicalError.contains('403')) {
        return 'Authentication required. Please log in again.';
      }
    }

    return 'Something went wrong. Please try again.';
  }

  // Get connection status message
  String getConnectionStatusMessage() {
    if (_isReconnecting && _reconnectionCountdown > 0) {
      return 'Reconnecting in $_reconnectionCountdown seconds...';
    }

    if (_isReconnecting) {
      return 'Reconnecting...';
    }

    if (!_isConnected) {
      return 'No internet connection';
    }

    return 'Connected';
  }

  // Get connection status icon
  String getConnectionStatusIcon() {
    if (_isReconnecting) {
      return '🔄';
    }

    if (!_isConnected) {
      return '📡';
    }

    return '🌐';
  }

  bool get isConnected => _isConnected;
  bool get isReconnecting => _isReconnecting;
  bool get isInternetAvailable => _isInternetAvailable;
  String? get lastError => _lastError;
  int get reconnectionCountdown => _reconnectionCountdown;
  DateTime? get lastConnectionLoss => _lastConnectionLoss;
  DateTime? get lastReconnection => _lastReconnection;

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _reconnectionTimer?.cancel();
    _connectionTestTimer?.cancel();
    super.dispose();
  }
}
