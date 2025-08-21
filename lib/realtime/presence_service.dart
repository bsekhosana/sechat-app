import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../core/services/se_socket_service.dart';
import '../core/services/se_session_service.dart';
import 'realtime_logger.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';

/// Service to manage user presence (online/offline) with robust TTL handling
class PresenceService {
  static PresenceService? _instance;
  static PresenceService get instance => _instance ??= PresenceService._();

  PresenceService._();

  final SeSocketService _socketService = SeSocketService.instance;
  final SeSessionService _sessionService = SeSessionService();

  // Presence state
  bool _isOnline = false;
  bool _isInitialized = false;
  DateTime? _lastPresenceUpdate;

  // Timers
  Timer? _keepaliveTimer;
  Timer? _backgroundTimer;

  // Constants
  static const Duration _keepaliveInterval = Duration(seconds: 25);
  static const Duration _backgroundDelay = Duration(seconds: 5);
  static const Duration _serverTTL = Duration(seconds: 35);

  // Stream controllers for presence updates
  final StreamController<PresenceUpdate> _presenceController =
      StreamController<PresenceUpdate>.broadcast();

  // Getters
  bool get isOnline => _isOnline;
  bool get isInitialized => _isInitialized;
  Stream<PresenceUpdate> get presenceStream => _presenceController.stream;

  /// Initialize the presence service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      RealtimeLogger.presence('Initializing presence service');

      // Set up app lifecycle listeners
      _setupAppLifecycleListeners();

      // Set up socket connection listener
      _setupSocketConnectionListener();

      // Start as offline initially
      _isOnline = false;
      _isInitialized = true;

