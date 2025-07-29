import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/global_user_service.dart';
import '../../../core/utils/guid_generator.dart';
import '../../chat/providers/chat_provider.dart';
import 'dart:async';

class InvitationProvider extends ChangeNotifier {
  List<Invitation> _invitations = [];
  final Map<String, User> _invitationUsers = {};
  bool _isLoading = false;
  String? _error;
  bool _isSyncingPendingInvitations = false;

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  User? getInvitationUser(String userId) {
    return _invitationUsers[userId];
  }

  InvitationProvider() {
    _setupSession();
    _setupNetworkListener();
    _loadInvitationsFromLocal();
    _setupLocalStorageListener();
    _setupNotificationHandlers();
  }

  void _setupSession() {
    // Set up Session Protocol event handlers for contact management
    SessionService.instance.onContactAdded = _handleContactAdded;
    SessionService.instance.onContactUpdated = _handleContactUpdated;
    SessionService.instance.onContactRemoved = _handleContactRemoved;
    SessionService.instance.onConnected = _handleSessionConnected;
    SessionService.instance.onDisconnected = _handleSessionDisconnected;
    SessionService.instance.onError = _handleSessionError;
  }

  void _setupNetworkListener() {
    NetworkService.instance.addListener(_handleNetworkChange);
  }

  void _setupLocalStorageListener() {
    LocalStorageService.instance.addListener(_handleLocalStorageChange);
  }

  void _setupNotificationHandlers() {
    // Set up notification service callbacks for real-time updates
    SimpleNotificationService.instance
        .setOnInvitationReceived(handleIncomingInvitation);
    SimpleNotificationService.instance
        .setOnInvitationResponse(handleInvitationResponse);

    print(
        '📱 InvitationProvider: ✅ Notification handlers set up for real-time updates');
  }

  // Handle incoming invitation notification
  Future<void> handleIncomingInvitation(
      String senderId, String senderName, String invitationId) async {
    print(
        '📱 InvitationProvider: Received invitation from $senderName ($senderId) with ID: $invitationId');

    // Check if invitation already exists
    final existingInvitationIndex =
        _invitations.indexWhere((inv) => inv.id == invitationId);
    print(
        '📱 InvitationProvider: Existing invitation index: $existingInvitationIndex');

    if (existingInvitationIndex != -1) {
      // Update existing invitation instead of creating a new one
      final existingInvitation = _invitations[existingInvitationIndex];
      final updatedInvitation = existingInvitation.copyWith(
        senderUsername: senderName,
        updatedAt: DateTime.now(),
      );

      _invitations[existingInvitationIndex] = updatedInvitation;
      print(
          '📱 InvitationProvider: Updated existing invitation: $invitationId');
    } else {
      // Create new invitation record
      final invitation = Invitation(
        id: invitationId,
        senderId: senderId,
        recipientId: SessionService.instance.currentSessionId ?? '',
        senderUsername: senderName,
        recipientUsername: GlobalUserService.instance.currentUsername ?? '',
        message: 'Contact request',
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: true, // This is a received invitation
      );

      print(
          '📱 InvitationProvider: Created new invitation object: ${invitation.toJson()}');

      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      print(
          '📱 InvitationProvider: Added new invitation to list. Total invitations: ${_invitations.length}');
    }

    // Sort by creation time (newest first) to ensure proper ordering
    _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Save to local storage
    await LocalStorageService.instance
        .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

    notifyListeners();
    print(
        '📱 InvitationProvider: ✅ Processed invitation: $invitationId and notified listeners');
  }

  // Handle invitation response notification
  Future<void> handleInvitationResponse(
      String responderId, String responderName, String status,
      {String? conversationGuid}) async {
    print(
        '📱 InvitationProvider: Received invitation response from $responderName ($responderId): $status');

    // Find and update the invitation (look for sent invitations that are pending)
    final invitationIndex = _invitations.indexWhere((inv) =>
        inv.senderId == responderId &&
        inv.status == 'pending' &&
        !inv.isReceived);

    if (invitationIndex != -1) {
      final oldInvitation = _invitations[invitationIndex];
      final updatedInvitation = oldInvitation.copyWith(
        status: status,
        updatedAt: DateTime.now(),
        // Add a flag to indicate this invitation has been processed
        message: status == 'accepted'
            ? 'Invitation accepted - conversation created'
            : 'Invitation declined',
      );

      _invitations[invitationIndex] = updatedInvitation;

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // If invitation was accepted, create conversation for the sender
      if (status == 'accepted') {
        await _createConversationForSender(
            oldInvitation, responderId, responderName, conversationGuid);
      }

      notifyListeners();
      print('📱 InvitationProvider: Updated invitation status to: $status');
    } else {
      print(
          '📱 InvitationProvider: No pending invitation found for responder: $responderId');
    }
  }

