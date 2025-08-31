import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'event_logger.dart';
import 'realtime_events.dart';
import '../config/airnotifier_config.dart';

enum RealtimeState { disconnected, connecting, waitingRegistration, ready }

class RealtimeGateway with EventLogger {
  RealtimeGateway._();
  static final RealtimeGateway instance = RealtimeGateway._();

  late final _events = StreamController<SocketEvent>.broadcast();
  Stream<SocketEvent> get events => _events.stream;

  RealtimeState _state = RealtimeState.disconnected;
  RealtimeState get state => _state;

  io.Socket? _socket;
  String? _sessionId;
  bool _manuallyClosed = false;

  void _setState(RealtimeState s) {
    if (_state == s) return;
    _state = s;
    logE('🔌 Gateway:', 'state=$_state');
  }

  Future<void> connect({
    required String baseUrl,
    required String sessionId,
    Map<String, dynamic>? extraQuery,
  }) async {
    if (_socket != null) {
      await disconnect();
    }
    _manuallyClosed = false;
    _sessionId = sessionId;
    _setState(RealtimeState.connecting);

    final query = <String, dynamic>{
      'EIO': '4',
      'transport': 'websocket',
      'sessionId': sessionId,
      ...?extraQuery,
    };

    final opts = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setQuery(query)
        .enableReconnection()
        .setReconnectionAttempts(double.maxFinite.toInt())
        .setReconnectionDelay(800)
        .setReconnectionDelayMax(30000)
        .build();

    // Add SSL configuration for development
    if (kDebugMode && !AirNotifierConfig.sslVerificationRequired) {
      opts['extraHeaders'] = {'Accept': '*/*'};
      opts['rejectUnauthorized'] = false;
    }

    final s = io.io(baseUrl, opts);
    _socket = s;

    s.onConnect((_) {
      logE('🔌 Gateway:', 'connected');
      _setState(RealtimeState.waitingRegistration);
      emit(RT.registerSession, {'sessionId': sessionId});
    });

    s.onDisconnect((_) {
      logE('🔌 Gateway:', 'disconnected');
      if (!_manuallyClosed) _setState(RealtimeState.connecting);
    });

    s.onReconnectAttempt((_) => logE('🔄 Gateway:', 'reconnect attempt'));
    s.onReconnect((_) => logE('🔄 Gateway:', 'reconnected'));
    s.onConnectError((e) => logE('❌ Gateway:', 'connect_error $e'));
    s.onError((e) => logE('❌ Gateway:', 'error $e'));

    _bindCore(s);

    s.connect();
  }

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _setState(RealtimeState.disconnected);
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  void emit(String event, Map<String, dynamic> payload) {
    if (_socket == null) return;
    logE('📤 Emit:', '$event $payload');
    _socket!.emit(event, payload);
  }

  void _bindCore(io.Socket s) {
    s.on(RT.sessionRegistered, (d) {
      logE('✅ Gateway:', 'session_registered $d');
      _setState(RealtimeState.ready);
      _events.add(SocketEvent(
          RT.sessionRegistered, Map<String, dynamic>.from(d ?? {})));
    });

    s.on(RT.heartbeatPing, (d) {
      emit(RT.heartbeatPong, {'ts': DateTime.now().toIso8601String()});
    });

    s.on(RT.connectionPing, (d) {
      emit(RT.connectionPong, {'ts': DateTime.now().toIso8601String()});
    });

    for (final ev in [
      RT.userDeparted,
      RT.msgReceived,
      RT.msgAcked,
      RT.rcptDelivered,
      RT.rcptRead,
      RT.typingStatusUpdate,
      RT.presenceUpdate,
      RT.userBlocked,
      RT.userUnblocked,
      RT.conversationBlocked,
      RT.conversationUnblocked,
      RT.kerResponse,
      RT.kerDeclined,
      RT.kerRevoked,
      RT.convCreated,
      RT.userDataData,
      RT.userDeleted,
      RT.connectionStability,
      RT.requestQueued,
    ]) {
      s.on(ev, (d) {
        final map =
            d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
        logE('📥 In:', '$ev $map');
        _events.add(SocketEvent(ev, map));
      });
    }
  }

  void registerSession() {
    if (_sessionId == null) return;
    emit(RT.registerSession, {'sessionId': _sessionId});
  }

  void leaveSession() {
    if (_sessionId == null) return;
    emit(RT.sessionLeaving, {'sessionId': _sessionId});
  }

  void sendMessage({
    required String toSessionId,
    required String conversationId,
    required String messageId,
    required String encryptedBody,
  }) {
    emit(RT.msgSend, {
      'toSessionId': toSessionId,
      'conversationId': conversationId,
      'messageId': messageId,
      'body': encryptedBody,
    });
  }

  void sendTyping({
    required String toSessionId,
    required bool isTyping,
  }) {
    emit(RT.typingUpdate, {
      'toSessionId': toSessionId,
      'isTyping': isTyping,
    });
  }

  void updatePresence(Map<String, dynamic> presence) {
    emit(RT.presenceUpdate, presence);
  }

  void kerRequest(Map<String, dynamic> payload) => emit(RT.kerRequest, payload);
  void kerAccept(Map<String, dynamic> payload) => emit(RT.kerAccept, payload);
  void kerDecline(Map<String, dynamic> payload) => emit(RT.kerDecline, payload);
  void kerRevoke(Map<String, dynamic> payload) => emit(RT.kerRevoke, payload);

  void userDataSend(Map<String, dynamic> payload) =>
      emit(RT.userDataSend, payload);

  void sendReadReceipt({
    required String conversationId,
    required String messageId,
    required String toSessionId,
  }) {
    emit(RT.rcptRead, {
      'conversationId': conversationId,
      'messageId': messageId,
      'toSessionId': toSessionId,
    });
  }
}
