import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying document message bubbles
class DocumentMessageBubble extends StatelessWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DocumentMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final fileName = content['fileName'] as String? ?? 'Document';
    final fileSize = content['fileSize'] as int? ?? 0;
    final fileType = content['fileType'] as String? ?? 'Unknown';
    final caption = content['caption'] as String?;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        padding: const EdgeInsets.all(16),
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
            // Document icon and info
            Row(
              children: [
                // Document icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: this.isFromCurrentUser
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.2)
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getDocumentIcon(fileType),
                    size: 24,
                    color: this.isFromCurrentUser
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(width: 12),

                // Document details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File name
                      Text(
                        fileName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: this.isFromCurrentUser
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      // File type and size
                      Text(
                        '${fileType.toUpperCase()} • ${_formatFileSize(fileSize)}',
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

                // Download icon
                Icon(
                  Icons.download,
                  color: this.isFromCurrentUser
                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.7),
                ),
              ],
            ),

            // Caption
            if (caption != null) ...[
              const SizedBox(height: 12),
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
    );
  }

  /// Get document icon based on file type
  IconData _getDocumentIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      case 'rtf':
        return Icons.text_fields;
      case 'odt':
        return Icons.edit_document;
      default:
        return Icons.insert_drive_file;
    }
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
