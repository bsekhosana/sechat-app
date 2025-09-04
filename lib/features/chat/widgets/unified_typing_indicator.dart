import 'package:flutter/material.dart';

/// Modern typing indicator with WhatsApp-like design
class UnifiedTypingIndicator extends StatefulWidget {
  final String typingUserName;

  const UnifiedTypingIndicator({
    super.key,
    required this.typingUserName,
  });

  @override
  State<UnifiedTypingIndicator> createState() => _UnifiedTypingIndicatorState();
}

class _UnifiedTypingIndicatorState extends State<UnifiedTypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 60, bottom: 8),
      child: Row(
        children: [
          // Typing indicator bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: Colors.grey[50], // Light grey to match main screen
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(8),
                topRight: const Radius.circular(8),
                bottomLeft: const Radius.circular(2),
                bottomRight: const Radius.circular(8),
              ),
              border: Border.all(
                color: Colors.grey[200]!, // Light grey border to match main screen
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05), // Lighter shadow to match main screen
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.typingUserName} is typing',
                  style: TextStyle(
                    color: Colors.grey[500], // Lighter text to match main screen
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 8),
                _buildTypingDots(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build animated typing dots
  Widget _buildTypingDots() {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animationValue = (_animation.value - delay).clamp(0.0, 1.0);
            final opacity = (animationValue * 2 - 1).abs();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
