import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/notification_service.dart';

class InvitationProvider extends ChangeNotifier {
  List<Invitation> _invitations = [];
  final Map<String, User> _invitationUsers = {};
  bool _isLoading = false;
  String? _error;
  int _pendingReceivedCount = 0;
  int _responsesSentCount = 0;
  bool _hasUnreadInvitations = false;
  bool _isOnInvitationsScreen = false; // Track if user is on invitations screen

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingReceivedCount => _pendingReceivedCount;
  int get responsesSentCount => _responsesSentCount;
  int get totalBadgeCount => _pendingReceivedCount + _responsesSentCount;
  bool get hasUnreadInvitations => _hasUnreadInvitations;
  bool get isOnInvitationsScreen => _isOnInvitationsScreen;

  User? getInvitationUser(String userId) {
    return _invitationUsers[userId];
  }

  InvitationProvider() {
    _setupSocket();
    _loadInvitationsFromLocal();
  }

  void _setupSocket() {
    SocketService.instance.onInvitationReceived = _handleInvitationReceived;
    SocketService.instance.onInvitationResponse = _handleInvitationResponse;
    SocketService.instance.onUserOnline = _handleUserOnline;
    SocketService.instance.onUserOffline = _handleUserOffline;
  }

  void _handleInvitationReceived(Map<String, dynamic> data) {
    final invitationData = data;
    final invitation = Invitation.fromJson(invitationData);

    // Store user data if available
    if (data['sender'] != null) {
      final senderData = data['sender'] as Map<String, dynamic>;
      final sender = User.fromJson(senderData);
      _invitationUsers[sender.id] = sender.copyWith(isOnline: true);
    }

    _addInvitation(invitation);

    // Trigger local notification only if user is not on invitations screen
    if (!_isOnInvitationsScreen) {
      _triggerInvitationReceivedNotification(invitation);
    }
  }

  void _handleInvitationResponse(Map<String, dynamic> data) {
    final invitationData = data;
    final status = invitationData['status'] as String;
    final invitationId =
        invitationData['id'].toString(); // Ensure it's a string

    print(
        '📱 InvitationProvider: Handling invitation response - ID: $invitationId, Status: $status');
    print(
        '📱 InvitationProvider: Local invitations count: ${_invitations.length}');
    print(
        '📱 InvitationProvider: Local invitation IDs: ${_invitations.map((i) => i.id).toList()}');

    // Store user data if available in the response
    if (invitationData['sender'] != null) {
      final senderData = invitationData['sender'] as Map<String, dynamic>;
      final sender = User.fromJson(senderData);
      _invitationUsers[sender.id] = sender.copyWith(isOnline: true);
      print('📱 InvitationProvider: Stored sender user: ${sender.username}');
    }

    if (invitationData['recipient'] != null) {
      final recipientData = invitationData['recipient'] as Map<String, dynamic>;
      final recipient = User.fromJson(recipientData);
      _invitationUsers[recipient.id] = recipient.copyWith(isOnline: true);
      print(
          '📱 InvitationProvider: Stored recipient user: ${recipient.username}');
    }

    // Update local invitation status
    final index = _invitations.indexWhere((i) => i.id == invitationId);
    if (index != -1) {
      print(
          '📱 InvitationProvider: Found invitation at index $index, updating status');
      _invitations[index] = _invitations[index].copyWith(
        status: status,
        acceptedAt: status == 'accepted' ? DateTime.now() : null,
        declinedAt: status == 'declined' ? DateTime.now() : null,
      );
      _saveInvitationsToLocal();
      _updateBadgeCounts();
      notifyListeners();
    } else {
      print(
          '📱 InvitationProvider: Invitation not found in local list, adding it');
      // If invitation not found locally, add it from the response data
      try {
        final invitation = Invitation.fromJson(invitationData);
        _invitations.insert(0, invitation);
        _saveInvitationsToLocal();
        _updateBadgeCounts();
        notifyListeners();
      } catch (e) {
        print(
            '📱 InvitationProvider: Error creating invitation from response data: $e');
      }
    }

    // Trigger local notification for response only if user is not on invitations screen
    if (!_isOnInvitationsScreen) {
      _triggerInvitationResponseNotification(invitationId, status);
    }
  }

