import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/socket_provider.dart';
import '../../features/notifications/services/notification_manager_service.dart';
import '../../core/services/se_session_service.dart';
import '../../core/services/se_socket_service.dart';

class SocketStatusButton extends StatefulWidget {
  const SocketStatusButton({super.key});

  @override
  State<SocketStatusButton> createState() => _SocketStatusButtonState();
}

class _SocketStatusButtonState extends State<SocketStatusButton>
    with TickerProviderStateMixin {
  late Animation<double> _glowAnimation;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late AnimationController _pulseController;

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Glow animation for connected state
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));

    // Pulse animation for reconnecting state
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _updateAnimationStatus(bool isConnected, bool isReconnecting) {
    if (isConnected) {
      _glowController.repeat(reverse: true);
      _pulseController.stop();
    } else if (isReconnecting) {
      _glowController.stop();
      _pulseController.repeat(reverse: true);
    } else {
      _glowController.stop();
      _pulseController.stop();
    }
  }

  void _showConnectionDebugDialog(
      BuildContext context, SocketProvider socketProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Socket Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Status: ${socketProvider.isConnected ? "Connected" : "Disconnected"}'),
              const SizedBox(height: 8),
              Text('Connecting: ${socketProvider.isConnecting ? "Yes" : "No"}'),
              const SizedBox(height: 8),
              Text(
                  'Session ID: ${SeSessionService().currentSessionId ?? 'None'}'),
              const SizedBox(height: 8),
              Text(
                  'Socket Connected: ${SeSocketService().isConnected ? "Yes" : "No"}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SocketProvider>(
      builder: (context, socketProvider, child) {
        final bool isConnected = socketProvider.isConnected;
        final bool isConnecting = socketProvider.isConnecting;

        // Debug print to see the actual values
        print(
            '🔌 SocketStatusButton: isConnected: $isConnected, isConnecting: $isConnecting');

        // Update animation based on connection status
        _updateAnimationStatus(isConnected, isConnecting);

        // Fixed orange background
        const Color orange = Color(0xFFFF6B35);

        // Determine status dot color
        Color statusColor;
        if (isConnected) {
          statusColor = const Color(0xFF4CAF50); // green
        } else if (isConnecting) {
          statusColor = Colors.orange; // connecting
        } else {
          statusColor = Colors.red; // disconnected
        }

        // Determine glow animation value (use orange glow)
        double animationValue;
        if (isConnected) {
          animationValue = _glowAnimation.value;
        } else if (isConnecting) {
          animationValue = _pulseAnimation.value;
        } else {
          animationValue = 0.3; // Static low glow for disconnected
        }

        return GestureDetector(
          onTap: () {
            _showConnectionDebugDialog(context, socketProvider);
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: orange,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: orange.withOpacity(animationValue * 0.6),
                  blurRadius: isConnecting ? 8 : 12,
                  spreadRadius: isConnecting ? 1 : 2,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: orange.withOpacity(animationValue * 0.8),
                width: isConnecting ? 1.5 : 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.hub, // socket-like connectivity icon
                  color: Colors.white,
                  size: 22,
                ),
                // Status dot (top-right)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