  // Create conversation for the sender when invitation is accepted
  Future<void> _createConversationForSender(
      Invitation invitation,
      String responderId,
      String responderName,
      String? conversationGuid) async {
    try {
      print(
          '📱 InvitationProvider: Creating conversation for sender after acceptance');

      // Use provided conversation GUID or generate a new one
      final finalConversationGuid =
          conversationGuid ?? GuidGenerator.generateGuid();

      final currentUserId = SessionService.instance.currentSessionId ?? '';
      final otherUserId = responderId;

      // Create new conversation for the sender
      final newChat = Chat(
        id: finalConversationGuid,
        user1Id: currentUserId,
        user2Id: otherUserId,
        status: 'active',
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': otherUserId,
          'username': responderName,
          'profile_picture': _invitationUsers[otherUserId]?.profilePicture,
        },
        lastMessage: {
          'content': 'You are now connected with $responderName',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Save conversation to local storage
      await LocalStorageService.instance.saveChat(newChat);
      print(
          '📱 InvitationProvider: ✅ Conversation created for sender: $finalConversationGuid');

      // Create initial message for the conversation
      final initialMessage = Message(
        id: GuidGenerator.generateShortId(),
        chatId: finalConversationGuid,
        senderId: 'system',
        content: 'You are now connected with $responderName',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'sent',
      );

      // Save initial message to local storage
      await LocalStorageService.instance.saveMessage(initialMessage);
      print(
          '📱 InvitationProvider: ✅ Initial message created for sender: ${initialMessage.id}');

      // Add local notification for the sender
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Invitation Accepted',
        body: '$responderName accepted your invitation',
        type: 'invitation_response',
        data: {
          'invitationId': invitation.id,
          'response': 'accepted',
          'conversationGuid': conversationGuid,
          'otherUserId': otherUserId,
          'otherUserName': responderName,
        },
      );
    } catch (e) {
      print(
          '📱 InvitationProvider: Error creating conversation for sender: $e');
    }
  }

  void _handleLocalStorageChange() {
    print(
        '📱 InvitationProvider: Local storage changed, reloading invitations...');
    _loadInvitationsFromLocal();
    _scheduleNotifyListeners();
  }

