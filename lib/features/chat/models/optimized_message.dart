import 'dart:convert';

/// Message Status Enum
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

/// Message Type Enum
enum MessageType {
  text,
  image,
  file,
  audio,
  video,
}

/// Optimized Message Model
/// Clean, focused model for chat messages
class OptimizedMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String content;
  final MessageType messageType;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final Map<String, dynamic>? metadata;

  const OptimizedMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    this.messageType = MessageType.text,
    this.status = MessageStatus.sending,
    required this.timestamp,
    this.deliveredAt,
    this.readAt,
    this.metadata,
  });

  /// Create from database map
  factory OptimizedMessage.fromMap(Map<String, dynamic> map) {
    return OptimizedMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      recipientId: map['recipient_id'] as String,
      content: map['content'] as String,
      messageType: _parseMessageType(map['message_type'] as String?),
      status: _parseMessageStatus(map['status'] as String?),
      timestamp: DateTime.parse(map['timestamp'] as String),
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(jsonDecode(map['metadata'] as String))
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'content': content,
      'message_type': messageType.name,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }

  /// Create copy with updates
  OptimizedMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? recipientId,
    String? content,
    MessageType? messageType,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? deliveredAt,
    DateTime? readAt,
    Map<String, dynamic>? metadata,
  }) {
    return OptimizedMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Check if message is from current user
  bool isFromCurrentUser(String currentUserId) {
    return senderId == currentUserId;
  }

  /// Check if message is incoming (received from someone else)
  bool get isIncoming => metadata?['messageDirection'] == 'incoming';

  /// Check if message is outgoing (sent by current user)
  bool get isOutgoing => metadata?['messageDirection'] == 'outgoing';

  /// Get message direction for UI rendering
  String get messageDirection => metadata?['messageDirection'] ?? 'unknown';

  /// Get status display text
  String get statusText {
    switch (status) {
      case MessageStatus.sending:
        return 'Sending...';
      case MessageStatus.sent:
        return 'Sent';
      case MessageStatus.delivered:
        return 'Delivered';
      case MessageStatus.read:
        return 'Read';
      case MessageStatus.failed:
        return 'Failed';
    }
  }

  /// Get status color for UI
  String get statusColor {
    switch (status) {
      case MessageStatus.sending:
        return '#FFA500'; // Orange
      case MessageStatus.sent:
        return '#808080'; // Gray
      case MessageStatus.delivered:
        return '#808080'; // Gray
      case MessageStatus.read:
        return '#2196F3'; // Blue
      case MessageStatus.failed:
        return '#F44336'; // Red
    }
  }

  /// Check if message can be deleted
  bool get canBeDeleted => status != MessageStatus.failed;

  /// Check if message can be forwarded
  bool get canBeForwarded => status != MessageStatus.failed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OptimizedMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'OptimizedMessage(id: $id, content: $content, status: $status, timestamp: $timestamp)';
  }

  // ===== PRIVATE HELPER METHODS =====

  /// Parse message type from string
  static MessageType _parseMessageType(String? type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'audio':
        return MessageType.audio;
      case 'video':
        return MessageType.video;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  /// Parse message status from string
  static MessageStatus _parseMessageStatus(String? status) {
    switch (status) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      case 'sending':
      default:
        return MessageStatus.sending;
    }
  }
}
