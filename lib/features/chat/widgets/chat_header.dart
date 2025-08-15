import 'package:flutter/material.dart';

/// Header widget for individual chat conversations
class ChatHeader extends StatelessWidget {
  final String recipientName;
  final bool isOnline;
  final DateTime? lastSeen;
  final VoidCallback onBackPressed;
  final VoidCallback onMorePressed;

  const ChatHeader({
    super.key,
    required this.recipientName,
    required this.isOnline,
    this.lastSeen,
    required this.onBackPressed,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: onBackPressed,
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Back',
          ),

          const SizedBox(width: 8),

          // Recipient info
          Expanded(
            child: GestureDetector(
              onTap: _showRecipientInfo,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recipient name
                  Text(
                    recipientName.isNotEmpty ? recipientName : 'Unknown User',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 2),

                  // Online status or last seen
                  _buildStatusIndicator(context),
                ],
              ),
            ),
          ),

          // More options button
          IconButton(
            onPressed: onMorePressed,
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: 'More options',
          ),
        ],
      ),
    );
  }

  /// Build status indicator
  Widget _buildStatusIndicator(BuildContext context) {
    if (isOnline) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Online',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      );
    } else if (lastSeen != null) {
      return Text(
        'Last seen ${_formatLastSeen(lastSeen!)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    } else {
      return Text(
        'Offline',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
  }

  /// Format last seen timestamp
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'just now';
        }
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }

  /// Show recipient information
  void _showRecipientInfo() {
    // TODO: Implement recipient info display
    // This could show a profile modal or navigate to a profile screen
    print('Show recipient info for: $recipientName');
  }
}
