import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../../../shared/models/user.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/airnotifier_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/indicator_service.dart';
import '../../../core/utils/guid_generator.dart';
import '../../../core/services/se_shared_preference_service.dart';

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
  List<Invitation> get sentInvitations {
    final currentSessionId = _sessionService.currentSessionId;
    print('📱 InvitationProvider: Getting sent invitations');
    print('📱 InvitationProvider: Current session ID: $currentSessionId');
    print('📱 InvitationProvider: Total invitations: ${_invitations.length}');

    final sent = _invitations.where((inv) {
      final matches = inv.fromUserId == currentSessionId;
      print(
          '📱 InvitationProvider: Invitation ${inv.id}: fromUserId=${inv.fromUserId}, matches=$matches');
      return matches;
    }).toList();

    print('📱 InvitationProvider: Found ${sent.length} sent invitations');
    return sent;
  }

  // Get pending invitations
  List<Invitation> get pendingInvitations => _invitations
      .where((inv) => inv.status == InvitationStatus.pending)
      .toList();

  InvitationProvider() {
    _loadInvitations();
    // Connect to SimpleNotificationService for real-time updates
    SimpleNotificationService.instance.setInvitationProvider(this);
  }

  Future<void> _loadInvitations() async {
    try {
      _isLoading = true;
      notifyListeners();

      final invitationsJson = await _prefsService.getJsonList('invitations');
      print(
          '📱 InvitationProvider: Loading invitations from storage: ${invitationsJson?.length ?? 0} found');

      _invitations =
          invitationsJson?.map((json) => Invitation.fromJson(json)).toList() ??
              [];

      print('📱 InvitationProvider: Loaded ${_invitations.length} invitations');
      print(
          '📱 InvitationProvider: Sent invitations: ${sentInvitations.length}');
      print(
          '📱 InvitationProvider: Received invitations: ${receivedInvitations.length}');

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error loading invitations: $e');
      _isLoading = false;
      _error = 'Failed to load invitations: $e';
      notifyListeners();
    }
  }

  // Public method to refresh invitations (called by SimpleNotificationService)
  Future<void> refreshInvitations() async {
    await _loadInvitations();
  }

  // Save chat to SharedPreferences
  Future<void> _saveChat(Chat chat) async {
    try {
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final existingIndex = chatsJson.indexWhere((c) => c['id'] == chat.id);

      if (existingIndex != -1) {
        chatsJson[existingIndex] = chat.toJson();
      } else {
        chatsJson.add(chat.toJson());
      }

      await _prefsService.setJsonList('chats', chatsJson);
      print('📱 InvitationProvider: ✅ Chat saved to SharedPreferences');
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error saving chat: $e');
    }
  }

  // Create initial welcome message
  Future<void> _createInitialMessage(
      String chatId, Invitation invitation) async {
    try {
      final initialMessage = Message(
        id: GuidGenerator.generateShortId(),
        chatId: chatId,
        senderId: 'system',
        content:
            'Welcome! You are now connected with ${invitation.fromUsername}. Start chatting!',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'sent',
      );

      // Save message to SharedPreferences
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      messagesJson.add(initialMessage.toJson());
      await _prefsService.setJsonList('messages', messagesJson);

      print(
          '📱 InvitationProvider: ✅ Initial message created for chat: $chatId');
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error creating initial message: $e');
    }
  }

  // Create local notification for invitation actions
  Future<void> _createLocalNotification({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingNotificationsJson =
          await prefsService.getJsonList('notifications') ?? [];

      final notification = {
        'id': 'invitation_${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
      };

      existingNotificationsJson.add(notification);
      await prefsService.setJsonList(
          'notifications', existingNotificationsJson);

      // Trigger indicator for new notification
      IndicatorService().setNewNotification();

      print('📱 InvitationProvider: ✅ Local notification created: $title');
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error creating local notification: $e');
    }
  }

  Future<void> _saveInvitations() async {
    try {
      final invitationsJson = _invitations.map((inv) => inv.toJson()).toList();
      print(
          '📱 InvitationProvider: Saving ${invitationsJson.length} invitations to storage');
      await _prefsService.setJsonList('invitations', invitationsJson);
      print('📱 InvitationProvider: ✅ Invitations saved successfully');
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error saving invitations: $e');
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

      // Create local notification for invitation sent
      await _createLocalNotification(
        title: 'Invitation Sent',
        body: 'Invitation sent to ${invitation.toUsername}',
        type: 'invitation_sent',
        data: {
          'invitationId': invitation.id,
          'toUsername': invitation.toUsername,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();

      // Trigger indicator for new invitation
      IndicatorService().setNewInvitation();

      return true;
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      return false;
    }
  }

  // New method for sending invitation by session ID
  Future<bool> sendInvitationBySessionId(String sessionId,
      {String? displayName}) async {
    try {
      final currentSession = _sessionService.currentSession;
      if (currentSession == null) {
        _error = 'No active session';
        notifyListeners();
        return false;
      }

      // Validate session ID format
      if (!GuidGenerator.isValidSessionGuid(sessionId)) {
        _error = 'Invalid session ID format';
        notifyListeners();
        return false;
      }

      // Check if it's the current user's session ID
      if (sessionId == currentSession.sessionId) {
        _error = 'Cannot invite yourself';
        notifyListeners();
        return false;
      }

      // Check if invitation already exists
      final existingInvitation = _invitations.firstWhere(
        (inv) =>
            inv.fromUserId == currentSession.sessionId &&
            inv.toUserId == sessionId &&
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
        toUserId: sessionId,
        toUsername: displayName ?? 'Unknown User',
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
      );

      _invitations.add(invitation);
      print(
          '📱 InvitationProvider: Added invitation to list: ${invitation.id}');
      print(
          '📱 InvitationProvider: Current invitations count: ${_invitations.length}');
      print(
          '📱 InvitationProvider: Sent invitations count: ${sentInvitations.length}');

      await _saveInvitations();
      print('📱 InvitationProvider: Saved invitations to storage');

      // Send push notification to the other user
      await _sendInvitationNotification(invitation);

      // Create local notification for invitation sent
      await _createLocalNotification(
        title: 'Invitation Sent',
        body: 'Invitation sent to ${invitation.toUsername}',
        type: 'invitation_sent',
        data: {
          'invitationId': invitation.id,
          'toUsername': invitation.toUsername,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();

      // Trigger indicator for new invitation
      IndicatorService().setNewInvitation();

      return true;
    } catch (e) {
      _error = 'Failed to send invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Accepting invitation: $invitationId');

      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Invitation is not pending';
        notifyListeners();
        return false;
      }

      print(
          '📱 InvitationProvider: Found invitation: ${invitation.fromUsername} -> ${invitation.toUsername}');

      // Generate chat GUID for the new conversation
      final chatGuid = GuidGenerator.generateGuid();
      print('📱 InvitationProvider: Generated chat GUID: $chatGuid');

      // Create chat conversation
      final chat = Chat(
        id: chatGuid,
        user1Id: invitation.fromUserId,
        user2Id: invitation.toUserId,
        user1DisplayName: invitation.fromUsername,
        user2DisplayName: invitation.toUsername,
        status: 'active',
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save chat to SharedPreferences
      await _saveChat(chat);
      print('📱 InvitationProvider: ✅ Chat conversation created: $chatGuid');

      // Create initial welcome message
      await _createInitialMessage(chatGuid, invitation);

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
        print('📱 InvitationProvider: ✅ Invitation status updated to accepted');
      }

      // Send acceptance notification with chat GUID (don't let this fail the whole operation)
      try {
        await _sendAcceptanceNotification(updatedInvitation, chatGuid);
      } catch (e) {
        print(
            '📱 InvitationProvider: ⚠️ Failed to send acceptance notification: $e');
        // Don't fail the whole operation if notification fails
      }

      // Create local notification for invitation accepted
      await _createLocalNotification(
        title: 'Invitation Accepted',
        body: 'You accepted invitation from ${invitation.fromUsername}',
        type: 'invitation_accepted',
        data: {
          'invitationId': invitation.id,
          'fromUsername': invitation.fromUsername,
          'chatId': chatGuid,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();

      // Trigger indicator for new chat
      IndicatorService().setNewChat();

      print('📱 InvitationProvider: ✅ Invitation accepted successfully');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error accepting invitation: $e');
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> declineInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Declining invitation: $invitationId');

      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Invitation is not pending';
        notifyListeners();
        return false;
      }

      print(
          '📱 InvitationProvider: Found invitation: ${invitation.fromUsername} -> ${invitation.toUsername}');

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
        print('📱 InvitationProvider: ✅ Invitation status updated to declined');
      }

      // Send decline notification (don't let this fail the whole operation)
      try {
        await _sendDeclineNotification(updatedInvitation);
      } catch (e) {
        print(
            '📱 InvitationProvider: ⚠️ Failed to send decline notification: $e');
        // Don't fail the whole operation if notification fails
      }

      // Create local notification for invitation declined
      await _createLocalNotification(
        title: 'Invitation Declined',
        body: 'You declined invitation from ${invitation.fromUsername}',
        type: 'invitation_declined',
        data: {
          'invitationId': invitation.id,
          'fromUsername': invitation.fromUsername,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();
      print('📱 InvitationProvider: ✅ Invitation declined successfully');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error declining invitation: $e');
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
          'senderId': invitation.fromUserId, // Changed from fromUserId
          'senderName': invitation.fromUsername, // Changed from fromUsername
        },
      );
    } catch (e) {
      print('Failed to send invitation notification: $e');
    }
  }

  Future<void> _sendAcceptanceNotification(
      Invitation invitation, String chatGuid) async {
    try {
      // Check if the target session ID is valid
      if (invitation.fromUserId.isEmpty || invitation.fromUserId == 'null') {
        print(
            '⚠️ InvitationProvider: Cannot send acceptance notification - invalid fromUserId: ${invitation.fromUserId}');
        return;
      }

      print(
          '📱 InvitationProvider: Sending acceptance notification to: ${invitation.fromUserId} with chat GUID: $chatGuid');

      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.fromUserId,
        title: 'Invitation Accepted',
        body: '${invitation.toUsername} accepted your invitation',
        data: {
          'type': 'invitation_accepted',
          'invitationId': invitation.id,
          'toUserId': invitation.toUserId,
          'toUsername': invitation.toUsername,
          'chatGuid': chatGuid, // Include chat GUID for sender
        },
      );

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Acceptance notification sent successfully with chat GUID: $chatGuid');
      } else {
        print(
            '📱 InvitationProvider: ❌ Failed to send acceptance notification');
      }
    } catch (e) {
      print(
          '📱 InvitationProvider: ❌ Error sending acceptance notification: $e');
    }
  }

  Future<void> _sendDeclineNotification(Invitation invitation) async {
    try {
      // Check if the target session ID is valid
      if (invitation.fromUserId.isEmpty || invitation.fromUserId == 'null') {
        print(
            '⚠️ InvitationProvider: Cannot send decline notification - invalid fromUserId: ${invitation.fromUserId}');
        return;
      }

      print(
          '📱 InvitationProvider: Sending decline notification to: ${invitation.fromUserId}');

      final success =
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

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Decline notification sent successfully');
      } else {
        print('📱 InvitationProvider: ❌ Failed to send decline notification');
      }
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error sending decline notification: $e');
    }
  }

  Future<void> _sendCancellationNotification(Invitation invitation) async {
    try {
      // Check if the target session ID is valid
      if (invitation.toUserId.isEmpty || invitation.toUserId == 'null') {
        print(
            '⚠️ InvitationProvider: Cannot send cancellation notification - invalid toUserId: ${invitation.toUserId}');
        return;
      }

      print(
          '📱 InvitationProvider: Sending cancellation notification to: ${invitation.toUserId}');

      final success =
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

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Cancellation notification sent successfully');
      } else {
        print(
            '📱 InvitationProvider: ❌ Failed to send cancellation notification');
      }
    } catch (e) {
      print(
          '📱 InvitationProvider: ❌ Error sending cancellation notification: $e');
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
