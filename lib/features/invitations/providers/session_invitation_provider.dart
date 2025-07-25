import 'package:flutter/foundation.dart';
import '../../../core/services/airnotifier_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/chat.dart';
import 'dart:async';

class SessionInvitationProvider extends ChangeNotifier {
  final AirNotifierService _airNotifier = AirNotifierService.instance;
  final NotificationService _notificationService = NotificationService.instance;
  final LocalStorageService _storage = LocalStorageService.instance;

  List<Invitation> _invitations = [];
  final Map<String, User> _invitationUsers = {};
  bool _isLoading = false;
  String? _error;

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  User? getInvitationUser(String userId) {
    return _invitationUsers[userId];
  }

  SessionInvitationProvider() {
    // No real-time callbacks needed - everything goes through silent notifications
  }

  // Send invitation using AirNotifier notifications
  Future<void> sendInvitation({
    required String recipientId,
    String? displayName,
    String message = 'Would you like to connect?',
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Generate unique invitation ID
      final invitationId =
          'inv_${DateTime.now().millisecondsSinceEpoch}_$recipientId';

      // Send visible invitation notification
      final success = await _airNotifier.sendInvitationNotification(
        recipientId: recipientId,
        senderName: displayName ?? 'Anonymous User',
        invitationId: invitationId,
        message: message,
      );

      // Always create local invitation record, even if notification fails
      // This allows for offline invitation handling
      final invitation = Invitation(
        id: invitationId,
        senderId: _airNotifier.currentUserId ?? '',
        recipientId: recipientId,
        message: message,
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: false, // This is sent by current user
        senderUsername:
            displayName ?? 'Anonymous User', // Store sender's display name
      );

      // Save to local database
      await _storage.saveInvitation(invitation.toJson());
      _invitations.add(invitation);

      // Create user object for the recipient
      final user = User(
        id: recipientId,
        username: displayName ?? 'Anonymous User',
        profilePicture: null,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'pending',
      );

      // Save user to local database
      await _storage.saveUser(user);
      _invitationUsers[recipientId] = user;

      if (success) {
        // Don't show local notification for sender - only recipient should get notification
        print(
            '📱 SessionInvitationProvider: Invitation sent via notification: $recipientId');
      } else {
        // Show a notification to the sender that the invitation was saved locally
        // but the recipient may not be online
        await _notificationService.showInvitationSentNotification(
          recipientUsername: displayName ?? 'Anonymous User',
          invitationId: invitationId,
        );
        print(
            '📱 SessionInvitationProvider: Invitation saved locally (recipient may be offline): $recipientId');
      }
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error sending invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Accept invitation using AirNotifier notifications
  Future<void> acceptInvitation(String invitationId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Find the invitation
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (invitationIndex == -1) {
        throw Exception('Invitation not found');
      }

      final invitation = _invitations[invitationIndex];

      // Generate chat ID for the new conversation
      final chatId =
          'chat_${DateTime.now().millisecondsSinceEpoch}_${invitation.senderId}';

      // Create chat object
      final chat = Chat(
        id: chatId,
        user1Id: _airNotifier.currentUserId ?? '',
        user2Id: invitation.senderId,
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': invitation.senderId,
          'username': invitation.senderUsername ?? 'Anonymous User',
          'is_online': false,
          'last_seen': DateTime.now().toIso8601String(),
        },
        lastMessage: null,
      );

      // Save chat to local database
      await _storage.saveChat(chat);

      // Send acceptance notification with chat ID
      final success = await _airNotifier.sendInvitationResponseNotification(
        recipientId: invitation.senderId,
        responderName: _airNotifier.currentUserId ?? 'Anonymous User',
        status: 'accepted',
        invitationId: invitationId,
        chatId: chatId, // Include chat ID for accepted invitations
      );

      if (success) {
        // Update local invitation status
        final updatedInvitation = invitation.copyWith(
          status: 'accepted',
          updatedAt: DateTime.now(),
          acceptedAt: DateTime.now(),
        );

        // Save to local database
        await _storage.saveInvitation(updatedInvitation.toJson());
        _invitations[invitationIndex] = updatedInvitation;

        // Update user status
        final user = _invitationUsers[invitation.senderId];
        if (user != null) {
          final updatedUser = user.copyWith(
            invitationStatus: 'accepted',
          );
          await _storage.saveUser(updatedUser);
          _invitationUsers[invitation.senderId] = updatedUser;
        }

        // Show notification
        await _notificationService.showInvitationResponseNotification(
          username: user?.username ?? 'Anonymous User',
          status: 'accepted',
          invitationId: invitationId,
        );

        print(
            '📱 SessionInvitationProvider: Invitation accepted and chat created: $invitationId -> $chatId');
      } else {
        throw Exception('Failed to send acceptance notification');
      }
    } catch (e) {
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error accepting invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Decline invitation using AirNotifier notifications
  Future<void> declineInvitation(String invitationId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Find the invitation
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (invitationIndex == -1) {
        throw Exception('Invitation not found');
      }

      final invitation = _invitations[invitationIndex];

      // Send decline notification
      final success = await _airNotifier.sendInvitationResponseNotification(
        recipientId: invitation.senderId,
        responderName: _airNotifier.currentUserId ?? 'Anonymous User',
        status: 'declined',
        invitationId: invitationId,
      );

      if (success) {
        // Update local invitation status
        final updatedInvitation = invitation.copyWith(
          status: 'declined',
          updatedAt: DateTime.now(),
          declinedAt: DateTime.now(),
        );

        // Save to local database
        await _storage.saveInvitation(updatedInvitation.toJson());
        _invitations[invitationIndex] = updatedInvitation;

        // Show notification
        final user = _invitationUsers[invitation.senderId];
        await _notificationService.showInvitationResponseNotification(
          username: user?.username ?? 'Anonymous User',
          status: 'declined',
          invitationId: invitationId,
        );

        print(
            '📱 SessionInvitationProvider: Invitation declined via notification: $invitationId');
      } else {
        throw Exception('Failed to send decline notification');
      }
    } catch (e) {
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error declining invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Handle invitation received via notification
  void handleInvitationReceived(Map<String, dynamic> data) {
    try {
      final invitationId = data['invitationId'] as String;
      final senderId = data['senderId'] as String;
      final senderName = data['senderName'] as String;
      final message = data['message'] as String;

      // Create invitation record
      final invitation = Invitation(
        id: invitationId,
        senderId: senderId,
        recipientId: _airNotifier.currentUserId ?? '',
        message: message,
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: true, // This is received by current user
      );

      // Save to local database
      _storage.saveInvitation(invitation.toJson());
      _invitations.add(invitation);

      // Create user object for the sender
      final user = User(
        id: senderId,
        username: senderName,
        profilePicture: null,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'pending',
      );

      // Save user to local database
      _storage.saveUser(user);
      _invitationUsers[senderId] = user;

      // Show notification
      _notificationService.showInvitationReceivedNotification(
        senderUsername: senderName,
        message: message,
        invitationId: invitationId,
      );

      print(
          '📱 SessionInvitationProvider: Invitation received via notification: $invitationId');
      notifyListeners();
    } catch (e) {
      print(
          '📱 SessionInvitationProvider: Error handling invitation received: $e');
    }
  }

  // Handle invitation response via notification
  void handleInvitationResponse(Map<String, dynamic> data) {
    try {
      final invitationId = data['invitationId'] as String;
      final status = data['status'] as String;
      final responderName = data['responderName'] as String;
      final chatId = data['chatId'] as String?;

      // Find and update invitation
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (invitationIndex != -1) {
        final invitation = _invitations[invitationIndex];
        final updatedInvitation = invitation.copyWith(
          status: status,
          updatedAt: DateTime.now(),
          acceptedAt: status == 'accepted' ? DateTime.now() : null,
          declinedAt: status == 'declined' ? DateTime.now() : null,
        );

        // Save to local database
        _storage.saveInvitation(updatedInvitation.toJson());
        _invitations[invitationIndex] = updatedInvitation;

        // Update user status
        final user = _invitationUsers[invitation.senderId];
        if (user != null) {
          final updatedUser = user.copyWith(
            invitationStatus: status,
          );
          _storage.saveUser(updatedUser);
          _invitationUsers[invitation.senderId] = updatedUser;
        }

        // If accepted and chat ID provided, create chat
        if (status == 'accepted' && chatId != null) {
          _createChatFromInvitationResponse(invitation, chatId, responderName);
        }

        // Show notification
        _notificationService.showInvitationResponseNotification(
          username: responderName,
          status: status,
          invitationId: invitationId,
        );

        print(
            '📱 SessionInvitationProvider: Invitation response received via notification: $invitationId - $status');
        notifyListeners();
      }
    } catch (e) {
      print(
          '📱 SessionInvitationProvider: Error handling invitation response: $e');
    }
  }

  // Create chat from invitation response
  void _createChatFromInvitationResponse(
      Invitation invitation, String chatId, String responderName) {
    try {
      // Create chat object
      final chat = Chat(
        id: chatId,
        user1Id: _airNotifier.currentUserId ?? '',
        user2Id: invitation.senderId,
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': invitation.senderId,
          'username': invitation.senderUsername ?? responderName,
          'is_online': false,
          'last_seen': DateTime.now().toIso8601String(),
        },
        lastMessage: null,
      );

      // Save chat to local database
      _storage.saveChat(chat);

      print(
          '📱 SessionInvitationProvider: Chat created from invitation response: $chatId');
    } catch (e) {
      print(
          '📱 SessionInvitationProvider: Error creating chat from invitation response: $e');
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
