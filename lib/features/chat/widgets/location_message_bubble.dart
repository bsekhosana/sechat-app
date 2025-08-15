import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying location message bubbles
class LocationMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const LocationMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final latitude = content['latitude'] as double? ?? 0.0;
    final longitude = content['longitude'] as double? ?? 0.0;
    final address = content['address'] as String? ?? 'Location';
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
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map preview
            _buildMapPreview(context, latitude, longitude),
            
            // Location details
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location icon and address
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: this.isFromCurrentUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      
                      const SizedBox(width: 8),
                      
                      Expanded(
                        child: Text(
                          address,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: this.isFromCurrentUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  
                  // Coordinates
                  const SizedBox(height: 8),
                  Text(
                    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: this.isFromCurrentUser
                          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontFamily: 'monospace',
                    ),
                  ),
                  
                  // Caption
                  if (caption != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      caption,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: this.isFromCurrentUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build map preview
  Widget _buildMapPreview(BuildContext context, double latitude, double longitude) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: this.isFromCurrentUser
            ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.1)
            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Stack(
        children: [
          // Placeholder map background
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map,
                  size: 48,
                  color: this.isFromCurrentUser
                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5)
                      : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Map Preview',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: this.isFromCurrentUser
                        ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          
          // Location pin
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.location_on,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
