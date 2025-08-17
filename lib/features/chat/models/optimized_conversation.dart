/// Optimized Conversation Model
/// Clean, focused model for chat conversations
class OptimizedConversation {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final String displayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isTyping;
  final String? typingUserId;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isPinned;

  const OptimizedConversation({
    required this.id,
    required this.participant1Id,
    required this.participant2Id,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.unreadCount = 0,
    this.isTyping = false,
    this.typingUserId,
    this.isOnline = false,
    this.lastSeen,
    this.isPinned = false,
  });

  /// Create from database map
  factory OptimizedConversation.fromMap(Map<String, dynamic> map) {
    return OptimizedConversation(
      id: map['id'] as String,
      participant1Id: map['participant1_id'] as String,
      participant2Id: map['participant2_id'] as String,
      displayName: map['display_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.parse(map['last_message_at'] as String)
          : null,
      lastMessagePreview: map['last_message_preview'] as String?,
      unreadCount: map['unread_count'] as int? ?? 0,
      isTyping: (map['is_typing'] as int? ?? 0) == 1,
      typingUserId: map['typing_user_id'] as String?,
      isOnline: (map['is_online'] as int? ?? 0) == 1,
      lastSeen: map['last_seen'] != null
          ? DateTime.parse(map['last_seen'] as String)
          : null,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participant1_id': participant1Id,
      'participant2_id': participant2Id,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_at': lastMessageAt?.toIso8601String(),
      'last_message_preview': lastMessagePreview,
      'unread_count': unreadCount,
      'is_typing': isTyping ? 1 : 0,
      'typing_user_id': typingUserId,
      'is_online': isOnline ? 1 : 0,
      'last_seen': lastSeen?.toIso8601String(),
      'is_pinned': isPinned ? 1 : 0,
    };
  }

  /// Create copy with updates
  OptimizedConversation copyWith({
    String? id,
    String? participant1Id,
    String? participant2Id,
    String? displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    int? unreadCount,
    bool? isTyping,
    String? typingUserId,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isPinned,
  }) {
    return OptimizedConversation(
      id: id ?? this.id,
      participant1Id: participant1Id ?? this.participant1Id,
      participant2Id: participant2Id ?? this.participant2Id,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      isTyping: isTyping ?? this.isTyping,
      typingUserId: typingUserId ?? this.typingUserId,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  /// Check if user is participant
  bool isParticipant(String userId) {
    return participant1Id == userId || participant2Id == userId;
  }

  /// Get other participant ID
  String? getOtherParticipantId(String currentUserId) {
    if (participant1Id == currentUserId) return participant2Id;
    if (participant2Id == currentUserId) return participant1Id;
    return null;
  }

  /// Get conversation display name for current user
  String getDisplayNameForUser(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Id; // For now, just return ID. Will be enhanced with user data
    } else if (participant2Id == currentUserId) {
      return participant1Id;
    }
    return displayName;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OptimizedConversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'OptimizedConversation(id: $id, displayName: $displayName, unreadCount: $unreadCount)';
  }
}
