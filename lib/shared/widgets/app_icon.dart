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
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.25),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF23272F).withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(width * 0.13),
          child: Image.asset(
            'assets/logo/seChat_Logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
