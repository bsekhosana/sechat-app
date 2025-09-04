import 'package:flutter/material.dart';

import '../models/message.dart';

/// WhatsApp-style system message bubble
class UnifiedSystemMessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UnifiedSystemMessageBubble({
    super.key,
    required this.message,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content['text'] ?? 'System message',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
