import 'package:flutter/material.dart';

class AppIcon extends StatelessWidget {
  final double widthPerc; // e.g. 0.2 for 20% of screen width
  const AppIcon({super.key, required this.widthPerc});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * widthPerc;
    return Center(
      child: Container(
        width: width,
        height: width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              const Color(0xFFFFF5F0), // Very light orange tint
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(width * 0.25),
          border: Border.all(
            color: const Color(0xFFFF6B35), // Orange border
            width: width * 0.02,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B35).withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(width * 0.05),
          child: Image.asset(
            'assets/logo/seChat_cleanLogo.png',
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }
}
