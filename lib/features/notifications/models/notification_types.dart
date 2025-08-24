/// Notification types for local notification items
class NotificationType {
  // Welcome notifications
  static const String welcome = 'welcome';

  // Key Exchange Request notifications
  static const String kerSent = 'ker_sent';
  static const String kerReceived = 'ker_received';
  static const String kerAccepted = 'ker_accepted';
  static const String kerDeclined = 'ker_declined';
  static const String kerResent = 'ker_resent';

  // Message notifications (for future use)
  static const String messageReceived = 'message_received';
  static const String messageDelivered = 'message_delivered';
  static const String messageRead = 'message_read';

  // Connection notifications (for future use)
  static const String connectionStatus = 'connection_status';
  static const String userOnline = 'user_online';
  static const String userOffline = 'user_offline';

  // Get all notification types
  static List<String> get allTypes => [
        welcome,
        kerSent,
        kerReceived,
        kerAccepted,
        kerDeclined,
        kerResent,
        messageReceived,
        messageDelivered,
        messageRead,
        connectionStatus,
        userOnline,
        userOffline,
      ];

  // Get KER-specific types
  static List<String> get kerTypes => [
        kerSent,
        kerReceived,
        kerAccepted,
        kerDeclined,
        kerResent,
      ];
}

/// Notification status values
class NotificationStatus {
  static const String unread = 'unread';
  static const String read = 'read';
  static const String archived = 'archived';

  static List<String> get allStatuses => [unread, read, archived];
}

/// Notification direction values
class NotificationDirection {
  static const String incoming = 'incoming';
  static const String outgoing = 'outgoing';

  static List<String> get allDirections => [incoming, outgoing];
}
