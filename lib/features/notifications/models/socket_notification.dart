import 'package:uuid/uuid.dart';

/// Socket notification model for tracking socket events
class SocketNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata;
  final String? senderId;
  final String? recipientId;
  final String? conversationId;
  final String? messageId;
  final NotificationPriority priority;
  final String? icon; // Icon identifier for the notification type

  SocketNotification({
    String? id,
    required this.type,
    required this.title,
    required this.message,
    DateTime? timestamp,
    this.isRead = false,
    this.metadata,
    this.senderId,
    this.recipientId,
    this.conversationId,
    this.messageId,
    this.priority = NotificationPriority.normal,
    this.icon,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Create a copy of this notification with updated fields
  SocketNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    Map<String, dynamic>? metadata,
    String? senderId,
    String? recipientId,
    String? conversationId,
    String? messageId,
    NotificationPriority? priority,
    String? icon,
  }) {
    return SocketNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      metadata: metadata ?? this.metadata,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      priority: priority ?? this.priority,
      icon: icon ?? this.icon,
    );
  }

  /// Convert notification to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead ? 1 : 0,
      'metadata': metadata != null ? metadata.toString() : null,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'conversation_id': conversationId,
      'message_id': messageId,
      'priority': priority.name,
      'icon': icon,
    };
  }

  /// Create notification from JSON
  factory SocketNotification.fromJson(Map<String, dynamic> json) {
    return SocketNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: (json['is_read'] as int?) == 1,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      senderId: json['sender_id'] as String?,
      recipientId: json['recipient_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      messageId: json['message_id'] as String?,
      priority: NotificationPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      icon: json['icon'] as String?,
    );
  }

  /// Create notification for message received
  factory SocketNotification.messageReceived({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
    String? messageId,
  }) {
    return SocketNotification(
      type: 'message_received',
      title: 'New Message',
      message: '$senderName: $message',
      senderId: senderId,
      conversationId: conversationId,
      messageId: messageId,
      priority: NotificationPriority.high,
    );
  }

  /// Create notification for typing indicator
  factory SocketNotification.typingIndicator({
    required String senderId,
    required String senderName,
    required String conversationId,
  }) {
    return SocketNotification(
      type: 'typing_indicator',
      title: 'Typing...',
      message: '$senderName is typing...',
      senderId: senderId,
      conversationId: conversationId,
      priority: NotificationPriority.low,
    );
  }

  /// Create notification for online status
  factory SocketNotification.onlineStatus({
    required String userId,
    required String userName,
    required bool isOnline,
  }) {
    return SocketNotification(
      type: 'online_status',
      title: isOnline ? 'User Online' : 'User Offline',
      message: '$userName is now ${isOnline ? 'online' : 'offline'}',
      senderId: userId,
      priority: NotificationPriority.low,
    );
  }

  /// Create notification for key exchange
  factory SocketNotification.keyExchange({
    required String type,
    required String senderId,
    required String senderName,
    String? message,
  }) {
    String title;
    String notificationMessage;

    switch (type) {
      case 'request':
        title = 'Key Exchange Request';
        notificationMessage = message ?? '$senderName wants to exchange keys';
        break;
      case 'accepted':
        title = 'Key Exchange Accepted';
        notificationMessage =
            message ?? '$senderName accepted your key exchange';
        break;
      case 'declined':
        title = 'Key Exchange Declined';
        notificationMessage =
            message ?? '$senderName declined your key exchange';
        break;
      default:
        title = 'Key Exchange';
        notificationMessage = message ?? 'Key exchange event from $senderName';
    }

    return SocketNotification(
      type: 'key_exchange_$type',
      title: title,
      message: notificationMessage,
      senderId: senderId,
      priority: NotificationPriority.high,
    );
  }

  /// Create notification for connection events
  factory SocketNotification.connectionEvent({
    required String event,
    String? message,
  }) {
    String title;
    String notificationMessage;
    NotificationPriority priority;

    switch (event) {
      case 'connected':
        title = 'Socket Connected';
        notificationMessage = message ?? 'Real-time connection established';
        priority = NotificationPriority.low;
        break;
      case 'disconnected':
        title = 'Socket Disconnected';
        notificationMessage =
            message ?? 'Connection lost, attempting to reconnect...';
        priority = NotificationPriority.medium;
        break;
      case 'reconnected':
        title = 'Socket Reconnected';
        notificationMessage = message ?? 'Connection restored successfully';
        priority = NotificationPriority.low;
        break;
      case 'error':
        title = 'Connection Error';
        notificationMessage = message ?? 'Connection error occurred';
        priority = NotificationPriority.high;
        break;
      default:
        title = 'Connection Event';
        notificationMessage = message ?? 'Socket connection event';
        priority = NotificationPriority.normal;
    }

    return SocketNotification(
      type: 'connection_$event',
      title: title,
      message: notificationMessage,
      priority: priority,
    );
  }

  /// Create notification for message status
  factory SocketNotification.messageStatus({
    required String status,
    required String senderId,
    required String messageId,
    String? conversationId,
  }) {
    String title;
    String message;

    switch (status) {
      case 'delivered':
        title = 'Message Delivered';
        message = 'Your message was delivered';
        break;
      case 'read':
        title = 'Message Read';
        message = 'Your message was read';
        break;
      case 'failed':
        title = 'Message Failed';
        message = 'Failed to send message';
        break;
      default:
        title = 'Message Status';
        message = 'Message status: $status';
    }

    return SocketNotification(
      type: 'message_status_$status',
      title: title,
      message: message,
      senderId: senderId,
      messageId: messageId,
      conversationId: conversationId,
      priority: NotificationPriority.low,
    );
  }

  /// Check if notification is expired (older than 30 days)
  bool get isExpired {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return timestamp.isBefore(thirtyDaysAgo);
  }

  /// Get the appropriate icon for this notification type
  String get notificationIcon {
    switch (type) {
      case 'key_exchange_request':
        return '🔑'; // Key for request
      case 'key_exchange_sent':
        return '📤'; // Outbox for sent
      case 'key_exchange_accepted':
        return '✅'; // Checkmark for accepted
      case 'key_exchange_declined':
        return '❌'; // X for declined
      case 'key_exchange_failed':
        return '⚠️'; // Warning for failed
      case 'key_exchange_retry':
        return '🔄'; // Refresh for retry
      case 'conversation_created':
        return '💬'; // Chat bubble for conversation
      case 'message_received':
        return '📨'; // Envelope for message
      case 'typing_indicator':
        return '✍️'; // Writing hand for typing
      case 'online_status':
        return '🟢'; // Green circle for online
      case 'message_status':
        return '📊'; // Chart for status
      default:
        return '🔔'; // Bell for general notifications
    }
  }

  /// Get notification age in human readable format
  String get age {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${difference.inDays ~/ 7}w ago';
    }
  }
}

/// Notification priority levels
enum NotificationPriority {
  low,
  normal,
  medium,
  high,
  urgent,
}
