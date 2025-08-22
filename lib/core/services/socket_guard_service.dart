import 'package:flutter/material.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';

/// Global service for guarding socket operations with connectivity checks and auto-retry
class SocketGuardService {
  static SocketGuardService? _instance;
  static SocketGuardService get instance =>
      _instance ??= SocketGuardService._();

  SocketGuardService._();

  final SeSocketService _socketService = SeSocketService.instance;

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Track retry attempts
  final Map<String, int> _retryAttempts = {};

  /// Check if socket is connected and ready for operations
  bool get isSocketReady =>
      _socketService.isConnected && SeSessionService().currentSessionId != null;

  /// Get current socket connection status
  SocketConnectionStatus get connectionStatus {
    if (!_socketService.isConnected) return SocketConnectionStatus.disconnected;
    if (SeSessionService().currentSessionId == null)
      return SocketConnectionStatus.connecting;
    return SocketConnectionStatus.connected;
  }

  /// Guard a socket operation with connectivity check and auto-retry
  /// Returns true if operation should proceed, false if blocked
  Future<bool> guardSocketOperation({
    required String operationName,
    required BuildContext context,
    bool showRetryDialog = true,
    bool autoRetry = true,
  }) async {
    try {
      // Check if socket is ready
      if (isSocketReady) {
        print('🔒 SocketGuard: ✅ Socket ready for operation: $operationName');
        return true;
      }

      print(
          '🔒 SocketGuard: ⚠️ Socket not ready for operation: $operationName');
      print('🔒 SocketGuard: 🔍 Connection status: ${connectionStatus.name}');

      // Show connection status widget if requested
      if (showRetryDialog) {
        _showConnectionStatusDialog(context, operationName);
      }

      // Auto-retry connection if enabled
      if (autoRetry) {
        return await _attemptConnectionWithRetry(operationName);
      }

      return false;
    } catch (e) {
      print('🔒 SocketGuard: ❌ Error in guardSocketOperation: $e');
      return false;
    }
  }

  /// Attempt to connect with retry logic
  Future<bool> _attemptConnectionWithRetry(String operationName) async {
    try {
      final retryKey =
          '${operationName}_${DateTime.now().millisecondsSinceEpoch}';
      int attempts = _retryAttempts[retryKey] ?? 0;

      while (attempts < _maxRetries && !isSocketReady) {
        attempts++;
        _retryAttempts[retryKey] = attempts;

        print(
            '🔒 SocketGuard: 🔄 Attempt $attempts/$_maxRetries to connect for: $operationName');

        // Try to connect
        final sessionId = SeSessionService().currentSessionId;
        if (sessionId != null) {
          await _socketService.connect(sessionId);
        }

        // Wait for connection to stabilize
        await Future.delayed(_retryDelay);

        // Check if connection is now ready
        if (isSocketReady) {
          print(
              '🔒 SocketGuard: ✅ Connection successful after $attempts attempts for: $operationName');
          _retryAttempts.remove(retryKey);
          return true;
        }

        // Wait before next retry
        if (attempts < _maxRetries) {
          await Future.delayed(_retryDelay);
        }
      }

      if (attempts >= _maxRetries) {
        print('🔒 SocketGuard: ❌ Max retries reached for: $operationName');
        _retryAttempts.remove(retryKey);
      }

      return false;
    } catch (e) {
      print('🔒 SocketGuard: ❌ Error during connection retry: $e');
      return false;
    }
  }

  /// Show connection status dialog with retry option
  void _showConnectionStatusDialog(BuildContext context, String operationName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.wifi_off,
              color: Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('Connection Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'The operation "$operationName" requires an active connection.'),
            const SizedBox(height: 16),
            const Text('Current Status:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildConnectionStatusWidget(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              // Show loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Connecting...'),
                    ],
                  ),
                ),
              );

              // Attempt connection
              final success = await _attemptConnectionWithRetry(operationName);

              // Hide loading indicator
              Navigator.of(context).pop();

              if (success) {
                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '✅ Connected successfully! You can now retry the operation.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                // Show error message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '❌ Failed to connect. Please check your internet connection.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Retry Connection'),
          ),
        ],
      ),
    );
  }

  /// Guard specific socket operations with appropriate error handling
  Future<bool> guardSendMessage(BuildContext context) async {
    return await guardSocketOperation(
      operationName: 'Send Message',
      context: context,
      showRetryDialog: true,
      autoRetry: true,
    );
  }

  Future<bool> guardTypingIndicator(BuildContext context) async {
    return await guardSocketOperation(
      operationName: 'Typing Indicator',
      context: context,
      showRetryDialog: false,
      autoRetry: true,
    );
  }

  Future<bool> guardPresenceUpdate(BuildContext context) async {
    return await guardSocketOperation(
      operationName: 'Presence Update',
      context: context,
      showRetryDialog: false,
      autoRetry: true,
    );
  }

  Future<bool> guardKeyExchange(BuildContext context) async {
    return await guardSocketOperation(
      operationName: 'Key Exchange',
      context: context,
      showRetryDialog: true,
      autoRetry: true,
    );
  }

  /// Clear retry attempts for a specific operation
  void clearRetryAttempts(String operationName) {
    _retryAttempts.removeWhere((key, value) => key.startsWith(operationName));
  }

  /// Clear all retry attempts
  void clearAllRetryAttempts() {
    _retryAttempts.clear();
  }

  /// Build a simple connection status widget
  Widget _buildConnectionStatusWidget() {
    final status = connectionStatus;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: status.color),
      ),
      child: Row(
        children: [
          Icon(status.icon, color: status.color, size: 20),
          const SizedBox(width: 8),
          Text(
            status.name,
            style: TextStyle(
              color: status.color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Socket connection status enum
enum SocketConnectionStatus {
  connected,
  connecting,
  disconnected,
  error,
}

/// Extension for SocketConnectionStatus
extension SocketConnectionStatusExtension on SocketConnectionStatus {
  String get name {
    switch (this) {
      case SocketConnectionStatus.connected:
        return 'Connected';
      case SocketConnectionStatus.connecting:
        return 'Connecting';
      case SocketConnectionStatus.disconnected:
        return 'Disconnected';
      case SocketConnectionStatus.error:
        return 'Error';
    }
  }

  Color get color {
    switch (this) {
      case SocketConnectionStatus.connected:
        return Colors.green;
      case SocketConnectionStatus.connecting:
        return Colors.orange;
      case SocketConnectionStatus.disconnected:
        return Colors.red;
      case SocketConnectionStatus.error:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case SocketConnectionStatus.connected:
        return Icons.wifi;
      case SocketConnectionStatus.connecting:
        return Icons.wifi_find;
      case SocketConnectionStatus.disconnected:
        return Icons.wifi_off;
      case SocketConnectionStatus.error:
        return Icons.error;
    }
  }
}
