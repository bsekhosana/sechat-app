class User {
  final String id;
  final String deviceId;
  final String username;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? publicKey;
  final DateTime createdAt;
  final bool alreadyInvited;

  User({
    required this.id,
    required this.deviceId,
    required this.username,
    this.isOnline = false,
    this.lastSeen,
    this.publicKey,
    DateTime? createdAt,
    this.alreadyInvited = false,
  }) : createdAt = createdAt ?? DateTime.now();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      deviceId: json['device_id'] ?? '',
      username: json['username'],
      isOnline: json['is_online'] ?? false,
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      publicKey: json['public_key'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      alreadyInvited: json['already_invited'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'username': username,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'public_key': publicKey,
      'created_at': createdAt.toIso8601String(),
      'already_invited': alreadyInvited,
    };
  }

  User copyWith({
    String? id,
    String? deviceId,
    String? username,
    bool? isOnline,
    DateTime? lastSeen,
    String? publicKey,
    DateTime? createdAt,
    bool? alreadyInvited,
  }) {
    return User(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      alreadyInvited: alreadyInvited ?? this.alreadyInvited,
    );
  }
}
