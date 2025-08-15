import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying image message bubbles
class ImageMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ImageMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final imagePath = content['imagePath'] as String?;
    final thumbnailPath = content['thumbnailPath'] as String?;
    final caption = content['caption'] as String?;
    final fileSize = content['fileSize'] as int?;

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
            // Image display
            _buildImageDisplay(context, imagePath, thumbnailPath),

            // Caption and metadata
            if (caption != null || fileSize != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Caption
                    if (caption != null) ...[
                      Text(
                        caption,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: this.isFromCurrentUser
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      if (fileSize != null) const SizedBox(height: 4),
                    ],

                    // File size
                    if (fileSize != null)
                      Text(
                        _formatFileSize(fileSize),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: this.isFromCurrentUser
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimary
                                      .withOpacity(0.7)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.7),
                              fontSize: 11,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build image display
  Widget _buildImageDisplay(
      BuildContext context, String? imagePath, String? thumbnailPath) {
    final displayPath = thumbnailPath ?? imagePath;

    if (displayPath == null) {
      return _buildPlaceholderImage(context);
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.asset(
          displayPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholderImage(context);
          },
        ),
      ),
    );
  }

  /// Build placeholder image
  Widget _buildPlaceholderImage(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: isFromCurrentUser
            ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.1)
            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 48,
              color: isFromCurrentUser
                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5)
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Image not available',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isFromCurrentUser
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.7)
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format file size for display
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes} B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
