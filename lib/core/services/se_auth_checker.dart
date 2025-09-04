import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// SeAuth Checker Service
/// Handles authentication validation and session management
class SeAuthChecker {
  static final SeAuthChecker _instance = SeAuthChecker._internal();
  factory SeAuthChecker() => _instance;
  SeAuthChecker._internal();

  // Services
  final SeSessionService _sessionService = SeSessionService();
  final SeSocketService _socketService = SeSocketService.instance;

  // Auth state
  bool _isAuthenticated = false;
  bool _isChecking = false;
  Timer? _authCheckTimer;
  Timer? _sessionValidationTimer;

  // Stream controllers
  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();
  final StreamController<String> _authErrorController =
      StreamController<String>.broadcast();

  // Streams
  Stream<bool> get authStateStream => _authStateController.stream;
  Stream<String> get authErrorStream => _authErrorController.stream;

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isChecking => _isChecking;

  /// Initialize auth checker
  Future<void> initialize() async {
    Logger.debug(' SeAuthChecker: Initializing...');

    try {
      // Check initial auth state
      await _checkAuthenticationState();

      // Set up periodic auth checks
      _setupPeriodicAuthChecks();

      // Set up session validation
      _setupSessionValidation();

      Logger.success(' SeAuthChecker:  Initialized successfully');
    } catch (e) {
      Logger.error(' SeAuthChecker:  Failed to initialize: $e');
      _authErrorController.add('Failed to initialize auth checker: $e');
    }
  }

  /// Check current authentication state
  Future<void> _checkAuthenticationState() async {
    if (_isChecking) return;

    _isChecking = true;
    Logger.debug(' SeAuthChecker: Checking authentication state...');

    try {
      // Check if session exists and is valid
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) {
        _updateAuthState(false);
        Logger.error(' SeAuthChecker:  No session ID found');
        return;
      }

      // Validate session with server
      final isValid = await _validateSessionWithServer(sessionId);
      _updateAuthState(isValid);

      if (isValid) {
        Logger.success(' SeAuthChecker:  Session is valid');
      } else {
        Logger.error(' SeAuthChecker:  Session is invalid');
      }
    } catch (e) {
      Logger.error(' SeAuthChecker:  Error checking auth state: $e');
      _authErrorController.add('Authentication check failed: $e');
      _updateAuthState(false);
    } finally {
      _isChecking = false;
    }
  }

  /// Validate session with server
  Future<bool> _validateSessionWithServer(String sessionId) async {
    try {
      // Check if socket is connected
      if (!_socketService.isConnected) {
        Logger.warning(
            ' SeAuthChecker:  Socket not connected, attempting to connect...');
        await _socketService.initialize();
        if (!_socketService.isConnected) {
          return false;
        }
      }

      // Send session validation request
      final completer = Completer<bool>();

      void onSessionValidated(dynamic data) {
        if (data['status'] == 'valid') {
          completer.complete(true);
        } else {
          completer.complete(false);
        }
      }

      void onSessionInvalidated(dynamic data) {
        completer.complete(false);
      }

      // Set up one-time listeners
      _socketService.on('session_validated', onSessionValidated);
      _socketService.on('session_invalidated', onSessionInvalidated);

      // Send validation request
      _socketService.emit('validate_session', {
        'sessionId': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Wait for response with timeout
      final isValid = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );

      // Clean up listeners
      _socketService.off('session_validated', onSessionValidated);
      _socketService.off('session_invalidated', onSessionInvalidated);

      return isValid;
    } catch (e) {
      Logger.error(' SeAuthChecker:  Error validating session with server: $e');
      return false;
    }
  }

  /// Update authentication state
  void _updateAuthState(bool isAuthenticated) {
    if (_isAuthenticated != isAuthenticated) {
      _isAuthenticated = isAuthenticated;
      _authStateController.add(isAuthenticated);
      Logger.info(
          ' SeAuthChecker:  Auth state changed to: ${isAuthenticated ? "authenticated" : "unauthenticated"}');
    }
  }

  /// Set up periodic authentication checks
  void _setupPeriodicAuthChecks() {
    _authCheckTimer?.cancel();
    _authCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isAuthenticated) {
        _checkAuthenticationState();
      }
    });
  }

  /// Set up session validation
  void _setupSessionValidation() {
    _sessionValidationTimer?.cancel();
    _sessionValidationTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isAuthenticated && _sessionService.currentSessionId != null) {
        _validateSessionLocally();
      }
    });
  }

  /// Validate session locally
  void _validateSessionLocally() {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) {
        _updateAuthState(false);
        return;
      }

      // Check if session is expired locally (placeholder)
      // final isExpired = _sessionService.isSessionExpired();
      // if (isExpired) {
      //   Logger.warning(' SeAuthChecker:  Session expired locally');
      //   _updateAuthState(false);
      //   _handleSessionExpired();
      // }
    } catch (e) {
      Logger.error(' SeAuthChecker:  Error in local session validation: $e');
    }
  }

  /// Handle session expired
  void _handleSessionExpired() {
    try {
      // Attempt to refresh session (placeholder)
      // _sessionService.refreshSession();

      // Re-check authentication
      _checkAuthenticationState();
    } catch (e) {
      Logger.error(' SeAuthChecker:  Failed to handle expired session: $e');
      _authErrorController.add('Session refresh failed: $e');
    }
  }

  /// Force authentication check
  Future<void> forceAuthCheck() async {
    Logger.info(' SeAuthChecker:  Forcing authentication check...');
    await _checkAuthenticationState();
  }

  /// Logout and clear auth state
  Future<void> logout() async {
    Logger.debug(' SeAuthChecker: 🔓 Logging out...');

    try {
      // Disconnect socket
      await _socketService.disconnect();

      // Clear session
      await _sessionService.logout();

      // Update auth state
      _updateAuthState(false);

      Logger.success(' SeAuthChecker:  Logout completed');
    } catch (e) {
      Logger.error(' SeAuthChecker:  Error during logout: $e');
      _authErrorController.add('Logout failed: $e');
    }
  }

  /// Check if user can perform action
  bool canPerformAction(String action) {
    if (!_isAuthenticated) {
      Logger.error(
          ' SeAuthChecker:  User not authenticated for action: $action');
      return false;
    }

    // Add specific action permissions here if needed
    return true;
  }

  /// Get current user permissions
  List<String> getCurrentPermissions() {
    if (!_isAuthenticated) return [];

    // Return list of permissions based on current session
    return [
      'send_message',
      'receive_message',
      'create_conversation',
      'key_exchange',
      'online_status',
    ];
  }

  /// Dispose resources
  void dispose() {
    _authCheckTimer?.cancel();
    _sessionValidationTimer?.cancel();
    _authStateController.close();
    _authErrorController.close();
  }
}
