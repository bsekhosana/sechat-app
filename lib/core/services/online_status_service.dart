import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/secure_notification_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';

/// Service to handle user online status
class OnlineStatusService {
  static OnlineStatusService? _instance;
  static OnlineStatusService get instance =>
      _instance ??= OnlineStatusService._();

  // Private constructor
  OnlineStatusService._();

  // Storage for online status
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  // Online status and last seen map for contacts
  final Map<String, OnlineStatusInfo> _onlineStatus = {};

  // Timer for periodic updates
  Timer? _updateTimer;

  // Event listeners for online status changes
  final Map<String, List<Function(OnlineStatusInfo)>> _listeners = {};

  /// Initialize online status service
  Future<void> initialize() async {
    try {
      // Load saved statuses from storage
      await _loadOnlineStatuses();

      // Start periodic online status updates
      _startPeriodicUpdates();

      // Set current user as online
      await setUserOnline(true);

      print('🟢 OnlineStatusService: Initialized successfully');
    } catch (e) {
      print('🟢 OnlineStatusService: Error during initialization: $e');
    }
  }

  /// Start periodic online status updates
  void _startPeriodicUpdates() {
    // Cancel existing timer if any
    _updateTimer?.cancel();

    // Send online status update every 5 minutes
    _updateTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await setUserOnline(true);
    });
  }

  /// Set current user's online status
  Future<void> setUserOnline(bool isOnline) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🟢 OnlineStatusService: User not logged in');
        return;
      }

      final lastSeen = DateTime.now();

      // Store own status locally
      _updateLocalStatus(currentUserId, isOnline, lastSeen);

      // Get all contacts
      final contactIds = await _getContacts();

      // Send online status to all contacts
      for (final contactId in contactIds) {
        await SecureNotificationService.instance.sendEncryptedOnlineStatus(
          recipientId: contactId,
          isOnline: isOnline,
        );
      }

      print('🟢 OnlineStatusService: User online status set to $isOnline');
    } catch (e) {
      print('🟢 OnlineStatusService: Error setting online status: $e');
    }
  }

  /// Update local status information for a user
  void _updateLocalStatus(String userId, bool isOnline, DateTime lastSeen) {
    // Create or update status info
    final statusInfo = _onlineStatus[userId] ??
        OnlineStatusInfo(
          userId: userId,
          isOnline: isOnline,
          lastSeen: lastSeen,
        );

    // Update with new values
    statusInfo.isOnline = isOnline;
    statusInfo.lastSeen = lastSeen;

    // Store in memory
    _onlineStatus[userId] = statusInfo;

    // Save to storage
    _saveOnlineStatuses();

    // Notify listeners
    _notifyListeners(userId, statusInfo);
  }

  /// Get online status info for a user
  OnlineStatusInfo getStatus(String userId) {
    // Return existing or default status
    return _onlineStatus[userId] ??
        OnlineStatusInfo(
          userId: userId,
          isOnline: false,
          lastSeen: DateTime.now().subtract(const Duration(days: 1)),
        );
  }

  /// Process received online status update
  void processOnlineStatusUpdate({
    required String senderId,
    required bool isOnline,
    String? lastSeen,
  }) {
    try {
      final lastSeenTime =
          lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now();

      _updateLocalStatus(senderId, isOnline, lastSeenTime);

      print(
          '🟢 OnlineStatusService: Updated status for $senderId to $isOnline');
    } catch (e) {
      print(
          '🟢 OnlineStatusService: Error processing online status update: $e');
    }
  }

  /// Save online statuses to storage
  Future<void> _saveOnlineStatuses() async {
    try {
      final statusMap = <String, Map<String, dynamic>>{};

      _onlineStatus.forEach((userId, status) {
        statusMap[userId] = {
          'userId': status.userId,
          'isOnline': status.isOnline,
          'lastSeen': status.lastSeen.toIso8601String(),
        };
      });

      await _prefsService.setJson('online_status_cache', statusMap);
    } catch (e) {
      print('🟢 OnlineStatusService: Error saving online statuses: $e');
    }
  }

  /// Load online statuses from storage
  Future<void> _loadOnlineStatuses() async {
    try {
      final statusMap = await _prefsService.getJson('online_status_cache');

      if (statusMap != null) {
        statusMap.forEach((userId, statusData) {
          if (statusData is Map<String, dynamic>) {
            final status = OnlineStatusInfo(
              userId: userId,
              isOnline: statusData['isOnline'] ?? false,
              lastSeen: statusData['lastSeen'] != null
                  ? DateTime.parse(statusData['lastSeen'])
                  : DateTime.now().subtract(const Duration(days: 1)),
            );

            _onlineStatus[userId] = status;
          }
        });
      }

      print(
          '🟢 OnlineStatusService: Loaded ${_onlineStatus.length} online statuses');
    } catch (e) {
      print('🟢 OnlineStatusService: Error loading online statuses: $e');
    }
  }

  /// Get list of contact IDs
  Future<List<String>> _getContacts() async {
    try {
      // Get chats and extract contact IDs
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final contactIds = <String>{};
      final currentUserId = SeSessionService().currentSessionId;

      if (currentUserId == null) {
        return [];
      }

      for (final chatJson in chatsJson) {
        final user1Id = chatJson['user1_id'] as String?;
        final user2Id = chatJson['user2_id'] as String?;

        if (user1Id == currentUserId && user2Id != null) {
          contactIds.add(user2Id);
        } else if (user2Id == currentUserId && user1Id != null) {
          contactIds.add(user1Id);
        }
      }

      return contactIds.toList();
    } catch (e) {
      print('🟢 OnlineStatusService: Error getting contacts: $e');
      return [];
    }
  }

  /// Add listener for status updates
  void addListener(String userId, Function(OnlineStatusInfo) listener) {
    if (!_listeners.containsKey(userId)) {
      _listeners[userId] = [];
    }

    _listeners[userId]!.add(listener);
  }

  /// Remove listener for status updates
  void removeListener(String userId, Function(OnlineStatusInfo) listener) {
    if (_listeners.containsKey(userId)) {
      _listeners[userId]!.remove(listener);

      if (_listeners[userId]!.isEmpty) {
        _listeners.remove(userId);
      }
    }
  }

  /// Notify listeners of status updates
  void _notifyListeners(String userId, OnlineStatusInfo status) {
    if (_listeners.containsKey(userId)) {
      for (final listener in _listeners[userId]!) {
        listener(status);
      }
    }
  }

  /// Handle app lifecycle changes
  void handleAppLifecycleChange(bool isInForeground) {
    // Update online status based on app lifecycle
    setUserOnline(isInForeground);

    // Restart or stop periodic updates
    if (isInForeground) {
      _startPeriodicUpdates();
    } else {
      _updateTimer?.cancel();
    }
  }

  /// Cleanup resources
  void dispose() {
    _updateTimer?.cancel();
    _listeners.clear();
  }
}

/// Class to hold online status information
class OnlineStatusInfo {
  final String userId;
  bool isOnline;
  DateTime lastSeen;

  OnlineStatusInfo({
    required this.userId,
    required this.isOnline,
    required this.lastSeen,
  });

  /// Get formatted last seen string (WhatsApp style)
  String get formattedLastSeen {
    if (isOnline) {
      return 'Online';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastSeenDate = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

    if (lastSeenDate == today) {
      return 'Last seen today at ${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}';
    } else if (lastSeenDate == yesterday) {
      return 'Last seen yesterday at ${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}';
    } else {
      return 'Last seen on ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }
}
