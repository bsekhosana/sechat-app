import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import '../models/local_notification_item.dart';
import '../models/notification_icons.dart';
import '../services/local_notification_items_service.dart';
import '../services/local_notification_badge_service.dart';
import '../widgets/notification_action_screen.dart';

/// Local Notifications Screen
/// Shows local notification items from the new database system
class SocketNotificationsScreen extends StatefulWidget {
  const SocketNotificationsScreen({Key? key}) : super(key: key);

  @override
  State<SocketNotificationsScreen> createState() =>
      _SocketNotificationsScreenState();
}

class _SocketNotificationsScreenState extends State<SocketNotificationsScreen> {
  final LocalNotificationItemsService _notificationService =
      LocalNotificationItemsService();
  final LocalNotificationBadgeService _badgeService =
      LocalNotificationBadgeService();

  List<LocalNotificationItem> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load notifications from the new database
      final notifications = await _notificationService.getAllNotifications();

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        print('❌ SocketNotificationsScreen: Failed to load notifications: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load notifications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadNotifications,
            ),
          ),
        );
      }
    }
  }

  Future<void> _clearAllNotifications() async {
    try {
      await _badgeService.clearAllAndUpdateBadge();

      setState(() {
        _notifications.clear();
      });

      // Clear indicators in the service
      final indicatorService = context.read<IndicatorService>();
      indicatorService.clearNotificationIndicator();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showNotificationAction(LocalNotificationItem notification) async {
    // Automatically mark as read when showing the action screen
    if (notification.status == 'unread') {
      try {
        await _badgeService.markAsReadAndUpdateBadge(notification.id);

        // Update local state
        setState(() {
          final index =
              _notifications.indexWhere((n) => n.id == notification.id);
          if (index != -1) {
            _notifications[index] =
                _notifications[index].copyWith(status: 'read');
          }
        });
      } catch (e) {
        print(
            '❌ SocketNotificationsScreen: Failed to mark notification as read: $e');
      }
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => NotificationActionScreen(
        notification: notification,
        onNotificationRead: () {
          // Refresh the list after marking as read
          _loadNotifications();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications,
                  color: Color(0xFFFF6B35),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadNotifications,
                  icon: const Icon(
                    Icons.refresh,
                    color: Color(0xFFFF6B35),
                  ),
                ),
                if (_notifications.isNotEmpty)
                  TextButton(
                    onPressed: _clearAllNotifications,
                    child: const Text(
                      'Clear All',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Notifications list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF6B35),
                    ),
                  )
                : _notifications.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No notifications',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'All notifications will appear here',
                              style: TextStyle(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          final isUnread = notification.status == 'unread';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: isUnread
                                  ? Border.all(
                                      color: const Color(0xFFFF6B35)
                                          .withValues(alpha: 0.3),
                                      width: 2,
                                    )
                                  : Border.all(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                              boxShadow: [
                                BoxShadow(
                                  color: isUnread
                                      ? const Color(0xFFFF6B35)
                                          .withValues(alpha: 0.1)
                                      : Colors.grey.withValues(alpha: 0.1),
                                  spreadRadius: 1,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isUnread
                                      ? const Color(0xFFFF6B35)
                                      : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Icon(
                                    NotificationIcons.getIconFromName(
                                        notification.icon),
                                    color: isUnread
                                        ? Colors.white
                                        : Colors.grey[600],
                                    size: 20,
                                  ),
                                ),
                              ),
                              title: Text(
                                notification.title,
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isUnread
                                      ? Colors.black
                                      : Colors.grey[600],
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  if (notification.description != null)
                                    Text(
                                      notification.description!,
                                      style: TextStyle(
                                        color: isUnread
                                            ? Colors.grey[700]
                                            : Colors.grey[500],
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTimestamp(notification.date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getDirectionColor(
                                              notification.direction),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          notification.direction,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: isUnread
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFF6B35),
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                              onTap: () =>
                                  _showNotificationAction(notification),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _getDirectionColor(String direction) {
    switch (direction) {
      case 'incoming':
        return Colors.blue;
      case 'outgoing':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
