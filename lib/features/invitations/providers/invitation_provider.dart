import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/services/notification_service.dart';

class InvitationProvider extends ChangeNotifier {
  List<Invitation> _invitations = [];
  final Map<String, User> _invitationUsers = {};
  bool _isLoading = false;
  String? _error;
  int _pendingReceivedCount = 0;
  int _responsesSentCount = 0;
  bool _hasUnreadInvitations = false;

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingReceivedCount => _pendingReceivedCount;
  int get responsesSentCount => _responsesSentCount;
  int get totalBadgeCount => _pendingReceivedCount + _responsesSentCount;
  bool get hasUnreadInvitations => _hasUnreadInvitations;

  User? getInvitationUser(String userId) {
    return _invitationUsers[userId];
  }

  InvitationProvider() {
    _setupWebSocket();
    _loadInvitationsFromLocal();
  }

  void _setupWebSocket() {
    WebSocketService.instance.onMessageReceived = _handleWebSocketMessage;
    WebSocketService.instance.onConnected = _handleWebSocketConnected;
    WebSocketService.instance.onDisconnected = _handleWebSocketDisconnected;
    WebSocketService.instance.onError = _handleWebSocketError;
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    if (data['type'] == 'invitation_received') {
      final invitationData = data['invitation'] as Map<String, dynamic>;
      final invitation = Invitation.fromJson(invitationData);

      // Store user data if available
      if (data['sender'] != null) {
        final senderData = data['sender'] as Map<String, dynamic>;
        final sender = User.fromJson(senderData);
        // Set default online status to true until WebSocket provides real data
        _invitationUsers[sender.id] = sender.copyWith(isOnline: true);
      }

      _addInvitation(invitation);

      // Trigger local notification
      _triggerInvitationReceivedNotification(invitation);
    } else if (data['type'] == 'invitation_response') {
      final invitationData = data['invitation'] as Map<String, dynamic>;
      final status = invitationData['status'] as String;
      final invitationId = invitationData['id'] as String;

      // Update local invitation status
      final index = _invitations.indexWhere((i) => i.id == invitationId);
      if (index != -1) {
        _invitations[index] = _invitations[index].copyWith(
          status: status,
          acceptedAt: status == 'accepted' ? DateTime.now() : null,
          declinedAt: status == 'declined' ? DateTime.now() : null,
        );
        _saveInvitationsToLocal();
        _updateBadgeCounts();
        notifyListeners();
      }

      // Trigger local notification for response
      _triggerInvitationResponseNotification(invitationId, status);
    } else if (data['type'] == 'user_online_status') {
      final userId = data['user_id'] as String;
      final isOnline = data['is_online'] as bool;
      final lastSeen =
          data['last_seen'] != null ? DateTime.parse(data['last_seen']) : null;

      _updateUserOnlineStatus(userId, isOnline, lastSeen);
    }
  }

  void _handleWebSocketConnected() {
    print('🔌 InvitationProvider: WebSocket connected');
  }

  void _handleWebSocketDisconnected() {
    print('🔌 InvitationProvider: WebSocket disconnected');
  }

  void _handleWebSocketError(String error) {
    print('🔌 InvitationProvider: WebSocket error: $error');
    // Don't set this as a blocking error - WebSocket is optional
    // _error = 'WebSocket error: $error';
    // notifyListeners();
  }

  void _addInvitation(Invitation invitation) {
    _invitations.insert(0, invitation);
    _saveInvitationsToLocal();
    _updateBadgeCounts();
    notifyListeners();
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
      final response = await ApiService.sendInvitation({
        'recipient_id': recipientId,
        'message': message,
      });

      if (response['success'] == true) {
        print('📱 InvitationProvider: Invitation sent successfully');

        // Reload invitations to update the sent section
        await loadInvitations();

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
    _pendingReceivedCount =
        _invitations.where((inv) => inv.isReceived && inv.isPending()).length;
    _responsesSentCount =
        _invitations.where((inv) => !inv.isReceived && !inv.isPending()).length;
    _hasUnreadInvitations =
        _pendingReceivedCount > 0 || _responsesSentCount > 0;
    print(
        '📱 InvitationProvider: Badge counts updated - Pending received: $_pendingReceivedCount, Responses sent: $_responsesSentCount');
  }

  void markReceivedInvitationsAsRead() {
    _pendingReceivedCount = 0;
    _updateBadgeCounts();
    notifyListeners();
  }

  void markSentInvitationsAsRead() {
    _responsesSentCount = 0;
    _updateBadgeCounts();
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
    final invitation = _invitations.firstWhere((i) => i.id == invitationId);
    final otherUser = getInvitationUser(invitation.recipientId);
    if (otherUser != null) {
      NotificationService.instance.showInvitationResponseNotification(
        username: otherUser.username,
        status: status,
        invitationId: invitationId,
      );
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
