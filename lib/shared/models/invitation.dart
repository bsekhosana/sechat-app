class Invitation {
  final String id;
  final String senderId;
  final String recipientId;
  final String message;
  final String status; // 'pending', 'accepted', 'declined', 'deleted', 'queued'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;
  final DateTime? declinedAt;
  final bool
      isReceived; // true if this user received the invitation, false if sent
  final String? senderUsername; // Store sender username locally
  final String? recipientUsername; // Store recipient username locally

  Invitation({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.acceptedAt,
    this.declinedAt,
    this.isReceived = false,
    this.senderUsername,
    this.recipientUsername,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id']?.toString() ?? '',
      senderId:
          json['sender_id']?.toString() ?? json['senderId']?.toString() ?? '',
      recipientId: json['recipient_id']?.toString() ??
          json['recipientId']?.toString() ??
          '',
      message: json['message'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'])
          : null,
      declinedAt: json['declined_at'] != null
          ? DateTime.parse(json['declined_at'])
          : null,
      isReceived: json['is_received'] ?? false,
      senderUsername: json['sender_username'] as String? ??
          json['senderUsername'] as String?,
      recipientUsername: json['recipient_username'] as String? ??
          json['recipientUsername'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'message': message,
      'status': status,
      'accepted_at': acceptedAt?.toIso8601String(),
      'declined_at': declinedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_received': isReceived,
      'sender_username': senderUsername,
      'recipient_username': recipientUsername,
      'other_user_id': null, // This field is no longer used
    };
  }

  bool isPending() {
    return status == 'pending';
  }

  bool isAccepted() {
    return status == 'accepted';
  }

  bool isDeclined() {
    return status == 'declined';
  }

  Invitation copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? message,
    String? status,
    DateTime? acceptedAt,
    DateTime? declinedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isReceived,
    String? senderUsername,
    String? recipientUsername,
  }) {
    return Invitation(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      message: message ?? this.message,
      status: status ?? this.status,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      declinedAt: declinedAt ?? this.declinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isReceived: isReceived ?? this.isReceived,
      senderUsername: senderUsername ?? this.senderUsername,
      recipientUsername: recipientUsername ?? this.recipientUsername,
    );
  }
}
