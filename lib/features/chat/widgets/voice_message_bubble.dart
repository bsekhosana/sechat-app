import 'package:flutter/material.dart';

import '../models/message.dart';

/// Widget for displaying voice message bubbles
class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadVoiceMessageData();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _loadVoiceMessageData() {
    final content = widget.message.content;
    final duration = content['duration'] as int? ?? 0;
    _totalDuration = Duration(seconds: duration);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isFromCurrentUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(widget.isFromCurrentUser ? 20 : 4),
            bottomRight: Radius.circular(widget.isFromCurrentUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/Pause button
            _buildPlayButton(context),

            const SizedBox(width: 12),

            // Voice wave visualization
            _buildVoiceWave(context),

            const SizedBox(width: 12),

            // Duration and progress
            _buildDurationInfo(context),
          ],
        ),
      ),
    );
  }

  /// Build play/pause button
  Widget _buildPlayButton(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayback,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isPlaying ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.isFromCurrentUser
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isFromCurrentUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build voice wave visualization
  Widget _buildVoiceWave(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(5, (index) {
          final height = _isPlaying ? 8.0 + (index * 2.0) : 4.0 + (index * 1.5);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 3,
            height: height,
            decoration: BoxDecoration(
              color: widget.isFromCurrentUser
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }

  /// Build duration and progress info
  Widget _buildDurationInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration text
        Text(
          _formatDuration(_currentPosition),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.isFromCurrentUser
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
        ),

        const SizedBox(height: 2),

        // Total duration
        Text(
          _formatDuration(_totalDuration),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.isFromCurrentUser
                    ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.7),
                fontSize: 10,
              ),
        ),
      ],
    );
  }

  /// Toggle playback
  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _startPlayback();
    } else {
      _pausePlayback();
    }
  }

  /// Start playback
  void _startPlayback() {
    _pulseController.repeat(reverse: true);

    // TODO: Implement actual audio playback
    // This will integrate with the VoiceMessageService
    print('🎵 Starting voice message playback');
  }

  /// Pause playback
  void _pausePlayback() {
    _pulseController.stop();

    // TODO: Implement actual audio pause
    print('🎵 Pausing voice message playback');
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Handle tap events
  void _onTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }
}
