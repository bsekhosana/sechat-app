import 'package:flutter/foundation.dart';
import '../../../core/services/session_messenger_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import 'dart:async';

class SessionInvitationProvider extends ChangeNotifier {
  final SessionMessengerService _messenger = SessionMessengerService.instance;
  final NotificationService _notificationService = NotificationService.instance;

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
    _setupMessengerCallbacks();
    loadInvitationsFromMessenger();
  }

  void _setupMessengerCallbacks() {
    _messenger.onInvitationReceived = _handleInvitationReceived;
    _messenger.onInvitationResponse = _handleInvitationResponse;
    _messenger.onContactOnline = _handleContactOnline;
    _messenger.onContactOffline = _handleContactOffline;
    _messenger.onError = _handleMessengerError;
  }

  // Send invitation using Session Messenger
  Future<void> sendInvitation({
    required String recipientId,
    String? displayName,
    String message = 'Would you like to connect?',
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Send invitation via Session Messenger
      final sessionInvitation = await _messenger.sendInvitation(
        recipientId: recipientId,
        message: message,
        metadata: {
          'displayName': displayName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Create local invitation record
      final invitation = Invitation(
        id: sessionInvitation.id,
        senderId: _messenger.currentSessionId ?? '',
        recipientId: recipientId,
        message: message,
        status: 'pending',
        createdAt: sessionInvitation.createdAt,
        updatedAt: sessionInvitation.createdAt,
      );

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

      _invitationUsers[recipientId] = user;

      // Show notification
      await _notificationService.showInvitationReceivedNotification(
        senderUsername: _messenger.currentName ?? 'Anonymous',
        message: 'Invitation sent successfully',
        invitationId: invitation.id,
      );

      print('📱 SessionInvitationProvider: Invitation sent: $recipientId');
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error sending invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Accept invitation
  Future<void> acceptInvitation(String invitationId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Accept via Session Messenger
      await _messenger.acceptInvitation(invitationId);

      // Update local invitation status
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (invitationIndex != -1) {
        final invitation = _invitations[invitationIndex];
        _invitations[invitationIndex] = invitation.copyWith(
          status: 'accepted',
          updatedAt: DateTime.now(),
        );
      }

      // Update user status
      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);
      final user = _invitationUsers[invitation.senderId];
      if (user != null) {
        _invitationUsers[invitation.senderId] = user.copyWith(
          invitationStatus: 'accepted',
        );
      }

      // Show notification
      await _notificationService.showInvitationResponseNotification(
        username: user?.username ?? 'Anonymous User',
        status: 'accepted',
        invitationId: invitationId,
      );

      print('📱 SessionInvitationProvider: Invitation accepted: $invitationId');
    } catch (e) {
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error accepting invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Decline invitation
  Future<void> declineInvitation(String invitationId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Decline via Session Messenger
      await _messenger.declineInvitation(invitationId);

      // Update local invitation status
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (invitationIndex != -1) {
        final invitation = _invitations[invitationIndex];
        _invitations[invitationIndex] = invitation.copyWith(
          status: 'declined',
          updatedAt: DateTime.now(),
        );
      }

      // Show notification
      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);
      final user = _invitationUsers[invitation.senderId];
      await _notificationService.showInvitationResponseNotification(
        username: user?.username ?? 'Anonymous User',
        status: 'declined',
        invitationId: invitationId,
      );

      print('📱 SessionInvitationProvider: Invitation declined: $invitationId');
    } catch (e) {
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      print('📱 SessionInvitationProvider: Error declining invitation: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load invitations from Session Messenger
  Future<void> loadInvitationsFromMessenger() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Get pending invitations (received)
      final pendingInvitations = _messenger.getPendingInvitations();
      for (final sessionInvitation in pendingInvitations) {
        final invitation = Invitation(
          id: sessionInvitation.id,
          senderId: sessionInvitation.senderId,
          recipientId: sessionInvitation.recipientId,
          message: sessionInvitation.message,
          status: sessionInvitation.status,
          createdAt: sessionInvitation.createdAt,
          updatedAt: sessionInvitation.createdAt,
        );

        if (!_invitations.any((inv) => inv.id == invitation.id)) {
          _invitations.add(invitation);
        }

        // Create user object
        final user = User(
          id: sessionInvitation.senderId,
          username: sessionInvitation.senderName,
          profilePicture: null,
          isOnline: false,
          lastSeen: DateTime.now(),
          alreadyInvited: true,
          invitationStatus: sessionInvitation.status,
        );

        _invitationUsers[sessionInvitation.senderId] = user;
      }

      // Get sent invitations
      final sentInvitations = _messenger.getSentInvitations();
      for (final sessionInvitation in sentInvitations) {
        final invitation = Invitation(
          id: sessionInvitation.id,
          senderId: sessionInvitation.senderId,
          recipientId: sessionInvitation.recipientId,
          message: sessionInvitation.message,
          status: sessionInvitation.status,
          createdAt: sessionInvitation.createdAt,
          updatedAt: sessionInvitation.createdAt,
        );

        if (!_invitations.any((inv) => inv.id == invitation.id)) {
          _invitations.add(invitation);
        }

        // Create user object for recipient
        final user = User(
          id: sessionInvitation.recipientId,
          username: 'Anonymous User',
          profilePicture: null,
          isOnline: false,
          lastSeen: DateTime.now(),
          alreadyInvited: true,
          invitationStatus: sessionInvitation.status,
        );

        _invitationUsers[sessionInvitation.recipientId] = user;
      }

      print(
          '📱 SessionInvitationProvider: Loaded ${_invitations.length} invitations');
    } catch (e) {
      _error = 'Failed to load invitations: $e';
      print('📱 SessionInvitationProvider: Error loading invitations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Event handlers
  void _handleInvitationReceived(SessionInvitation sessionInvitation) {
    try {
      print(
          '📱 SessionInvitationProvider: Invitation received: ${sessionInvitation.id}');

      // Create local invitation record
      final invitation = Invitation(
        id: sessionInvitation.id,
        senderId: sessionInvitation.senderId,
        recipientId: sessionInvitation.recipientId,
        message: sessionInvitation.message,
        status: sessionInvitation.status,
        createdAt: sessionInvitation.createdAt,
        updatedAt: sessionInvitation.createdAt,
      );

      if (!_invitations.any((inv) => inv.id == invitation.id)) {
        _invitations.add(invitation);
      }

      // Create user object
      final user = User(
        id: sessionInvitation.senderId,
        username: sessionInvitation.senderName,
        profilePicture: null,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: sessionInvitation.status,
      );

      _invitationUsers[sessionInvitation.senderId] = user;

      // Show notification
      _notificationService.showInvitationReceivedNotification(
        senderUsername: sessionInvitation.senderName,
        message: sessionInvitation.message,
        invitationId: sessionInvitation.id,
      );

      notifyListeners();
    } catch (e) {
      print(
          '📱 SessionInvitationProvider: Error handling invitation received: $e');
    }
  }

  void _handleInvitationResponse(SessionInvitation sessionInvitation) {
    try {
      print(
          '📱 SessionInvitationProvider: Invitation response: ${sessionInvitation.id}');

      // Update local invitation
      final invitationIndex =
          _invitations.indexWhere((inv) => inv.id == sessionInvitation.id);
      if (invitationIndex != -1) {
        final invitation = _invitations[invitationIndex];
        _invitations[invitationIndex] = invitation.copyWith(
          status: sessionInvitation.status,
          updatedAt: DateTime.now(),
        );
      }

      // Update user status
      final user = _invitationUsers[sessionInvitation.recipientId];
      if (user != null) {
        _invitationUsers[sessionInvitation.recipientId] = user.copyWith(
          invitationStatus: sessionInvitation.status,
        );
      }

      // Show notification
      _notificationService.showInvitationResponseNotification(
        username: user?.username ?? 'Anonymous User',
        status: sessionInvitation.status,
        invitationId: sessionInvitation.id,
      );

      notifyListeners();
    } catch (e) {
      print(
          '📱 SessionInvitationProvider: Error handling invitation response: $e');
    }
  }

  void _handleContactOnline(String sessionId) {
    final user = _invitationUsers[sessionId];
    if (user != null) {
      _invitationUsers[sessionId] = user.copyWith(isOnline: true);
      notifyListeners();
    }
  }

  void _handleContactOffline(String sessionId) {
    final user = _invitationUsers[sessionId];
    if (user != null) {
      _invitationUsers[sessionId] = user.copyWith(
        isOnline: false,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void _handleMessengerError(String error) {
    _error = error;
    notifyListeners();
    print('📱 SessionInvitationProvider: Messenger error: $error');
  }

  // Public methods for UI compatibility
  Future<void> loadInvitations() async {
    await loadInvitationsFromMessenger();
  }

  void markReceivedInvitationsAsRead() {
    // All invitations are considered read in real-time system
    notifyListeners();
  }

  void markSentInvitationsAsRead() {
    // All invitations are considered read in real-time system
    notifyListeners();
  }

  void setOnInvitationsScreen(bool isOnScreen) {
    // This method is for UI state tracking
    notifyListeners();
  }

  bool get hasUnreadInvitations {
    // In real-time system, all invitations are considered read
    return false;
  }

  Future<bool> sendInvitationLegacy(String recipientId) async {
    try {
      await sendInvitation(recipientId: recipientId);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool isUserInvited(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'accepted');
  }

  bool isUserQueued(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'pending');
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset provider state
  void reset() {
    _invitations.clear();
    _invitationUsers.clear();
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
