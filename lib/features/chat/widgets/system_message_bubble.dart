import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying system message bubbles
class SystemMessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SystemMessageBubble({
    super.key,
    required this.message,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final text = content['text'] as String? ?? 'System message';
    final type = content['type'] as String? ?? 'info';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // System message icon
                  Icon(
                    _getSystemIcon(type),
                    size: 16,
                    color: _getSystemColor(context, type),
                  ),

                  const SizedBox(width: 8),

                  // System message text
                  Flexible(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _getSystemColor(context, type),
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get system message icon based on type
  IconData _getSystemIcon(String type) {
    switch (type) {
      case 'info':
        return Icons.info_outline;
      case 'success':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      case 'join':
        return Icons.person_add;
      case 'leave':
        return Icons.person_remove;
      case 'typing_start':
        return Icons.edit;
      case 'typing_stop':
        return Icons.edit_off;
      default:
        return Icons.info_outline;
    }
  }

  /// Get system message color based on type
  Color _getSystemColor(BuildContext context, String type) {
    switch (type) {
      case 'info':
        return Theme.of(context).colorScheme.primary;
      case 'success':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Theme.of(context).colorScheme.error;
      case 'join':
        return Colors.green;
      case 'leave':
        return Colors.red;
      case 'typing_start':
      case 'typing_stop':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}
