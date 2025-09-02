import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:sechat_app/features/notifications/services/local_notification_badge_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';

import '../../core/realtime/realtime_gateway.dart';
import '../../core/realtime/realtime_events.dart';
import '../../core/realtime/event_logger.dart';
import '../../core/realtime/lru_set.dart';
import '../../core/utils/conversation_id_generator.dart';

class UnifiedAppProvider extends ChangeNotifier with EventLogger {
  final RealtimeGateway gateway;
  final LocalNotificationBadgeService badgeService;
  final LruSet _seenIds = LruSet(capacity: 1000);

  UnifiedAppProvider({
    required this.gateway,
    required this.badgeService,
  });

  String? _sessionId;
  Timer? _typingEndTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isReady => gateway.state == RealtimeState.ready;

  Future<void> init({
    required String baseUrl,
    required String sessionId,
  }) async {
    _sessionId = sessionId;
    await gateway.connect(baseUrl: baseUrl, sessionId: sessionId);
    _sub ??= gateway.events.listen(_onEvent, onError: (_) {});
  }

  StreamSubscription<SocketEvent>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _typingEndTimer?.cancel();
    super.dispose();
  }

  Future<void> _onEvent(SocketEvent e) async {
    switch (e.type) {
      case RT.sessionRegistered:
        break;

      case RT.msgReceived:
        await _handleMessageReceived(e.data);
        break;

      case RT.msgAcked:
        break;

      case RT.rcptDelivered:
        break;

      case RT.rcptRead:
        break;

      case RT.typingStatusUpdate:
        break;

      case RT.presenceUpdate:
        break;

      case RT.kerResponse:
        await _handleKerAccepted(e.data);
        break;

      case RT.kerDeclined:
        await _handleKerDeclined(e.data);
        break;

      case RT.kerRevoked:
        await _handleKerRevoked(e.data);
        break;

      case RT.convCreated:
        await _handleConversationCreated(e.data);
        break;

      case RT.userDataData:
        await _handleUserDataExchange(e.data);
        break;

      case RT.userBlocked:
      case RT.userUnblocked:
      case RT.conversationBlocked:
      case RT.conversationUnblocked:
        await _notifyOS('SeChat', _titleFor(e.type), _bodyFor(e.type, e.data));
        break;

      case RT.userDeleted:
        await _notifyOS('SeChat', 'User Deleted', 'A user was deleted');
        break;

      default:
        break;
    }
  }

  String _titleFor(String type) {
    switch (type) {
      case RT.userBlocked:
        return 'User Blocked';
      case RT.userUnblocked:
        return 'User Unblocked';
      case RT.conversationBlocked:
        return 'Conversation Blocked';
      case RT.conversationUnblocked:
        return 'Conversation Unblocked';
      default:
        return 'Notification';
    }
  }

  String _bodyFor(String type, Map<String, dynamic> d) {
    switch (type) {
      case RT.userBlocked:
        return 'A user blocked you or a conversation';
      case RT.userUnblocked:
        return 'A user unblocked you or a conversation';
      case RT.conversationBlocked:
        return 'A conversation was blocked';
      case RT.conversationUnblocked:
        return 'A conversation was unblocked';
      default:
        return '';
    }
  }

  Future<void> _handleMessageReceived(Map<String, dynamic> d) async {
    final messageId = d['messageId']?.toString() ?? d['id']?.toString() ?? '';
    if (messageId.isEmpty) return;
    if (!_seenIds.addIfNew('msg:$messageId')) return;

    final fromUserId =
        d['fromUserId']?.toString() ?? d['senderId']?.toString() ?? '';
    final conversationId = d['conversationId']?.toString() ??
        (fromUserId.isNotEmpty && _sessionId != null
            ? ConversationIdGenerator.generateConsistentConversationId(
                _sessionId!, fromUserId)
            : '');

    final cipher = d['body']?.toString();
    String plain = '';
    if (cipher != null && cipher.isNotEmpty) {
      final map = await EncryptionService.decryptData(cipher);
      plain = map?['text']?.toString() ?? map?['body']?.toString() ?? '';
    }

    // ✅ FIXED: Always show push notification for message received events
    // This ensures all message received events show push notifications
    await _notifyOS(
      fromUserId.isNotEmpty ? fromUserId : 'SeChat',
      'New Message',
      plain.isNotEmpty ? plain : 'You have a new encrypted message',
      payload: {
        'type': 'new_message',
        'messageId': messageId,
        'conversationId': conversationId,
        'senderId': fromUserId,
      },
    );

    notifyListeners();
  }

  Future<void> _handleKerAccepted(Map<String, dynamic> d) async {
    final reqId = d['requestId']?.toString() ?? '';
    if (reqId.isNotEmpty && !_seenIds.addIfNew('ker:acc:$reqId')) return;

    await _notifyOS(
        'Key Exchange', 'Accepted', 'Your key exchange was accepted',
        payload: {
          'type': 'ker_accepted',
          'requestId': reqId,
        });

    notifyListeners();
  }

  Future<void> _handleKerDeclined(Map<String, dynamic> d) async {
    final reqId = d['requestId']?.toString() ?? '';
    if (reqId.isNotEmpty && !_seenIds.addIfNew('ker:dec:$reqId')) return;

    await _notifyOS(
        'Key Exchange', 'Declined', 'Your key exchange was declined',
        payload: {
          'type': 'ker_declined',
          'requestId': reqId,
        });

    notifyListeners();
  }

  Future<void> _handleKerRevoked(Map<String, dynamic> d) async {
    final reqId = d['requestId']?.toString() ?? '';
    if (reqId.isNotEmpty && !_seenIds.addIfNew('ker:rev:$reqId')) return;

    await _notifyOS('Key Exchange', 'Revoked', 'A key exchange was revoked',
        payload: {
          'type': 'ker_revoked',
          'requestId': reqId,
        });

    notifyListeners();
  }

  Future<void> _handleConversationCreated(Map<String, dynamic> d) async {
    final cid = d['conversationId']?.toString() ??
        d['conversation_id_local']?.toString() ??
        '';
    if (cid.isEmpty || !_seenIds.addIfNew('conv:$cid')) return;

    await _notifyOS('SeChat', 'Conversation Created', 'You can now chat',
        payload: {
          'type': 'conversation_created',
          'conversationId': cid,
        });

    notifyListeners();
  }

  Future<void> _handleUserDataExchange(Map<String, dynamic> d) async {
    final key = d['requestId']?.toString() ?? d['senderId']?.toString() ?? '';
    if (key.isEmpty || !_seenIds.addIfNew('udx:$key')) return;
    await _notifyOS('SeChat', 'Contact Updated', 'User data received');
    notifyListeners();
  }

  Future<void> _notifyOS(String title, String subtitle, String body,
      {Map<String, dynamic>? payload}) async {
    try {
      await badgeService.showKerNotification(
        title: '$title • $subtitle',
        body: body,
        type: 'info',
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> sendText({
    required String toSessionId,
    required String messageId,
    required String text,
  }) async {
    if (_sessionId == null) return;
    final convId = ConversationIdGenerator.generateConsistentConversationId(
        _sessionId!, toSessionId);
    final cipher =
        await EncryptionService.encryptData({'text': text}, toSessionId);
    gateway.sendMessage(
      toSessionId: toSessionId,
      conversationId: convId,
      messageId: messageId,
      encryptedBody: cipher,
    );
  }

  void typing({
    required String toSessionId,
    required bool isTyping,
    Duration throttle = const Duration(milliseconds: 1500),
  }) {
    final now = DateTime.now();
    if (isTyping) {
      if (now.difference(_lastTypingSent) >= throttle) {
        _lastTypingSent = now;
        gateway.sendTyping(toSessionId: toSessionId, isTyping: true);
      }
      _typingEndTimer?.cancel();
      _typingEndTimer = Timer(const Duration(seconds: 3), () {
        gateway.sendTyping(toSessionId: toSessionId, isTyping: false);
      });
    } else {
      gateway.sendTyping(toSessionId: toSessionId, isTyping: false);
      _typingEndTimer?.cancel();
    }
  }

  void sendRead({
    required String toSessionId,
    required String conversationId,
    required String messageId,
  }) {
    gateway.sendReadReceipt(
      toSessionId: toSessionId,
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  void sendKerRequest({
    required String toSessionId,
    required String requestId,
    required String publicKey,
    required String requestPhrase,
  }) {
    gateway.kerRequest({
      'recipientId': toSessionId,
      'requestId': requestId,
      'publicKey': publicKey,
      'requestPhrase': requestPhrase,
      'version': '1',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void acceptKer({
    required String requestId,
    required String toSessionId,
    required String publicKey,
  }) {
    gateway.kerAccept({
      'requestId': requestId,
      'recipientId': toSessionId,
      'publicKey': publicKey,
      'version': '1',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void declineKer({
    required String requestId,
    required String toSessionId,
    String? reason,
  }) {
    gateway.kerDecline({
      'requestId': requestId,
      'recipientId': toSessionId,
      if (reason != null) 'reason': reason,
      'version': '1',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void revokeKer({
    required String requestId,
    required String toSessionId,
  }) {
    gateway.kerRevoke({
      'requestId': requestId,
      'recipientId': toSessionId,
      'version': '1',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> persistSession(String sessionId) async {
    // final prefs = await SeSharedPreferenceService.instance.getInstance();
    // await prefs.setString('current_user_id', sessionId);
  }

  Future<void> hapticLight() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
