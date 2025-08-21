import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/se_socket_service.dart';

class SocketConnectionStatusWidget extends StatefulWidget {
  const SocketConnectionStatusWidget({super.key});

  @override
  State<SocketConnectionStatusWidget> createState() =>
      _SocketConnectionStatusWidgetState();
}

class _SocketConnectionStatusWidgetState
    extends State<SocketConnectionStatusWidget> {
  Timer? _periodicTimer;
  bool _isVisible = false;
  String _statusMessage = '';
  Color _statusColor = Colors.orange;
  final SeSocketService _socketService = SeSocketService.instance;

  @override
  void initState() {
    super.initState();
    _checkSocketStatus();
    _startPeriodicCheck();
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicCheck() {
    // Check socket status every 3 seconds to ensure widget stays in sync
    _periodicTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _checkSocketStatus();
      } else {
        timer.cancel();
      }
    });
  }

  void _checkSocketStatus() {
    final isConnected = _socketService.isConnected;
    final isConnecting = _socketService.isConnecting;

    String message;
    Color color;
    bool showWidget = false;

    if (isConnected) {
      // Socket is connected
      message = 'Socket Connected';
      color = Colors.green;
      showWidget = false; // Hide when connected
    } else if (isConnecting) {
      // Socket is connecting
      message = 'Connecting to SeChat...';
      color = Colors.orange;
      showWidget = true;
    } else {
      // Socket is disconnected
      message = 'Socket Disconnected';
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

  Future<void> _attemptReconnect() async {
    try {
      print('SocketConnectionStatusWidget: Attempting to reconnect...');

      // Use the channel socket service to reconnect
      await _socketService.initialize();

      // Refresh status after reconnection attempt
      _checkSocketStatus();
    } catch (e) {
      print('SocketConnectionStatusWidget: Reconnection failed: $e');
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Socket reconnection failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
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
        color: _statusColor.withValues(alpha: 0.1),
        border: Border(
          top: BorderSide(color: _statusColor, width: 1),
          bottom: BorderSide(color: _statusColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // Socket icon
          Icon(
            Icons.hub,
            color: _statusColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          // Status message
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
          // Retry button (show for red/orange status)
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
