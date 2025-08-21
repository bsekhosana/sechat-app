import 'package:flutter/material.dart';
import '../../../core/services/global_user_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import '../../../core/services/channel_socket_service.dart';
import '../../../realtime/realtime_service_manager.dart';
import 'package:sechat_app/features/chat/providers/chat_list_provider.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/shared/providers/socket_status_provider.dart';

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

      // Disconnect channel socket before deleting account
      try {
        final socketService = SeSocketService.instance;
        socketService.dispose();
        print(
            '🔌 ProfileScreen: ✅ Channel socket disposed before account deletion');
      } catch (e) {
        print(
            '🔌 ProfileScreen: ⚠️ Error disposing channel socket: $e, but continuing with account deletion');
      }

      // Note: Session deletion on server is now handled by ChannelSocketService
      // The server will automatically clean up when the connection is closed

      // Use the comprehensive account deletion method (local data)
      await SeSessionService().deleteAccount();

      // CRITICAL: Clear all provider data to prevent old conversations from showing
      try {
        print('🗑️ ProfileScreen: 🧹 Clearing all provider data...');

        // Clear ChatListProvider
        final chatListProvider =
            Provider.of<ChatListProvider>(context, listen: false);
        chatListProvider.clearAllData();
        print('🗑️ ProfileScreen: ✅ ChatListProvider cleared');

        // Clear KeyExchangeRequestProvider
        final keyExchangeProvider =
            Provider.of<KeyExchangeRequestProvider>(context, listen: false);
        keyExchangeProvider.clearAllData();
        print('🗑️ ProfileScreen: ✅ KeyExchangeRequestProvider cleared');

        // Clear IndicatorService
        final indicatorService =
            Provider.of<IndicatorService>(context, listen: false);
        indicatorService.clearAllIndicators();
        print('🗑️ ProfileScreen: ✅ IndicatorService cleared');

        // Clear SocketStatusProvider
        final socketStatusProvider =
            Provider.of<SocketStatusProvider>(context, listen: false);
        socketStatusProvider.resetState();
        print('🗑️ ProfileScreen: ✅ SocketStatusProvider reset');

        print('🗑️ ProfileScreen: ✅ All provider data cleared');
      } catch (e) {
        print('🗑️ ProfileScreen: ⚠️ Warning - provider cleanup failed: $e');
        // Don't fail the account deletion if provider cleanup fails
      }

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
                final socketService = SeSocketService.instance;
                // Send offline status via realtime service
                try {
                  final realtimeManager = RealtimeServiceManager();
                  if (realtimeManager.isInitialized) {
                    realtimeManager.presence.forcePresenceUpdate(false);
                  } else {
                    // This part of the logic needs to be updated to use ChannelSocketService
                    // For now, we'll just print a message as the original SeSocketService is removed.
                    print(
                        '🔌 ProfileScreen: RealtimeServiceManager not initialized, cannot send offline status.');
                  }
                } catch (e) {
                  // This part of the logic needs to be updated to use ChannelSocketService
                  print('🔌 ProfileScreen: Error sending offline status: $e');
                }
                socketService.dispose(); // Disconnect the channel socket
                print(
                    '🔌 ProfileScreen: ✅ Channel socket disconnected during logout');
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
