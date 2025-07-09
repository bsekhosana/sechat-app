import 'package:flutter/material.dart';

class InvitationsScreen extends StatelessWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Center(
        child: Text('Invitations', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
