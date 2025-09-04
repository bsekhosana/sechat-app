import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';
import '/../core/utils/logger.dart';

/// Comprehensive chat settings screen for conversation configuration
class ChatSettingsScreen extends StatefulWidget {
  final ChatConversation conversation;

  const ChatSettingsScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  // Notification settings removed - now handled by socket service
  bool _readReceiptsEnabled = true;
  bool _typingIndicatorsEnabled = true;
  bool _lastSeenEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load conversation settings
    setState(() {
      _readReceiptsEnabled = widget.conversation.readReceiptsEnabled ?? true;
      _typingIndicatorsEnabled =
          widget.conversation.typingIndicatorsEnabled ?? true;
      _lastSeenEnabled = widget.conversation.lastSeenEnabled ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Conversation info header
            _buildConversationHeader(),

            const SizedBox(height: 16),

            // Notification settings removed - now handled by socket service

            const SizedBox(height: 16),

            // Privacy settings
            _buildPrivacySettings(),

            const SizedBox(height: 16),

            const SizedBox(height: 16),

            // Conversation actions
            _buildConversationActions(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white,
            child: Text(
              widget.conversation.recipientName?.isNotEmpty ?? false
                  ? widget.conversation.recipientName![0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.conversation.recipientName ?? '',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.conversation.recipientId ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // Notification settings removed - now handled by socket service

  Widget _buildPrivacySettings() {
    return _buildSettingsSection(
      title: 'Privacy',
      icon: Icons.privacy_tip,
      children: [
        _buildSwitchTile(
          title: 'Read Receipts',
          subtitle: 'Show when messages are read',
          value: _readReceiptsEnabled,
          onChanged: (value) {
            setState(() => _readReceiptsEnabled = value);
            _updatePrivacySettings();
          },
        ),
        _buildSwitchTile(
          title: 'Typing Indicators',
          subtitle: 'Show when typing',
          value: _typingIndicatorsEnabled,
          onChanged: (value) {
            setState(() => _typingIndicatorsEnabled = value);
            _updatePrivacySettings();
          },
        ),
        _buildSwitchTile(
          title: 'Last Seen',
          subtitle: 'Show last seen status',
          value: _lastSeenEnabled,
          onChanged: (value) {
            setState(() => _lastSeenEnabled = value);
            _updatePrivacySettings();
          },
        ),
      ],
    );
  }

  Widget _buildConversationActions() {
    return _buildSettingsSection(
      title: 'Conversation',
      icon: Icons.chat,
      children: [
        _buildListTile(
          title: 'Block User',
          subtitle: 'Block this user',
          trailing: const Icon(Icons.block, color: Colors.red),
          onTap: () => _blockUser(),
        ),
        _buildListTile(
          title: 'Delete Conversation',
          subtitle: 'Permanently delete this conversation',
          trailing: const Icon(Icons.delete_forever, color: Colors.red),
          onTap: () => _deleteConversation(),
        ),
      ],
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }

  // Notification settings update removed - now handled by socket service

  void _updatePrivacySettings() {
    // Update conversation privacy settings
    try {
      // TODO: In a full implementation, this would:
      // 1. Save settings to local storage
      // 2. Send settings update to server
      // 3. Update conversation metadata

      Logger.debug(
          ' Update privacy settings: $_readReceiptsEnabled, $_typingIndicatorsEnabled, $_lastSeenEnabled');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Privacy settings updated'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      Logger.debug(' Error updating privacy settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update privacy settings: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${widget.conversation.recipientName}? '
          'You will no longer receive messages from this user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Implement block user functionality
      Logger.debug('🚫 Block user option selected');

      if (mounted) {
        Navigator.pop(context); // Return to chat list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
      }
    }
  }

  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text(
          'Are you sure you want to delete this conversation? '
          'This action cannot be undone and all messages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Implement delete conversation functionality
      Logger.info(' Delete conversation option selected');

      if (mounted) {
        Navigator.pop(context); // Return to chat list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation deleted')),
        );
      }
    }
  }
}
