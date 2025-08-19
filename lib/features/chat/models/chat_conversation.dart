import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'message.dart';

/// Chat conversation model for managing 1-on-1 conversations
class ChatConversation {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final String? displayName; // Custom display name for the conversation
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessageId;
  final String? lastMessagePreview;
  final MessageType? lastMessageType;
  final int unreadCount;
  final bool isArchived;
  final bool isMuted;
  final bool isPinned;
  final Map<String, dynamic>? metadata;
  final DateTime? lastSeen; // Last time the other participant was seen
  final bool isOnline; // Whether the other participant is currently online
  final bool isTyping; // Whether the other participant is typing
  final DateTime? typingStartedAt; // When typing started

  // Settings properties
  final bool? notificationsEnabled;
  final bool? soundEnabled;
  final bool? vibrationEnabled;
  final bool? readReceiptsEnabled;
  final bool? typingIndicatorsEnabled;
  final bool? lastSeenEnabled;
  final bool? mediaAutoDownload;
  final bool? encryptMedia;
  final String? mediaQuality;
  final String? messageRetention;
  final bool? isBlocked;
  final DateTime? blockedAt;

  // Recipient information (for convenience)
  final String? recipientId;
  final String? recipientName;

  ChatConversation({
    String? id,
    required this.participant1Id,
    required this.participant2Id,
    this.displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastMessageAt,
    this.lastMessageId,
    this.lastMessagePreview,
    this.lastMessageType,
    this.unreadCount = 0,
    this.isArchived = false,
    this.isMuted = false,
    this.isPinned = false,
    this.metadata,
    this.lastSeen,
    this.isOnline = false,
    this.isTyping = false,
    this.typingStartedAt,
    this.notificationsEnabled,
    this.soundEnabled,
    this.vibrationEnabled,
    this.readReceiptsEnabled,
    this.typingIndicatorsEnabled,
    this.lastSeenEnabled,
    this.mediaAutoDownload,
    this.encryptMedia,
    this.mediaQuality,
    this.messageRetention,
    this.isBlocked,
    this.blockedAt,
    this.recipientId,
    this.recipientName,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Get the other participant's ID
  String getOtherParticipantId(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Id;
    } else if (participant2Id == currentUserId) {
      return participant1Id;
    }
    throw ArgumentError(
        'Current user is not a participant in this conversation');
  }

  /// Check if a user is a participant in this conversation
  bool isParticipant(String userId) {
    return participant1Id == userId || participant2Id == userId;
  }

  /// Create a copy with updated fields
  ChatConversation copyWith({
    String? id,
    String? participant1Id,
    String? participant2Id,
    String? displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    String? lastMessageId,
    String? lastMessagePreview,
    MessageType? lastMessageType,
    int? unreadCount,
    bool? isArchived,
    bool? isMuted,
    bool? isPinned,
    Map<String, dynamic>? metadata,
    DateTime? lastSeen,
    bool? isOnline,
    bool? isTyping,
    DateTime? typingStartedAt,
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? lastSeenEnabled,
    bool? mediaAutoDownload,
    bool? encryptMedia,
    String? mediaQuality,
    String? messageRetention,
    bool? isBlocked,
    DateTime? blockedAt,
    String? recipientId,
    String? recipientName,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      participant1Id: participant1Id ?? this.participant1Id,
      participant2Id: participant2Id ?? this.participant2Id,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(), // Always update when copying
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      unreadCount: unreadCount ?? this.unreadCount,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      metadata: metadata ?? this.metadata,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      isTyping: isTyping ?? this.isTyping,
      typingStartedAt: typingStartedAt ?? this.typingStartedAt,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      typingIndicatorsEnabled:
          typingIndicatorsEnabled ?? this.typingIndicatorsEnabled,
      lastSeenEnabled: lastSeenEnabled ?? this.lastSeenEnabled,
      mediaAutoDownload: mediaAutoDownload ?? this.mediaAutoDownload,
      encryptMedia: encryptMedia ?? this.encryptMedia,
      mediaQuality: mediaQuality ?? this.mediaQuality,
      messageRetention: messageRetention ?? this.messageRetention,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedAt: blockedAt ?? this.blockedAt,
      recipientId: recipientId ?? this.recipientId,
      recipientName: recipientName ?? this.recipientName,
    );
  }

  /// Update conversation with new message
  ChatConversation updateWithNewMessage({
    required String messageId,
    required String messagePreview,
    required MessageType messageType,
    required bool isFromCurrentUser,
  }) {
    return copyWith(
      lastMessageAt: DateTime.now(),
      lastMessageId: messageId,
      lastMessagePreview: messagePreview,
      lastMessageType: messageType,
      unreadCount: isFromCurrentUser ? 0 : unreadCount + 1,
      updatedAt: DateTime.now(),
    );
  }

  /// Mark conversation as read
  ChatConversation markAsRead() {
    return copyWith(
      unreadCount: 0,
      updatedAt: DateTime.now(),
    );
  }

  /// Update typing indicator
  ChatConversation updateTypingIndicator(bool isTyping) {
    return copyWith(
      isTyping: isTyping,
      typingStartedAt: isTyping ? DateTime.now() : null,
      updatedAt: DateTime.now(),
    );
  }

  /// Update last seen
  ChatConversation updateLastSeen() {
    return copyWith(
      lastSeen: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Toggle archive status
  ChatConversation toggleArchive() {
    return copyWith(
      isArchived: !isArchived,
      updatedAt: DateTime.now(),
    );
  }

  /// Toggle mute status
  ChatConversation toggleMute() {
    return copyWith(
      isMuted: !isMuted,
      updatedAt: DateTime.now(),
    );
  }

  /// Toggle pin status
  ChatConversation togglePin() {
    return copyWith(
      isPinned: !isPinned,
      updatedAt: DateTime.now(),
    );
  }

  /// Get conversation display name
  String getDisplayName(String currentUserId, {String? fallbackName}) {
    if (displayName != null && displayName!.isNotEmpty) {
      return displayName!;
    }

    // Try to get name from metadata
    if (metadata != null) {
      final otherUserId = getOtherParticipantId(currentUserId);
      final otherUserName = metadata!['user_names']?[otherUserId] as String?;
      if (otherUserName != null && otherUserName.isNotEmpty) {
        return otherUserName;
      }
    }

    // Fallback to session ID format
    final otherUserId = getOtherParticipantId(currentUserId);
    return fallbackName ?? '${otherUserId.substring(0, 8)}...';
  }

  /// Get last message preview with typing indicator
  String getLastMessagePreviewWithTyping(String currentUserId) {
    if (isTyping) {
      return 'Typing...';
    }

    if (lastMessagePreview != null && lastMessagePreview!.isNotEmpty) {
      return lastMessagePreview!;
    }

    return 'No messages yet';
  }

  /// Check if conversation has unread messages
  bool get hasUnreadMessages => unreadCount > 0;

  /// Check if conversation is active (not archived)
  bool get isActive => !isArchived;

  /// Get conversation priority for sorting
  int get priority {
    if (isPinned) return 3;
    if (hasUnreadMessages) return 2;
    if (isActive) return 1;
    return 0;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant1_id': participant1Id,
      'participant2_id': participant2Id,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_at': lastMessageAt?.toIso8601String(),
      'last_message_id': lastMessageId,
      'last_message_preview': lastMessagePreview,
      'last_message_type': lastMessageType?.name,
      'unread_count': unreadCount,
      'is_archived': isArchived ? 1 : 0,
      'is_muted': isMuted ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'last_seen': lastSeen?.toIso8601String(),
      'is_typing': isTyping ? 1 : 0,
      'typing_started_at': typingStartedAt?.toIso8601String(),
      'notifications_enabled': notificationsEnabled ?? true ? 1 : 0,
      'sound_enabled': soundEnabled ?? true ? 1 : 0,
      'vibration_enabled': vibrationEnabled ?? true ? 1 : 0,
      'read_receipts_enabled': readReceiptsEnabled ?? true ? 1 : 0,
      'typing_indicators_enabled': typingIndicatorsEnabled ?? true ? 1 : 0,
      'last_seen_enabled': lastSeenEnabled ?? true ? 1 : 0,
      'media_auto_download': mediaAutoDownload ?? true ? 1 : 0,
      'encrypt_media': encryptMedia ?? true ? 1 : 0,
      'media_quality': mediaQuality,
      'message_retention': messageRetention,
      'is_blocked': isBlocked ?? false ? 1 : 0,
      'blocked_at': blockedAt?.toIso8601String(),
      'recipient_id': recipientId,
      'recipient_name': recipientName,
    };
  }

  /// Create from JSON
  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String,
      participant1Id: json['participant1_id'] as String,
      participant2Id: json['participant2_id'] as String,
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      lastMessageId: json['last_message_id'] as String?,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageType: json['last_message_type'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == json['last_message_type'],
              orElse: () => MessageType.text,
            )
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      isArchived: _parseBool(json['is_archived']) ?? false,
      isMuted: _parseBool(json['is_muted']) ?? false,
      isPinned: _parseBool(json['is_pinned']) ?? false,
      metadata: _parseMetadata(json['metadata']),
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      isTyping: _parseBool(json['is_typing']) ?? false,
      typingStartedAt: json['typing_started_at'] != null
          ? DateTime.parse(json['typing_started_at'] as String)
          : null,
      notificationsEnabled: _parseBool(json['notifications_enabled']),
      soundEnabled: _parseBool(json['sound_enabled']),
      vibrationEnabled: _parseBool(json['vibration_enabled']),
      readReceiptsEnabled: _parseBool(json['read_receipts_enabled']),
      typingIndicatorsEnabled: _parseBool(json['typing_indicators_enabled']),
      lastSeenEnabled: _parseBool(json['last_seen_enabled']),
      mediaAutoDownload: _parseBool(json['media_auto_download']),
      encryptMedia: _parseBool(json['encrypt_media']),
      mediaQuality: json['media_quality'] as String?,
      messageRetention: json['message_retention'] as String?,
      isBlocked: _parseBool(json['is_blocked']),
      blockedAt: json['blocked_at'] != null
          ? DateTime.parse(json['blocked_at'] as String)
          : null,
      recipientId: json['recipient_id'] as String?,
      recipientName: json['recipient_name'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatConversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatConversation(id: $id, participants: [$participant1Id, $participant2Id], unread: $unreadCount)';
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
        print('💾 ChatConversation: ❌ Failed to parse metadata JSON: $e');
        print('💾 ChatConversation: 🔍 Raw metadata: $value');
        return null;
      }
    }
    return null;
  }
}
