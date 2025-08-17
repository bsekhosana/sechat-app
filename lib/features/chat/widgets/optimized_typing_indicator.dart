import 'package:flutter/material.dart';

/// Optimized Typing Indicator Widget
/// Clean, animated typing indicator for chat
class OptimizedTypingIndicator extends StatefulWidget {
  final String userName;

  const OptimizedTypingIndicator({
    super.key,
    required this.userName,
  });

  @override
  State<OptimizedTypingIndicator> createState() =>
      _OptimizedTypingIndicatorState();
}

class _OptimizedTypingIndicatorState extends State<OptimizedTypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _dotControllers;
  late List<Animation<double>> _dotAnimations;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void dispose() {
    for (final controller in _dotControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Initialize animation controllers and animations
  void _initializeAnimations() {
    _dotControllers = List.generate(3, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 600 + (index * 200)),
        vsync: this,
      );
    });

    _dotAnimations = _dotControllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // Start animations
    for (final controller in _dotControllers) {
      controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _buildAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: _buildTypingBubble(),
          ),
        ],
      ),
    );
  }

  /// Build avatar for typing user
  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _getAvatarColor(),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getAvatarInitials(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Build typing bubble with dots
  Widget _buildTypingBubble() {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.6,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.userName} is typing',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          _buildTypingDots(),
        ],
      ),
    );
  }

  /// Build animated typing dots
  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _dotAnimations[index],
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color:
                    Colors.grey[600]?.withOpacity(_dotAnimations[index].value),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }

  /// Get avatar color based on user name
  Color _getAvatarColor() {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];

    final index = widget.userName.hashCode % colors.length;
    return colors[index.abs() % colors.length];
  }

  /// Get avatar initials from user name
  String _getAvatarInitials() {
    final name = widget.userName.trim();
    if (name.isEmpty) return '?';

    final parts = name.split(' ');
    if (parts.length == 1) {
      return name.substring(0, 1).toUpperCase();
    }

    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
