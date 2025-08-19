import 'package:flutter/material.dart';
import '../../../core/services/global_user_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_socket_service.dart';
import '../../../core/services/se_socket_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Show delete account confirmation dialog
  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone and will:\n\n'
            '• Remove all your data\n'
            '• Delete all conversations\n'
            '• Clear all encryption keys',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteAccount(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete Account'),
            ),
          ],
        );
      },
    );
  }

  /// Delete account and clear all data
  Future<void> _deleteAccount(BuildContext context) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Deleting account...'),
              ],
            ),
          );
        },
      );

      // Disconnect socket before deleting account
      try {
        final socketService = SeSocketService();
        await socketService.disconnect();
        print(
            '🔌 ProfileScreen: ✅ Socket disconnected before account deletion');
      } catch (e) {
        print(
            '🔌 ProfileScreen: ⚠️ Error disconnecting socket: $e, but continuing with account deletion');
      }

      // Tell socket server to remove this session and clear queues before local purge
      try {
        final socketService = SeSocketService();
        final sessionId = SeSessionService().currentSessionId;
        await socketService.deleteSessionOnServer(sessionId: sessionId);
      } catch (e) {
        // Continue even if this fails; local cleanup still proceeds
      }

      // Use the comprehensive account deletion method (local data)
      await SeSessionService().deleteAccount();

      // Close loading dialog
      Navigator.of(context).pop();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Account deleted successfully - All data has been cleared'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to login screen or show logout message
      // You can add navigation logic here if needed
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Send offline status and disconnect socket before logout
              try {
                final socketService = SeSocketService();
                await socketService.sendOnlineStatusToAllContacts(false);
                await socketService.disconnect();
                print('🔌 ProfileScreen: ✅ Socket disconnected during logout');
              } catch (e) {
                print(
                    '🔌 ProfileScreen: ⚠️ Error handling socket during logout: $e');
              }

              await SeSessionService().logout();
              // Navigate to login screen or show logout message
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${GlobalUserService.instance.currentUsername ?? 'User'}!',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Session ID: ${SeSessionService().currentSessionId ?? 'Not set'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Settings
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  // Navigate to settings
                },
              ),
            ),

            const SizedBox(height: 16),

            // Danger Zone
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Danger Zone',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showDeleteAccountDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete Account'),
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
}
