import 'package:flutter/material.dart';

/// Header widget for individual chat conversations
class ChatHeader extends StatelessWidget {
  final String recipientName;
  final bool isOnline;
  final DateTime? lastSeen;
  final VoidCallback onBackPressed;
  final VoidCallback onMorePressed;
  final GlobalKey<NavigatorState>? navigatorKey;

  const ChatHeader({
    super.key,
    required this.recipientName,
    required this.isOnline,
    this.lastSeen,
    required this.onBackPressed,
    required this.onMorePressed,
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    print(
        '🔍 ChatHeader: Building with isOnline=$isOnline, recipientName=$recipientName');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: onBackPressed,
            icon: Icon(
              Icons.arrow_back,
              color: Colors.grey[700], // Dark grey back button
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
                          color: Colors.grey[800], // Dark grey name text
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
              color: Colors.grey[600], // Light grey for offline/last seen
            ),
      );
    } else {
      return Text(
        'Offline',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600], // Light grey for offline/last seen
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
    // Show recipient info in a bottom sheet
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      recipientName.isNotEmpty
                          ? recipientName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipientName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        _buildStatusIndicator(context),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoRow(context, 'Status', isOnline ? 'Online' : 'Offline'),
              if (lastSeen != null)
                _buildInfoRow(context, 'Last seen', _formatLastSeen(lastSeen!)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Navigate to full profile screen when implemented
                  },
                  child: const Text('View Full Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build info row for recipient info
  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600], // Light grey for info labels
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[800], // Dark grey for info values
                ),
          ),
        ],
      ),
    );
  }
}
