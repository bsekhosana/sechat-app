/// Detailed message status tracking model
class MessageStatus {
  final String messageId;
  final String conversationId;
  final String recipientId;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime timestamp;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? errorMessage;
  final int retryCount;
  final DateTime? lastRetryAt;

  MessageStatus({
    required this.messageId,
    required this.conversationId,
    required this.recipientId,
    this.deliveryStatus = MessageDeliveryStatus.pending,
    DateTime? timestamp,
    this.deliveredAt,
    this.readAt,
    this.errorMessage,
    this.retryCount = 0,
    this.lastRetryAt,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a copy with updated fields
  MessageStatus copyWith({
    String? messageId,
    String? conversationId,
    String? recipientId,
    MessageDeliveryStatus? deliveryStatus,
    DateTime? timestamp,
    DateTime? deliveredAt,
    DateTime? readAt,
    String? errorMessage,
    int? retryCount,
    DateTime? lastRetryAt,
  }) {
    return MessageStatus(
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      recipientId: recipientId ?? this.recipientId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      timestamp: timestamp ?? this.timestamp,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
    );
  }

  /// Mark message as delivered
  MessageStatus markAsDelivered() {
    return copyWith(
      deliveryStatus: MessageDeliveryStatus.delivered,
      deliveredAt: DateTime.now(),
      errorMessage: null, // Clear any previous error
    );
  }

  /// Mark message as read
  MessageStatus markAsRead() {
    return copyWith(
      deliveryStatus: MessageDeliveryStatus.read,
      readAt: DateTime.now(),
    );
  }

  /// Mark message as failed
  MessageStatus markAsFailed(String error) {
    return copyWith(
      deliveryStatus: MessageDeliveryStatus.failed,
      errorMessage: error,
      retryCount: retryCount + 1,
      lastRetryAt: DateTime.now(),
    );
  }

  /// Mark message for retry
  MessageStatus markForRetry() {
    return copyWith(
      deliveryStatus: MessageDeliveryStatus.pending,
      errorMessage: null,
    );
  }

  /// Check if message can be retried
  bool get canRetry =>
      deliveryStatus == MessageDeliveryStatus.failed &&
      retryCount < 3; // Max 3 retries

  /// Get status display text
  String get statusDisplayText {
    switch (deliveryStatus) {
      case MessageDeliveryStatus.pending:
        return 'Sending...';
      case MessageDeliveryStatus.sent:
        return '✓';
      case MessageDeliveryStatus.delivered:
        return '✓✓';
      case MessageDeliveryStatus.read:
        return '✓✓';
      case MessageDeliveryStatus.failed:
        return '✗';
      case MessageDeliveryStatus.retrying:
        return 'Retrying...';
    }
  }

  /// Get status color
  String get statusColor {
    switch (deliveryStatus) {
      case MessageDeliveryStatus.pending:
        return '#FFA500'; // Orange
      case MessageDeliveryStatus.sent:
        return '#808080'; // Gray
      case MessageDeliveryStatus.delivered:
        return '#808080'; // Gray
      case MessageDeliveryStatus.read:
        return '#2196F3'; // Blue
      case MessageDeliveryStatus.failed:
        return '#F44336'; // Red
      case MessageDeliveryStatus.retrying:
        return '#FF9800'; // Orange
    }
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'conversation_id': conversationId,
      'recipient_id': recipientId,
      'delivery_status': deliveryStatus.name,
      'timestamp': timestamp.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'error_message': errorMessage,
      'retry_count': retryCount,
      'last_retry_at': lastRetryAt?.toIso8601String(),
    };
  }

  /// Create from JSON
  factory MessageStatus.fromJson(Map<String, dynamic> json) {
    return MessageStatus(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      recipientId: json['recipient_id'] as String,
      deliveryStatus: MessageDeliveryStatus.values.firstWhere(
        (e) => e.name == json['delivery_status'],
        orElse: () => MessageDeliveryStatus.pending,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
      retryCount: json['retry_count'] as int? ?? 0,
      lastRetryAt: json['last_retry_at'] != null
          ? DateTime.parse(json['last_retry_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageStatus &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId &&
          recipientId == other.recipientId;

  @override
  int get hashCode => Object.hash(messageId, recipientId);

  @override
  String toString() {
    return 'MessageStatus(messageId: $messageId, status: $deliveryStatus, timestamp: $timestamp)';
  }
}

/// Enum for message delivery status
enum MessageDeliveryStatus {
  pending, // Message is being sent
  sent, // Message sent to server (1 tick)
  delivered, // Message delivered to recipient (2 ticks)
  read, // Message read by recipient (2 blue ticks)
  failed, // Message failed to send
  retrying, // Message is being retried
}