      RealtimeLogger.presence('Presence service initialized successfully');
    } catch (e) {
      RealtimeLogger.presence('Failed to initialize presence service: $e',
          details: {'error': e.toString()});
      rethrow;
    }
  }

  /// Set up app lifecycle listeners for presence management
  void _setupAppLifecycleListeners() {
    // Listen for app state changes
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == AppLifecycleState.resumed.toString()) {
        _onAppResumed();
      } else if (msg == AppLifecycleState.paused.toString()) {
        _onAppPaused();
      } else if (msg == AppLifecycleState.detached.toString()) {
        _onAppDetached();
      }
      return null;
    });
  }

  /// Set up socket connection listener
  void _setupSocketConnectionListener() {
    // Listen for socket connection changes
    _socketService.connectionStateStream.listen((isConnected) {
      if (isConnected && _isOnline) {
        // Socket reconnected while we should be online
        _emitPresence(true);
      }
    });
  }

  /// Handle app resumed (foreground)
  void _onAppResumed() {
    RealtimeLogger.presence('App resumed, setting presence to online');

    // Cancel background timer if it was set
    _backgroundTimer?.cancel();

    // Set presence to online immediately
    _setPresence(true);
  }

  /// Handle app paused (background)
  void _onAppPaused() {
    RealtimeLogger.presence('App paused, scheduling offline presence');

    // Schedule offline presence after delay to handle quick foreground/background transitions
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(_backgroundDelay, () {
      if (!_isOnline) return; // Already offline

      RealtimeLogger.presence('App backgrounded, setting presence to offline');
      _setPresence(false);
    });
  }

  /// Handle app detached (terminated)
  void _onAppDetached() {
    RealtimeLogger.presence('App detached, setting presence to offline');

    // Immediate offline presence
    _setPresence(false);
  }

  /// Set presence state and emit to server
  void _setPresence(bool online) {
    if (_isOnline == online) return; // No change

    _isOnline = online;
    _lastPresenceUpdate = DateTime.now();

    // Emit presence update
    _emitPresence(online);

    // Start/stop keepalive timer
    if (online) {
      _startKeepaliveTimer();
    } else {
      _stopKeepaliveTimer();
    }

    // Notify listeners
    _presenceController.add(PresenceUpdate(
      isOnline: online,
      timestamp: _lastPresenceUpdate!,
      source: 'local',
    ));

    RealtimeLogger.presence('Presence set to ${online ? 'online' : 'offline'}');
  }

  /// Emit presence to server via socket
  void _emitPresence(bool online) {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) {
        RealtimeLogger.presence('No session ID available for presence update');
        return;
      }

      final presenceData = {
        'type': online ? 'presence:online' : 'presence:offline',
        'sessionId': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'deviceInfo': {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'version': '1.0.0',
        },
      };

      if (_socketService.isConnected) {
        _socketService.emit('presence:update', presenceData);
        RealtimeLogger.presence(
            'Presence update sent to server: ${online ? 'online' : 'offline'}',
            peerId: sessionId);
      } else {
        RealtimeLogger.presence('Socket not connected, presence update queued',
            peerId: sessionId);
        // Note: Server will handle TTL if socket is disconnected
      }
    } catch (e) {
      RealtimeLogger.presence('Failed to emit presence update: $e',
          details: {'error': e.toString()});
    }
  }

  /// Send presence update to the server
  void _sendPresenceUpdate(bool isOnline) async {
    try {
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        print(
            '🟢 PresenceService: ❌ No session ID available for presence update');
        return;
      }

      // Get all active contacts from the session service
      final activeContacts = _getActiveContactsFromSession();
      if (activeContacts.isEmpty) {
        print('🟢 PresenceService: ℹ️ No active contacts to send presence to');
        return;
      }

      // Use the new channel-based socket service
      final socketService = SeSocketService.instance;

      // Send presence update to all active contacts
      for (final contactId in activeContacts) {
        socketService.sendPresenceUpdate(contactId, isOnline);
      }

      print(
          '🟢 PresenceService: ✅ Presence update sent via channel socket: ${isOnline ? 'online' : 'offline'} to ${activeContacts.length} contacts');
    } catch (e) {
      print('🟢 PresenceService: ❌ Failed to send presence update: $e');
    }
  }

  /// Get active contacts from the session service
  List<String> _getActiveContactsFromSession() {
    try {
      // Get contacts from the current session's message cache
      // This represents users we've communicated with
      final session = _sessionService.currentSession;
      if (session == null) return [];

      // For now, return an empty list since we don't have a contacts service yet
      // In a real implementation, this would come from a contacts/relationships service
      // or be derived from the message cache
      return <String>[];
    } catch (e) {
      print('🟢 PresenceService: ❌ Error getting active contacts: $e');
      return [];
    }
  }

  /// Start keepalive timer
  void _startKeepaliveTimer() {
    _stopKeepaliveTimer();

    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (timer) {
      if (!_isOnline) {
        timer.cancel();
        return;
      }

      _sendKeepalive();
    });

    RealtimeLogger.presence(
        'Keepalive timer started (${_keepaliveInterval.inSeconds}s)');
  }

  /// Stop keepalive timer
  void _stopKeepaliveTimer() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  /// Send keepalive ping
  void _sendKeepalive() {
    try {
      final sessionId = _sessionService.currentSessionId;
      if (sessionId == null) return;

      final keepaliveData = {
        'type': 'presence:ping',
        'sessionId': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (_socketService.isConnected) {
        _socketService.emit('presence:ping', keepaliveData);
        RealtimeLogger.presence('Keepalive ping sent', peerId: sessionId);
      }
    } catch (e) {
      RealtimeLogger.presence('Failed to send keepalive: $e');
    }
  }

  /// Force presence update (for manual control)
  void forcePresenceUpdate(bool online) {
    RealtimeLogger.presence(
        'Force presence update requested: ${online ? 'online' : 'offline'}');
    _setPresence(online);
  }

  /// Get presence statistics
  Map<String, dynamic> getPresenceStats() {
    return {
      'isOnline': _isOnline,
      'lastUpdate': _lastPresenceUpdate?.toIso8601String(),
      'keepaliveActive': _keepaliveTimer?.isActive ?? false,
      'backgroundTimerActive': _backgroundTimer?.isActive ?? false,
      'serverTTL': _serverTTL.inSeconds,
      'keepaliveInterval': _keepaliveInterval.inSeconds,
    };
  }

  /// Dispose the service
  void dispose() {
    _keepaliveTimer?.cancel();
    _backgroundTimer?.cancel();
    _presenceController.close();
    _isInitialized = false;

    RealtimeLogger.presence('Presence service disposed');
  }
}

/// Presence update event
class PresenceUpdate {
  final bool isOnline;
  final DateTime timestamp;
  final String source; // 'local', 'server', 'peer'

  PresenceUpdate({
    required this.isOnline,
    required this.timestamp,
    required this.source,
  });

  @override
  String toString() =>
      'PresenceUpdate(isOnline: $isOnline, source: $source, timestamp: $timestamp)';
}
