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
      invitationStatus: json['invitation_status'],
      invitationId: json['invitation_id']?.toString(),
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
      'invitation_status': invitationStatus,
      'invitation_id': invitationId,
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
