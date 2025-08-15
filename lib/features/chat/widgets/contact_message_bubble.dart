import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying contact message bubbles
class ContactMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ContactMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final name = content['name'] as String? ?? 'Contact';
    final phone = content['phone'] as String?;
    final email = content['email'] as String?;
    final caption = content['caption'] as String?;
    
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: this.isFromCurrentUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(this.isFromCurrentUser ? 20 : 4),
            bottomRight: Radius.circular(this.isFromCurrentUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contact header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Contact avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: this.isFromCurrentUser
                          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.2)
                          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: this.isFromCurrentUser
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Contact name
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: this.isFromCurrentUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  
                  // Contact icon
                  Icon(
                    Icons.person_add,
                    color: this.isFromCurrentUser
                        ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ],
              ),
            ),
            
            // Contact details
            if (phone != null || email != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phone number
                    if (phone != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 16,
                            color: this.isFromCurrentUser
                                ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            phone,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: this.isFromCurrentUser
                                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                      if (email != null) const SizedBox(height: 8),
                    ],
                    
                    // Email
                    if (email != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.email,
                            size: 16,
                            color: this.isFromCurrentUser
                                ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            email,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: this.isFromCurrentUser
                                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            
            // Caption
            if (caption != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  caption,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: this.isFromCurrentUser
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
