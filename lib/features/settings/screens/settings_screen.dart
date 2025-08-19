import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/se_socket_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../../core/services/se_session_service.dart';
import 'queue_statistics_screen.dart';
import '../../../realtime/realtime_service_manager.dart';

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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(
                        Icons.logout,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    const Text(
                      'Are you sure you want to log out? You\'ll need to enter your password to log back in.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _performLogout(context),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Logout',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _performLogout(BuildContext context) async {
    Navigator.of(context).pop(); // Close action sheet first

    try {
      print('🔍 Settings: Starting logout process...');

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF6B35),
          ),
        ),
      );

      // Send offline status to all contacts and disconnect socket
      try {
        final socketService = SeSocketService();
        // Send offline status via realtime service
        try {
          final realtimeManager = RealtimeServiceManager.instance;
          if (realtimeManager.isInitialized) {
            realtimeManager.presence.forcePresenceUpdate(false);
            print('🔌 Settings: ✅ Offline status sent via realtime service');
          } else {
            // Fallback to direct socket service
            await socketService.sendUserOnlineStatus(false);
            print('🔌 Settings: ✅ Offline status sent via fallback');
          }
        } catch (e) {
          // Fallback to direct socket service
          await socketService.sendUserOnlineStatus(false);
          print('🔌 Settings: ✅ Offline status sent via fallback');
        }

        // Best effort: remove session on server
        final sessionId = SeSessionService().currentSessionId;
        await socketService.deleteSessionOnServer(sessionId: sessionId);

        // Disconnect socket
        await socketService.disconnect();
        print('🔌 Settings: ✅ Socket disconnected');
      } catch (e) {
        print(
            '🔌 Settings: ⚠️ Error handling socket during logout: $e, but continuing with logout');
      }

      // Perform logout using SeSessionService
      final seSessionService = SeSessionService();
      final logoutSuccess = await seSessionService.logout();

      print('🔍 Settings: Logout result: $logoutSuccess');

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }

      // Check if widget is still mounted before navigation
      if (context.mounted) {
        print('🔍 Settings: Navigating to login screen...');
        // Navigate to login screen without back button
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
          (route) => false,
        );
        print('🔍 Settings: Navigation completed');
      } else {
        print('🔍 Settings: Context not mounted after logout');
        // Force navigation even if context is not mounted
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
            (route) => false,
          );
        });
      }
    } catch (e) {
      print('🔍 Settings: Logout error: $e');
      // Close loading dialog if there's an error
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showGeneralChatSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GeneralChatSettingsScreen(),
      ),
    );
  }

  void _showQueueStatistics(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QueueStatisticsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Settings options
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 24),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildSettingsItem(
                        title: 'Storage & Data',
                        subtitle: 'Manage your data and storage',
                        onTap: () => _showStorageManagementSheet(context),
                      ),
                      _buildSettingsItem(
                        title: 'General Chat Settings',
                        subtitle: 'Manage your chat settings',
                        onTap: () => _showGeneralChatSettings(context),
                      ),
                      _buildSettingsItem(
                        title: 'Queue Statistics',
                        subtitle: 'View and manage message queues',
                        onTap: () => _showQueueStatistics(context),
                      ),
                      _buildSettingsItem(
                        title: 'Logout',
                        subtitle: 'Sign out of your account',
                        onTap: () => _showLogoutConfirmation(context),
                        isDestructive: true,
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
            // Footer with version info
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'SeChat',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0 (Build 1)',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
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
    // Determine icon based on title
    IconData icon;
    if (isDestructive) {
      icon = Icons.logout;
    } else if (title.contains('Storage')) {
      icon = Icons.storage;
    } else if (title.contains('Chat Settings')) {
      icon = Icons.chat;
    } else if (title.contains('Queue Statistics')) {
      icon = Icons.queue;
    } else {
      icon = Icons.settings;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Colors.red.withValues(alpha: 0.1)
                        : const Color(0xFFFF6B35).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive ? Colors.red : const Color(0xFFFF6B35),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDestructive ? Colors.red : Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
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
        backgroundColor: Colors.white,
        title: const Text(
          'Clear Old Messages',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'This will permanently delete messages older than 30 days. This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.instance.clearOldMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Old messages cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadStorageStats(); // Refresh stats
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Clear All Data',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'This will permanently delete all your messages, invitations, and app data. This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.instance.clearAllData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadStorageStats(); // Refresh stats
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
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
          color: Colors.white,
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            const Text(
              'Storage & Data',
              style: TextStyle(
                color: Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your local data and storage',
              style: TextStyle(
                color: Colors.grey[600],
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
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Storage Overview',
                      style: TextStyle(
                        color: Colors.black,
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
              const SizedBox(height: 24),

              // Action Buttons
              _buildActionButton(
                'Clear Old Messages',
                'Delete messages older than 30 days',
                Icons.delete_sweep,
                _clearOldMessages,
                Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                'Clear All Data',
                'Delete all messages and app data',
                Icons.delete_forever,
                _clearAllData,
                Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageItem(String label, String size, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFFFF6B35),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            size,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple general chat settings screen
class GeneralChatSettingsScreen extends StatefulWidget {
  const GeneralChatSettingsScreen({super.key});

  @override
  State<GeneralChatSettingsScreen> createState() =>
      _GeneralChatSettingsScreenState();
}

class _GeneralChatSettingsScreenState extends State<GeneralChatSettingsScreen> {
  // Notification settings removed - now handled by socket service
  bool _readReceiptsEnabled = true;
  bool _typingIndicatorsEnabled = true;
  bool _lastSeenEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Chat Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: const Color(0xFFFF6B35),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'General Chat Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B35),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Notification settings removed - now handled by socket service

              const SizedBox(height: 24),

              // Privacy settings
              _buildSettingsSection(
                'Privacy',
                Icons.privacy_tip,
                [
                  SwitchListTile(
                    title: const Text('Read receipts'),
                    subtitle: const Text('Show when messages are read'),
                    value: _readReceiptsEnabled,
                    onChanged: (value) =>
                        setState(() => _readReceiptsEnabled = value),
                    activeColor: const Color(0xFFFF6B35),
                  ),
                  SwitchListTile(
                    title: const Text('Typing indicators'),
                    subtitle: const Text('Show when someone is typing'),
                    value: _typingIndicatorsEnabled,
                    onChanged: (value) =>
                        setState(() => _typingIndicatorsEnabled = value),
                    activeColor: const Color(0xFFFF6B35),
                  ),
                  SwitchListTile(
                    title: const Text('Last seen'),
                    subtitle: const Text('Show when you were last online'),
                    value: _lastSeenEnabled,
                    onChanged: (value) =>
                        setState(() => _lastSeenEnabled = value),
                    activeColor: const Color(0xFFFF6B35),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(
      String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
