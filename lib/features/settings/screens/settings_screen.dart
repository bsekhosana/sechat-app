import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../core/services/local_storage_service.dart';
import '../../auth/screens/login_screen.dart';

import '../../chat/providers/chat_provider.dart';
import 'package:sechat_app/shared/widgets/invite_user_widget.dart';
import 'package:sechat_app/core/services/session_service.dart';
import 'package:sechat_app/shared/widgets/app_icon.dart';
import 'package:sechat_app/core/services/notification_service.dart';
import 'package:sechat_app/core/services/network_service.dart';
import 'package:sechat_app/shared/widgets/connection_status_widget.dart';
import '../../invitations/providers/invitation_provider.dart';
import 'package:sechat_app/features/notifications/providers/notification_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _shareApp() {
    const String shareText = '''
🔒 Join me on SeChat - Private & Secure Messaging! 

✨ Features:
• End-to-end encrypted conversations
• Anonymous messaging
• No personal data required
• Clean, modern interface

Download now and let's chat securely!

#SeChat #PrivateMessaging #Encrypted
    ''';

    Share.share(
      shareText,
      subject: 'Join me on SeChat - Secure Messaging App',
    );
  }

  void _showStorageManagementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _StorageManagementSheet(),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text(
            'Logout',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out? You\'ll need to enter your password to log back in.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog first

                try {
                  // Show loading indicator
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                  );

                  // Perform logout
                  await Provider.of<AuthProvider>(context, listen: false)
                      .logout();

                  // Check if widget is still mounted before navigation
                  if (context.mounted) {
                    // Navigate to login screen without back button
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  print('Logout error: $e');
                  // If there's an error and context is still mounted, close loading dialog
                  if (context.mounted) {
                    Navigator.of(context).pop(); // Close loading dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logout failed. Please try again.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5555),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header matching the designs
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _shareApp,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: InviteUserWidget(),
                  ),
                  const SizedBox(width: 12),
                  const ProfileIconWidget(),
                ],
              ),
            ),

            // Settings title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Settings options
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildSettingsItem(
                      title: 'Storage & Data',
                      onTap: () => _showStorageManagementSheet(context),
                    ),
                    _buildSettingsItem(
                      title: 'Last Synced',
                      subtitle: _getLastSyncedTime(),
                      onTap: () => _showSyncInfo(context),
                    ),
                    _buildSettingsItem(
                      title: 'Logout',
                      onTap: () => _showLogoutConfirmation(context),
                      isDestructive: true,
                    ),
                    const Spacer(),
                    // App version info
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Column(
                        children: [
                          Text(
                            'SeChat',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Version 1.0.0 (Build 1)',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDestructive
                              ? const Color(0xFFFF5555)
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: isDestructive
                      ? const Color(0xFFFF5555)
                      : const Color(0xFF666666),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getLastSyncedTime() {
    // TODO: Get actual last sync time from SessionService
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year} at ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _showSyncInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: const Text(
          'Sync Information',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Synced: ${_getLastSyncedTime()}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'SeChat automatically syncs messages and contacts using the Session Protocol. No manual sync is required.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}

class _StorageManagementSheet extends StatefulWidget {
  const _StorageManagementSheet();

  @override
  State<_StorageManagementSheet> createState() =>
      _StorageManagementSheetState();
}

class _StorageManagementSheetState extends State<_StorageManagementSheet> {
  Map<String, dynamic> _storageStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorageStats();
  }

  Future<void> _loadStorageStats() async {
    try {
      final stats = await LocalStorageService.instance.getStorageStats();
      setState(() {
        _storageStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearOldMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Clear Old Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete messages older than 30 days. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.instance.clearOldMessages();
        await _loadStorageStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Old messages cleared successfully'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing messages: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Clear All Data',
          style: TextStyle(color: Colors.red),
        ),
        content: const Text(
          'This will delete ALL your chats, messages, and files. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.instance.clearAllData();
        await _loadStorageStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All data cleared successfully'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF232323),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: ListView(
          controller: scrollController,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            const Text(
              'Storage & Data',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your local data and storage',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF6B35),
                ),
              )
            else ...[
              // Storage Overview
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Storage Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStorageItem(
                      'Total Storage',
                      _formatBytes(_storageStats['totalStorageSize'] ?? 0),
                      Icons.storage,
                    ),
                    _buildStorageItem(
                      'Images',
                      _formatBytes(_storageStats['totalImageSize'] ?? 0),
                      Icons.image,
                    ),
                    _buildStorageItem(
                      'Voice Messages',
                      _formatBytes(_storageStats['totalVoiceSize'] ?? 0),
                      Icons.mic,
                    ),
                    _buildStorageItem(
                      'Files',
                      _formatBytes(_storageStats['totalFileSize'] ?? 0),
                      Icons.file_present,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Data Statistics
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Statistics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDataItem(
                      'Total Messages',
                      '${_storageStats['totalMessages'] ?? 0}',
                      Icons.message,
                    ),
                    _buildDataItem(
                      'Text Messages',
                      '${_storageStats['textMessages'] ?? 0}',
                      Icons.text_fields,
                    ),
                    _buildDataItem(
                      'Image Messages',
                      '${_storageStats['imageMessages'] ?? 0}',
                      Icons.image,
                    ),
                    _buildDataItem(
                      'Voice Messages',
                      '${_storageStats['voiceMessages'] ?? 0}',
                      Icons.mic,
                    ),
                    _buildDataItem(
                      'File Messages',
                      '${_storageStats['fileMessages'] ?? 0}',
                      Icons.file_present,
                    ),
                    _buildDataItem(
                      'Chats',
                      '${_storageStats['chatsCount'] ?? 0}',
                      Icons.chat,
                    ),
                    _buildDataItem(
                      'Users',
                      '${_storageStats['usersCount'] ?? 0}',
                      Icons.people,
                    ),
                    _buildDataItem(
                      'Pending Messages',
                      '${_storageStats['pendingMessagesCount'] ?? 0}',
                      Icons.schedule,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: _clearOldMessages,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear Old Messages (30+ days)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _clearAllData,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Clear All Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Refresh Button
              TextButton.icon(
                onPressed: _loadStorageStats,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Statistics'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                ),
              ),
              const SizedBox(height: 16),

              // Close Button
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF6B35), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF6B35), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
