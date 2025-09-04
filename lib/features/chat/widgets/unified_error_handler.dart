import 'package:flutter/material.dart';

/// Error handler widget for unified chat screen
class UnifiedErrorHandler extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  final bool isConnected;

  const UnifiedErrorHandler({
    super.key,
    this.error,
    this.onRetry,
    this.isConnected = true,
  });

  @override
  Widget build(BuildContext context) {
    if (error == null && isConnected) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.orange[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.orange[200]! : Colors.red[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.warning_amber : Icons.wifi_off,
            color: isConnected ? Colors.orange[700] : Colors.red[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isConnected ? 'Error' : 'No Internet Connection',
                  style: TextStyle(
                    color: isConnected ? Colors.orange[700] : Colors.red[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    error!,
                    style: TextStyle(
                      color: isConnected ? Colors.orange[600] : Colors.red[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null && isConnected) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
