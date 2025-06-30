class User {
  final String id;
  final String deviceId;
  final String username;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? publicKey;

  User({
    required this.id,
    required this.deviceId,
    required this.username,
    this.isOnline = false,
    this.lastSeen,
    this.publicKey,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      deviceId: json['device_id'],
      username: json['username'],
      isOnline: json['is_online'] ?? false,
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      publicKey: json['public_key'],
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
    };
  }

  User copyWith({
    String? id,
    String? deviceId,
    String? username,
    bool? isOnline,
    DateTime? lastSeen,
    String? publicKey,
  }) {
    return User(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      publicKey: publicKey ?? this.publicKey,
    );
  }
}
