import 'package:flutter/material.dart';

class CustomElevatedButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  final String text;
  final IconData? icon;
  final bool isPrimary;
  final bool orangeLoading;
  const CustomElevatedButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    required this.text,
    this.orangeLoading = false,
    this.isPrimary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    orangeLoading ? Color(0xFFFF6B35) : Colors.white,
                  ),
                ),
              )
            : Icon(icon ?? Icons.add_circle_outline),
        label: isLoading ? const SizedBox.shrink() : Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFFFF6B35) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
