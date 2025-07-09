import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';

class ChatInvitationScreen extends StatefulWidget {
  final User recipient;

  const ChatInvitationScreen({super.key, required this.recipient});

  @override
  State<ChatInvitationScreen> createState() => _ChatInvitationScreenState();
}

class _ChatInvitationScreenState extends State<ChatInvitationScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendInvitation() async {
    if (_messageController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter a message';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'User not authenticated';
        });
        return;
      }

      // TODO: Implement invitation API call
      // final response = await ApiService.sendInvitation({
      //   'recipient_id': widget.recipient.id,
      //   'message': _messageController.text.trim(),
      // });

      // Simulate API call for now
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation sent to ${widget.recipient.username}'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Invitation'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recipient Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        widget.recipient.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.recipient.username,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            widget.recipient.isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: widget.recipient.isOnline
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Invitation Message
            Text(
              'Invitation Message',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a custom message to invite ${widget.recipient.username} to chat with you.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter your invitation message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (_error != null) const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendInvitation,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Send Invitation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
