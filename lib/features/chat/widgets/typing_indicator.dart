import 'package:flutter/material.dart';

/// Widget for showing typing indicator when someone is typing
class TypingIndicator extends StatefulWidget {
  final String typingUserName; // Name of the person who is typing
  final Duration animationDuration;

  const TypingIndicator({
    super.key,
    required this.typingUserName,
    this.animationDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Start the continuous typing animation
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(_slideAnimation),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Typing dots animation
              _buildTypingDots(),

              const SizedBox(width: 12),

              // Typing user name
              Text(
                '${widget.typingUserName} is typing...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.deepOrangeAccent,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build animated typing dots
  Widget _buildTypingDots() {
    return SizedBox(
      width: 24,
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final delay = index * 0.3;
              final animationValue = (_animationController.value + delay) % 1.0;
              // Create a wave effect: fade in, then fade out
              final opacity = (animationValue < 0.5)
                  ? (animationValue * 2)
                  : ((1.0 - animationValue) * 2);

              return Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.deepOrangeAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
