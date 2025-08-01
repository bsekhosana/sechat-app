import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../../../shared/models/user.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/airnotifier_service.dart';

enum InvitationStatus {
  pending,
  accepted,
  declined,
  cancelled,
}

class Invitation {
  final String id;
  final String fromUserId;
  final String fromUsername;
  final String toUserId;
  final String toUsername;
  final InvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  Invitation({
    required this.id,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.toUsername,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'toUserId': toUserId,
      'toUsername': toUsername,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
    };
  }

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'],
      fromUserId: json['fromUserId'],
      fromUsername: json['fromUsername'],
      toUserId: json['toUserId'],
      toUsername: json['toUsername'],
      status: InvitationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => InvitationStatus.pending,
      ),
      createdAt: DateTime.parse(json['createdAt']),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'])
          : null,
    );
  }
}

class InvitationProvider extends ChangeNotifier {
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();
  final SeSessionService _sessionService = SeSessionService();

  List<Invitation> _invitations = [];
  bool _isLoading = false;
  String? _error;

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get invitations for current user
  List<Invitation> get receivedInvitations => _invitations
      .where((inv) => inv.toUserId == _sessionService.currentSessionId)
      .toList();

  // Get invitations sent by current user
  List<Invitation> get sentInvitations => _invitations
      .where((inv) => inv.fromUserId == _sessionService.currentSessionId)
      .toList();

  // Get pending invitations
  List<Invitation> get pendingInvitations => _invitations
      .where((inv) => inv.status == InvitationStatus.pending)
      .toList();

  InvitationProvider() {
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    try {
      _isLoading = true;
      notifyListeners();

      final invitationsJson = await _prefsService.getJsonList('invitations');
      _invitations =
          invitationsJson?.map((json) => Invitation.fromJson(json)).toList() ??
              [];

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load invitations: $e';
      notifyListeners();
    }
  }

  Future<void> _saveInvitations() async {
    try {
      final invitationsJson = _invitations.map((inv) => inv.toJson()).toList();
      await _prefsService.setJsonList('invitations', invitationsJson);
    } catch (e) {
      _error = 'Failed to save invitations: $e';
      notifyListeners();
    }
  }

  Future<bool> sendInvitation(String toUserId, {String? displayName}) async {
    try {
      final currentSession = _sessionService.currentSession;
      if (currentSession == null) {
        _error = 'No active session';
        notifyListeners();
        return false;
      }

      // Check if invitation already exists
      final existingInvitation = _invitations.firstWhere(
        (inv) =>
            inv.fromUserId == currentSession.sessionId &&
            inv.toUserId == toUserId &&
            inv.status == InvitationStatus.pending,
        orElse: () => Invitation(
          id: '',
          fromUserId: '',
          fromUsername: '',
          toUserId: '',
          toUsername: '',
          status: InvitationStatus.pending,
          createdAt: DateTime.now(),
        ),
      );

      if (existingInvitation.id.isNotEmpty) {
        _error = 'Invitation already sent';
        notifyListeners();
        return false;
      }

      // Create new invitation
      final invitation = Invitation(
        id: _generateInvitationId(),
        fromUserId: currentSession.sessionId,
        fromUsername: currentSession.displayName,
        toUserId: toUserId,
        toUsername: displayName ?? 'Unknown User',
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
      );

      _invitations.add(invitation);
      await _saveInvitations();

      // Send notification
      await _sendInvitationNotification(invitation);

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptInvitation(String invitationId) async {
    try {
      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Invitation is not pending';
        notifyListeners();
        return false;
      }

      // Update invitation status
      final updatedInvitation = Invitation(
        id: invitation.id,
        fromUserId: invitation.fromUserId,
        fromUsername: invitation.fromUsername,
        toUserId: invitation.toUserId,
        toUsername: invitation.toUsername,
        status: InvitationStatus.accepted,
        createdAt: invitation.createdAt,
        respondedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
        await _saveInvitations();
      }

      // Send acceptance notification
      await _sendAcceptanceNotification(updatedInvitation);

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> declineInvitation(String invitationId) async {
    try {
      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Invitation is not pending';
        notifyListeners();
        return false;
      }

      // Update invitation status
      final updatedInvitation = Invitation(
        id: invitation.id,
        fromUserId: invitation.fromUserId,
        fromUsername: invitation.fromUsername,
        toUserId: invitation.toUserId,
        toUsername: invitation.toUsername,
        status: InvitationStatus.declined,
        createdAt: invitation.createdAt,
        respondedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
        await _saveInvitations();
      }

      // Send decline notification
      await _sendDeclineNotification(updatedInvitation);

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelInvitation(String invitationId) async {
    try {
      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Invitation is not pending';
        notifyListeners();
        return false;
      }

      // Update invitation status
      final updatedInvitation = Invitation(
        id: invitation.id,
        fromUserId: invitation.fromUserId,
        fromUsername: invitation.fromUsername,
        toUserId: invitation.toUserId,
        toUsername: invitation.toUsername,
        status: InvitationStatus.cancelled,
        createdAt: invitation.createdAt,
        respondedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
        await _saveInvitations();
      }

      // Send cancellation notification
      await _sendCancellationNotification(updatedInvitation);

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to cancel invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _sendInvitationNotification(Invitation invitation) async {
    try {
      await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.toUserId,
        title: 'New Invitation',
        body: '${invitation.fromUsername} wants to connect with you',
        data: {
          'type': 'invitation',
          'invitationId': invitation.id,
          'fromUserId': invitation.fromUserId,
          'fromUsername': invitation.fromUsername,
        },
      );
    } catch (e) {
      print('Failed to send invitation notification: $e');
    }
  }

  Future<void> _sendAcceptanceNotification(Invitation invitation) async {
    try {
      await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.fromUserId,
        title: 'Invitation Accepted',
        body: '${invitation.toUsername} accepted your invitation',
        data: {
          'type': 'invitation_accepted',
          'invitationId': invitation.id,
          'toUserId': invitation.toUserId,
          'toUsername': invitation.toUsername,
        },
      );
    } catch (e) {
      print('Failed to send acceptance notification: $e');
    }
  }

  Future<void> _sendDeclineNotification(Invitation invitation) async {
    try {
      await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.fromUserId,
        title: 'Invitation Declined',
        body: '${invitation.toUsername} declined your invitation',
        data: {
          'type': 'invitation_declined',
          'invitationId': invitation.id,
          'toUserId': invitation.toUserId,
          'toUsername': invitation.toUsername,
        },
      );
    } catch (e) {
      print('Failed to send decline notification: $e');
    }
  }

  Future<void> _sendCancellationNotification(Invitation invitation) async {
    try {
      await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.toUserId,
        title: 'Invitation Cancelled',
        body: '${invitation.fromUsername} cancelled their invitation',
        data: {
          'type': 'invitation_cancelled',
          'invitationId': invitation.id,
          'fromUserId': invitation.fromUserId,
          'fromUsername': invitation.fromUsername,
        },
      );
    } catch (e) {
      print('Failed to send cancellation notification: $e');
    }
  }

  String _generateInvitationId() {
    return 'inv_${DateTime.now().millisecondsSinceEpoch}_${_sessionService.currentSessionId?.hashCode ?? 0}';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearAllData() {
    _invitations.clear();
    _error = null;
    notifyListeners();
  }
}
