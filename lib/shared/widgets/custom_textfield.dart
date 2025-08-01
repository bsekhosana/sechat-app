import 'package:flutter/material.dart';

class CustomTextfield extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?) validator;
  final void Function(String)? onChanged;

  const CustomTextfield({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.grey),
      cursorColor: Colors.grey,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF6B35), width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
