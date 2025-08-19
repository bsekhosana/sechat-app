import 'package:flutter/foundation.dart';

class IndicatorService extends ChangeNotifier {
  static final IndicatorService _instance = IndicatorService._internal();
  factory IndicatorService() => _instance;
  IndicatorService._internal();

  // Count-based badges instead of boolean indicators
  int _unreadChatsCount = 0;
  int _pendingKeyExchangeCount = 0;
  int _unreadNotificationsCount = 0;

  // Getters for counts
  int get unreadChatsCount => _unreadChatsCount;
  int get pendingKeyExchangeCount => _pendingKeyExchangeCount;
  int get unreadNotificationsCount => _unreadNotificationsCount;

  // Boolean getters for backward compatibility
  bool get hasNewChats => _unreadChatsCount > 0;
  bool get hasNewKeyExchange => _pendingKeyExchangeCount > 0;
  bool get hasNewNotifications => _unreadNotificationsCount > 0;

  Future<void> checkForNewItems() async {
    try {
      // This method will be called by the providers when data changes
      // The actual counts are updated via updateCounts() method
      notifyListeners();
    } catch (e) {
      print('🔔 IndicatorService: Error checking for new items: $e');
    }
  }

  void clearChatIndicator() {
    _unreadChatsCount = 0;
    notifyListeners();
  }

  void clearNotificationIndicator() {
    _unreadNotificationsCount = 0;
    notifyListeners();
  }

  void clearKeyExchangeIndicator() {
    _pendingKeyExchangeCount = 0;
    notifyListeners();
  }

  /// Update counts from external sources
  void updateCounts({
    int? unreadChats,
    int? pendingKeyExchange,
    int? unreadNotifications,
  }) {
    bool hasChanges = false;

    if (unreadChats != null && _unreadChatsCount != unreadChats) {
      _unreadChatsCount = unreadChats;
      hasChanges = true;
    }

    if (pendingKeyExchange != null &&
        _pendingKeyExchangeCount != pendingKeyExchange) {
      _pendingKeyExchangeCount = pendingKeyExchange;
      hasChanges = true;
    }

    if (unreadNotifications != null &&
        _unreadNotificationsCount != unreadNotifications) {
      _unreadNotificationsCount = unreadNotifications;
      hasChanges = true;
    }

    if (hasChanges) {
      notifyListeners();
      print(
          '🔔 IndicatorService: ✅ Counts updated - Chats: $_unreadChatsCount, KER: $_pendingKeyExchangeCount, Notifications: $_unreadNotificationsCount');
    }
  }
}
