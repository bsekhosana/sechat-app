import 'package:flutter/material.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';

/// Optimized Chat List Item Widget
/// Clean, focused chat list item with real-time updates
class OptimizedChatListItem extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const OptimizedChatListItem({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 16),
              Expanded(
                child: _buildContent(),
              ),
              _buildTrailingContent(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Build avatar/profile picture
  Widget _buildAvatar() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: _getAvatarColor(),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Center(
        child: Text(
          _getAvatarInitials(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Build main content area
  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                conversation.displayName ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (conversation.lastSeen != null)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _buildLastMessagePreview(),
            ),
            const SizedBox(width: 8),
            _buildTimestamp(),
          ],
        ),
      ],
    );
  }

  /// Build last message preview
  Widget _buildLastMessagePreview() {
    if (conversation.lastMessagePreview == null) {
      return Text(
        'No messages yet',
        style: TextStyle(
          color: Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Row(
      children: [
        if (conversation.isTyping) _buildTypingIndicator(),
        Expanded(
          child: Text(
            conversation.lastMessagePreview!,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Build typing indicator
  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'typing...',
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          _buildTypingDots(),
        ],
      ),
    );
  }

  /// Build typing dots animation
  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTypingDot(0),
        _buildTypingDot(1),
        _buildTypingDot(2),
      ],
    );
  }

  /// Build individual typing dot
  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.grey[600],
            shape: BoxShape.circle,
          ),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: null,
    );
  }

  /// Build timestamp
  Widget _buildTimestamp() {
    if (conversation.lastMessageAt == null) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final messageTime = conversation.lastMessageAt!;
    final difference = now.difference(messageTime);

    String timeText;
    if (difference.inDays > 0) {
      timeText = '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      timeText = '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      timeText = '${difference.inMinutes}m';
    } else {
      timeText = 'now';
    }

    return Text(
      timeText,
      style: TextStyle(
        color: Colors.grey[600],
        fontSize: 12,
      ),
    );
  }

  /// Build trailing content (unread count, etc.)
  Widget _buildTrailingContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (conversation.unreadCount > 0) _buildUnreadBadge(context),
        if (conversation.lastSeen != null) _buildLastSeen(),
      ],
    );
  }

  /// Build unread badge
  Widget _buildUnreadBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        conversation.unreadCount.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Build last seen indicator
  Widget _buildLastSeen() {
    final now = DateTime.now();
    final lastSeen = conversation.lastSeen!;
    final difference = now.difference(lastSeen);

    String lastSeenText;
    if (difference.inDays > 0) {
      lastSeenText = '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      lastSeenText = '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      lastSeenText = '${difference.inMinutes}m ago';
    } else {
      lastSeenText = 'Just now';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        lastSeenText,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 10,
        ),
      ),
    );
  }

  /// Get avatar color based on display name
  Color _getAvatarColor() {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];

    final index =
        (conversation.displayName ?? 'Unknown').hashCode % colors.length;
    return colors[index.abs() % colors.length];
  }

  /// Get avatar initials from display name
  String _getAvatarInitials() {
    final name = conversation.displayName?.trim() ?? '';
    if (name.isEmpty) return '?';

    final parts = name.split(' ');
    if (parts.length == 1) {
      return name.substring(0, 1).toUpperCase();
    }

    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
