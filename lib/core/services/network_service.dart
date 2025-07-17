import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkService extends ChangeNotifier {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isConnected = true;
  bool _isReconnecting = false;
  String? _lastError;

  NetworkService._() {
    _initConnectivity();
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
        _isConnected = false;
        _lastError = 'Network connectivity error';
        notifyListeners();
      },
    );
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final wasConnected = _isConnected;

    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
        _isConnected = true;
        _lastError = null;
        print('🌐 NetworkService: Network connected via ${result.name}');
        break;
      case ConnectivityResult.none:
        _isConnected = false;
        _lastError = 'No internet connection available';
        print('🌐 NetworkService: Network disconnected');
        break;
      default:
        _isConnected = false;
        _lastError = 'Unknown network status';
        print('🌐 NetworkService: Unknown network status: $result');
    }

    // Notify listeners if connection status changed
    if (wasConnected != _isConnected) {
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
  String? get lastError => _lastError;

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
