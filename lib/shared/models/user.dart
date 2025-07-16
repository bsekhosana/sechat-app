class User {
  final String id;
  final String deviceId;
  final String username;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? publicKey;
  final DateTime createdAt;
  final bool alreadyInvited;
  final String?
      invitationStatus; // 'pending', 'accepted', 'declined', 'deleted', null
  final String? invitationId; // ID of the invitation if exists
  final bool isTyping; // For typing indicators

  User({
    required this.id,
    required this.deviceId,
    required this.username,
    this.isOnline = false,
    this.lastSeen,
    this.publicKey,
    DateTime? createdAt,
    this.alreadyInvited = false,
    this.invitationStatus,
    this.invitationId,
    this.isTyping = false,
  }) : createdAt = createdAt ?? DateTime.now();

  factory User.fromJson(dynamic json) {
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> data = Map<String, dynamic>.from(json);

      return User(
        id: data['id']?.toString() ?? '',
        deviceId: data['device_id'] ?? data['deviceId'] ?? '',
        username: data['username'] ?? 'Unknown User',
        isOnline: data['is_online'] ?? data['isOnline'] ?? false,
        lastSeen: data['last_seen'] != null
            ? DateTime.parse(data['last_seen'])
            : null,
        publicKey: data['public_key'],
        createdAt: data['created_at'] != null
            ? DateTime.parse(data['created_at'])
            : DateTime.now(),
        alreadyInvited: data['already_invited'] ?? false,
        invitationStatus: data['invitation_status'],
        invitationId: data['invitation_id']?.toString(),
        isTyping: data['is_typing'] ?? false,
      );
    } catch (e) {
      print('📱 User.fromJson error: $e for data: $json');
      // Return a default user with available data
      return User(
        id: json['id']?.toString() ?? 'unknown',
        deviceId: json['device_id'] ?? json['deviceId'] ?? '',
        username: json['username'] ?? 'Unknown User',
        isOnline: json['is_online'] ?? json['isOnline'] ?? false,
        createdAt: DateTime.now(),
      );
    }
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
      'invitation_status': invitationStatus,
      'invitation_id': invitationId,
      'is_typing': isTyping,
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
    String? invitationStatus,
    String? invitationId,
    bool? isTyping,
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
      invitationStatus: invitationStatus ?? this.invitationStatus,
      invitationId: invitationId ?? this.invitationId,
      isTyping: isTyping ?? this.isTyping,
    );
  }

  // Helper methods for invitation status
  bool get canReinvite =>
      invitationStatus == 'declined' ||
      invitationStatus == 'deleted' ||
      (!alreadyInvited && invitationStatus == null);

  bool get hasPendingInvitation => invitationStatus == 'pending';

  bool get hasDeclinedInvitation => invitationStatus == 'declined';

  bool get hasDeletedInvitation => invitationStatus == 'deleted';

  String get invitationStatusText {
    switch (invitationStatus) {
      case 'pending':
        return 'Invited';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'deleted':
        return 'Deleted';
      default:
        return 'Invite';
    }
  }
}
