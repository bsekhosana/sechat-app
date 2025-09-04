import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../providers/unified_chat_provider.dart';
import 'unified_text_message_bubble.dart';
import 'unified_reply_message_bubble.dart';
import 'unified_system_message_bubble.dart';

/// Modern message bubble widget with WhatsApp-like design and smooth animations
class UnifiedMessageBubble extends StatefulWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isLast;

  const UnifiedMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
    this.isLast = false,
  });

  @override
  State<UnifiedMessageBubble> createState() => _UnifiedMessageBubbleState();
}

class _UnifiedMessageBubbleState extends State<UnifiedMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Start animation
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UnifiedChatProvider>(
      key: ValueKey('consumer_${widget.message.id}'),
      builder: (context, provider, child) {
        // Get the real-time message from the provider
        final realTimeMessage = provider.messages.firstWhere(
          (msg) => msg.id == widget.message.id,
          orElse: () => widget.message,
        );

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _buildMessageBubble(context, realTimeMessage),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message realTimeMessage) {
    return Container(
      key: ValueKey('message_${realTimeMessage.id}_${realTimeMessage.status}'),
      margin: EdgeInsets.only(
        left: widget.isFromCurrentUser ? 60 : 16,
        right: widget.isFromCurrentUser ? 16 : 60,
        bottom: widget.isLast ? 16 : 8,
        top: 8,
      ),
      child: Column(
        crossAxisAlignment: widget.isFromCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Message content
          _buildMessageContent(context, realTimeMessage),

          const SizedBox(height: 4),

          // Message metadata (time, status, etc.)
          _buildMessageMetadata(context, realTimeMessage),
        ],
      ),
    );
  }

  /// Build the main message content based on type
  Widget _buildMessageContent(BuildContext context, Message realTimeMessage) {
    switch (realTimeMessage.type) {
      case MessageType.text:
        return UnifiedTextMessageBubble(
          message: realTimeMessage,
          isFromCurrentUser: widget.isFromCurrentUser,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
        );

      case MessageType.reply:
        return UnifiedReplyMessageBubble(
          message: realTimeMessage,
          isFromCurrentUser: widget.isFromCurrentUser,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
        );

      case MessageType.system:
        return UnifiedSystemMessageBubble(
          message: realTimeMessage,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
        );
    }
  }

  /// Build message metadata (time, status, etc.)
  Widget _buildMessageMetadata(BuildContext context, Message realTimeMessage) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: widget.isFromCurrentUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        // Time
        Text(
          _formatTimestamp(realTimeMessage.timestamp),
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),

        // Status indicators (only for current user's messages)
        if (widget.isFromCurrentUser) ...[
          const SizedBox(width: 6),
          _buildStatusIndicator(context, realTimeMessage),
        ],
      ],
    );
  }

  /// Build status indicator (WhatsApp-style ticks)
  Widget _buildStatusIndicator(BuildContext context, Message realTimeMessage) {
    IconData icon;
    Color color;

    switch (realTimeMessage.status) {
      case MessageStatus.pending:
        icon = Icons.schedule;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.sending:
        icon = Icons.schedule;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.sent:
        icon = Icons.check; // Single tick
        color = Colors.grey[500]!;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all; // Double ticks
        color = Colors.grey[500]!;
        break;
      case MessageStatus.read:
        icon = Icons.done_all; // Double blue ticks
        color = const Color(0xFF4FC3F7); // WhatsApp blue
        break;
      case MessageStatus.queued:
        icon = Icons.schedule_send;
        color = Colors.grey[500]!;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red[600]!;
        break;
      case MessageStatus.deleted:
        icon = Icons.delete_outline;
        color = Colors.grey[400]!;
        break;
    }

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  /// Format timestamp for display (WhatsApp style)
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      // Today: show time only
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(timestamp).inDays < 7) {
      // Within a week: show day name
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      // Older: show date
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
