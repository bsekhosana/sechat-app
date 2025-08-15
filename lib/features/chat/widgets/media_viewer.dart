import 'package:flutter/material.dart';

import '../models/message.dart';

/// Comprehensive media viewer for all message types
class MediaViewer extends StatefulWidget {
  final Message message;
  final VoidCallback? onClose;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;

  const MediaViewer({
    super.key,
    required this.message,
    this.onClose,
    this.onShare,
    this.onDownload,
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header with controls
            _buildHeader(),

            // Media content
            Expanded(
              child: _buildMediaContent(),
            ),

            // Bottom controls
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  /// Build header with controls
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Close button
          IconButton(
            onPressed: widget.onClose ?? () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Close',
          ),

          const Spacer(),

          // Share button
          IconButton(
            onPressed: widget.onShare,
            icon: Icon(
              Icons.share,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Share',
          ),

          const SizedBox(width: 8),

          // Download button
          IconButton(
            onPressed: widget.onDownload,
            icon: Icon(
              Icons.download,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Download',
          ),
        ],
      ),
    );
  }

  /// Build media content
  Widget _buildMediaContent() {
    switch (widget.message.type) {
      case MessageType.image:
        return _buildImageViewer();
      case MessageType.video:
        return _buildVideoViewer();
      case MessageType.document:
        return _buildDocumentViewer();
      case MessageType.voice:
        return _buildVoiceViewer();
      case MessageType.location:
        return _buildLocationViewer();
      case MessageType.contact:
        return _buildContactViewer();
      default:
        return _buildUnsupportedMedia();
    }
  }

  /// Build image viewer
  Widget _buildImageViewer() {
    final content = widget.message.content;
    final imagePath = content['imagePath'] as String?;
    final caption = content['caption'] as String?;

    return Column(
      children: [
        // Image display
        Expanded(
          child: Center(
            child: imagePath != null
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildErrorDisplay('Image not available');
                      },
                    ),
                  )
                : _buildErrorDisplay('Image not available'),
          ),
        ),

        // Caption
        if (caption != null)
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              caption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// Build video viewer
  Widget _buildVideoViewer() {
    final content = widget.message.content;
    final videoPath = content['videoPath'] as String?;
    final thumbnailPath = content['thumbnailPath'] as String?;
    final duration = content['duration'] as int? ?? 0;
    final caption = content['caption'] as String?;

    return Column(
      children: [
        // Video player placeholder
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Video thumbnail
                if (thumbnailPath != null)
                  Container(
                    width: 300,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: AssetImage(thumbnailPath),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Play button
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 16),

                // Duration
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Caption
        if (caption != null)
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              caption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// Build document viewer
  Widget _buildDocumentViewer() {
    final content = widget.message.content;
    final fileName = content['fileName'] as String? ?? 'Document';
    final fileSize = content['fileSize'] as int? ?? 0;
    final fileType = content['fileType'] as String? ?? 'Unknown';
    final caption = content['caption'] as String?;

    return Column(
      children: [
        // Document preview
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Document icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getDocumentIcon(fileType),
                    color: Colors.white,
                    size: 60,
                  ),
                ),

                const SizedBox(height: 24),

                // File name
                Text(
                  fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // File info
                Text(
                  '${fileType.toUpperCase()} • ${_formatFileSize(fileSize)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                // Open button
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement document opening
                    print('📄 Opening document: $fileName');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Caption
        if (caption != null)
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              caption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// Build voice viewer
  Widget _buildVoiceViewer() {
    final content = widget.message.content;
    final duration = content['duration'] as int? ?? 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Voice wave visualization
          SizedBox(
            width: 200,
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(10, (index) {
                return Container(
                  width: 8,
                  height: 20 + (index * 3.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 32),

          // Play button
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
          ),

          const SizedBox(height: 16),

          // Duration
          Text(
            _formatDuration(duration),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  /// Build location viewer
  Widget _buildLocationViewer() {
    final content = widget.message.content;
    final latitude = content['latitude'] as double? ?? 0.0;
    final longitude = content['longitude'] as double? ?? 0.0;
    final address = content['address'] as String? ?? 'Location';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Map placeholder
          Container(
            width: 300,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Map Preview',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Location info
          Text(
            address,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 8),

          Text(
            '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Build contact viewer
  Widget _buildContactViewer() {
    final content = widget.message.content;
    final name = content['name'] as String? ?? 'Contact';
    final phone = content['phone'] as String?;
    final email = content['email'] as String?;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Contact avatar
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Contact name
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          // Contact details
          if (phone != null) ...[
            _buildContactDetail(Icons.phone, phone),
            const SizedBox(height: 8),
          ],

          if (email != null) ...[
            _buildContactDetail(Icons.email, email),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 24),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Implement call functionality
                  print('📞 Calling: $phone');
                },
                icon: const Icon(Icons.call),
                label: const Text('Call'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Implement message functionality
                  print('💬 Messaging: $phone');
                },
                icon: const Icon(Icons.message),
                label: const Text('Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build contact detail row
  Widget _buildContactDetail(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white70,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  /// Build unsupported media display
  Widget _buildUnsupportedMedia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white70,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Unsupported Media Type',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This media type cannot be previewed',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Build error display
  Widget _buildErrorDisplay(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.white70,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  /// Build bottom controls
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Previous button
          IconButton(
            onPressed: _currentPage > 0 ? _previousPage : null,
            icon: Icon(
              Icons.chevron_left,
              color: _currentPage > 0 ? Colors.white : Colors.white38,
            ),
            tooltip: 'Previous',
          ),

          // Page indicator
          Text(
            '${_currentPage + 1} / 1',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),

          // Next button
          IconButton(
            onPressed: _currentPage < 0 ? _nextPage : null,
            icon: Icon(
              Icons.chevron_right,
              color: _currentPage < 0 ? Colors.white : Colors.white38,
            ),
            tooltip: 'Next',
          ),
        ],
      ),
    );
  }

  /// Navigate to previous page
  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Navigate to next page
  void _nextPage() {
    if (_currentPage < 0) {
      setState(() {
        _currentPage++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Format duration for display
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
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


