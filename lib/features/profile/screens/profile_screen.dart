import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/global_user_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';

import '../../../realtime/realtime_service_manager.dart';
import 'package:sechat_app/features/chat/providers/chat_list_provider.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/shared/providers/socket_status_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Copy feedback state
  bool _showSessionIdCopied = false;

  void _copySessionIdToClipboard() {
    final sessionId = SeSessionService().currentSessionId;
    if (sessionId != null) {
      Clipboard.setData(ClipboardData(text: sessionId));

      // Force UI rebuild
      setState(() {
        _showSessionIdCopied = true;
      });

      // Hide the copied message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showSessionIdCopied = false;
          });
        }
      });
    }
  }

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

  /// Show clear all chats confirmation dialog
  void _showClearAllChatsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear All Chats'),
          content: const Text(
            'Are you sure you want to clear all chats? This action cannot be undone and will:\n\n'
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
                await _clearAllChats(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear All Chats'),
            ),
          ],
        );
      },
    );
  }

  /// Delete account and clear all data
  Future<void> _deleteAccount(BuildContext context) async {
    // Store context before async operations
    final navigatorContext = context;
    final scaffoldContext = context;

    try {
      // Show loading dialog
      showDialog(
        context: navigatorContext,
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
            Provider.of<ChatListProvider>(navigatorContext, listen: false);
        chatListProvider.clearAllData();
        print('🗑️ ProfileScreen: ✅ ChatListProvider cleared');

        // Clear KeyExchangeRequestProvider
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorContext,
            listen: false);
        keyExchangeProvider.clearAllData();
        print('🗑️ ProfileScreen: ✅ KeyExchangeRequestProvider cleared');

        // Clear IndicatorService
        final indicatorService =
            Provider.of<IndicatorService>(navigatorContext, listen: false);
        indicatorService.clearAllIndicators();
        print('🗑️ ProfileScreen: ✅ IndicatorService cleared');

        // Clear SocketStatusProvider
        final socketStatusProvider =
            Provider.of<SocketStatusProvider>(navigatorContext, listen: false);
        socketStatusProvider.resetState();
        print('🗑️ ProfileScreen: ✅ SocketStatusProvider reset');

        print('🗑️ ProfileScreen: ✅ All provider data cleared');
      } catch (e) {
        print('🗑️ ProfileScreen: ⚠️ Warning - provider cleanup failed: $e');
        // Don't fail the account deletion if provider cleanup fails
      }

      // Close loading dialog
      Navigator.of(navigatorContext).pop();

      // Show success message
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
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
      Navigator.of(navigatorContext).pop();

      // Show error message
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Clear all chats and related data
  Future<void> _clearAllChats(BuildContext context) async {
    // Store context before async operations
    final navigatorContext = context;
    final scaffoldContext = context;

    try {
      // Show loading dialog
      showDialog(
        context: navigatorContext,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Clearing chats...'),
              ],
            ),
          );
        },
      );

      // Disconnect channel socket before clearing chats
      try {
        final socketService = SeSocketService.instance;
        socketService.dispose();
        print(
            '🔌 ProfileScreen: ✅ Channel socket disposed before clearing chats');
      } catch (e) {
        print(
            '🔌 ProfileScreen: ⚠️ Error disposing channel socket: $e, but continuing with chat clearing');
      }

      // Clear ChatListProvider
      final chatListProvider =
          Provider.of<ChatListProvider>(navigatorContext, listen: false);
      chatListProvider.clearAllData();
      print('🗑️ ProfileScreen: ✅ ChatListProvider cleared');

      // Clear KeyExchangeRequestProvider
      final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
          navigatorContext,
          listen: false);
      keyExchangeProvider.clearAllData();
      print('🗑️ ProfileScreen: ✅ KeyExchangeRequestProvider cleared');

      // Clear IndicatorService
      final indicatorService =
          Provider.of<IndicatorService>(navigatorContext, listen: false);
      indicatorService.clearAllIndicators();
      print('🗑️ ProfileScreen: ✅ IndicatorService cleared');

      // Clear SocketStatusProvider
      final socketStatusProvider =
          Provider.of<SocketStatusProvider>(navigatorContext, listen: false);
      socketStatusProvider.resetState();
      print('🗑️ ProfileScreen: ✅ SocketStatusProvider reset');

      print('🗑️ ProfileScreen: ✅ All chat data cleared');

      // Close loading dialog
      Navigator.of(navigatorContext).pop();

      // Show success message
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        const SnackBar(
          content: Text(
              'All chats cleared successfully - All data has been cleared'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(navigatorContext).pop();

      // Show error message
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text('Error clearing chats: $e'),
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
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Session Code Container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Session Code',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    SeSessionService().currentSessionId ?? 'Not set',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Copy Button
                      Expanded(
                        child: GestureDetector(
                          onTap: _showSessionIdCopied
                              ? null
                              : _copySessionIdToClipboard,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _showSessionIdCopied
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _showSessionIdCopied
                                      ? Icons.check_circle
                                      : Icons.copy,
                                  color: _showSessionIdCopied
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showSessionIdCopied ? 'Copied' : 'Copy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _showSessionIdCopied
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[300]!),
              ),
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
                      onPressed: () => _showClearAllChatsDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[600],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear All Chats'),
                    ),
                  ),
                  const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }
}
