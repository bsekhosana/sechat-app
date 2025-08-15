import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Enum for different message types
enum MessageType {
  text,
  voice,
  video,
  image,
  document,
  location,
  contact,
  emoticon,
  reply,
  system,
}

/// Enum for message status
enum MessageStatus {
  sending, // Message is being sent
  sent, // Message sent to server (1 tick)
  delivered, // Message delivered to recipient (2 ticks)
  read, // Message read by recipient (2 blue ticks)
  failed, // Message failed to send
  deleted, // Message deleted
}

/// Core message model for all message types
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final MessageType type;
  final Map<String, dynamic> content;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? deletedAt;
  final String? replyToMessageId;
  final Map<String, dynamic>? metadata;
  final bool isEncrypted;
  final String? checksum;
  final int? fileSize; // Size in bytes for media messages
  final String? mimeType; // MIME type for media messages

  Message({
    String? id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.type,
    required this.content,
    this.status = MessageStatus.sending,
    DateTime? timestamp,
    this.deliveredAt,
    this.readAt,
    this.deletedAt,
    this.replyToMessageId,
    this.metadata,
    this.isEncrypted = true,
    this.checksum,
    this.fileSize,
    this.mimeType,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Create a copy of this message with updated fields
  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? recipientId,
    MessageType? type,
    Map<String, dynamic>? content,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? deletedAt,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    bool? isEncrypted,
    String? checksum,
    int? fileSize,
    String? mimeType,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      type: type ?? this.type,
      content: content ?? this.content,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      deletedAt: deletedAt ?? this.deletedAt,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      metadata: metadata ?? this.metadata,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      checksum: checksum ?? this.checksum,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
    );
  }

  /// Convert message to JSON for storage/transmission
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'type': type.name,
      'content': jsonEncode(content),
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'reply_to_message_id': replyToMessageId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'is_encrypted': isEncrypted ? 1 : 0,
      'checksum': checksum,
      'file_size': fileSize,
      'mime_type': mimeType,
    };
  }

  /// Create message from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      recipientId: json['recipient_id'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      content: _parseContent(json['content']),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sending,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      replyToMessageId: json['reply_to_message_id'] as String?,
      metadata: _parseMetadata(json['metadata']),
      isEncrypted: _parseBool(json['is_encrypted']) ?? true,
      checksum: json['checksum'] as String?,
      fileSize: json['file_size'] as int?,
      mimeType: json['mime_type'] as String?,
    );
  }

  /// Check if message is a media message
  bool get isMediaMessage =>
      type == MessageType.voice ||
      type == MessageType.video ||
      type == MessageType.image ||
      type == MessageType.document;

  /// Check if message is a text-based message
  bool get isTextMessage =>
      type == MessageType.text ||
      type == MessageType.emoticon ||
      type == MessageType.reply;

  /// Get message preview text for chat list
  String get previewText {
    switch (type) {
      case MessageType.text:
        return content['text'] as String? ?? '';
      case MessageType.voice:
        final duration = content['duration'] as int? ?? 0;
        return '🎤 Voice message (${duration}s)';
      case MessageType.video:
        final duration = content['duration'] as int? ?? 0;
        return '🎥 Video message (${duration}s)';
      case MessageType.image:
        return '🖼️ Image';
      case MessageType.document:
        final fileName = content['file_name'] as String? ?? 'Document';
        return '📄 $fileName';
      case MessageType.location:
        return '📍 Location';
      case MessageType.contact:
        final contactName = content['contact_name'] as String? ?? 'Contact';
        return '👤 $contactName';
      case MessageType.emoticon:
        return content['emoticon'] as String? ?? '😊';
      case MessageType.reply:
        final replyText = content['reply_text'] as String? ?? '';
        return '↩️ Reply: $replyText';
      case MessageType.system:
        return content['system_text'] as String? ?? 'System message';
    }
  }

  /// Get status display text
  String get statusDisplayText {
    switch (status) {
      case MessageStatus.sending:
        return 'Sending...';
      case MessageStatus.sent:
        return '✓';
      case MessageStatus.delivered:
        return '✓✓';
      case MessageStatus.read:
        return '✓✓';
      case MessageStatus.failed:
        return '✗';
      case MessageStatus.deleted:
        return 'Deleted';
    }
  }

  /// Get status color
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
      case MessageStatus.deleted:
        return '#9E9E9E'; // Light gray
    }
  }

  /// Check if message is from current user
  bool isFromCurrentUser(String currentUserId) => senderId == currentUserId;

  /// Check if message can be deleted
  bool get canBeDeleted => status != MessageStatus.deleted;

  /// Check if message can be forwarded
  bool get canBeForwarded =>
      status != MessageStatus.deleted && type != MessageType.system;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Message(id: $id, type: $type, status: $status, timestamp: $timestamp)';
  }

  /// Helper method to parse boolean values from database (which stores them as integers)
  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lowerValue = value.toLowerCase();
      return lowerValue == 'true' || lowerValue == '1';
    }
    return false;
  }

  /// Helper method to parse content from database (which stores it as JSON string)
  static Map<String, dynamic> _parseContent(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        // Try to parse as JSON string
        final Map<String, dynamic> parsed = jsonDecode(value);
        return parsed;
      } catch (e) {
        print('💾 Message: ❌ Failed to parse content JSON: $e');
        print('💾 Message: 🔍 Raw content: $value');
        return {};
      }
    }
    return {};
  }

  /// Helper method to parse metadata from database (which stores it as JSON string)
  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        // Try to parse as JSON string
        final Map<String, dynamic> parsed = jsonDecode(value);
        return parsed;
      } catch (e) {
        print('💾 Message: ❌ Failed to parse metadata JSON: $e');
        print('💾 Message: 🔍 Raw metadata: $value');
        return null;
      }
    }
    return null;
  }
}
