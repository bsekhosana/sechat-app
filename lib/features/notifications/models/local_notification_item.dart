import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:sechat_app//../core/utils/logger.dart';

/// Local notification item for in-app notifications
class LocalNotificationItem {
  final String id;
  final String type;
  final String icon;
  final String title;
  final String? description;
  final String status;
  final String direction;
  final String? senderId;
  final String? recipientId;
  final String? conversationId;
  final Map<String, dynamic>? metadata;
  final DateTime date;
  final DateTime createdAt;

  LocalNotificationItem({
    String? id,
    required this.type,
    required this.icon,
    required this.title,
    this.description,
    required this.status,
    required this.direction,
    this.senderId,
    this.recipientId,
    this.conversationId,
    this.metadata,
    required this.date,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Create a copy of this notification with updated fields
  LocalNotificationItem copyWith({
    String? id,
    String? type,
    String? icon,
    String? title,
    String? description,
    String? status,
    String? direction,
    String? senderId,
    String? recipientId,
    String? conversationId,
    Map<String, dynamic>? metadata,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return LocalNotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      direction: direction ?? this.direction,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      conversationId: conversationId ?? this.conversationId,
      metadata: metadata ?? this.metadata,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'icon': icon,
      'title': title,
      'description': description,
      'status': status,
      'direction': direction,
      'senderId': senderId,
      'recipientId': recipientId,
      'conversationId': conversationId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create from Map from database
  factory LocalNotificationItem.fromMap(Map<String, dynamic> map) {
    try {
      // Safely parse metadata
      Map<String, dynamic>? parsedMetadata;
      if (map['metadata'] != null) {
        try {
          if (map['metadata'] is String) {
            parsedMetadata = Map<String, dynamic>.from(
                jsonDecode(map['metadata'] as String));
          } else if (map['metadata'] is Map<String, dynamic>) {
            parsedMetadata = Map<String, dynamic>.from(
                map['metadata'] as Map<String, dynamic>);
          }
        } catch (e) {
          Logger.warning(
              ' LocalNotificationItem: Failed to parse metadata: $e');
          parsedMetadata = null;
        }
      }

      return LocalNotificationItem(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        icon: map['icon'] as String? ?? '',
        title: map['title'] as String? ?? '',
        description: map['description'] as String?,
        status: map['status'] as String? ?? 'unread',
        direction: map['direction'] as String? ?? 'incoming',
        senderId: map['senderId'] as String?,
        recipientId: map['recipientId'] as String?,
        conversationId: map['conversationId'] as String?,
        metadata: parsedMetadata,
        date: map['date'] != null
            ? DateTime.parse(map['date'] as String)
            : DateTime.now(),
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : DateTime.now(),
      );
    } catch (e) {
      Logger.error(' LocalNotificationItem: Error creating from map: $e');
      Logger.error(' LocalNotificationItem: Map data: $map');
      rethrow;
    }
  }

  @override
  String toString() {
    return 'LocalNotificationItem(id: $id, type: $type, title: $title, status: $status, direction: $direction, date: $date)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalNotificationItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
