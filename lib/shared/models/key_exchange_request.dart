/// Model for key exchange requests
class KeyExchangeRequest {
  final String id;
  final String fromSessionId;
  final String toSessionId;
  final String requestPhrase;
  String status; // 'pending', 'received', 'accepted', 'declined', 'failed'
  final DateTime timestamp;
  final String type;
  DateTime? respondedAt;
  String? errorMessage;
  String? displayName; // Added: display name from user_data_exchange

  KeyExchangeRequest({
    required this.id,
    required this.fromSessionId,
    required this.toSessionId,
    required this.requestPhrase,
    required this.status,
    required this.timestamp,
    required this.type,
    this.respondedAt,
    this.errorMessage,
    this.displayName, // Added: display name parameter
  });

  /// Create from JSON
  factory KeyExchangeRequest.fromJson(Map<String, dynamic> json) {
    return KeyExchangeRequest(
      id: json['id'] as String,
      fromSessionId: json['fromSessionId'] as String,
      toSessionId: json['toSessionId'] as String,
      requestPhrase: json['requestPhrase'] as String,
      status: json['status'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      type: json['type'] as String,
      respondedAt: json['respondedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['respondedAt'] as int)
          : null,
      errorMessage: json['errorMessage'] as String?,
      displayName: json['displayName'] as String?, // Added: parse display name
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromSessionId': fromSessionId,
      'toSessionId': toSessionId,
      'requestPhrase': requestPhrase,
      'status': status,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type,
      'respondedAt': respondedAt?.millisecondsSinceEpoch,
      'errorMessage': errorMessage,
      'displayName': displayName, // Added: include display name
    };
  }

  /// Create a copy with updated fields
  KeyExchangeRequest copyWith({
    String? id,
    String? fromSessionId,
    String? toSessionId,
    String? requestPhrase,
    String? status,
    DateTime? timestamp,
    String? type,
    DateTime? respondedAt,
    String? errorMessage,
    String? displayName, // Added: display name parameter
  }) {
    return KeyExchangeRequest(
      id: id ?? this.id,
      fromSessionId: fromSessionId ?? this.fromSessionId,
      toSessionId: toSessionId ?? this.toSessionId,
      requestPhrase: requestPhrase ?? this.requestPhrase,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      respondedAt: respondedAt ?? this.respondedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      displayName:
          displayName ?? this.displayName, // Added: update display name
    );
  }

  /// Check if the request is pending
  bool get isPending => status == 'pending';

  /// Check if the request is received
  bool get isReceived => status == 'received';

  /// Check if the request is accepted
  bool get isAccepted => status == 'accepted';

  /// Check if the request is declined
  bool get isDeclined => status == 'declined';

  /// Check if the request failed
  bool get isFailed => status == 'failed';

  /// Check if the request has been responded to
  bool get hasResponse => respondedAt != null;

  /// Get status display text
  String get statusDisplayText {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'sent':
        return 'Sent';
      case 'received':
        return 'Received';
      case 'processing':
        return 'Processing';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  /// Get status color
  String get statusColor {
    switch (status) {
      case 'pending':
        return '#FFA500'; // Orange
      case 'sent':
        return '#2196F3'; // Blue
      case 'received':
        return '#2196F3'; // Blue
      case 'processing':
        return '#FF9800'; // Orange
      case 'accepted':
        return '#4CAF50'; // Green
      case 'declined':
        return '#F44336'; // Red
      case 'failed':
        return '#9C27B0'; // Purple
      default:
        return '#757575'; // Grey
    }
  }

  @override
  String toString() {
    return 'KeyExchangeRequest(id: $id, fromSessionId: $fromSessionId, toSessionId: $toSessionId, status: $status, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeyExchangeRequest &&
        other.id == id &&
        other.fromSessionId == fromSessionId &&
        other.toSessionId == toSessionId &&
        other.status == status;
  }

  @override
  int get hashCode {
    return Object.hash(id, fromSessionId, toSessionId, status);
  }
}
