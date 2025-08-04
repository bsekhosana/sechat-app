import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/shared/widgets/profile_icon_widget.dart';
import 'package:sechat_app/shared/widgets/invite_user_widget.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'package:sechat_app/features/notifications/providers/notification_provider.dart';
import 'package:sechat_app/features/notifications/models/local_notification.dart';
import 'package:sechat_app/features/auth/screens/main_nav_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.notifications,
                      color: Color(0xFFFF6B35),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Consumer<NotificationProvider>(
                    builder: (context, notificationProvider, child) {
                      if (notificationProvider.notifications.isNotEmpty) {
                        return GestureDetector(
                          onTap: () => _showClearAllDialog(
                              context, notificationProvider),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.clear_all,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),

            // Notifications List
            Expanded(
              child: Consumer<NotificationProvider>(
                builder: (context, notificationProvider, child) {
                  if (notificationProvider.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                      ),
                    );
                  }

                  if (notificationProvider.notifications.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: 24, left: 24, right: 24, top: 24),
                    itemCount: notificationProvider.notifications.length,
                    itemBuilder: (context, index) {
                      final notification =
                          notificationProvider.notifications[index];
                      return _buildNotificationCard(
                          notification, notificationProvider);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll see notifications here when you receive messages or invitations',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog(
      BuildContext context, NotificationProvider notificationProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text(
          'This will permanently delete all notifications. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              notificationProvider.clearAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All notifications cleared'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    LocalNotification notification,
    NotificationProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: notification.isRead
              ? Colors.grey[300]!
              : const Color(0xFFFF6B35).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
        leading: _buildNotificationIcon(notification),
        title: Text(
          notification.title,
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // const SizedBox(height: 4),
            Text(
              notification.body,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatTimestamp(notification.timestamp),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B35),
                  shape: BoxShape.circle,
                ),
              ),
        onTap: () => _handleNotificationTap(notification, provider),
      ),
    );
  }

  Widget _buildNotificationIcon(LocalNotification notification) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case NotificationType.message:
        icon = Icons.message;
        color = Colors.blue;
        break;
      case NotificationType.invitation:
        icon = Icons.person_add;
        color = Colors.green;
        break;
      case NotificationType.invitationResponse:
        icon = Icons.check_circle;
        color = Colors.teal;
        break;
      case NotificationType.system:
        icon = Icons.info;
        color = Colors.orange;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.grey;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: color,
        size: 20,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _handleNotificationTap(
      LocalNotification notification, NotificationProvider provider) {
    // Mark as read
    provider.markAsRead(notification.id);

    // Handle navigation based on notification type
    switch (notification.type) {
      case NotificationType.message:
        // Navigate to chat
        if (notification.data != null && notification.data!['chatId'] != null) {
          _navigateToChat(notification.data!['chatId'] as String);
        }
        break;
      case NotificationType.invitation:
        // Navigate to invitations tab
        _navigateToInvitations();
        break;
      case NotificationType.invitationResponse:
        // Navigate to invitations tab to see updated status
        _navigateToInvitations();
        break;
      case NotificationType.system:
        // Show system notification details
        _showNotificationDetails(notification);
        break;
    }
  }

  void _navigateToChat(String chatId) {
    // Navigate to main nav screen and switch to chats tab
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainNavScreen()),
      (route) => false,
    );

    // Switch to chats tab (this would need to be handled by the main nav screen)
    // For now, we'll just navigate to the main screen
  }

  void _navigateToInvitations() {
    // Navigate to main nav screen and switch to invitations tab
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainNavScreen()),
      (route) => false,
    );

    // Switch to invitations tab (this would need to be handled by the main nav screen)
    // For now, we'll just navigate to the main screen
  }

  void _showNotificationDetails(LocalNotification notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: Text(
          notification.title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          notification.body,
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _shareApp() {
    // Implement app sharing functionality
    // This would typically use the share_plus package
    // For now, we'll show a dialog with sharing options
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: const Text(
          'Share SeChat',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Share SeChat with friends and family for secure, private messaging.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement actual sharing
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sharing functionality coming soon!'),
                  backgroundColor: Color(0xFFFF6B35),
                ),
              );
            },
            child:
                const Text('Share', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }
}
