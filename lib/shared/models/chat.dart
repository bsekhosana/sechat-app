class Chat {
  final String id;
  final String user1Id;
  final String user2Id;
  final String status;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Chat({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    this.status = 'active',
    this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'].toString(),
      user1Id: json['user1_id'].toString(),
      user2Id: json['user2_id'].toString(),
      status: json['status'] ?? 'active',
      lastMessageAt:
          json['last_message_at'] != null
              ? DateTime.parse(json['last_message_at'])
              : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user1_id': user1Id,
      'user2_id': user2Id,
      'status': status,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String getOtherUserId(String currentUserId) {
    return user1Id == currentUserId ? user2Id : user1Id;
  }

  bool isActive() {
    return status == 'active';
  }

  Chat copyWith({
    String? id,
    String? user1Id,
    String? user2Id,
    String? status,
    DateTime? lastMessageAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Chat(
      id: id ?? this.id,
      user1Id: user1Id ?? this.user1Id,
      user2Id: user2Id ?? this.user2Id,
      status: status ?? this.status,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
