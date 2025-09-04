import 'package:flutter/material.dart';

/// Modern chat header with WhatsApp-like design
class UnifiedChatHeader extends StatelessWidget {
  final String recipientName;
  final bool isOnline;
  final DateTime? lastSeen;
  final VoidCallback onBackPressed;
  final VoidCallback onMorePressed;

  const UnifiedChatHeader({
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
      decoration: BoxDecoration(
        color: Colors.white, // Match main screen background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: MediaQuery.of(context).padding.top + 12, // Add status bar height
          bottom: 12,
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              onPressed: onBackPressed,
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.black, // Match main screen text color
              ),
            ),

            const SizedBox(width: 8),

            // Profile picture placeholder
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  const Color(0xFFFF6B35), // Use app's primary orange color
              child: Text(
                recipientName.isNotEmpty ? recipientName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Recipient info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipientName,
                    style: const TextStyle(
                      color: Colors.black, // Match main screen text color
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      color: Colors.black
                          .withOpacity(0.6), // Match main screen secondary text
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            // More options button
            IconButton(
              onPressed: onMorePressed,
              icon: const Icon(
                Icons.more_vert,
                color: Colors.black, // Match main screen text color
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get status text based on online status and last seen
  String _getStatusText() {
    if (isOnline) {
      return 'Online';
    } else if (lastSeen != null) {
      final now = DateTime.now();
      final difference = now.difference(lastSeen!);

      if (difference.inMinutes < 1) {
        return 'Last seen just now';
      } else if (difference.inMinutes < 60) {
        return 'Last seen ${difference.inMinutes} minutes ago';
      } else if (difference.inHours < 24) {
        return 'Last seen ${difference.inHours} hours ago';
      } else if (difference.inDays == 1) {
        return 'Last seen yesterday';
      } else {
        return 'Last seen ${difference.inDays} days ago';
      }
    } else {
      return 'Last seen recently';
    }
  }
}
