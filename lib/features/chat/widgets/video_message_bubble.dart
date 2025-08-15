import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying video message bubbles
class VideoMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const VideoMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final videoPath = content['videoPath'] as String?;
    final thumbnailPath = content['thumbnailPath'] as String?;
    final duration = content['duration'] as int? ?? 0;
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
            // Video thumbnail with play button
            _buildVideoThumbnail(context, videoPath, thumbnailPath, duration),

            // Caption
            if (caption != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
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

  /// Build video thumbnail with play button
  Widget _buildVideoThumbnail(BuildContext context, String? videoPath,
      String? thumbnailPath, int duration) {
    final displayPath = thumbnailPath ?? videoPath;

    return Stack(
      children: [
        // Video thumbnail
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: displayPath != null
                ? Image.asset(
                    displayPath,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildPlaceholderVideo(context);
                    },
                  )
                : _buildPlaceholderVideo(context),
          ),
        ),

        // Play button overlay
        Positioned.fill(
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
        ),

        // Duration badge
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatDuration(duration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build placeholder video
  Widget _buildPlaceholderVideo(BuildContext context) {
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
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              size: 48,
              color: this.isFromCurrentUser
                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5)
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Video not available',
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
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format duration for display
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
