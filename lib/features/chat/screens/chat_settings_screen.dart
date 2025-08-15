import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import '../models/chat_conversation.dart';

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
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _readReceiptsEnabled = true;
  bool _typingIndicatorsEnabled = true;
  bool _lastSeenEnabled = true;
  bool _mediaAutoDownload = true;
  bool _encryptMedia = true;
  String _messageRetention = '30 days';
  String _mediaQuality = 'High';
  double _storageUsage = 0.0;
  String _storageUsageText = '0 MB';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load conversation settings
    setState(() {
      _notificationsEnabled = widget.conversation.notificationsEnabled ?? true;
      _soundEnabled = widget.conversation.soundEnabled ?? true;
      _vibrationEnabled = widget.conversation.vibrationEnabled ?? true;
      _readReceiptsEnabled = widget.conversation.readReceiptsEnabled ?? true;
      _typingIndicatorsEnabled =
          widget.conversation.typingIndicatorsEnabled ?? true;
      _lastSeenEnabled = widget.conversation.lastSeenEnabled ?? true;
      _mediaAutoDownload = widget.conversation.mediaAutoDownload ?? true;
      _encryptMedia = widget.conversation.encryptMedia ?? true;
      _messageRetention = widget.conversation.messageRetention ?? '30 days';
      _mediaQuality = widget.conversation.mediaQuality ?? 'High';
    });

    // Calculate storage usage
    await _calculateStorageUsage();
  }

  Future<void> _calculateStorageUsage() async {
    // This would be implemented to calculate actual storage usage
    setState(() {
      _storageUsage = 0.25; // 25% of available storage
      _storageUsageText = '156 MB';
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

            // Notification settings
            _buildNotificationSettings(),

            const SizedBox(height: 16),

            // Privacy settings
            _buildPrivacySettings(),

            const SizedBox(height: 16),

            // Media settings
            _buildMediaSettings(),

            const SizedBox(height: 16),

            // Storage management
            _buildStorageSettings(),

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

  Widget _buildNotificationSettings() {
    return _buildSettingsSection(
      title: 'Notifications',
      icon: Icons.notifications,
      children: [
        _buildSwitchTile(
          title: 'Enable Notifications',
          subtitle: 'Receive notifications for new messages',
          value: _notificationsEnabled,
          onChanged: (value) {
            setState(() => _notificationsEnabled = value);
            _updateNotificationSettings();
          },
        ),
        if (_notificationsEnabled) ...[
          _buildSwitchTile(
            title: 'Sound',
            subtitle: 'Play sound for notifications',
            value: _soundEnabled,
            onChanged: (value) {
              setState(() => _soundEnabled = value);
              _updateNotificationSettings();
            },
          ),
          _buildSwitchTile(
            title: 'Vibration',
            subtitle: 'Vibrate for notifications',
            value: _vibrationEnabled,
            onChanged: (value) {
              setState(() => _vibrationEnabled = value);
              _updateNotificationSettings();
            },
          ),
        ],
      ],
    );
  }

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

  Widget _buildMediaSettings() {
    return _buildSettingsSection(
      title: 'Media',
      icon: Icons.photo_library,
      children: [
        _buildSwitchTile(
          title: 'Auto-download Media',
          subtitle: 'Automatically download media files',
          value: _mediaAutoDownload,
          onChanged: (value) {
            setState(() => _mediaAutoDownload = value);
            _updateMediaSettings();
          },
        ),
        _buildSwitchTile(
          title: 'Encrypt Media',
          subtitle: 'Encrypt all media files',
          value: _encryptMedia,
          onChanged: (value) {
            setState(() => _encryptMedia = value);
            _updateMediaSettings();
          },
        ),
        _buildListTile(
          title: 'Media Quality',
          subtitle: _mediaQuality,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showMediaQualityDialog(),
        ),
        _buildListTile(
          title: 'Message Retention',
          subtitle: _messageRetention,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showRetentionDialog(),
        ),
      ],
    );
  }

  Widget _buildStorageSettings() {
    return _buildSettingsSection(
      title: 'Storage',
      icon: Icons.storage,
      children: [
        _buildListTile(
          title: 'Storage Usage',
          subtitle: _storageUsageText,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showStorageDetails(),
        ),
        _buildListTile(
          title: 'Clear Media Cache',
          subtitle: 'Free up storage space',
          trailing: const Icon(Icons.delete_outline),
          onTap: () => _clearMediaCache(),
        ),
        _buildListTile(
          title: 'Export Chat',
          subtitle: 'Save chat history',
          trailing: const Icon(Icons.download),
          onTap: () => _exportChat(),
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

  void _updateNotificationSettings() {
    // Update conversation notification settings
    final provider = context.read<ChatProvider>();
    provider.updateConversationSettings(
      widget.conversation.id,
      notificationsEnabled: _notificationsEnabled,
      soundEnabled: _soundEnabled,
      vibrationEnabled: _vibrationEnabled,
    );
  }

  void _updatePrivacySettings() {
    // Update conversation privacy settings
    final provider = context.read<ChatProvider>();
    provider.updateConversationSettings(
      widget.conversation.id,
      readReceiptsEnabled: _readReceiptsEnabled,
      typingIndicatorsEnabled: _typingIndicatorsEnabled,
      lastSeenEnabled: _lastSeenEnabled,
    );
  }

  void _updateMediaSettings() {
    // Update conversation media settings
    final provider = context.read<ChatProvider>();
    provider.updateConversationSettings(
      widget.conversation.id,
      mediaAutoDownload: _mediaAutoDownload,
      encryptMedia: _encryptMedia,
      mediaQuality: _mediaQuality,
      messageRetention: _messageRetention,
    );
  }

  void _showMediaQualityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media Quality'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'Low',
            'Medium',
            'High',
            'Original',
          ]
              .map((quality) => RadioListTile<String>(
                    title: Text(quality),
                    value: quality,
                    groupValue: _mediaQuality,
                    onChanged: (value) {
                      setState(() => _mediaQuality = value!);
                      Navigator.pop(context);
                      _updateMediaSettings();
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showRetentionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Retention'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            '7 days',
            '30 days',
            '90 days',
            '1 year',
            'Never',
          ]
              .map((retention) => RadioListTile<String>(
                    title: Text(retention),
                    value: retention,
                    groupValue: _messageRetention,
                    onChanged: (value) {
                      setState(() => _messageRetention = value!);
                      Navigator.pop(context);
                      _updateMediaSettings();
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showStorageDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Usage: $_storageUsageText'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _storageUsage,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Breakdown:'),
            const Text('• Images: 45 MB'),
            const Text('• Videos: 89 MB'),
            const Text('• Documents: 12 MB'),
            const Text('• Voice Messages: 10 MB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearMediaCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Media Cache'),
        content: const Text(
          'This will delete all downloaded media files for this conversation. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Clear media cache
      final provider = context.read<ChatProvider>();
      await provider.clearConversationMedia(widget.conversation.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media cache cleared')),
        );
        await _calculateStorageUsage();
      }
    }
  }

  Future<void> _exportChat() async {
    // Show export options
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Text File (.txt)'),
              onTap: () => Navigator.pop(context, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('PDF Document (.pdf)'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel Spreadsheet (.xlsx)'),
              onTap: () => Navigator.pop(context, 'xlsx'),
            ),
          ],
        ),
      ),
    );

    if (format != null) {
      // Export chat
      final provider = context.read<ChatProvider>();
      await provider.exportConversation(widget.conversation.id, format);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat exported as .$format')),
        );
      }
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
      // Block user
      final provider = context.read<ChatProvider>();
      await provider.blockUser(widget.conversation.id);

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
      // Delete conversation
      final provider = context.read<ChatProvider>();
      await provider.deleteConversation(widget.conversation.id ?? '');

      if (mounted) {
        Navigator.pop(context); // Return to chat list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation deleted')),
        );
      }
    }
  }
}
