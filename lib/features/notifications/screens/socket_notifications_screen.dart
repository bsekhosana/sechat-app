import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:sechat_app/features/notifications/models/socket_notification.dart';
import 'package:sechat_app/features/notifications/services/notification_database_service.dart';

/// Notifications screen
/// Shows notifications from the database (socket events are now handled by ChannelSocketService)
class SocketNotificationsScreen extends StatefulWidget {
  const SocketNotificationsScreen({Key? key}) : super(key: key);

  @override
  State<SocketNotificationsScreen> createState() =>
      _SocketNotificationsScreenState();
}

class _SocketNotificationsScreenState extends State<SocketNotificationsScreen> {
  final NotificationDatabaseService _databaseService =
      NotificationDatabaseService();
  List<SocketNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();

    // Listen for new notifications
    _databaseService.getNotifications().then((notifications) {
      if (mounted) {
        setState(() {
          _notifications = notifications;
        });
      }
    });
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load notifications from database
      final notifications = await _databaseService.getNotifications(limit: 100);

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _markAsRead(String notificationId) {
    setState(() {
      final notificationIndex =
          _notifications.indexWhere((n) => n.id == notificationId);
      if (notificationIndex != -1) {
        _notifications[notificationIndex] =
            _notifications[notificationIndex].copyWith(isRead: true);
      }
    });

    // Mark as read in database
    _databaseService.markAsRead(notificationId);
  }

  void _clearAllNotifications() async {
    setState(() {
      _notifications.clear();
    });

    // Clear all notifications from database
    await _databaseService.clearAllNotifications();

    // Clear indicators in the service
    final indicatorService = context.read<IndicatorService>();
    indicatorService.clearNotificationIndicator();
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
                  color: Colors.grey.withOpacity(0.1),
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
                          final isRead = notification.isRead;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
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
                                  color: isRead
                                      ? Colors.grey[300]
                                      : const Color(0xFFFF6B35),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    notification.notificationIcon,
                                    style: TextStyle(
                                      fontSize: 20,
                                      color: isRead
                                          ? Colors.grey[600]
                                          : Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              title: Text(
                                notification.title,
                                style: TextStyle(
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                  color:
                                      isRead ? Colors.grey[600] : Colors.black,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    notification.message,
                                    style: TextStyle(
                                      color: isRead
                                          ? Colors.grey[500]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    notification.age,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: !isRead
                                  ? IconButton(
                                      onPressed: () =>
                                          _markAsRead(notification.id),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        color: Color(0xFFFF6B35),
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                if (!isRead) {
                                  _markAsRead(notification.id);
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'message':
        return Icons.message;
      case 'key_exchange':
        return Icons.key;
      case 'online_status':
        return Icons.person;
      case 'error':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final difference = now.difference(timestamp);

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
