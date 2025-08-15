import 'dart:async';
import 'package:flutter/material.dart';

/// Widget for voice recording with visual feedback
class InputVoiceRecorder extends StatefulWidget {
  final Function(int, String) onVoiceMessageRecorded;
  final VoidCallback onClose;

  const InputVoiceRecorder({
    super.key,
    required this.onVoiceMessageRecorded,
    required this.onClose,
  });

  @override
  State<InputVoiceRecorder> createState() => _InputVoiceRecorderState();
}

class _InputVoiceRecorderState extends State<InputVoiceRecorder>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Voice Recorder',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Recording visualization
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Recording button
                  _buildRecordingButton(),

                  const SizedBox(height: 24),

                  // Recording status
                  _buildRecordingStatus(),

                  const SizedBox(height: 16),

                  // Wave visualization
                  _buildWaveVisualization(),

                  const SizedBox(height: 24),

                  // Recording controls
                  _buildRecordingControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build recording button
  Widget _buildRecordingButton() {
    return GestureDetector(
      onTapDown: (_) => _startRecording(),
      onTapUp: (_) => _stopRecording(),
      onTapCancel: () => _cancelRecording(),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isRecording ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _isRecording
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary)
                        .withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build recording status
  Widget _buildRecordingStatus() {
    return Column(
      children: [
        Text(
          _isRecording ? 'Recording...' : 'Tap to record',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _isRecording
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (_isRecording) ...[
          const SizedBox(height: 8),
          Text(
            _formatDuration(_recordingDuration),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
          ),
        ],
      ],
    );
  }

  /// Build wave visualization
  Widget _buildWaveVisualization() {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(7, (index) {
          return AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              final delay = index * 0.1;
              final animationValue = (_waveAnimation.value + delay) % 1.0;
              final height =
                  _isRecording ? 20.0 + (animationValue * 40.0) : 20.0;

              return Container(
                width: 6,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  /// Build recording controls
  Widget _buildRecordingControls() {
    if (!_isRecording) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Cancel button
        TextButton.icon(
          onPressed: _cancelRecording,
          icon: Icon(
            Icons.close,
            color: Theme.of(context).colorScheme.error,
          ),
          label: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),

        const SizedBox(width: 32),

        // Stop button
        ElevatedButton.icon(
          onPressed: _stopRecording,
          icon: Icon(
            Icons.stop,
            color: Colors.white,
          ),
          label: const Text(
            'Stop',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  /// Start recording
  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });

    _pulseController.repeat(reverse: true);
    _waveController.repeat();

    // Start recording timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });

      // Stop recording after 2 minutes (120 seconds)
      if (_recordingDuration.inSeconds >= 120) {
        _stopRecording();
      }
    });

    // TODO: Integrate with VoiceMessageService
    print('🎤 Starting voice recording...');
  }

  /// Stop recording
  void _stopRecording() {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    _pulseController.stop();
    _waveController.stop();
    _recordingTimer?.cancel();

    // TODO: Get recorded file path from VoiceMessageService
    final filePath = '/path/to/recorded/audio.m4a'; // Placeholder

    widget.onVoiceMessageRecorded(_recordingDuration.inSeconds, filePath);
    print('🎤 Voice recording stopped: ${_formatDuration(_recordingDuration)}');
  }

  /// Cancel recording
  void _cancelRecording() {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });

    _pulseController.stop();
    _waveController.stop();
    _recordingTimer?.cancel();

    // TODO: Cancel recording in VoiceMessageService
    print('🎤 Voice recording cancelled');
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