  void _handleUserOnline(Map<String, dynamic> data) {
    final userId = data['userId'].toString();
    _updateUserOnlineStatus(userId, true, null);
  }

  void _handleUserOffline(Map<String, dynamic> data) {
    final userId = data['userId'].toString();
    _updateUserOnlineStatus(userId, false, DateTime.now());
  }

  void _addInvitation(Invitation invitation) {
    _invitations.insert(0, invitation);
    _saveInvitationsToLocal();
    _updateBadgeCounts();
    notifyListeners();
  }

  // Method to track when user enters/exits invitations screen
  void setOnInvitationsScreen(bool isOnScreen) {
    _isOnInvitationsScreen = isOnScreen;
    if (isOnScreen) {
      // Mark invitations as read when user enters the screen
      markAllInvitationsAsRead();
    }
  }

  Future<void> loadInvitations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Load from local storage first for instant UI
    await _loadInvitationsFromLocal();

    try {
      print('📱 InvitationProvider: Loading invitations from API...');
      final response = await ApiService.getInvitations();
      print('📱 InvitationProvider: API response: $response');

      if (response['success'] == true) {
        final invitationsData = response['invitations'] as List;
        _invitations = invitationsData
            .map((invitationData) => Invitation.fromJson(invitationData))
            .toList();

        // Extract and store user information from invitation data
        for (int i = 0; i < invitationsData.length; i++) {
          final invitationData = invitationsData[i] as Map<String, dynamic>;
          final invitation = _invitations[i];

          // Store sender user info
          if (invitationData['sender'] != null) {
            final senderData = invitationData['sender'] as Map<String, dynamic>;
            final sender = User.fromJson(senderData);
            // Set default online status to true until WebSocket provides real data
            _invitationUsers[sender.id] = sender.copyWith(isOnline: true);
          }

          // Store recipient user info
          if (invitationData['recipient'] != null) {
            final recipientData =
                invitationData['recipient'] as Map<String, dynamic>;
            final recipient = User.fromJson(recipientData);
            // Set default online status to true until WebSocket provides real data
            _invitationUsers[recipient.id] = recipient.copyWith(isOnline: true);
          }

          // Store other_user info (the user who is not the current user)
          if (invitationData['other_user'] != null) {
            final otherUserData =
                invitationData['other_user'] as Map<String, dynamic>;
            final otherUser = User.fromJson(otherUserData);
            // Set default online status to true until WebSocket provides real data
            _invitationUsers[otherUser.id] = otherUser.copyWith(isOnline: true);
          }
        }

        print(
            '📱 InvitationProvider: Loaded ${_invitations.length} invitations');
        await _saveInvitationsToLocal();

        // Update badge counts
        _updateBadgeCounts();
      } else {
        throw Exception(response['message'] ?? 'Failed to load invitations');
      }
    } catch (e) {
      print('📱 InvitationProvider: Error loading invitations: $e');
      _error = 'Failed to load invitations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadInvitationsFromLocal() async {
    final box = Hive.box('invitations');
    final localInvitations = box.values
        .map((e) => Invitation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _invitations = localInvitations;
    _updateBadgeCounts();
    notifyListeners();
  }

  Future<void> _saveInvitationsToLocal() async {
    final box = Hive.box('invitations');
    await box.clear();
    for (var invitation in _invitations) {
      await box.put(invitation.id, invitation.toJson());
    }
  }

  Future<bool> sendInvitation({
    required String recipientId,
    required String message,
  }) async {
    try {
      print('📱 InvitationProvider: Sending invitation to $recipientId');

      // Check Socket.IO connection and authentication status
      final isSocketConnected = SocketService.instance.isConnected;
      final isSocketAuthenticated = SocketService.instance.isAuthenticated;

      print(
          '📱 InvitationProvider: Socket.IO connected: $isSocketConnected, authenticated: $isSocketAuthenticated');

      // Try Socket.IO first for real-time invitation
      if (isSocketConnected && isSocketAuthenticated) {
        print(
            '📱 InvitationProvider: Using Socket.IO for real-time invitation');

        SocketService.instance.sendInvitation(
          recipientId: recipientId,
          message: message,
        );

        // Create temporary invitation for immediate UI feedback
        final tempInvitation = Invitation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: SocketService.instance.currentUserId ?? '',
          recipientId: recipientId,
          message: message,
          status: 'pending',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Add to local invitations immediately
        _invitations.insert(0, tempInvitation);
        await _saveInvitationsToLocal();
        _updateBadgeCounts();
        notifyListeners();

        return true;
      } else {
        print(
            '📱 InvitationProvider: Socket.IO not available, using API fallback');

        // Try to reconnect Socket.IO for future invitations
        if (!isSocketConnected) {
          print('📱 InvitationProvider: Attempting to reconnect Socket.IO');
          await SocketService.instance.manualConnect();
        }
      }

      // Fallback to API if Socket.IO is not available
      print('📱 InvitationProvider: Sending invitation via API');
      final response = await ApiService.sendInvitation({
        'recipient_id': recipientId,
        'message': message,
      });

      if (response['success'] == true) {
        print('📱 InvitationProvider: Invitation sent successfully via API');

        // Reload invitations to update the sent section
        await loadInvitations();

        // Try to trigger a Socket.IO event for real-time updates if possible
        if (SocketService.instance.isAuthenticated) {
          print(
              '📱 InvitationProvider: Triggering Socket.IO event for real-time update');
          // Emit a custom event to notify other clients about the new invitation
          SocketService.instance.emitCustomEvent('invitation_created', {
            'invitationId': response['invitation_id'],
            'senderId': SocketService.instance.currentUserId,
            'recipientId': recipientId,
            'message': message,
          });
        }

        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to send invitation');
      }
    } catch (e) {
      print('📱 InvitationProvider: Error sending invitation: $e');
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptInvitation(String invitationId) async {
    try {
      // Try Socket.IO first for real-time response
      if (SocketService.instance.isAuthenticated) {
        SocketService.instance.respondToInvitation(
          invitationId: invitationId,
          response: 'accept',
        );

        // Update local invitation status immediately
        final index = _invitations.indexWhere((i) => i.id == invitationId);
        if (index != -1) {
          _invitations[index] = _invitations[index].copyWith(
            status: 'accepted',
            acceptedAt: DateTime.now(),
          );
          await _saveInvitationsToLocal();
          _updateBadgeCounts();
          notifyListeners();
        }

        return true;
      }

      // Fallback to API if Socket.IO is not available
      final response = await ApiService.acceptInvitation(invitationId);

      if (response['success'] == true) {
        // Update local invitation status
        final index = _invitations.indexWhere((i) => i.id == invitationId);
        if (index != -1) {
          _invitations[index] = _invitations[index].copyWith(
            status: 'accepted',
            acceptedAt: DateTime.now(),
          );
          await _saveInvitationsToLocal();
          _updateBadgeCounts();
          notifyListeners();
        }
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to accept invitation');
      }
    } catch (e) {
      print('📱 InvitationProvider: Error accepting invitation: $e');
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> declineInvitation(String invitationId) async {
    try {
      // Try Socket.IO first for real-time response
      if (SocketService.instance.isAuthenticated) {
        SocketService.instance.respondToInvitation(
          invitationId: invitationId,
          response: 'decline',
        );

        // Update local invitation status immediately
        final index = _invitations.indexWhere((i) => i.id == invitationId);
        if (index != -1) {
          _invitations[index] = _invitations[index].copyWith(
            status: 'declined',
            declinedAt: DateTime.now(),
          );
          await _saveInvitationsToLocal();
          _updateBadgeCounts();
          notifyListeners();
        }

        return true;
      }

      // Fallback to API if Socket.IO is not available
      final response = await ApiService.declineInvitation(invitationId);

      if (response['success'] == true) {
        // Update local invitation status
        final index = _invitations.indexWhere((i) => i.id == invitationId);
        if (index != -1) {
          _invitations[index] = _invitations[index].copyWith(
            status: 'declined',
            declinedAt: DateTime.now(),
          );
          await _saveInvitationsToLocal();
          _updateBadgeCounts();
          notifyListeners();
        }
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to decline invitation');
      }
    } catch (e) {
      print('📱 InvitationProvider: Error declining invitation: $e');
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteInvitation(String invitationId) async {
    try {
      final response = await ApiService.deleteInvitation(invitationId);

      if (response['success'] == true) {
        // Remove from local list
        _invitations.removeWhere((i) => i.id == invitationId);
        await _saveInvitationsToLocal();
        _updateBadgeCounts();
        notifyListeners();
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to delete invitation');
      }
    } catch (e) {
      print('📱 InvitationProvider: Error deleting invitation: $e');
      _error = 'Failed to delete invitation: $e';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void addInvitationUser(User user) {
    _invitationUsers[user.id] = user;
    notifyListeners();
  }

  void _updateBadgeCounts() {
    // Count pending received invitations (new invitations from others)
    _pendingReceivedCount =
        _invitations.where((inv) => inv.isReceived && inv.isPending()).length;

    // Count responses to sent invitations (accepted/declined by others)
    _responsesSentCount =
        _invitations.where((inv) => !inv.isReceived && !inv.isPending()).length;

    // Show badge if there are any unread invitations
    _hasUnreadInvitations =
        _pendingReceivedCount > 0 || _responsesSentCount > 0;

    print(
        '📱 InvitationProvider: Badge counts updated - Pending received: $_pendingReceivedCount, Responses sent: $_responsesSentCount, Has unread: $_hasUnreadInvitations');
  }

  void markReceivedInvitationsAsRead() {
    _pendingReceivedCount = 0;
    _hasUnreadInvitations = _responsesSentCount > 0;
    notifyListeners();
  }

  void markSentInvitationsAsRead() {
    _responsesSentCount = 0;
    _hasUnreadInvitations = _pendingReceivedCount > 0;
    notifyListeners();
  }

  void markAllInvitationsAsRead() {
    _pendingReceivedCount = 0;
    _responsesSentCount = 0;
    _hasUnreadInvitations = false;
    notifyListeners();
  }

  void _triggerInvitationReceivedNotification(Invitation invitation) {
    final sender = getInvitationUser(invitation.senderId);
    if (sender != null) {
      NotificationService.instance.showInvitationReceivedNotification(
        senderUsername: sender.username,
        message: invitation.message,
        invitationId: invitation.id,
      );
    }
  }

  void _triggerInvitationResponseNotification(
      String invitationId, String status) {
    try {
      final invitation = _invitations.firstWhere(
        (i) => i.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      final otherUser = getInvitationUser(invitation.recipientId);
      if (otherUser != null) {
        NotificationService.instance.showInvitationResponseNotification(
          username: otherUser.username,
          status: status,
          invitationId: invitationId,
        );
      }
    } catch (e) {
      print(
          '📱 InvitationProvider: Error triggering notification for invitation $invitationId: $e');
      // Don't throw the error - just log it and continue
    }
  }

  void _updateUserOnlineStatus(
      String userId, bool isOnline, DateTime? lastSeen) {
    if (_invitationUsers.containsKey(userId)) {
      _invitationUsers[userId] = _invitationUsers[userId]!.copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );
      print(
          '📱 InvitationProvider: Updated online status for user $userId - Online: $isOnline');
      notifyListeners();
    }
  }

  void updateUserOnlineStatus(String userId, bool isOnline) {
    _updateUserOnlineStatus(userId, isOnline, isOnline ? null : DateTime.now());
  }
}
