class Invitation {
  final String id;
  final String senderId;
  final String recipientId;
  final String message;
  final String status;
  final DateTime? acceptedAt;
  final DateTime? declinedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isReceived;
  final String? otherUserId;

  Invitation({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.message,
    this.status = 'pending',
    this.acceptedAt,
    this.declinedAt,
    required this.createdAt,
    required this.updatedAt,
    this.isReceived = false,
    this.otherUserId,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'].toString(),
      senderId: json['sender_id'].toString(),
      recipientId: json['recipient_id'].toString(),
      message: json['message'],
      status: json['status'] ?? 'pending',
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'])
          : null,
      declinedAt: json['declined_at'] != null
          ? DateTime.parse(json['declined_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isReceived: json['is_received'] ?? false,
      otherUserId: json['other_user']?['id']?.toString(),
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
      'other_user_id': otherUserId,
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
    String? otherUserId,
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
      otherUserId: otherUserId ?? this.otherUserId,
    );
  }
}
