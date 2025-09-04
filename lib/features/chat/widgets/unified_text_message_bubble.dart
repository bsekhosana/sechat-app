import 'package:flutter/material.dart';

import '../models/message.dart';

/// WhatsApp-style text message bubble
class UnifiedTextMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UnifiedTextMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isFromCurrentUser
              ? const Color(0xFFFF6B35)
                  .withOpacity(0.1) // Light orange for sent messages
              : Colors.grey[
                  50], // Light grey for received messages to match main screen
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
            bottomLeft: Radius.circular(isFromCurrentUser ? 8 : 2),
            bottomRight: Radius.circular(isFromCurrentUser ? 2 : 8),
          ),
          border: Border.all(
            color: isFromCurrentUser
                ? const Color(0xFFFF6B35)
                    .withOpacity(0.2) // Light orange border for sent messages
                : Colors.grey[200]!, // Light grey border for received messages
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.05), // Lighter shadow to match main screen
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message.content['text'] ?? '',
          style: const TextStyle(
            color: Colors.black, // Match main screen text color
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
