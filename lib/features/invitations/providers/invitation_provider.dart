import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/airnotifier_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/indicator_service.dart';
import '../../../core/utils/guid_generator.dart';

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
      'status': status.toString().split('.').last,
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
        (e) => e.toString().split('.').last == json['status'],
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

  // Get chats from SharedPreferences
  Future<List<Chat>> getChats() async {
    try {
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      return chatsJson.map((json) => Chat.fromJson(json)).toList();
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error loading chats: $e');
      return [];
    }
  }

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

      // Check for existing invitations in all directions
      final existingInvitation = _invitations.firstWhere(
        (inv) =>
            (inv.fromUserId == currentSession.sessionId &&
                inv.toUserId == sessionId) ||
            (inv.fromUserId == sessionId &&
                inv.toUserId == currentSession.sessionId),
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
        // Check the status of the existing invitation
        if (existingInvitation.status == InvitationStatus.pending) {
          if (existingInvitation.fromUserId == currentSession.sessionId) {
            _error = 'Invitation already sent to this user';
          } else {
            _error = 'You already have a pending invitation from this user';
          }
        } else if (existingInvitation.status == InvitationStatus.accepted) {
          _error = 'You are already connected with this user';
        } else if (existingInvitation.status == InvitationStatus.declined) {
          if (existingInvitation.fromUserId == currentSession.sessionId) {
            _error = 'Your invitation was declined by this user';
          } else {
            _error = 'You previously declined an invitation from this user';
          }
        } else if (existingInvitation.status == InvitationStatus.cancelled) {
          _error = 'Previous invitation was cancelled';
        }

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
      final notificationSuccess = await _sendInvitationNotification(invitation);

      if (!notificationSuccess) {
        _error =
            'Failed to send invitation notification. Please check your internet connection and try again.';
        notifyListeners();
        return false;
      }

      // Also send encrypted version for enhanced security
      try {
        await _sendEncryptedInvitationNotification(invitation);
      } catch (e) {
        print(
            '📱 InvitationProvider: ⚠️ Failed to send encrypted invitation: $e');
        // Don't fail the whole operation if encrypted notification fails
      }

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

      // Send acceptance notification with chat GUID - CRITICAL: Must succeed for invitation to be accepted
      final notificationSuccess =
          await _sendAcceptanceNotification(updatedInvitation, chatGuid);

      if (!notificationSuccess) {
        print(
            '📱 InvitationProvider: ❌ Failed to send acceptance notification - reverting invitation acceptance');

        // Revert the invitation status back to pending
        final revertedInvitation = Invitation(
          id: invitation.id,
          fromUserId: invitation.fromUserId,
          fromUsername: invitation.fromUsername,
          toUserId: invitation.toUserId,
          toUsername: invitation.toUsername,
          status: InvitationStatus.pending,
          createdAt: invitation.createdAt,
          respondedAt: null,
        );

        final index = _invitations.indexWhere((inv) => inv.id == invitationId);
        if (index != -1) {
          _invitations[index] = revertedInvitation;
          await _saveInvitations();
          print(
              '📱 InvitationProvider: ✅ Invitation status reverted to pending');
        }

        // Delete the created chat since invitation failed
        await _deleteChat(chatGuid);
        print(
            '📱 InvitationProvider: ✅ Chat deleted due to notification failure');

        _error =
            'Unable to reach the invitation sender. They may be offline or have notifications disabled. Please try again later.';
        notifyListeners();
        return false;
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

      // Send decline notification - CRITICAL: Must succeed for invitation to be declined
      final notificationSuccess =
          await _sendDeclineNotification(updatedInvitation);

      if (!notificationSuccess) {
        print(
            '📱 InvitationProvider: ❌ Failed to send decline notification - reverting invitation decline');

        // Revert the invitation status back to pending
        final revertedInvitation = Invitation(
          id: invitation.id,
          fromUserId: invitation.fromUserId,
          fromUsername: invitation.fromUsername,
          toUserId: invitation.toUserId,
          toUsername: invitation.toUsername,
          status: InvitationStatus.pending,
          createdAt: invitation.createdAt,
          respondedAt: null,
        );

        final index = _invitations.indexWhere((inv) => inv.id == invitationId);
        if (index != -1) {
          _invitations[index] = revertedInvitation;
          await _saveInvitations();
          print(
              '📱 InvitationProvider: ✅ Invitation status reverted to pending');
        }

        _error =
            'Unable to reach the invitation sender. They may be offline or have notifications disabled. Please try again later.';
        notifyListeners();
        return false;
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

  Future<bool> _sendInvitationNotification(Invitation invitation) async {
    try {
      print(
          '📱 InvitationProvider: Sending invitation notification to: ${invitation.toUserId}');
      print('📱 InvitationProvider: Invitation data: ${invitation.toJson()}');

      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: invitation.toUserId,
        title: 'New Invitation',
        body: '${invitation.fromUsername} wants to connect with you',
        data: {
          'type': 'invitation',
          'invitationId': invitation.id,
          'senderId': invitation.fromUserId,
          'senderName': invitation.fromUsername,
          'fromUserId': invitation.fromUserId,
          'fromUsername': invitation.fromUsername,
          'toUserId': invitation.toUserId,
          'toUsername': invitation.toUsername,
        },
      );

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Invitation notification sent successfully');
        return true;
      } else {
        print(
            '📱 InvitationProvider: ❌ Failed to send invitation notification');
        return false;
      }
    } catch (e) {
      print(
          '📱 InvitationProvider: ❌ Error sending invitation notification: $e');
      return false;
    }
  }

  Future<void> _sendEncryptedInvitationNotification(
      Invitation invitation) async {
    try {
      print(
          '📱 InvitationProvider: Sending encrypted invitation notification to: ${invitation.toUserId}');

      // For now, skip encrypted notifications
      // TODO: Implement encryption when needed
      print(
          '📱 InvitationProvider: Encrypted notifications not yet implemented');
      return;
    } catch (e) {
      print(
          '📱 InvitationProvider: ❌ Error sending encrypted invitation notification: $e');
    }
  }

  Future<bool> _sendAcceptanceNotification(
      Invitation invitation, String chatGuid) async {
    try {
      // Check if the target session ID is valid
      if (invitation.fromUserId.isEmpty || invitation.fromUserId == 'null') {
        print(
            '⚠️ InvitationProvider: Cannot send acceptance notification - invalid fromUserId: ${invitation.fromUserId}');
        return false;
      }

      print(
          '📱 InvitationProvider: Sending acceptance notification to: ${invitation.fromUserId} with chat GUID: $chatGuid');

      // TEMPORARY: Debug session status
      print(
          '📱 InvitationProvider: 🔍 Checking session status for: ${invitation.fromUserId}');

      // TEMPORARY: Send directly to AirNotifier like regular invitations with retry
      bool success = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!success && retryCount < maxRetries) {
        retryCount++;
        print('📱 InvitationProvider: 🔄 Attempt $retryCount of $maxRetries');

        final response = await AirNotifierService.instance
            .sendNotificationToSessionWithResponse(
          sessionId: invitation.fromUserId,
          title: 'Invitation Accepted',
          body: '${invitation.toUsername} accepted your invitation',
          data: {
            'type': 'invitation', // Use same type as working invitations
            'subtype': 'accepted', // Add subtype for differentiation
            'invitationId': invitation.id,
            'senderId': invitation.toUserId,
            'senderName': invitation.toUsername,
            'fromUserId': invitation.toUserId,
            'fromUsername': invitation.toUsername,
            'toUserId': invitation.fromUserId,
            'toUsername': invitation.fromUsername,
            'chatGuid': chatGuid,
          },
        );

        // Check if notification was actually delivered
        if (response != null && response['notifications_sent'] == 0) {
          print(
              '📱 InvitationProvider: ❌ Notification sent but not delivered: $response');
          success = false;
        } else if (response != null && response['notifications_sent'] > 0) {
          print('📱 InvitationProvider: ✅ Notification delivered successfully');
          success = true;
        } else {
          success = false;
        }

        if (!success && retryCount < maxRetries) {
          print('📱 InvitationProvider: ⏳ Waiting 2 seconds before retry...');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Acceptance notification sent successfully with chat GUID: $chatGuid');
        return true;
      } else {
        print(
            '📱 InvitationProvider: ❌ Failed to send acceptance notification');
        // Set error message for user feedback
        _error =
            'Unable to reach the invitation sender. They may be offline or have notifications disabled.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      print(
          '📱 InvitationProvider: ❌ Error sending acceptance notification: $e');
      return false;
    }
  }

  // Delete a chat conversation from SharedPreferences
  Future<void> _deleteChat(String chatId) async {
    try {
      print('📱 InvitationProvider: Deleting chat: $chatId');

      // Get current chats
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      final chats = chatsJson.map((json) => Chat.fromJson(json)).toList();

      // Remove the chat with the specified ID
      final updatedChats = chats.where((chat) => chat.id != chatId).toList();

      // Save updated chats back to SharedPreferences
      final updatedChatsJson =
          updatedChats.map((chat) => chat.toJson()).toList();
      await _prefsService.setJsonList('chats', updatedChatsJson);

      print('📱 InvitationProvider: ✅ Chat deleted successfully: $chatId');
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error deleting chat: $e');
    }
  }

  Future<bool> _sendDeclineNotification(Invitation invitation) async {
    try {
      // Check if the target session ID is valid
      if (invitation.fromUserId.isEmpty || invitation.fromUserId == 'null') {
        print(
            '⚠️ InvitationProvider: Cannot send decline notification - invalid fromUserId: ${invitation.fromUserId}');
        return false;
      }

      print(
          '📱 InvitationProvider: Sending decline notification to: ${invitation.fromUserId}');

      // TEMPORARY: Send directly to AirNotifier like regular invitations with retry
      bool success = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!success && retryCount < maxRetries) {
        retryCount++;
        print(
            '📱 InvitationProvider: 🔄 Attempt $retryCount of $maxRetries (decline)');

        final response = await AirNotifierService.instance
            .sendNotificationToSessionWithResponse(
          sessionId: invitation.fromUserId,
          title: 'Invitation Declined',
          body: '${invitation.toUsername} declined your invitation',
          data: {
            'type': 'invitation', // Use same type as working invitations
            'subtype': 'declined', // Add subtype for differentiation
            'invitationId': invitation.id,
            'senderId': invitation.toUserId,
            'senderName': invitation.toUsername,
            'fromUserId': invitation.toUserId,
            'fromUsername': invitation.toUsername,
            'toUserId': invitation.fromUserId,
            'toUsername': invitation.fromUsername,
          },
        );

        // Check if notification was actually delivered
        if (response != null && response['notifications_sent'] == 0) {
          print(
              '📱 InvitationProvider: ❌ Decline notification sent but not delivered: $response');
          success = false;
        } else if (response != null && response['notifications_sent'] > 0) {
          print(
              '📱 InvitationProvider: ✅ Decline notification delivered successfully');
          success = true;
        } else {
          success = false;
        }

        if (!success && retryCount < maxRetries) {
          print('📱 InvitationProvider: ⏳ Waiting 2 seconds before retry...');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (success) {
        print(
            '📱 InvitationProvider: ✅ Decline notification sent successfully');
        return true;
      } else {
        print('📱 InvitationProvider: ❌ Failed to send decline notification');
        // Set error message for user feedback
        _error =
            'Unable to reach the invitation sender. They may be offline or have notifications disabled.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error sending decline notification: $e');
      return false;
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

  // Handle invitation response from notifications
  Future<void> handleInvitationResponse(
      String responderId, String responderName, String response,
      {String? conversationGuid}) async {
    try {
      print(
          '📱 InvitationProvider: Handling invitation response: $response from $responderName ($responderId)');

      // Find the invitation that matches this response
      final invitation = _invitations.firstWhere(
        (inv) =>
            inv.toUserId == responderId &&
            inv.fromUserId == _sessionService.currentSessionId,
        orElse: () => throw Exception('Invitation not found for response'),
      );

      // Update invitation status
      final updatedInvitation = Invitation(
        id: invitation.id,
        fromUserId: invitation.fromUserId,
        fromUsername: invitation.fromUsername,
        toUserId: invitation.toUserId,
        toUsername: invitation.toUsername,
        status: response == 'accepted'
            ? InvitationStatus.accepted
            : InvitationStatus.declined,
        createdAt: invitation.createdAt,
        respondedAt: DateTime.now(),
      );

      // Update in the list
      final index = _invitations.indexWhere((inv) => inv.id == invitation.id);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
        await _saveInvitations();
        print(
            '📱 InvitationProvider: ✅ Invitation status updated to $response');
      }

      // If accepted and we have a conversation GUID, create the chat
      if (response == 'accepted' && conversationGuid != null) {
        final chat = Chat(
          id: conversationGuid,
          user1Id: invitation.fromUserId,
          user2Id: invitation.toUserId,
          user1DisplayName: invitation.fromUsername,
          user2DisplayName: invitation.toUsername,
          status: 'active',
          lastMessageAt: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _saveChat(chat);
        print('📱 InvitationProvider: ✅ Chat created for accepted invitation');

        // Create initial welcome message
        await _createInitialMessage(conversationGuid, invitation);

        // Trigger indicator for new chat
        IndicatorService().setNewChat();
      }

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error handling invitation response: $e');
    }
  }

  // Delete invitation (for pending sent invitations)
  Future<bool> deleteInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Deleting invitation: $invitationId');

      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.pending) {
        _error = 'Only pending invitations can be deleted';
        notifyListeners();
        return false;
      }

      // Remove invitation from list
      _invitations.removeWhere((inv) => inv.id == invitationId);
      await _saveInvitations();

      // Send cancellation notification to recipient
      await _sendCancellationNotification(invitation);

      // Create local notification for invitation deleted
      await _createLocalNotification(
        title: 'Invitation Deleted',
        body: 'Invitation to ${invitation.toUsername} has been deleted',
        type: 'invitation_deleted',
        data: {
          'invitationId': invitationId,
          'toUsername': invitation.toUsername,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();
      print('📱 InvitationProvider: ✅ Invitation deleted successfully');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error deleting invitation: $e');
      _error = 'Failed to delete invitation: $e';
      notifyListeners();
      return false;
    }
  }

  // Resend invitation (for declined sent invitations)
  Future<bool> resendInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Resending invitation: $invitationId');

      final invitation = _invitations.firstWhere(
        (inv) => inv.id == invitationId,
        orElse: () => throw Exception('Invitation not found'),
      );

      if (invitation.status != InvitationStatus.declined) {
        _error = 'Only declined invitations can be resent';
        notifyListeners();
        return false;
      }

      // Create new invitation with updated timestamp
      final newInvitation = Invitation(
        id: GuidGenerator.generateGuid(),
        fromUserId: invitation.fromUserId,
        fromUsername: invitation.fromUsername,
        toUserId: invitation.toUserId,
        toUsername: invitation.toUsername,
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
        respondedAt: null,
      );

      // Replace old invitation with new one
      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = newInvitation;
        await _saveInvitations();
      }

      // Send new invitation notification
      await _sendInvitationNotification(newInvitation);

      // Create local notification for invitation sent
      await _createLocalNotification(
        title: 'Invitation Sent',
        body: 'Invitation sent to ${newInvitation.toUsername}',
        type: 'invitation_sent',
        data: {
          'invitationId': newInvitation.id,
          'toUsername': newInvitation.toUsername,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _error = null;
      notifyListeners();

      // Trigger indicator for new invitation
      IndicatorService().setNewInvitation();

      print('📱 InvitationProvider: ✅ Invitation resent successfully');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: ❌ Error resending invitation: $e');
      _error = 'Failed to resend invitation: $e';
      notifyListeners();
      return false;
    }
  }

  void clearAllData() {
    _invitations.clear();
    _error = null;
    notifyListeners();
  }

  // Check if a session ID can be invited (for UI feedback)
  Map<String, dynamic> canInviteSessionId(String sessionId) {
    try {
      final currentSession = _sessionService.currentSession;
      if (currentSession == null) {
        return {
          'canInvite': false,
          'reason': 'No active session',
        };
      }

      // Validate session ID format
      if (!GuidGenerator.isValidSessionGuid(sessionId)) {
        return {
          'canInvite': false,
          'reason': 'Invalid session ID format',
        };
      }

      // Check if it's the current user's session ID
      if (sessionId == currentSession.sessionId) {
        return {
          'canInvite': false,
          'reason': 'Cannot invite yourself',
        };
      }

      // Check for existing invitations in all directions
      final existingInvitation = _invitations.firstWhere(
        (inv) =>
            (inv.fromUserId == currentSession.sessionId &&
                inv.toUserId == sessionId) ||
            (inv.fromUserId == sessionId &&
                inv.toUserId == currentSession.sessionId),
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
        // Check the status of the existing invitation
        if (existingInvitation.status == InvitationStatus.pending) {
          if (existingInvitation.fromUserId == currentSession.sessionId) {
            return {
              'canInvite': false,
              'reason': 'Invitation already sent to this user',
            };
          } else {
            return {
              'canInvite': false,
              'reason': 'You already have a pending invitation from this user',
            };
          }
        } else if (existingInvitation.status == InvitationStatus.accepted) {
          return {
            'canInvite': false,
            'reason': 'You are already connected with this user',
          };
        } else if (existingInvitation.status == InvitationStatus.declined) {
          if (existingInvitation.fromUserId == currentSession.sessionId) {
            return {
              'canInvite': false,
              'reason': 'Your invitation was declined by this user',
            };
          } else {
            return {
              'canInvite': false,
              'reason': 'You previously declined an invitation from this user',
            };
          }
        } else if (existingInvitation.status == InvitationStatus.cancelled) {
          return {
            'canInvite': false,
            'reason': 'Previous invitation was cancelled',
          };
        }
      }

      return {
        'canInvite': true,
        'reason': 'Ready to send invitation',
      };
    } catch (e) {
      return {
        'canInvite': false,
        'reason': 'Error checking invitation status: $e',
      };
    }
  }
}
