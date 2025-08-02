class Chat {
  final String id;
  final String user1Id;
  final String user2Id;
  final String user1DisplayName;
  final String user2DisplayName;
  final String status;
  final bool isBlocked;
  final DateTime? blockedAt;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? otherUser; // Store the other_user data from API
  final Map<String, dynamic>?
      lastMessage; // Store the last message data from API

  Chat({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    required this.user1DisplayName,
    required this.user2DisplayName,
    this.status = 'active',
    this.isBlocked = false,
    this.blockedAt,
    this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    this.otherUser,
    this.lastMessage,
  });

  factory Chat.fromJson(dynamic json) {
    // Convert LinkedMap to Map<String, dynamic> if needed
    final Map<String, dynamic> data = Map<String, dynamic>.from(json);

    // Handle API response structure with other_user
    if (data.containsKey('other_user')) {
      return Chat(
        id: data['id'].toString(),
        user1Id: '', // Will be determined later
        user2Id: '', // Will be determined later
        user1DisplayName: data['user1_display_name'] ?? 'Unknown User',
        user2DisplayName: data['user2_display_name'] ?? 'Unknown User',
        status: data['status'] ?? 'active',
        isBlocked: data['is_blocked'] ?? false,
        blockedAt: data['blocked_at'] != null
            ? DateTime.parse(data['blocked_at'])
            : null,
        lastMessageAt: data['last_message_at'] != null
            ? DateTime.parse(data['last_message_at'])
            : null,
        createdAt: DateTime.parse(data['created_at']),
        updatedAt: DateTime.parse(data['updated_at']),
        otherUser: data['other_user'] != null
            ? Map<String, dynamic>.from(data['other_user'])
            : null,
        lastMessage: data['last_message'] != null
            ? Map<String, dynamic>.from(data['last_message'])
            : null,
      );
    }

    // Handle legacy structure with user1_id and user2_id
    return Chat(
      id: data['id'].toString(),
      user1Id: data['user1_id'].toString(),
      user2Id: data['user2_id'].toString(),
      user1DisplayName: data['user1_display_name'] ?? 'Unknown User',
      user2DisplayName: data['user2_display_name'] ?? 'Unknown User',
      status: data['status'] ?? 'active',
      isBlocked: data['is_blocked'] ?? false,
      blockedAt: data['blocked_at'] != null
          ? DateTime.parse(data['blocked_at'])
          : null,
      lastMessageAt: data['last_message_at'] != null
          ? DateTime.parse(data['last_message_at'])
          : null,
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user1_id': user1Id,
      'user2_id': user2Id,
      'user1_display_name': user1DisplayName,
      'user2_display_name': user2DisplayName,
      'status': status,
      'is_blocked': isBlocked,
      'blocked_at': blockedAt?.toIso8601String(),
      'last_message_at': lastMessageAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (otherUser != null) 'other_user': otherUser,
      if (lastMessage != null) 'last_message': lastMessage,
    };
  }

  String getOtherUserId(String currentUserId) {
    // If we have other_user data, use that
    if (otherUser != null && otherUser!.containsKey('id')) {
      return otherUser!['id'].toString();
    }
    // Fallback to legacy logic
    return user1Id == currentUserId ? user2Id : user1Id;
  }

  String getOtherUserDisplayName(String currentUserId) {
    return user1Id == currentUserId ? user2DisplayName : user1DisplayName;
  }

  bool isActive() {
    return status == 'active';
  }

  bool getBlockedStatus() {
    return isBlocked;
  }

  Chat copyWith({
    String? id,
    String? user1Id,
    String? user2Id,
    String? user1DisplayName,
    String? user2DisplayName,
    String? status,
    bool? isBlocked,
    DateTime? blockedAt,
    DateTime? lastMessageAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? otherUser,
    Map<String, dynamic>? lastMessage,
  }) {
    return Chat(
      id: id ?? this.id,
      user1Id: user1Id ?? this.user1Id,
      user2Id: user2Id ?? this.user2Id,
      user1DisplayName: user1DisplayName ?? this.user1DisplayName,
      user2DisplayName: user2DisplayName ?? this.user2DisplayName,
      status: status ?? this.status,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedAt: blockedAt ?? this.blockedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
