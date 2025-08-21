import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/socket_status_provider.dart';

/// Global socket status banner that shows connection status across all screens
class GlobalSocketStatusBanner extends StatelessWidget {
  const GlobalSocketStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SocketStatusProvider>(
      builder: (context, socketProvider, child) {
        // Don't show banner when connected
        if (!socketProvider.isVisible) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: socketProvider.statusColor.withValues(alpha: 0.1),
            border: Border(
              top: BorderSide(color: socketProvider.statusColor, width: 1),
              bottom: BorderSide(color: socketProvider.statusColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Status indicator dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: socketProvider.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // Socket icon
              Icon(
                Icons.hub,
                color: socketProvider.statusColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              // Status message
              Expanded(
                child: Text(
                  socketProvider.statusMessage,
                  style: TextStyle(
                    color: socketProvider.statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Retry button (show for red/orange status)
              if (socketProvider.statusColor == Colors.red ||
                  socketProvider.statusColor == Colors.orange)
                Container(
                  decoration: BoxDecoration(
                    color: socketProvider.statusColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextButton(
                    onPressed: () => _handleReconnect(context, socketProvider),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
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
      },
    );
  }

  Future<void> _handleReconnect(
      BuildContext context, SocketStatusProvider provider) async {
    try {
      final success = await provider.attemptReconnect();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Reconnected successfully!'
                  : 'Reconnection failed. Please try again.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconnection error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
