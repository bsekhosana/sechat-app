class RT {
  static const registerSession = 'register_session';
  static const sessionRegistered = 'session_registered';
  static const sessionLeaving = 'session:leaving';
  static const userDeparted = 'user:departed';

  static const kerRequest = 'key_exchange:request';
  static const kerResponse = 'key_exchange:response';
  static const kerDeclined = 'key_exchange:declined';
  static const kerRevoked = 'key_exchange:revoked';
  static const kerAccept = 'key_exchange:accept';
  static const kerDecline = 'key_exchange:decline';
  static const kerRevoke = 'key_exchange:revoke';

  static const userDataSend = 'user_data_exchange:send';
  static const userDataData = 'user_data_exchange:data';

  static const kerConvCreatedClient = 'key_exchange:conversation_created';
  static const convCreated = 'conversation:created';

  static const msgSend = 'message:send';
  static const msgReceived = 'message:received';
  static const msgAcked = 'message:acked';

  static const rcptDelivered = 'receipt:delivered';
  static const rcptRead = 'receipt:read';

  static const typingUpdate = 'typing:update';
  static const typingStatusUpdate = 'typing:status_update';

  static const presenceUpdate = 'presence:update';

  static const userBlocked = 'user:blocked';
  static const userUnblocked = 'user:unblocked';
  static const conversationBlocked = 'conversation:blocked';
  static const conversationUnblocked = 'conversation:unblocked';

  static const userDeleted = 'user:deleted';
  static const requestQueued = 'request_queued_events';

  static const heartbeatPing = 'heartbeat:ping';
  static const heartbeatPong = 'heartbeat:pong';

  static const connectionPing = 'connection:ping';
  static const connectionPong = 'connection:pong';
  static const connectionStability = 'connection:stability_check';
}

class SocketEvent {
  final String type;
  final Map<String, dynamic> data;
  const SocketEvent(this.type, this.data);
}
