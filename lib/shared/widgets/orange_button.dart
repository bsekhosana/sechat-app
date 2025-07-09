import 'package:flutter/material.dart';

class OrangeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool isDelete;

  const OrangeButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.isDelete = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final elementHeight = screenHeight * 0.065; // ≈6.5% of height
    // delete button must be red with white text and white border
    final bgColor = isDelete
        ? Colors.white
        : primary
            ? const Color(0xFFFF6B35)
            : Colors.white;
    final fgColor = isDelete
        ? Colors.red
        : primary
            ? Colors.white
            : const Color(0xFFFF6B35);
    return SizedBox(
      width: double.infinity,
      height: elementHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: bgColor,
              width: 1.5,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          elevation: 0,
        ),
        child: Text(label),
      ),
    );
  }
}
