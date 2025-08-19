import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/network_service.dart';

class ConnectionStatusWidget extends StatefulWidget {
  const ConnectionStatusWidget({super.key});

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  Timer? _countdownTimer;
  final int _countdownSeconds = 30;
  bool _isVisible = false;
  String _statusMessage = '';
  Color _statusColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();
    _setupConnectionListeners();
    _startPeriodicCheck();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _setupConnectionListeners() {
    // Listen for network service changes only
    // Session connection is now handled by notification system
    NetworkService.instance.addListener(() {
      if (mounted) {
        _checkConnectionStatus();
      }
    });
  }

  void _startPeriodicCheck() {
    // Check connection status every 5 seconds to ensure widget stays in sync
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _checkConnectionStatus();
      } else {
        timer.cancel();
      }
    });
  }

  void _checkConnectionStatus() {
    final isNetworkConnected = NetworkService.instance.isConnected;
    final isReconnecting = NetworkService.instance.isReconnecting;
    final hasSession = SeSessionService().currentSession != null;

    String message;
    Color color;
    bool showWidget = false;

    if (isNetworkConnected && hasSession) {
      // Network connected and session exists
      message = 'Connected to SeChat Network';
      color = Colors.green;
      showWidget = false; // Hide when fully connected
    } else if (isNetworkConnected && !hasSession) {
      // Network available but no session
      message = 'No active session';
      color = Colors.orange;
      showWidget = true;
    } else if (isReconnecting) {
      // Reconnecting
      message = 'Reconnecting to network...';
      color = Colors.orange;
      showWidget = true;
    } else {
      // No connection
      message = 'No internet connection';
      color = Colors.red;
      showWidget = true;
    }

    if (mounted) {
      setState(() {
        _isVisible = showWidget;
        _statusMessage = message;
        _statusColor = color;
      });
    }
  }

  void _showReconnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Issue'),
        content: Text(_statusMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _attemptReconnect();
            },
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptReconnect() async {
    try {
      print('ConnectionStatusWidget: Attempting to reconnect...');

      // Check if session exists and try to initialize notification services
      final seSessionService = SeSessionService();
      if (seSessionService.currentSession != null) {
        await seSessionService.initializeNotificationServices();
      }

      // Note: Connection is now handled by notification system
      // No need to manually reconnect as it's handled automatically

      // Refresh connection status
      _checkConnectionStatus();
    } catch (e) {
      print('ConnectionStatusWidget: Reconnection failed: $e');
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _statusColor.withOpacity(0.1),
        border: Border(
          top: BorderSide(color: _statusColor, width: 1),
          bottom: BorderSide(color: _statusColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_statusColor == Colors.red || _statusColor == Colors.orange)
            Container(
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextButton(
                onPressed: _attemptReconnect,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