  void _scheduleNotifyListeners() {
    // Schedule notification to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        notifyListeners();
      } catch (e) {
        print('📱 InvitationProvider: Error notifying listeners: $e');
      }
    });
  }

  bool _isHandlingNetworkChange = false;

  void _handleNetworkChange() {
    if (_isHandlingNetworkChange) {
      print(
          '📱 InvitationProvider: Network change handler already in progress, skipping...');
      return;
    }

    _isHandlingNetworkChange = true;
    final networkService = NetworkService.instance;

    if (networkService.isConnected && !networkService.isReconnecting) {
      print('📱 InvitationProvider: Network reconnected, refreshing services');

      if (!SessionService.instance.isConnected) {
        print(
            '📱 InvitationProvider: Session not connected - attempting to connect');
        SessionService.instance.connect();
      } else {
        NetworkService.instance.handleSuccessfulReconnection();
      }

      _syncPendingInvitations();
    } else if (!networkService.isConnected) {
      print('📱 InvitationProvider: Network disconnected');
    }

    Timer(const Duration(seconds: 2), () {
      _isHandlingNetworkChange = false;
    });
  }

  void _syncPendingInvitations() {
    if (_isSyncingPendingInvitations) {
      print(
          '📱 InvitationProvider: Already syncing pending invitations, skipping...');
      return;
    }

    _isSyncingPendingInvitations = true;
    print('📱 InvitationProvider: Syncing pending invitations...');

    // In Session Protocol, we don't have traditional invitations
    // Instead, we sync contacts and their status
    _isSyncingPendingInvitations = false;
  }

  // Load invitations from local storage
  Future<void> _loadInvitationsFromLocal() async {
    try {
      print('📱 InvitationProvider: Loading invitations from local storage...');
      final invitationData =
          await LocalStorageService.instance.getInvitations();
      print(
          '📱 InvitationProvider: Found ${invitationData.length} invitations in storage');

      // Debug: Print each invitation data
      for (int i = 0; i < invitationData.length; i++) {
        print('📱 InvitationProvider: Invitation $i: ${invitationData[i]}');
      }

      _invitations =
          invitationData.map((data) => Invitation.fromJson(data)).toList();
      print('📱 InvitationProvider: Loaded ${_invitations.length} invitations');

      // Debug: Print each loaded invitation
      for (int i = 0; i < _invitations.length; i++) {
        print(
            '📱 InvitationProvider: Loaded invitation $i: ${_invitations[i].toJson()}');
      }

      notifyListeners();
      print('📱 InvitationProvider: ✅ Notified listeners of invitation update');
    } catch (e) {
      print(
          '📱 InvitationProvider: Error loading invitations from local storage: $e');
    }
  }

  // Add contact using Session Protocol
  Future<void> addContact({
    required String sessionId,
    String? displayName,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Add contact via Session Protocol
      await SessionService.instance.addContact(
        sessionId: sessionId,
        name: displayName,
      );

      // Create invitation record for local tracking
      final invitation = Invitation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: SessionService.instance.currentSessionId ?? '',
        recipientId: sessionId,
        senderUsername: GlobalUserService.instance.currentUsername ?? '',
        recipientUsername: displayName ?? 'Anonymous User',
        message: 'Contact request',
        status: 'accepted', // In Session, adding contact is immediate
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: false, // This is a sent invitation (user initiated contact)
      );

      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      // Sort by creation time (newest first) to ensure proper ordering
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Create user object for the contact
      final user = User(
        id: sessionId,
        username: displayName ?? 'Anonymous User',
        profilePicture: null, // No profile picture in Session Protocol
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[sessionId] = user;

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Show instant notification for successful contact addition
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Contact Added',
        body: 'Contact $displayName added successfully',
        type: 'contact_added',
        data: {
          'contactName': displayName ?? 'Anonymous',
          'invitationId': invitation.id,
        },
      );

      print('📱 InvitationProvider: Contact added: $sessionId');
    } catch (e) {
      _error = 'Failed to add contact: $e';
      _scheduleNotifyListeners();
      print('📱 InvitationProvider: Error adding contact: $e');
    } finally {
      _isLoading = false;
      _scheduleNotifyListeners();
    }
  }

  // Remove contact using Session Protocol
  Future<void> removeContact(String sessionId) async {
    try {
      _isLoading = true;
      _error = null;
      _scheduleNotifyListeners();

      // Remove contact via Session Protocol
      await SessionService.instance.removeContact(sessionId);

      // Remove from local invitations
      _invitations.removeWhere((inv) => inv.recipientId == sessionId);
      _invitationUsers.remove(sessionId);

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      print('📱 InvitationProvider: Contact removed: $sessionId');
    } catch (e) {
      _error = 'Failed to remove contact: $e';
      _scheduleNotifyListeners();
      print('📱 InvitationProvider: Error removing contact: $e');
    } finally {
      _isLoading = false;
      _scheduleNotifyListeners();
    }
  }

  // Get all contacts
  Map<String, LocalSessionContact> getContacts() {
    return SessionService.instance.contacts;
  }

  // Check if user is a contact
  bool isContact(String sessionId) {
    return SessionService.instance.contacts.containsKey(sessionId);
  }

  // Get contact by session ID
  LocalSessionContact? getContact(String sessionId) {
    return SessionService.instance.contacts[sessionId];
  }

  // Update contact profile
  Future<bool> updateContactProfile({
    required String sessionId,
    String? displayName,
    String? profilePicture,
  }) async {
    try {
      // Update contact via Session Protocol
      // Note: This would need to be implemented in SessionService
      print('📱 InvitationProvider: Updating contact profile: $sessionId');

      // Update local user object
      final user = _invitationUsers[sessionId];
      if (user != null) {
        _invitationUsers[sessionId] = user.copyWith(
          username: displayName ?? user.username,
          profilePicture: profilePicture ?? user.profilePicture,
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error updating contact profile: $e');
      _error = 'Failed to update contact profile: $e';
      notifyListeners();
      return false;
    }
  }

  // Block contact
  Future<bool> blockContact(String sessionId) async {
    try {
      print('📱 InvitationProvider: Blocking contact: $sessionId');

      // Block contact via Session Protocol
      // Note: This would need to be implemented in SessionService

      // Update local user object
      final user = _invitationUsers[sessionId];
      if (user != null) {
        _invitationUsers[sessionId] = user.copyWith(
            // Add blocked status to User model if needed
            );
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error blocking contact: $e');
      _error = 'Failed to block contact: $e';
      notifyListeners();
      return false;
    }
  }

  // Unblock contact
  Future<bool> unblockContact(String sessionId) async {
    try {
      print('📱 InvitationProvider: Unblocking contact: $sessionId');

      // Unblock contact via Session Protocol
      // Note: This would need to be implemented in SessionService

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error unblocking contact: $e');
      _error = 'Failed to unblock contact: $e';
      notifyListeners();
      return false;
    }
  }

  // Get blocked contacts
  List<LocalSessionContact> getBlockedContacts() {
    return SessionService.instance.contacts.values
        .where((contact) => contact.isBlocked)
        .toList();
  }

  // Refresh contacts from Session Protocol
  Future<void> refreshContacts() async {
    try {
      print('📱 InvitationProvider: Refreshing contacts...');

      // Contacts are automatically managed by Session Protocol
      // This method can be used to trigger UI updates
      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error refreshing contacts: $e');
      _error = 'Failed to refresh contacts: $e';
      notifyListeners();
    }
  }

  // Session Protocol Event Handlers
  void _handleContactAdded(LocalSessionContact contact) async {
    try {
      print(
          '📱 InvitationProvider: Contact added via Session: ${contact.sessionId}');

      // Create user object for the contact
      final user = User(
        id: contact.sessionId,
        username: contact.name ?? 'Anonymous User',
        profilePicture: contact.profilePicture,
        isOnline: contact.isOnline,
        lastSeen: contact.lastSeen,
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[contact.sessionId] = user;

      // Create invitation record
      final invitation = Invitation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: SessionService.instance.currentSessionId ?? '',
        recipientId: contact.sessionId,
        message: 'Contact added',
        status: 'accepted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: false, // This is a sent invitation (contact was added)
      );

      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      // Sort by creation time (newest first) to ensure proper ordering
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Show notification for contact added (invitation accepted)
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Contact Added',
        body: '${contact.name ?? 'Anonymous User'} is now your contact',
        type: 'contact_added',
        data: {
          'contactName': contact.name ?? 'Anonymous User',
          'status': 'accepted',
          'invitationId': invitation.id,
        },
      );

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact added: $e');
    }
  }

  void _handleContactUpdated(LocalSessionContact contact) {
    try {
      print(
          '📱 InvitationProvider: Contact updated via Session: ${contact.sessionId}');

      // Update local user object
      final user = User(
        id: contact.sessionId,
        username: contact.name ?? 'Anonymous User',
        profilePicture: contact.profilePicture,
        isOnline: contact.isOnline,
        lastSeen: contact.lastSeen,
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[contact.sessionId] = user;

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact updated: $e');
    }
  }

  void _handleContactRemoved(String sessionId) {
    try {
      print('📱 InvitationProvider: Contact removed via Session: $sessionId');

      // Remove from local data
      _invitationUsers.remove(sessionId);
      _invitations.removeWhere((inv) => inv.recipientId == sessionId);

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact removed: $e');
    }
  }

  void _handleSessionConnected() {
    print('📱 InvitationProvider: Session connected');
    // Refresh contacts when Session connects
    refreshContacts();
  }

  void _handleSessionDisconnected() {
    print('📱 InvitationProvider: Session disconnected');
  }

  void _handleSessionError(String error) {
    print('📱 InvitationProvider: Session error: $error');
    _error = error;
    notifyListeners();
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
    _isSyncingPendingInvitations = false;
    notifyListeners();
  }

  // Public methods for UI compatibility

  // Load invitations (merge local storage with Session contacts)
  Future<void> loadInvitations({bool forceRefresh = false}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print(
          '📱 InvitationProvider: Loading invitations (merge local storage with Session contacts)... forceRefresh: $forceRefresh');

      // First, load invitations from local storage
      await _loadInvitationsFromLocal();
      print(
          '📱 InvitationProvider: Loaded ${_invitations.length} invitations from local storage');

      // Get contacts from Session Service
      final contacts = SessionService.instance.contacts;
      print('📱 InvitationProvider: Found ${contacts.length} Session contacts');

      // Create a map of existing invitation IDs to avoid duplicates
      final existingInvitationIds = _invitations.map((inv) => inv.id).toSet();
      print(
          '📱 InvitationProvider: Existing invitation IDs: $existingInvitationIds');

      // Check if we already have Session contacts in our invitations
      final hasSessionContacts = _invitations
          .any((inv) => inv.status == 'accepted' && inv.isReceived == false);

      print(
          '📱 InvitationProvider: Already has Session contacts: $hasSessionContacts');

      // Only add Session contacts if we don't have them already or if force refresh is requested
      int addedCount = 0;
      if (!hasSessionContacts || forceRefresh) {
        // Add Session contacts as invitations (if not already present)
        for (final contact in contacts.values) {
          if (!existingInvitationIds.contains(contact.sessionId)) {
            final sessionInvitation = Invitation(
              id: contact.sessionId,
              senderId:
                  SessionService.instance.currentIdentity?.sessionId ?? '',
              recipientId: contact.sessionId,
              message: 'Contact added',
              status: 'accepted',
              createdAt: contact.lastSeen,
              updatedAt: contact.lastSeen,
              isReceived:
                  false, // These are sent invitations (user initiated contact)
            );

            _invitations.add(sessionInvitation);
            addedCount++;
            print(
                '📱 InvitationProvider: Added Session contact as invitation: ${contact.sessionId}');
          } else {
            print(
                '📱 InvitationProvider: Skipped duplicate Session contact: ${contact.sessionId}');
          }

          // Create user objects for contacts (always update user data)
          _invitationUsers[contact.sessionId] = User(
            id: contact.sessionId,
            username: contact.name ?? 'Anonymous User',
            profilePicture: contact.profilePicture,
            isOnline: contact.isOnline,
            lastSeen: contact.lastSeen,
            alreadyInvited: true,
            invitationStatus: 'accepted',
          );
        }

        // Only save to local storage if we actually added new invitations
        if (addedCount > 0) {
          await LocalStorageService.instance.saveInvitations(
              _invitations.map((inv) => inv.toJson()).toList());
          print(
              '📱 InvitationProvider: Saved ${_invitations.length} invitations to local storage (added $addedCount new)');
        } else {
          print(
              '📱 InvitationProvider: No new invitations added, skipping local storage save');
        }
      } else {
        print(
            '📱 InvitationProvider: Session contacts already exist, skipping addition');

        // Still update user objects for contacts
        for (final contact in contacts.values) {
          _invitationUsers[contact.sessionId] = User(
            id: contact.sessionId,
            username: contact.name ?? 'Anonymous User',
            profilePicture: contact.profilePicture,
            isOnline: contact.isOnline,
            lastSeen: contact.lastSeen,
            alreadyInvited: true,
            invitationStatus: 'accepted',
          );
        }
      }

      // Sort by creation time (newest first)
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Only save to local storage if we actually added new invitations
      if (addedCount > 0) {
        await LocalStorageService.instance
            .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());
        print(
            '📱 InvitationProvider: Saved ${_invitations.length} invitations to local storage (added $addedCount new)');
      } else {
        print(
            '📱 InvitationProvider: No new invitations added, skipping local storage save');
      }

      print(
          '📱 InvitationProvider: Loaded ${_invitations.length} total invitations (local + Session contacts)');
    } catch (e) {
      print('📱 InvitationProvider: Error loading invitations: $e');
      _error = 'Failed to load invitations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Mark received invitations as read
  void markReceivedInvitationsAsRead() {
    // In Session Protocol, all contacts are considered "read"
    notifyListeners();
  }

  // Mark sent invitations as read
  void markSentInvitationsAsRead() {
    // In Session Protocol, all contacts are considered "read"
    notifyListeners();
  }

  // Set on invitations screen (for tracking UI state)
  void setOnInvitationsScreen(bool isOnScreen) {
    // This method is for UI state tracking
    // No state change needed, so no notifyListeners() call
  }

  // Check if there are unread invitations
  bool get hasUnreadInvitations {
    // In Session Protocol, all contacts are considered "read"
    return false;
  }

  // Block user via Session ID and update invitation status
  Future<bool> blockUser(String sessionId) async {
    try {
      print('📱 InvitationProvider: Blocking user via Session ID: $sessionId');

      // Find the invitation for this user
      final invitation = _invitations.firstWhere(
        (inv) => inv.senderId == sessionId || inv.recipientId == sessionId,
        orElse: () =>
            throw Exception('Invitation not found for user: $sessionId'),
      );

      // Update invitation status to blocked (but keep it for reference)
      final updatedInvitation = invitation.copyWith(
        status: 'blocked',
        updatedAt: DateTime.now(),
      );

      // Update in memory
      final index = _invitations.indexWhere((inv) => inv.id == invitation.id);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      // Save to local storage for persistence
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Update user status to blocked
      if (_invitationUsers.containsKey(sessionId)) {
        final user = _invitationUsers[sessionId]!;
        final updatedUser = user.copyWith(
          invitationStatus: 'blocked',
        );
        _invitationUsers[sessionId] = updatedUser;
      }

      // Remove contact via Session Protocol (this effectively blocks them)
      try {
        await SessionService.instance.removeContact(sessionId);
        print(
            '📱 InvitationProvider: ✅ User removed via Session Protocol: $sessionId');
      } catch (e) {
        print('📱 InvitationProvider: ⚠️ Session Protocol removal failed: $e');
        // Continue anyway - we've already blocked locally
      }

      notifyListeners();
      print('📱 InvitationProvider: ✅ User blocked successfully: $sessionId');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error blocking user: $e');
      _error = 'Failed to block user: $e';
      notifyListeners();
      return false;
    }
  }

  // Accept invitation (Session Protocol equivalent)
  Future<bool> acceptInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Accepting invitation: $invitationId');

      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);
      final currentUserId = SessionService.instance.currentSessionId ?? '';
      final otherUserId =
          invitation.senderId; // The person who sent the invitation
      final otherUserName = invitation.senderUsername ?? 'Unknown User';

      // Update invitation status
      final updatedInvitation = invitation.copyWith(
        status: 'accepted',
        updatedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      // Save updated invitation to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Add as contact in Session Protocol
      try {
        await SessionService.instance.addContact(
          sessionId: otherUserId,
          name: otherUserName,
          profilePicture: _invitationUsers[otherUserId]?.profilePicture,
        );
        print(
            '📱 InvitationProvider: ✅ Contact added via Session Protocol: $otherUserId');
      } catch (e) {
        print(
            '📱 InvitationProvider: ⚠️ Session Protocol addContact failed: $e');
        // Continue anyway - we've already accepted locally
      }

      // Generate GUID for the new conversation
      final conversationGuid = GuidGenerator.generateGuid();
      print(
          '📱 InvitationProvider: Generated conversation GUID: $conversationGuid');

      // Create new conversation for the accepter
      final newChat = Chat(
        id: conversationGuid,
        user1Id: currentUserId,
        user2Id: otherUserId,
        status: 'active',
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': otherUserId,
          'username': otherUserName,
          'profile_picture': _invitationUsers[otherUserId]?.profilePicture,
        },
        lastMessage: {
          'content': 'You are now connected with $otherUserName',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Save conversation to local storage
      await LocalStorageService.instance.saveChat(newChat);
      print(
          '📱 InvitationProvider: ✅ Conversation saved to local storage: $conversationGuid');

      // Create initial message for the conversation
      final initialMessage = Message(
        id: GuidGenerator.generateShortId(),
        chatId: conversationGuid,
        senderId: 'system',
        content: 'You are now connected with $otherUserName',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'sent',
      );

      // Save initial message to local storage
      await LocalStorageService.instance.saveMessage(initialMessage);
      print(
          '📱 InvitationProvider: ✅ Initial message saved: ${initialMessage.id}');

      // Note: The new chat will be loaded by ChatProvider.loadChats()
      // which now merges local storage chats with Session contacts
      // The chat is already saved to local storage above, so it will appear
      // when the chat screen is refreshed or when loadChats() is called
      print(
          '📱 InvitationProvider: ✅ New chat ready for ChatProvider to load: $conversationGuid');

      // Send invitation response notification to the original sender
      final responseSuccess =
          await SimpleNotificationService.instance.sendInvitationResponse(
        recipientId: otherUserId,
        senderName:
            GlobalUserService.instance.currentUsername ?? 'Unknown User',
        invitationId: invitationId,
        response: 'accepted',
        conversationGuid: conversationGuid,
      );

      if (responseSuccess) {
        print(
            '📱 InvitationProvider: ✅ Invitation response notification sent to: $otherUserId');
      } else {
        print(
            '📱 InvitationProvider: ⚠️ Failed to send invitation response notification');
      }

      // Add local notification for the accepter
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Invitation Accepted',
        body: 'You are now connected with $otherUserName',
        type: 'invitation_response',
        data: {
          'invitationId': invitationId,
          'response': 'accepted',
          'conversationGuid': conversationGuid,
          'otherUserId': otherUserId,
          'otherUserName': otherUserName,
        },
      );

      // Update the invitation status to prevent duplication
      // This ensures that when the response notification is received,
      // it won't create a duplicate invitation
      final finalUpdatedInvitation = updatedInvitation.copyWith(
        status: 'accepted',
        updatedAt: DateTime.now(),
        // Add a flag to indicate this invitation has been processed
        message: 'Invitation accepted - conversation created',
      );

      final finalIndex =
          _invitations.indexWhere((inv) => inv.id == invitationId);
      if (finalIndex != -1) {
        _invitations[finalIndex] = finalUpdatedInvitation;
        // Save the final updated invitation
        await LocalStorageService.instance
            .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());
      }

      notifyListeners();
      print(
          '📱 InvitationProvider: ✅ Invitation accepted successfully: $invitationId');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error accepting invitation: $e');
      _error = 'Failed to accept invitation: $e';
      notifyListeners();
      return false;
    }
  }

  // Decline invitation
  Future<bool> declineInvitation(String invitationId) async {
    try {
      print('📱 InvitationProvider: Declining invitation: $invitationId');

      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);
      final otherUserId =
          invitation.senderId; // The person who sent the invitation
      final otherUserName = invitation.senderUsername ?? 'Unknown User';

      // Update invitation status
      final updatedInvitation = invitation.copyWith(
        status: 'declined',
        updatedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      // Save updated invitation to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Send invitation response notification to the original sender
      final responseSuccess =
          await SimpleNotificationService.instance.sendInvitationResponse(
        recipientId: otherUserId,
        senderName:
            GlobalUserService.instance.currentUsername ?? 'Unknown User',
        invitationId: invitationId,
        response: 'declined',
      );

      if (responseSuccess) {
        print(
            '📱 InvitationProvider: ✅ Invitation response notification sent to: $otherUserId');
      } else {
        print(
            '📱 InvitationProvider: ⚠️ Failed to send invitation response notification');
      }

      // Add local notification for the decliner
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Invitation Declined',
        body: 'You declined the invitation from $otherUserName',
        type: 'invitation_response',
        data: {
          'invitationId': invitationId,
          'response': 'declined',
          'otherUserId': otherUserId,
          'otherUserName': otherUserName,
        },
      );

      notifyListeners();
      print(
          '📱 InvitationProvider: ✅ Invitation declined successfully: $invitationId');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error declining invitation: $e');
      _error = 'Failed to decline invitation: $e';
      notifyListeners();
      return false;
    }
  }

  // Delete invitation (does NOT delete notifications - they persist independently)
  Future<bool> deleteInvitation(String invitationId) async {
    try {
      _invitations.removeWhere((inv) => inv.id == invitationId);

      // Save updated invitations to local storage for persistence
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      notifyListeners();
      print(
          '📱 InvitationProvider: ✅ Deleted invitation $invitationId and saved to local storage (notifications preserved)');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error deleting invitation: $e');
      return false;
    }
  }

  // Clear all data (for account deletion)
  Future<void> clearAllData() async {
    try {
      print('📱 InvitationProvider: Clearing all invitation data...');

      _invitations.clear();
      _invitationUsers.clear();
      _isLoading = false;
      _error = null;
      _isSyncingPendingInvitations = false;

      notifyListeners();
      print('📱 InvitationProvider: ✅ All invitation data cleared');
    } catch (e) {
      print('📱 InvitationProvider: Error clearing all data: $e');
    }
  }

  // [STEP 1] Send invitation using AirNotifier
  Future<bool> sendInvitation(String recipientId,
      {required String displayName}) async {
    // The display name is required and will be the name saved for this contact on the local device

    try {
      // [STEP 2] Validate invitation request
      // Check if trying to invite yourself
      final currentSessionId = SessionService.instance.currentSessionId;
      if (recipientId == currentSessionId) {
        print(
            '📱 InvitationProvider: Cannot send invitation to yourself: $recipientId');
        return false;
      }

      if (isUserInvited(recipientId)) {
        print(
            '📱 InvitationProvider: User $recipientId is already in contacts');
        return false;
      }

      if (isUserQueued(recipientId)) {
        print(
            '📱 InvitationProvider: Invitation to $recipientId is already pending');
        return false;
      }

      // [STEP 3] Generate unique invitation ID and prepare data
      final invitationId =
          'inv_${DateTime.now().millisecondsSinceEpoch}_${recipientId}';

      final recipientName = displayName; // Display name is now required

      // Get current user info from global user service
      final senderName =
          GlobalUserService.instance.currentUsername ?? 'Unknown User';

      // [STEP 4] Send push notification via SimpleNotificationService
      final success = await SimpleNotificationService.instance.sendInvitation(
        recipientId: recipientId,
        senderName: senderName,
        invitationId: invitationId,
        message: 'Contact request',
      );

      if (success) {
        print(
            '📱 InvitationProvider: Invitation sent via AirNotifier to: $recipientId');

        // [STEP 5] Create invitation record for local tracking
        final invitation = Invitation(
          id: invitationId,
          senderId: SessionService.instance.currentSessionId ?? '',
          recipientId: recipientId,
          senderUsername: senderName,
          recipientUsername: recipientName,
          message: 'Contact request',
          status: 'pending', // Set as pending until recipient responds
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isReceived: false, // This is a sent invitation
        );

        // Add new invitation at the top (index 0) for real-time updates
        _invitations.insert(0, invitation);

        // Sort by creation time (newest first) to ensure proper ordering
        _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // [STEP 6] Create local notification for sender's notifications screen
        // Show recipient's name in the notification (not sender's name)
        await SimpleNotificationService.instance.showLocalNotification(
          title: 'Invitation Sent',
          body: 'Invitation sent to $recipientName',
          type: 'invitation_sent',
          data: {
            'recipientName': recipientName,
            'invitationId': invitationId,
          },
        );

        notifyListeners();

        // No local notification for sender - only recipient should get notification

        return true;
      } else {
        print(
            '📱 InvitationProvider: Failed to send invitation via AirNotifier to: $recipientId');

        // Set error message for UI display
        _error =
            'Failed to send invitation. Recipient may be offline or not registered.';
        _scheduleNotifyListeners();

        return false;
      }
    } catch (e) {
      print('📱 InvitationProvider: Error sending invitation: $e');

      // Set error message for UI display
      _error = 'Failed to send invitation: ${e.toString()}';
      _scheduleNotifyListeners();

      return false;
    }
  }

  // Check if user is invited
  bool isUserInvited(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'accepted');
  }

  // Check if user is queued (pending invitation)
  bool isUserQueued(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'pending');
  }

  @override
  void dispose() {
    // Remove network listener
    NetworkService.instance.removeListener(_handleNetworkChange);
    super.dispose();
  }
}
