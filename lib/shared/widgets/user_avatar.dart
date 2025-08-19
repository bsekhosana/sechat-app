import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? profilePicture;
  final String? displayName;
  final String? sessionId;
  final double radius;
  final Color? backgroundColor;
  final Color? textColor;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.profilePicture,
    this.displayName,
    this.sessionId,
    this.radius = 20,
    this.backgroundColor,
    this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String initials = _getInitials();
    final Color bgColor = backgroundColor ?? const Color(0xFFFF6B35);
    final Color txtColor = textColor ?? Colors.white;

    // Determine border color based on background
    final Color borderColor =
        bgColor == Colors.black || bgColor == const Color(0xFF121212)
            ? const Color(0xFFFF6B35)
            : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: bgColor.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: _buildAvatarContent(initials, txtColor),
      ),
    );
  }

  Widget _buildAvatarContent(String initials, Color textColor) {
    // If we have a valid profile picture, show it
    if (profilePicture != null && profilePicture!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          profilePicture!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to initials if image fails to load
            return _buildInitialsContent(initials, textColor);
          },
        ),
      );
    }

    // Otherwise show initials
    return _buildInitialsContent(initials, textColor);
  }

  Widget _buildInitialsContent(String initials, Color textColor) {
    return Center(
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getInitials() {
    // Try to get initials from display name first
    if (displayName != null && displayName!.isNotEmpty) {
      final nameParts = displayName!.trim().split(' ');
      if (nameParts.isNotEmpty) {
        if (nameParts.length >= 2) {
          return '${nameParts[0][0]}${nameParts[1][0]}';
        } else {
          return nameParts[0][0];
        }
      }
    }

    // Fallback to session ID initials
    if (sessionId != null && sessionId!.isNotEmpty) {
      return sessionId!.substring(0, 2);
    }

    // Final fallback
    return 'U';
  }
}
