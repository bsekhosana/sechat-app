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
    print(
        '🔔 IndicatorService: 🧹 Clearing KER indicator (was: $_pendingKeyExchangeCount)');
    _pendingKeyExchangeCount = 0;
    notifyListeners();
    print('🔔 IndicatorService: ✅ KER indicator cleared');
  }

  /// Clear all indicators at once (used when account is deleted)
  void clearAllIndicators() {
    _unreadChatsCount = 0;
    _pendingKeyExchangeCount = 0;
    _unreadNotificationsCount = 0;
    notifyListeners();
    print('🔔 IndicatorService: ✅ All indicators cleared');
  }

  /// Update counts from external sources
  void updateCounts({
    int? unreadChats,
    int? pendingKeyExchange,
    int? unreadNotifications,
  }) {
    bool hasChanges = false;

    if (unreadChats != null && _unreadChatsCount != unreadChats) {
      print(
          '🔔 IndicatorService: 🔄 Chat count changing from $_unreadChatsCount to $unreadChats');
      _unreadChatsCount = unreadChats;
      hasChanges = true;
    }

    if (pendingKeyExchange != null &&
        _pendingKeyExchangeCount != pendingKeyExchange) {
      print(
          '🔔 IndicatorService: 🔄 KER count changing from $_pendingKeyExchangeCount to $pendingKeyExchange');
      _pendingKeyExchangeCount = pendingKeyExchange;
      hasChanges = true;
    }

    if (unreadNotifications != null &&
        _unreadNotificationsCount != unreadNotifications) {
      print(
          '🔔 IndicatorService: 🔄 Notifications count changing from $_unreadNotificationsCount to $unreadNotifications');
      _unreadNotificationsCount = unreadNotifications;
      hasChanges = true;
    }

    if (hasChanges) {
      notifyListeners();
      print(
          '🔔 IndicatorService: ✅ Counts updated - Chats: $_unreadChatsCount, KER: $_pendingKeyExchangeCount, Notifications: $_unreadNotificationsCount');
    } else {
      print('🔔 IndicatorService: ℹ️ No changes detected in badge counts');
    }
  }

  /// Force display current badge counts (useful when navigating to tabs)
  void forceDisplayCurrentCounts() {
    print('🔔 IndicatorService: 🔄 Force displaying current badge counts');
    print(
        '🔔 IndicatorService: 📊 Current counts - Chats: $_unreadChatsCount, KER: $_pendingKeyExchangeCount, Notifications: $_unreadNotificationsCount');
    notifyListeners();
  }

  /// Prevent badge updates when on specific screens
  bool _isOnKeyExchangeScreen = false;
  bool _isOnNotificationsScreen = false;

  void setScreenContext({
    bool? isOnKeyExchangeScreen,
    bool? isOnNotificationsScreen,
  }) {
    bool hasChanges = false;

    if (isOnKeyExchangeScreen != null &&
        _isOnKeyExchangeScreen != isOnKeyExchangeScreen) {
      _isOnKeyExchangeScreen = isOnKeyExchangeScreen;
      hasChanges = true;
      print(
          '🔔 IndicatorService: 🔄 KER screen context changed to: $_isOnKeyExchangeScreen');
    }

    if (isOnNotificationsScreen != null &&
        _isOnNotificationsScreen != isOnNotificationsScreen) {
      _isOnNotificationsScreen = isOnNotificationsScreen;
      hasChanges = true;
      print(
          '🔔 IndicatorService: 🔄 Notifications screen context changed to: $_isOnNotificationsScreen');
    }

    if (hasChanges) {
      print(
          '🔔 IndicatorService: ✅ Screen context updated - KER: $_isOnKeyExchangeScreen, Notifications: $_isOnNotificationsScreen');
    }
  }

  /// Update counts with screen context awareness
  void updateCountsWithContext({
    int? unreadChats,
    int? pendingKeyExchange,
    int? unreadNotifications,
  }) {
    print(
        '🔔 IndicatorService: 🔍 Context check - KER Screen: $_isOnKeyExchangeScreen, Notifications Screen: $_isOnNotificationsScreen');

    // For KER badge: only prevent external updates when on KER screen
    // But allow the badge to show the current count
    if (pendingKeyExchange != null && _isOnKeyExchangeScreen) {
      // If we're on the KER screen and the count is 0, allow the update to show the current count
      if (_pendingKeyExchangeCount == 0 && pendingKeyExchange > 0) {
        print(
            '🔔 IndicatorService: ℹ️ Allowing KER badge update to show current count on KER screen: $pendingKeyExchange');
      } else {
        print(
            '🔔 IndicatorService: ℹ️ Skipping KER badge update from external source - user on KER screen (current count: $_pendingKeyExchangeCount)');
        return;
      }
    }

    // For notifications badge: only prevent external updates when on notifications screen
    // But allow the badge to show the current count
    if (unreadNotifications != null && _isOnNotificationsScreen) {
      // If we're on the notifications screen and the count is 0, allow the update to show the current count
      if (_unreadNotificationsCount == 0 && unreadNotifications > 0) {
        print(
            '🔔 IndicatorService: ℹ️ Allowing notifications badge update to show current count on notifications screen: $unreadNotifications');
      } else {
        print(
            '🔔 IndicatorService: ℹ️ Skipping notifications badge update from external source - user on notifications screen (current count: $_unreadNotificationsCount)');
        return;
      }
    }

    // Proceed with normal update
    print(
        '🔔 IndicatorService: ✅ Proceeding with badge update - KER: $pendingKeyExchange, Notifications: $unreadNotifications');
    updateCounts(
      unreadChats: unreadChats,
      pendingKeyExchange: pendingKeyExchange,
      unreadNotifications: unreadNotifications,
    );
  }
}
