import 'package:flutter/foundation.dart';
import 'se_shared_preference_service.dart';

class IndicatorService extends ChangeNotifier {
  static final IndicatorService _instance = IndicatorService._internal();
  factory IndicatorService() => _instance;
  IndicatorService._internal();

  bool _hasNewChats = false;
  bool _hasNewInvitations = false;
  bool _hasNewNotifications = false;

  bool get hasNewChats => _hasNewChats;
  bool get hasNewInvitations => _hasNewInvitations;
  bool get hasNewNotifications => _hasNewNotifications;

  Future<void> checkForNewItems() async {
    try {
      final prefsService = SeSharedPreferenceService();
      
      // Check for new chats (chats with recent activity)
      final chatsJson = await prefsService.getJsonList('chats') ?? [];
      final now = DateTime.now();
      _hasNewChats = chatsJson.any((chat) {
        final lastMessageAt = chat['last_message_at'];
        if (lastMessageAt != null) {
          final lastMessageTime = DateTime.parse(lastMessageAt);
          return now.difference(lastMessageTime).inMinutes < 5; // New if within 5 minutes
        }
        return false;
      });

      // Check for new invitations (pending invitations)
      final invitationsJson = await prefsService.getJsonList('invitations') ?? [];
      _hasNewInvitations = invitationsJson.any((invitation) {
        return invitation['status'] == 'pending';
      });

      // Check for new notifications (unread notifications)
      final notificationsJson = await prefsService.getJsonList('notifications') ?? [];
      _hasNewNotifications = notificationsJson.any((notification) {
        return notification['isRead'] == false;
      });

      notifyListeners();
    } catch (e) {
      print('🔔 IndicatorService: Error checking for new items: $e');
    }
  }

  void clearChatIndicator() {
    _hasNewChats = false;
    notifyListeners();
  }

  void clearInvitationIndicator() {
    _hasNewInvitations = false;
    notifyListeners();
  }

  void clearNotificationIndicator() {
    _hasNewNotifications = false;
    notifyListeners();
  }

  void setNewChat() {
    _hasNewChats = true;
    notifyListeners();
  }

  void setNewInvitation() {
    _hasNewInvitations = true;
    notifyListeners();
  }

  void setNewNotification() {
    _hasNewNotifications = true;
    notifyListeners();
  }
} 