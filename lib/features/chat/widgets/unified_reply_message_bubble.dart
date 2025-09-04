import 'package:flutter/material.dart';

import '../models/message.dart';

/// WhatsApp-style reply message bubble (placeholder for future implementation)
class UnifiedReplyMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UnifiedReplyMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // For now, treat reply messages as regular text messages
    // This will be enhanced in future updates
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: isFromCurrentUser
            ? const Color(0xFFDCF8C6) // WhatsApp green for sent messages
            : Colors.white, // White for received messages
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
          bottomLeft: Radius.circular(isFromCurrentUser ? 8 : 2),
          bottomRight: Radius.circular(isFromCurrentUser ? 2 : 8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        message.content['text'] ?? '',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
