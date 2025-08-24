import 'package:flutter/material.dart';
import '../models/local_notification_item.dart';
import '../models/notification_icons.dart';

/// Modal overlay screen for notification actions
class NotificationActionScreen extends StatefulWidget {
  final LocalNotificationItem notification;
  final VoidCallback? onNotificationRead;

  const NotificationActionScreen({
    super.key,
    required this.notification,
    this.onNotificationRead,
  });

  @override
  State<NotificationActionScreen> createState() =>
      _NotificationActionScreenState();
}

class _NotificationActionScreenState extends State<NotificationActionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: _buildModalContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModalContent() {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with icon and close button
          _buildHeader(),

          // Scrollable content area
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Notification content
                  _buildNotificationContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _getIconColor(),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              NotificationIcons.getIconFromName(widget.notification.icon),
              color: Colors.white,
              size: 28,
            ),
          ),

          const SizedBox(width: 16),

          // Title and type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.notification.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getNotificationTypeText(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Close button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          if (widget.notification.description != null) ...[
            Text(
              widget.notification.description!,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Metadata details
          _buildMetadataSection(),

          // Date
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(widget.notification.date),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    if (widget.notification.metadata == null) return const SizedBox.shrink();

    final metadata = widget.notification.metadata!;
    final List<Widget> metadataWidgets = [];

    // Add relevant metadata based on notification type
    if (metadata.containsKey('requestPhrase')) {
      metadataWidgets
          .add(_buildMetadataItem('Request Phrase', metadata['requestPhrase']));
    }

    if (metadata.containsKey('senderId')) {
      metadataWidgets.add(_buildMetadataItem('From', metadata['senderId']));
    }

    if (metadata.containsKey('recipientId')) {
      metadataWidgets.add(_buildMetadataItem('To', metadata['recipientId']));
    }

    if (metadataWidgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        ...metadataWidgets,
      ],
    );
  }

  Widget _buildMetadataItem(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // View Details button (for KER notifications)
          if (_shouldShowViewDetailsButton())
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _viewDetails,
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('View Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getIconColor() {
    switch (widget.notification.type) {
      case 'welcome':
        return Colors.green;
      case 'ker_sent':
      case 'ker_received':
        return Colors.blue;
      case 'ker_accepted':
        return Colors.green;
      case 'ker_declined':
        return Colors.red;
      case 'ker_resent':
        return Colors.orange;
      default:
        return const Color(0xFFFF6B35);
    }
  }

  String _getNotificationTypeText() {
    switch (widget.notification.type) {
      case 'welcome':
        return 'Welcome Message';
      case 'ker_sent':
        return 'Key Exchange Request Sent';
      case 'ker_received':
        return 'Key Exchange Request Received';
      case 'ker_accepted':
        return 'Key Exchange Request Accepted';
      case 'ker_declined':
        return 'Key Exchange Request Declined';
      case 'ker_resent':
        return 'Key Exchange Request Resent';
      default:
        return 'Notification';
    }
  }

  bool _shouldShowViewDetailsButton() {
    return widget.notification.type.startsWith('ker_');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  void _viewDetails() {
    // Close the modal first
    Navigator.of(context).pop();

    // Navigate to appropriate screen based on notification type
    if (widget.notification.type.startsWith('ker_')) {
      // Navigate to key exchange screen
      Navigator.of(context).pushNamed('/key-exchange');
    }
  }
}
